#!/usr/bin/env bash
# shellcheck disable=SC2034

DEMO_ENV_PASSTHROUGH="PATH HOME TMPDIR TERM OPERATOR_CIDR DEMO_INJECT_FAIL DEMO_NAME"
DEMO_ENV_FIXED="LANG=C LC_ALL=C TZ=UTC AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1 AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_EC2_METADATA_DISABLED=true TF_CLI_ARGS_plan=-no-color TF_CLI_ARGS_apply=-no-color TF_CLI_ARGS_destroy=-no-color TF_CLI_CONFIG_FILE=/dev/null TF_WORKSPACE=default TARGET=localstack DEMO_BOUNDARY=1"
DEMO_GENERATOR_SHARED="demo/lib.sh demo/env.sh demo/record.sh"
DEMO_GENERATOR_INFRA="Makefile envs/preview modules policy tests/conftest-gate.sh tests/fixtures/conftest scripts/fixture-hygiene.sh"

demo_recording_config() {
  case "${1:-}" in
    demo)
      printf '%s\n' \
        'TAPE=demo/demo.tape' \
        'DOC=docs/assets/DEMO_PROVENANCE.md' \
        'GIF=docs/assets/demo.gif' \
        'ENV_ID=demo' \
        'KIND=lifecycle'
      ;;
    lease)
      printf '%s\n' \
        'TAPE=demo/demo-lease.tape' \
        'DOC=docs/assets/DEMO_PROVENANCE_LEASE.md' \
        'GIF=docs/assets/demo-lease.gif' \
        'ENV_ID=demo-lease' \
        'KIND=lease'
      ;;
    supply)
      printf '%s\n' \
        'TAPE=demo/demo-supplychain.tape' \
        'DOC=docs/assets/DEMO_PROVENANCE_SUPPLYCHAIN.md' \
        'GIF=docs/assets/demo-supplychain.gif' \
        'ENV_ID=' \
        'KIND=verify'
      ;;
    *)
      echo "demo: unknown DEMO_NAME '${1:-}'" >&2
      return 2
      ;;
  esac
}

demo_required_output_patterns() {
  case "$1" in
    lifecycle)
      printf '%s\n' \
        '^Plan: [0-9]+ to add' \
        '^Apply complete! Resources: [0-9]+ added' \
        '^Destroy complete! Resources: [0-9]+ destroyed' \
        '^PASS: conftest-gate suite' \
        '^aws_' \
        '[Ll]ocal[Ss]tack' \
        '\b(ecs|elbv2|s3)\b.*(running|available)'
      ;;
    lease)
      printf '%s\n' \
        '^Plan: 61 to add, 0 to change, 0 to destroy[.]$' \
        '^Apply complete! Resources: 61 added, 0 changed, 0 destroyed[.]$' \
        '"status": "open"' \
        '^sweep[.]sh: demo-lease Stage 2 complete; lease is closed$' \
        '^final_status=closed$'
      ;;
    verify)
      printf '%s\n' \
        '^identical=0$' \
        '^identical=1$' \
        '^PASS: SBOM canonicalization contracts [(]14 assertions[)]$'
      ;;
    *) return 2 ;;
  esac
}

demo_generator_paths() {
  case "$1" in
    lifecycle)
      printf '%s\n' "$DEMO_GENERATOR_SHARED demo/demo.tape demo/provenance/lifecycle.md $DEMO_GENERATOR_INFRA"
      ;;
    lease)
      printf '%s\n' "$DEMO_GENERATOR_SHARED demo/demo-lease.tape demo/provenance/lease.md $DEMO_GENERATOR_INFRA scripts/lease.sh scripts/close-env.sh scripts/cleanup-verifier.sh scripts/sweep.sh scripts/aws-cli.sh scripts/lease-sweep-until-closed.sh"
      ;;
    verify)
      printf '%s\n' "$DEMO_GENERATOR_SHARED demo/demo-supplychain.tape demo/provenance/supply.md $DEMO_GENERATOR_INFRA scripts/sbom-canon.sh tests/sbom-canon.sh tests/fixtures/sbom"
      ;;
    *) return 2 ;;
  esac
}

generator_clean_check() {
  local root=${1:-}
  local commit=${2:-}
  local kind=${3:-${RECORDING_KIND:-lifecycle}}
  local paths dirty ignored_file path failed diff_rc
  paths=$(demo_generator_paths "$kind") || return 2
  (
    cd -- "$root" 2>/dev/null || {
      echo "generator root unavailable: $root" >&2
      exit 1
    }
    failed=0
    # shellcheck disable=SC2086
    if dirty=$(git status --porcelain --untracked-files=all -- $paths 2>/dev/null); then
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
      if git ls-files --others --ignored --exclude-standard -z -- $paths > "$ignored_file" 2>/dev/null; then
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
        if git diff --quiet "$commit" HEAD -- $paths 2>/dev/null; then
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
