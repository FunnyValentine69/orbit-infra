#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

REPO_ROOT="${DEMO_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck disable=SC1091
source "$REPO_ROOT/demo/lib.sh"

tmp_dir="$(mktemp -d)"
results="$tmp_dir/results.txt"
failures=0
trap 'rm -rf "$tmp_dir"' EXIT

pass_case() {
  printf 'PASS: %s\n' "$1" | tee -a "$results"
}

fail_case() {
  printf 'FAIL: %s%s\n' "$1" "${2:+ -> $2}" | tee -a "$results" >&2
  failures=$((failures + 1))
}

field_line() {
  local field=$1
  local doc=$2
  grep -F "| $field |" "$doc" || true
}

field_value() {
  local field=$1
  local doc=$2
  field_line "$field" "$doc" | sed -E 's/^\| [^|]+ \| (.*) \|$/\1/'
}

generator_clean() {
  local root=$1
  local commit=$2
  local dirty ignored_file ignored path
  ignored_file="$tmp_dir/ignored-$RANDOM.bin"
  (
    cd "$root"
    if ! git cat-file -e "$commit^{commit}" 2>/dev/null; then
      echo "generator commit unreachable; fetch full history" >&2
      return 1
    fi
    # shellcheck disable=SC2086
    if ! git diff --quiet "$commit" HEAD -- $DEMO_GENERATOR_PATHS; then
      echo "generator inputs differ from recorded commit" >&2
      return 1
    fi
    # shellcheck disable=SC2086
    dirty="$(git status --porcelain --untracked-files=all -- $DEMO_GENERATOR_PATHS)"
    if [ -n "$dirty" ]; then
      echo "generator tree dirty; commit before recording" >&2
      return 1
    fi
    : > "$ignored_file"
    # shellcheck disable=SC2086
    while IFS= read -r -d '' path; do
      case "$path" in
        demo/out/*|*/.terraform/*|*/.terraform-localstack/*|*/.terraform-localstack-*/*)
          continue
          ;;
      esac
      case "$path" in
        *.tfvars|*.tfvars.json|*.tf|*.tf.json)
          if [ "$path" != "envs/preview/backend_override.tf" ]; then
            printf '%s\0' "$path" >> "$ignored_file"
          fi
          ;;
      esac
    done < <(git ls-files --others --ignored --exclude-standard -z -- $DEMO_GENERATOR_PATHS)
    if IFS= read -r -d '' ignored < "$ignored_file"; then
      echo "ignored terraform input present: $ignored" >&2
      return 1
    fi
  )
}

init_generator_clone() {
  local destination=$1
  local path parent
  mkdir -p "$destination"
  for path in $DEMO_GENERATOR_PATHS; do
    parent=${path%/*}
    if [ "$parent" != "$path" ]; then
      mkdir -p "$destination/$parent"
    fi
    cp -R "$REPO_ROOT/$path" "$destination/$path"
  done
  cp "$REPO_ROOT/.gitignore" "$destination/.gitignore"
  if [ -d "$destination/demo/out" ]; then
    find "$destination/demo/out" -type f -delete
  fi
  (
    cd "$destination"
    git init -q
    git add -A
    git -c user.name=t -c user.email=t@example.com commit -q -m x
  )
}

echo "== demo contracts: environment =="
environment_root="$tmp_dir/environment"
mkdir -p "$environment_root/cdpath/demo" "$environment_root/bin"
printf '%s\n' 'DEMO_ENV_PASSTHROUGH=sentinel' > "$environment_root/cdpath/demo/lib.sh"
printf '%s\n' 'export TF_VAR_api_image=from_bash_env' \
  'touch "${BASH_ENV_SENTINEL:?}"' > "$environment_root/bash-env.sh"

actual_env="$environment_root/actual.env"
expected_env="$environment_root/expected.env"
set +e
env_output="$(
  env TF_VAR_api_image=ambient \
  AWS_REGION=eu-west-1 \
  AWS_PROFILE=ambient \
  TF_CLI_ARGS_plan=ambient \
  TF_WORKSPACE=qa \
  MAKEFILES=ambient.mk \
  PROMPT_COMMAND=ambient \
  SHELLOPTS=braceexpand \
  CDPATH="$environment_root/cdpath" \
  UNRELATED_SENTINEL=ambient \
  BASH_ENV="$environment_root/bash-env.sh" \
  BASH_ENV_SENTINEL="$environment_root/bash-env-ran" \
  PATH="$PATH" \
  HOME="$environment_root/home" \
  TMPDIR="$environment_root" \
  TERM=xterm-contract \
  OPERATOR_CIDR=203.0.113.0/24 \
  DEMO_INJECT_FAIL=none \
    bash -p "$REPO_ROOT/demo/env.sh" env 2>&1
)"
environment_rc=$?
set -e
printf '%s\n' "$env_output" | sort > "$actual_env"
for name in $DEMO_ENV_PASSTHROUGH; do
  case "$name" in
    PATH) value=$PATH ;;
    HOME) value="$environment_root/home" ;;
    TMPDIR) value=$environment_root ;;
    TERM) value=xterm-contract ;;
    OPERATOR_CIDR) value=203.0.113.0/24 ;;
    DEMO_INJECT_FAIL) value=none ;;
    *) value=unexpected ;;
  esac
  printf '%s=%s\n' "$name" "$value" >> "$expected_env"
done
for assignment in $DEMO_ENV_FIXED; do
  printf '%s\n' "$assignment" >> "$expected_env"
done
sort -o "$expected_env" "$expected_env"
if [ "$environment_rc" -eq 0 ] && cmp -s "$expected_env" "$actual_env" && \
   [ ! -e "$environment_root/bash-env-ran" ]; then
  pass_case "environment exact constructed allowlist"
else
  fail_case "environment exact constructed allowlist" "$env_output"
fi

makeflags_ok=1
for makeflags in n t q i k -kn; do
  set +e
  refusal="$(env PATH="$environment_root/bin" MAKEFLAGS="$makeflags" \
    /bin/bash -p "$REPO_ROOT/demo/env.sh" 2>&1)"
  refusal_rc=$?
  set -e
  if [ "$refusal_rc" -eq 0 ] || \
     ! grep -Fq "demo: refusing MAKEFLAGS='$makeflags' (-i/-k/-n/-t/-q); run make demo directly" <<< "$refusal"; then
    makeflags_ok=0
  fi
done
if [ "$makeflags_ok" -eq 1 ]; then
  pass_case "environment MAKEFLAGS n/t/q/i/k/-kn refusal before tools"
else
  fail_case "environment MAKEFLAGS n/t/q/i/k/-kn refusal before tools"
fi
echo "PASS: demo contract group environment"

echo "== demo contracts: steps and tape =="
expected_steps="status
plan
conftest
apply
statelist
destroy"
actual_steps="$(tape_steps "$REPO_ROOT/demo/demo.tape")"
if [ "$actual_steps" = "$expected_steps" ]; then
  pass_case "steps marker set"
else
  fail_case "steps marker set" "$actual_steps"
fi

make_step_names="$(awk '
  /^Type `make [^`]*; record_rc [a-z]+`( Enter)?( Wait)?$/ {
    line=$0
    sub(/^.*; record_rc /, "", line)
    sub(/`.*/, "", line)
    print line
  }
' "$REPO_ROOT/demo/demo.tape")"
if [ "$make_step_names" = "$expected_steps" ]; then
  pass_case "steps every make target records one labelled rc"
else
  fail_case "steps every make target records one labelled rc" "$make_step_names"
fi

statelist_line="$(grep 'make localstack-state-list' "$REPO_ROOT/demo/demo.tape" || true)"
if [ -n "$statelist_line" ] && [[ "$statelist_line" != *'|'* ]] && \
   grep -Fq "sed -n '1,12p' \"\$RUN/statelist.log\"" "$REPO_ROOT/demo/demo.tape"; then
  pass_case "steps state-list status is captured before display truncation"
else
  fail_case "steps state-list status is captured before display truncation" "$statelist_line"
fi

floor="$(tape_expected_seconds "$REPO_ROOT/demo/demo.tape")"
if [ "$floor" = "28.36" ]; then
  pass_case "tape expected floor 28.36"
else
  fail_case "tape expected floor 28.36" "$floor"
fi

tape_negative_ok=1
for tape_case in \
  'playback|Set TypingSpeed 40ms\nSet PlaybackSpeed 2' \
  'type-at|Set TypingSpeed 40ms\nType@500ms `x`' \
  'sleep-unit|Set TypingSpeed 40ms\nSleep 2' \
  'typing-missing|Show\nType `x`' \
  'enter-count|Set TypingSpeed 40ms\nEnter 2' \
  'unknown|Set TypingSpeed 40ms\nLaunch rocket'; do
  tape_name=${tape_case%%|*}
  tape_body=${tape_case#*|}
  negative_tape="$tmp_dir/tape-$tape_name.tape"
  printf '%b\n' "$tape_body" > "$negative_tape"
  set +e
  negative_output="$(tape_expected_seconds "$negative_tape" 2>&1)"
  negative_rc=$?
  set -e
  if [ "$negative_rc" -eq 0 ]; then
    tape_negative_ok=0
  elif [ "$tape_name" = typing-missing ]; then
    grep -Fq 'Set TypingSpeed must be present' <<< "$negative_output" || tape_negative_ok=0
  elif ! grep -Fq 'unsupported tape construct:' <<< "$negative_output"; then
    tape_negative_ok=0
  fi
done
if [ "$tape_negative_ok" -eq 1 ]; then
  pass_case "tape parser fail-closed constructs"
else
  fail_case "tape parser fail-closed constructs"
fi
echo "PASS: demo contract group steps and tape"

echo "== demo contracts: CIDR and provenance =="
cidr_ok=1
for cidr in 203.0.113.0/24 203.0.113.128/25 203.0.113.16/28 203.0.113.7/32; do
  cidr_in_test_net_3 "$cidr" || cidr_ok=0
done
for cidr in 203.0.113.7 203.0.113.0/16 203.0.113.5/24 \
  203.0.113.17/28 203.0.113.256/32 203.0.113.01/32 \
  203.0.114.0/24 203.0.113.0/33 203.0.113.0/8; do
  if cidr_in_test_net_3 "$cidr"; then cidr_ok=0; fi
done
if [ "$cidr_ok" -eq 1 ]; then
  pass_case "CIDR TEST-NET-3 containment truth table"
else
  fail_case "CIDR TEST-NET-3 containment truth table"
fi

validate_provenance() {
  local doc=$1
  local gif=$2
  local field count artifact sha commit recorded_on command environment
  local command_cidr environment_cidr expected_size expected_sha
  for field in recorded_from recorded_on 'generator commit' recorder command environment \
    'plan / apply / destroy' artifact 'artifact sha256'; do
    count="$(grep -Fc "| $field |" "$doc")"
    if [ "$count" -ne 1 ]; then
      echo "required provenance row count $field: $count" >&2
      return 1
    fi
  done
  artifact="$(field_value artifact "$doc")"
  expected_size="$(wc -c < "$gif" | tr -d ' ')"
  case "$artifact" in
    "$expected_size bytes,"*) ;;
    *) echo "artifact byte count mismatch" >&2; return 1 ;;
  esac
  sha="$(field_value 'artifact sha256' "$doc")"
  expected_sha="$(shasum -a 256 "$gif" | awk '{print $1}')"
  if [ "$sha" != "$expected_sha" ]; then
    echo "artifact sha256 mismatch" >&2
    return 1
  fi
  commit="$(field_value 'generator commit' "$doc" | sed -E 's/^`?([0-9a-f]{7}).*/\1/')"
  [[ "$commit" =~ ^[0-9a-f]{7}$ ]] || { echo "generator commit is not 7 hex" >&2; return 1; }
  recorded_on="$(field_value recorded_on "$doc")"
  [[ "$recorded_on" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "recorded_on is not YYYY-MM-DD" >&2; return 1; }
  if ! awk '/^\| plan \/ apply \/ destroy \|/ {
      count=0
      rest=$0
      while (match(rest, /Resources: [0-9]+|Plan: [0-9]+/)) {
        value=substr(rest, RSTART, RLENGTH)
        sub(/^.* /, "", value)
        counts[++count]=value
        rest=substr(rest, RSTART + RLENGTH)
      }
      if (count != 3 || counts[1] != counts[2] || counts[1] != counts[3]) exit 1
      found=1
    } END { if (!found) exit 1 }' "$doc"; then
    echo "plan/apply/destroy counts differ" >&2
    return 1
  fi
  command="$(field_value command "$doc")"
  environment="$(field_value environment "$doc")"
  command_cidr="$(sed -E 's/.*OPERATOR_CIDR=([^ `]+).*/\1/' <<< "$command")"
  environment_cidr="$(sed -E 's/.*operator CIDR `?([^ `,(]+).*/\1/' <<< "$environment")"
  if [ "$command_cidr" != "$environment_cidr" ] || ! cidr_in_test_net_3 "$command_cidr"; then
    echo "command/environment CIDR mismatch or outside TEST-NET-3" >&2
    return 1
  fi
}

if provenance_output="$(validate_provenance "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" \
  "$REPO_ROOT/docs/assets/demo.gif" 2>&1)"; then
  pass_case "provenance committed artifact rows"
else
  fail_case "provenance committed artifact rows" "$provenance_output"
fi

provenance_negative_ok=1
for provenance_case in size sha missing duplicate cidr-mismatch environment-outside; do
  doc_copy="$tmp_dir/provenance-$provenance_case.md"
  case "$provenance_case" in
    size)
      sed -E '/^\| artifact \|/s/[0-9]+ bytes/1 bytes/' \
        "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" > "$doc_copy"
      ;;
    sha)
      sed -E '/^\| artifact sha256 \|/s/[0-9a-f]{64}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
        "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" > "$doc_copy"
      ;;
    missing)
      awk '!/^\| recorder \|/' "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" > "$doc_copy"
      ;;
    duplicate)
      awk '{print} /^\| recorder \|/{print}' "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" > "$doc_copy"
      ;;
    cidr-mismatch)
      sed '/^| command |/s#203\.0\.113\.0/24#203.0.113.128/25#' \
        "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" > "$doc_copy"
      ;;
    environment-outside)
      sed '/^| environment |/s#203\.0\.113\.0/24#203.0.114.0/24#' \
        "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" > "$doc_copy"
      ;;
  esac
  if validate_provenance "$doc_copy" "$REPO_ROOT/docs/assets/demo.gif" >/dev/null 2>&1; then
    provenance_negative_ok=0
  fi
done
if [ "$provenance_negative_ok" -eq 1 ]; then
  pass_case "provenance negative mutation table"
else
  fail_case "provenance negative mutation table"
fi

recorded_commit="$(field_value 'generator commit' "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" | \
  sed -E 's/^`?([0-9a-f]{7}).*/\1/')"
set +e
baseline_drift_output="$(generator_clean "$REPO_ROOT" "$recorded_commit" 2>&1)"
baseline_drift_rc=$?
set -e
if [ "$baseline_drift_rc" -eq 0 ]; then
  pass_case "generator commit drift"
else
  fail_case "generator commit drift" "$baseline_drift_output"
fi

positive_clone="$tmp_dir/generator-positive"
init_generator_clone "$positive_clone"
positive_commit="$(git -C "$positive_clone" rev-parse HEAD)"
mkdir -p "$positive_clone/demo/out/run-x" \
  "$positive_clone/envs/preview/.terraform/cache" \
  "$positive_clone/modules/network/.terraform/cache"
printf '%s\n' runtime > "$positive_clone/demo/out/run-x/.started"
printf '%s\n' runtime > "$positive_clone/envs/preview/.terraform/cache/provider.tf"
printf '%s\n' runtime > "$positive_clone/modules/network/.terraform/cache/provider.tf"
if generator_clean "$positive_clone" "$positive_commit" >/dev/null 2>&1; then
  pass_case "generator cleanliness allows runtime output and Terraform caches"
else
  fail_case "generator cleanliness allows runtime output and Terraform caches"
fi

generator_negative_ok=1
for generator_case in committed-record committed-module staged-preview uncommitted-preview \
  untracked-demo ignored-preview-tfvars ignored-module-override ignored-space-input; do
  clone="$tmp_dir/generator-$generator_case"
  init_generator_clone "$clone"
  base_commit="$(git -C "$clone" rev-parse HEAD)"
  case "$generator_case" in
    committed-record)
      printf '%s\n' '# mutation' >> "$clone/demo/record.sh"
      (cd "$clone" && git add -A && git -c user.name=t -c user.email=t@example.com commit -q -m mutation)
      ;;
    committed-module)
      printf '%s\n' '# mutation' >> "$clone/modules/network/main.tf"
      (cd "$clone" && git add -A && git -c user.name=t -c user.email=t@example.com commit -q -m mutation)
      ;;
    staged-preview)
      printf '%s\n' '# mutation' >> "$clone/envs/preview/main.tf"
      (cd "$clone" && git add envs/preview/main.tf)
      ;;
    uncommitted-preview) printf '%s\n' '# mutation' >> "$clone/envs/preview/main.tf" ;;
    untracked-demo) printf '%s\n' mutation > "$clone/demo/untracked.txt" ;;
    ignored-preview-tfvars) printf '%s\n' 'x = 1' > "$clone/envs/preview/terraform.tfvars" ;;
    ignored-module-override)
      printf '%s\n' 'modules/network/zz_override.tf' >> "$clone/.git/info/exclude"
      printf '%s\n' '# ignored input' > "$clone/modules/network/zz_override.tf"
      ;;
    ignored-space-input)
      printf '%s\n' 'envs/preview/hidden input.tf' >> "$clone/.git/info/exclude"
      printf '%s\n' '# ignored input' > "$clone/envs/preview/hidden input.tf"
      ;;
  esac
  if generator_clean "$clone" "$base_commit" >/dev/null 2>&1; then
    generator_negative_ok=0
  fi
done
unreachable_clone="$tmp_dir/generator-unreachable"
init_generator_clone "$unreachable_clone"
set +e
unreachable_output="$(generator_clean "$unreachable_clone" deadbee 2>&1)"
unreachable_rc=$?
set -e
if [ "$unreachable_rc" -eq 0 ] || \
   ! grep -Fq 'generator commit unreachable; fetch full history' <<< "$unreachable_output"; then
  generator_negative_ok=0
fi
if [ "$generator_negative_ok" -eq 1 ]; then
  pass_case "generator drift negative mutation table and unreachable history"
else
  fail_case "generator drift negative mutation table and unreachable history"
fi
gates_job="$(sed -n '/^  gates:/,/^  plan-localstack:/p' \
  "$REPO_ROOT/.github/workflows/terraform-plan.yml")"
if grep -Fq 'fetch-depth: 0' <<< "$gates_job"; then
  pass_case "generator drift CI checkout has full history"
else
  fail_case "generator drift CI checkout has full history"
fi
echo "PASS: demo contract group CIDR and provenance (generator drift reported separately)"


echo "== demo contracts: lifecycle =="
lifecycle_template="$tmp_dir/lifecycle-template"
mkdir -p "$lifecycle_template/demo" "$lifecycle_template/docs/assets" \
  "$lifecycle_template/envs/preview"
cp "$REPO_ROOT/demo/record.sh" "$REPO_ROOT/demo/lib.sh" "$REPO_ROOT/demo/env.sh" \
  "$REPO_ROOT/demo/demo.tape" "$lifecycle_template/demo/"
cp "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" "$REPO_ROOT/docs/assets/demo.gif" \
  "$lifecycle_template/docs/assets/"
find "$REPO_ROOT/envs/preview" -maxdepth 1 -type f \
  -exec cp {} "$lifecycle_template/envs/preview/" \;

fake_bin="$tmp_dir/fake-bin"
mkdir -p "$fake_bin"
for tool in vhs ffprobe ffmpeg ttyd curl jq make terraform docker aws git shasum; do
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'tool=${0##*/}' \
    'printf "%s %s\n" "$tool" "$*" >> "${FAKE_CALL_LOG:?}"' \
    'case "$tool" in' \
    '  vhs)' \
    '    if [ "$*" = --version ]; then echo "vhs 0.11.0"; exit 0; fi' \
    '    [ "${FAKE_FAIL:-}" != record ] || exit 1' \
    '    while IFS= read -r step; do' \
    '      [ -n "$step" ] || continue' \
    '      [ "${FAKE_VHS_MODE:-}" != rc_missing ] || { [ "$step" != plan ] || continue; }' \
    '      rc=0' \
    '      if [ "${FAKE_VHS_MODE:-}" = rc_nonzero ] && [ "$step" = plan ]; then rc=1; fi' \
    '      printf "%s\n" "$rc" > "$RUN/$step.rc"' \
    '    done < <(awk '\''/^# DEMO-SECTION / { print $3 }'\'' "$RUN/demo.tape")' \
    '    printf "%s\n" "localstack | s3 | running" > "$RUN/status.log"' \
    '    printf "%s\n" "Plan: 59 to add, 0 to change, 0 to destroy." > "$RUN/plan.log"' \
    '    printf "%s\n" "PASS: conftest-gate suite" > "$RUN/conftest.log"' \
    '    printf "%s\n" "Apply complete! Resources: 59 added, 0 changed, 0 destroyed." > "$RUN/apply.log"' \
    '    printf "%s\n" "aws_ecs_cluster.this" > "$RUN/statelist.log"' \
    '    printf "%s\n" "Destroy complete! Resources: 59 destroyed." > "$RUN/destroy.log"' \
    '    printf "%s\n" 1 > "$RUN/env.ok"' \
    '    printf "%s\n" "localstack | s3 | running" "Plan: 59 to add, 0 to change, 0 to destroy." "PASS: conftest-gate suite" "Apply complete! Resources: 59 added, 0 changed, 0 destroyed." "aws_ecs_cluster.this" "Destroy complete! Resources: 59 destroyed." > "$RUN/demo.txt"' \
    '    printf "%s\n" GIF > "$RUN/demo.gif"' \
    '    touch -t 203001010000 "$RUN/demo.gif"' \
    '    if [ "${FAKE_VHS_MODE:-}" = stale ]; then touch -t 200001010000 "$RUN/demo.gif"; fi' \
    '    if [ "${FAKE_STATE_MODE:-}" = post_apply ]; then touch "${FAKE_LIVE_MARKER:?}"; fi' \
    '    ;;' \
    '  ffprobe)' \
    '    case "$*" in *format=duration*) printf "%s\n" "${FAKE_DURATION:-31.72}" ;; *) printf "%s\n" 793 ;; esac' \
    '    ;;' \
    '  ffmpeg)' \
    '    if [ "$1" = -version ]; then echo "ffmpeg version 9.0.1"; exit 0; fi' \
    '    [ "${FAKE_FAIL:-}" != inspect_decode ]' \
    '    ;;' \
    '  ttyd) echo "ttyd version 1.7.7" ;;' \
    '  curl)' \
    '    case "$*" in *-s\ localhost*) echo '\''{"version":"2026.8.1"}'\'' ;; *) : ;; esac' \
    '    ;;' \
    '  jq) echo "2026.8.1" ;;' \
    '  make)' \
    '    case " $* " in' \
    '      *" render-localstack-backend "*)' \
    '        mkdir -p "$PREVIEW_ROOT"' \
    '        find "$PREVIEW_ROOT" -maxdepth 1 -type f ! -name backend_override.tf ! -name "*.tfstate*" -delete' \
    '        while IFS= read -r -d "" source; do' \
    '          name=${source##*/}' \
    '          case "$name" in backend_override.tf|*.tfstate*) continue ;; esac' \
    '          cp "$source" "$PREVIEW_ROOT/$name"' \
    '        done < <(find envs/preview -maxdepth 1 -type f -print0)' \
    '        printf "%s\n" generated > "$PREVIEW_ROOT/backend_override.tf"' \
    '        ;;' \
    '      *" destroy "*)' \
    '        touch "${FAKE_DESTROY_MARKER:?}"' \
    '        [ "${FAKE_FAIL:-}" != teardown_destroy ] || exit 1' \
    '        ;;' \
    '    esac' \
    '    ;;' \
    '  terraform)' \
    '    case " $* " in' \
    '      *" state list "*)' \
    '        case "${FAKE_STATE_MODE:-empty}" in' \
    '          leftover) echo aws_leftover.example ;;' \
    '          teardown_nonempty) [ ! -e "${FAKE_DESTROY_MARKER:?}" ] || echo aws_leftover.example ;;' \
    '          post_apply) [ ! -e "${FAKE_LIVE_MARKER:?}" ] || { [ -e "${FAKE_DESTROY_MARKER:?}" ] || echo aws_live.example; } ;;' \
    '        esac' \
    '        ;;' \
    '      *" version "*) echo "Terraform v1.16.0" ;;' \
    '    esac' \
    '    ;;' \
    '  docker|aws) : ;;' \
    '  git)' \
    '    case "$*" in' \
    '      "status --porcelain --untracked-files=all --"*) : ;;' \
    '      "ls-files --others --ignored --exclude-standard -z --"*) : ;;' \
    '      "rev-parse --short=7 HEAD") echo abcdef0 ;;' \
    '      *) echo "unexpected fake git call: $*" >&2; exit 2 ;;' \
    '    esac' \
    '    ;;' \
    '  shasum) /usr/bin/shasum "$@" ;;' \
    'esac' > "$fake_bin/$tool"
  chmod +x "$fake_bin/$tool"
done


run_lifecycle() {
  local name=$1
  local fake_fail=$2
  local vhs_mode=$3
  local state_mode=$4
  local inject=$5
  local mutation=$6
  local case_root repo call_log destroy_marker live_marker before after output rc run_dir
  case_root="$tmp_dir/lifecycle-$name"
  repo="$case_root/repo"
  mkdir -p "$case_root"
  cp -R "$lifecycle_template" "$repo"
  call_log="$case_root/calls.log"
  destroy_marker="$case_root/destroyed"
  live_marker="$case_root/live"
  : > "$call_log"
  case "$mutation" in
    stale-destination)
      mkdir -p "$repo/.preview-runs/demo"
      printf '%s\n' stale > "$repo/.preview-runs/demo/stale.tfstate.tf"
      ;;
    missing-source)
      printf '%s\n' source > "$repo/envs/preview/migration.tfstate.tf"
      ;;
    missing-field)
      awk '!/^\| artifact sha256 \|/' "$repo/docs/assets/DEMO_PROVENANCE.md" > "$case_root/doc"
      cp "$case_root/doc" "$repo/docs/assets/DEMO_PROVENANCE.md"
      ;;
  esac
  before="$(shasum -a 256 "$repo/docs/assets/demo.gif" "$repo/docs/assets/DEMO_PROVENANCE.md")"
  set +e
  output="$(
    cd "$repo"
    PATH="$fake_bin:$PATH" \
    HOME="$case_root/home" \
    TMPDIR="$case_root" \
    TERM=xterm \
    OPERATOR_CIDR=203.0.113.0/24 \
    DEMO_INJECT_FAIL="$inject" \
      bash -p demo/env.sh env \
        FAKE_CALL_LOG="$call_log" \
        FAKE_FAIL="$fake_fail" \
        FAKE_VHS_MODE="$vhs_mode" \
        FAKE_STATE_MODE="$state_mode" \
        FAKE_DURATION="${FAKE_CASE_DURATION:-31.72}" \
        FAKE_DESTROY_MARKER="$destroy_marker" \
        FAKE_LIVE_MARKER="$live_marker" \
        bash demo/record.sh 2>&1
  )"
  rc=$?
  set -e
  after="$(shasum -a 256 "$repo/docs/assets/demo.gif" "$repo/docs/assets/DEMO_PROVENANCE.md")"
  set -- "$repo"/demo/out/run-*
  run_dir=$1
  LIFECYCLE_OUTPUT=$output
  LIFECYCLE_RC=$rc
  LIFECYCLE_BEFORE=$before
  LIFECYCLE_AFTER=$after
  LIFECYCLE_RUN=$run_dir
  LIFECYCLE_CALLS=$call_log
  LIFECYCLE_REPO=$repo
}

boundary_root="$tmp_dir/lifecycle-boundary"
cp -R "$lifecycle_template" "$boundary_root"
boundary_calls="$tmp_dir/lifecycle-boundary.calls"
: > "$boundary_calls"
boundary_before="$(shasum -a 256 "$boundary_root/docs/assets/demo.gif" \
  "$boundary_root/docs/assets/DEMO_PROVENANCE.md")"
set +e
boundary_output="$(cd "$boundary_root" && PATH="$fake_bin:$PATH" \
  TF_VAR_api_image=ambient AWS_REGION=eu-west-1 AWS_PROFILE=ambient \
  FAKE_CALL_LOG="$boundary_calls" bash demo/record.sh 2>&1)"
boundary_rc=$?
set -e
boundary_after="$(shasum -a 256 "$boundary_root/docs/assets/demo.gif" \
  "$boundary_root/docs/assets/DEMO_PROVENANCE.md")"
if [ "$boundary_rc" -ne 0 ] && [ ! -s "$boundary_calls" ] && \
   [ "$boundary_before" = "$boundary_after" ] && \
   grep -Fq 'run make demo; demo/record.sh must be started through demo/env.sh' <<< "$boundary_output"; then
  pass_case "lifecycle boundary direct invocation has zero tool calls"
else
  fail_case "lifecycle boundary direct invocation has zero tool calls" "$boundary_output"
fi

lifecycle_failures_ok=1
for lifecycle_case in \
  'preflight-leftover||normal|leftover||none|environment demo already has state' \
  'preflight-render-unexpected||normal|empty||stale-destination|execution root differs from envs/preview: stale.tfstate.tf' \
  'preflight-render-missing||normal|empty||missing-source|execution root differs from envs/preview: migration.tfstate.tf' \
  'record|record|normal|empty||none|vhs failed' \
  'assert-rc-nonzero||rc_nonzero|empty||none|plan.rc was not 0' \
  'assert-rc-missing||rc_missing|empty||none|step rc set differs from tape markers' \
  'inspect-stale||stale|empty||none|demo.gif mtime predates run start' \
  'inspect-duration||normal|empty||none|demo.gif duration' \
  'render-provenance||normal|empty||missing-field|required provenance row artifact sha256 count was 0' \
  'teardown-destroy|teardown_destroy|normal|empty||none|teardown failed; not publishing' \
  'teardown-state||normal|teardown_nonempty||none|teardown failed; not publishing' \
  'post-apply||normal|post_apply|post-apply|none|injected failure after apply'; do
  IFS='|' read -r name fake_fail vhs_mode state_mode inject mutation expected_message <<< "$lifecycle_case"
  if [ "$name" = inspect-duration ]; then
    FAKE_CASE_DURATION=28.35
  else
    FAKE_CASE_DURATION=31.72
  fi
  export FAKE_CASE_DURATION
  run_lifecycle "$name" "$fake_fail" "$vhs_mode" "$state_mode" "$inject" "$mutation"
  unset FAKE_CASE_DURATION
  if [ "$LIFECYCLE_RC" -eq 0 ] || [ "$LIFECYCLE_BEFORE" != "$LIFECYCLE_AFTER" ] || \
     ! grep -Fq "$expected_message" <<< "$LIFECYCLE_OUTPUT" || \
     grep -Fq 'publish:ok' "$LIFECYCLE_RUN/lifecycle.log"; then
    lifecycle_failures_ok=0
    fail_case "lifecycle $name" "$LIFECYCLE_OUTPUT"
    continue
  fi
  case_ok=1
  case "$name" in
    preflight-*) phase=preflight; trapped=0 ;;
    record) phase=record; trapped=1 ;;
    assert-*) phase=assert_steps; trapped=1 ;;
    inspect-*) phase=inspect_artifact; trapped=1 ;;
    render-provenance) phase=render_provenance; trapped=1 ;;
    teardown-*) phase=teardown; trapped=1 ;;
    post-apply) phase=inject_check; trapped=1 ;;
    *) phase=unknown; trapped=1 ;;
  esac
  phase_failures="$(grep -c "^$phase:fail$" "$LIFECYCLE_RUN/lifecycle.log" || true)"
  [ "$phase_failures" -eq 1 ] || case_ok=0
  destroy_calls="$(grep -c '^make destroy$' "$LIFECYCLE_CALLS" || true)"
  teardown_lines="$(grep -c '^teardown:' "$LIFECYCLE_RUN/lifecycle.log" || true)"
  if [ "$trapped" -eq 0 ]; then
    [ "$destroy_calls" -eq 0 ] && [ "$teardown_lines" -eq 0 ] || case_ok=0
  else
    [ "$destroy_calls" -eq 1 ] && [ "$teardown_lines" -eq 1 ] || case_ok=0
  fi
  if [ "$case_ok" -eq 1 ]; then
    pass_case "lifecycle $name"
  else
    lifecycle_failures_ok=0
    fail_case "lifecycle $name" "unexpected lifecycle or teardown count"
  fi
done

run_lifecycle success '' normal empty '' none
success_order="$(awk -F: '$1 == "teardown" { teardown=NR } $1 == "publish" { publish=NR }
  END { if (teardown && publish && teardown < publish) print "ok" }' \
  "$LIFECYCLE_RUN/lifecycle.log")"
teardown_lines="$(grep -c '^teardown:' "$LIFECYCLE_RUN/lifecycle.log")"
expected_lifecycle="$tmp_dir/expected-success-lifecycle.log"
printf '%s\n' guard:ok setup:ok preflight:ok record:ok inject_check:ok \
  assert_steps:ok inspect_artifact:ok build_manifest:ok render_provenance:ok \
  teardown:ok publish:ok > "$expected_lifecycle"
if [ "$LIFECYCLE_RC" -eq 0 ] && [ "$LIFECYCLE_BEFORE" != "$LIFECYCLE_AFTER" ] && \
   [ "$success_order" = ok ] && [ "$teardown_lines" -eq 1 ] && \
   cmp -s "$expected_lifecycle" "$LIFECYCLE_RUN/lifecycle.log" && \
   validate_provenance "$LIFECYCLE_REPO/docs/assets/DEMO_PROVENANCE.md" \
     "$LIFECYCLE_REPO/docs/assets/demo.gif" >/dev/null 2>&1; then
  pass_case "lifecycle success publishes only after one successful teardown"
else
  lifecycle_failures_ok=0
  fail_case "lifecycle success publishes only after one successful teardown" "$LIFECYCLE_OUTPUT"
fi
if [ -s "$LIFECYCLE_CALLS" ] && \
   ! grep '^curl ' "$LIFECYCLE_CALLS" | grep -vF 'localhost:4566' >/dev/null; then
  pass_case "lifecycle fake-only curl network boundary"
else
  lifecycle_failures_ok=0
  fail_case "lifecycle fake-only curl network boundary"
fi
if [ "$lifecycle_failures_ok" -eq 1 ]; then
  echo "PASS: demo contract group lifecycle"
else
  echo "FAIL: demo contract group lifecycle" >&2
fi

echo "== demo contract case results =="
cat "$results"
if [ "$failures" -ne 0 ]; then
  echo "FAIL: demo contracts ($failures case(s))" >&2
  exit 1
fi
echo "PASS: demo contracts (4 groups)"
