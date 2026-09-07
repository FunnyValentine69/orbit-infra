#!/usr/bin/env bash
# shellcheck disable=SC2034

DEMO_ENV_PASSTHROUGH="PATH HOME TMPDIR TERM OPERATOR_CIDR DEMO_INJECT_FAIL"
DEMO_ENV_FIXED="LANG=C LC_ALL=C TZ=UTC AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1 AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_EC2_METADATA_DISABLED=true TF_CLI_ARGS_plan=-no-color TF_CLI_ARGS_apply=-no-color TF_CLI_ARGS_destroy=-no-color TF_CLI_CONFIG_FILE=/dev/null TF_WORKSPACE=default TARGET=localstack ENV_ID=demo PREVIEW_ROOT=.preview-runs/demo DEMO_BOUNDARY=1"
DEMO_GENERATOR_PATHS="demo Makefile envs/preview modules policy tests/conftest-gate.sh tests/fixtures/conftest scripts/fixture-hygiene.sh"

generator_clean_check() {
  local root=${1:-}
  local commit=${2:-}
  local dirty ignored_file path failed diff_rc
  (
    cd -- "$root" 2>/dev/null || {
      echo "generator root unavailable: $root" >&2
      exit 1
    }
    failed=0
    # shellcheck disable=SC2086
    if dirty=$(git status --porcelain --untracked-files=all -- $DEMO_GENERATOR_PATHS 2>/dev/null); then
      if [ -n "$dirty" ]; then
        echo "generator tree dirty; commit before recording" >&2
        failed=1
      fi
    else
      echo "could not inspect generator tree" >&2
      failed=1
    fi

    ignored_file=
    if ignored_file=$(mktemp "${TMPDIR:-/tmp}/demo-generator-ignored-XXXXXXXX" 2>/dev/null); then
      # shellcheck disable=SC2086
      if git ls-files --others --ignored --exclude-standard -z -- $DEMO_GENERATOR_PATHS > "$ignored_file" 2>/dev/null; then
        while IFS= read -r -d '' path; do
          case "$path" in
            demo/out/*|*/.terraform/*|*/.terraform-localstack/*|*/.terraform-localstack-*/*)
              continue
              ;;
          esac
          case "$path" in
            *.tfvars|*.tfvars.json|*.tf|*.tf.json)
              if [ "$path" != "envs/preview/backend_override.tf" ]; then
                echo "ignored terraform input present: $path" >&2
                failed=1
              fi
              ;;
          esac
        done < "$ignored_file"
      else
        echo "could not inspect ignored generator inputs" >&2
        failed=1
      fi
      rm -f "$ignored_file"
    else
      echo "could not allocate ignored generator input list" >&2
      failed=1
    fi

    if [ -n "$commit" ]; then
      if git cat-file -e "$commit^{commit}" 2>/dev/null; then
        # shellcheck disable=SC2086
        if git diff --quiet "$commit" HEAD -- $DEMO_GENERATOR_PATHS 2>/dev/null; then
          :
        else
          diff_rc=$?
          if [ "$diff_rc" -eq 1 ]; then
            echo "generator inputs differ from recorded commit" >&2
          else
            echo "could not compare generator commit" >&2
          fi
          failed=1
        fi
      else
        echo "generator commit unreachable; fetch full history" >&2
        failed=1
      fi
    fi
    exit "$failed"
  )
}

cidr_in_test_net_3() {
  local cidr=${1:-}
  local octet prefix host_mask
  [[ "$cidr" =~ ^203\.0\.113\.([0-9]{1,3})/([0-9]{2})$ ]] || return 1
  octet=${BASH_REMATCH[1]}
  prefix=${BASH_REMATCH[2]}
  if [[ "$octet" != 0 && "$octet" == 0* ]]; then
    return 1
  fi
  case "$prefix" in
    24|25|26|27|28|29|30|31|32) ;;
    *) return 1 ;;
  esac
  [ "$octet" -le 255 ] || return 1
  host_mask=$(( (1 << (32 - prefix)) - 1 ))
  [ $((octet & host_mask)) -eq 0 ]
}

tape_steps() {
  awk '/^# DEMO-SECTION / { print $3 }' "$1"
}

tape_expected_seconds() {
  awk '
    BEGIN { shown=1; typing_seen=0; typing_ms=0; total=0; failed=0 }
    function unsupported(value) {
      print "unsupported tape construct: " value > "/dev/stderr"
      failed=1
    }
    {
      line=$0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*$/ || line ~ /^#/) next
      if (line ~ /^Output[[:space:]]+[^[:space:]].*$/) next
      if (line ~ /^Set[[:space:]]+/) {
        split(line, parts, /[[:space:]]+/)
        key=parts[2]
        if (key !~ /^(Shell|FontSize|Width|Height|Framerate|TypingSpeed|Padding|WaitTimeout)$/) {
          unsupported(line)
          next
        }
        if (key == "TypingSpeed") {
          if (line !~ /^Set TypingSpeed [0-9]+ms$/) {
            unsupported(line)
            next
          }
          value=line
          sub(/^Set TypingSpeed /, "", value)
          sub(/ms$/, "", value)
          typing_ms=value + 0
          typing_seen=1
        }
        next
      }
      if (line == "Hide") { shown=0; next }
      if (line == "Show") { shown=1; next }
      if (line ~ /^Sleep [0-9]+([.][0-9]+)?s$/) {
        if (shown) {
          value=line
          sub(/^Sleep /, "", value)
          sub(/s$/, "", value)
          total += value + 0
        }
        next
      }
      if (line ~ /^Type `[^`]*`( Enter)?( Wait)?$/) {
        if (shown) {
          value=line
          sub(/^Type `/, "", value)
          sub(/`( Enter)?( Wait)?$/, "", value)
          total += length(value) * typing_ms / 1000
        }
        next
      }
      unsupported(line)
    }
    END {
      if (failed) exit 1
      if (!typing_seen) {
        print "Set TypingSpeed must be present" > "/dev/stderr"
        exit 1
      }
      printf "%.2f\n", total
    }
  ' "$1"
}
