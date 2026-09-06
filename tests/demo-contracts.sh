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

refusal_bin="$environment_root/refusal-bin"
refusal_calls="$environment_root/refusal.calls"
mkdir -p "$refusal_bin"
: > "$refusal_calls"
printf '%s\n' '#!/bin/sh' \
  "printf '%s\\n' env >> '$refusal_calls'" \
  'exit 0' > "$refusal_bin/env"
chmod +x "$refusal_bin/env"
set +e
refusal_output="$(
  /usr/bin/env -i \
    PATH="$refusal_bin:$PATH" \
    HOME="$environment_root/home" \
    TMPDIR="$environment_root" \
    TERM=xterm-contract \
    OPERATOR_CIDR=203.0.113.0/24 \
      /bin/bash -p "$REPO_ROOT/demo/env.sh" env EXTRA=1 bash -c true 2>&1
)"
refusal_rc=$?
set -e
if [ "$refusal_rc" -ne 0 ] && [ ! -s "$refusal_calls" ] && \
   grep -Fq 'demo/env.sh: only "env" is accepted as an argument' <<< "$refusal_output"; then
  pass_case "environment arbitrary command refusal before downstream calls"
else
  fail_case "environment arbitrary command refusal before downstream calls" "$refusal_output"
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

provenance_matches_manifest() {
  local doc=$1
  local manifest=$2
  local mapping key field expected actual count
  for mapping in \
    'recorded_from|recorded_from' \
    'recorded_on|recorded_on' \
    'generator_commit|generator commit' \
    'recorder|recorder' \
    'command|command' \
    'environment|environment' \
    'plan_apply_destroy|plan / apply / destroy' \
    'artifact|artifact' \
    'artifact_sha256|artifact sha256'; do
    IFS='|' read -r key field <<< "$mapping"
    count="$(grep -Fc "| $field |" "$doc")"
    if [ "$count" -ne 1 ]; then
      echo "required provenance row count $field: $count" >&2
      return 1
    fi
    expected="$(sed -n "s/^${key}=//p" "$manifest")"
    actual="$(field_value "$field" "$doc")"
    if [ "$actual" != "$expected" ]; then
      echo "provenance row differs from run manifest: $field" >&2
      return 1
    fi
  done
}

if provenance_output="$(validate_provenance "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" \
  "$REPO_ROOT/docs/assets/demo.gif" 2>&1)"; then
  pass_case "provenance committed artifact rows"
else
  fail_case "provenance committed artifact rows" "$provenance_output"
fi

provenance_negative_ok=1
for provenance_case in size sha missing duplicate counts-mismatch cidr-mismatch environment-outside commit-format date-format; do
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
    counts-mismatch)
      sed -E '/^\| plan \/ apply \/ destroy \|/s/Apply complete! Resources: [0-9]+ added/Apply complete! Resources: 1 added/' \
        "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" > "$doc_copy"
      ;;
    cidr-mismatch)
      sed '/^| command |/s#203\.0\.113\.0/24#203.0.113.128/25#' \
        "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" > "$doc_copy"
      ;;
    environment-outside)
      sed '/^| environment |/s#203\.0\.113\.0/24#203.0.114.0/24#' \
        "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" > "$doc_copy"
      ;;
    commit-format)
      sed -E '/^\| generator commit \|/s/[0-9a-f]{7}/zzzz/' \
        "$REPO_ROOT/docs/assets/DEMO_PROVENANCE.md" > "$doc_copy"
      ;;
    date-format)
      sed -E '/^\| recorded_on \|/s/[0-9]{4}-[0-9]{2}-[0-9]{2}/2026-9-6/' \
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
baseline_drift_output="$(generator_clean_check "$REPO_ROOT" "$recorded_commit" 2>&1)"
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
if generator_clean_check "$positive_clone" "$positive_commit" >/dev/null 2>&1; then
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
  if generator_clean_check "$clone" "$base_commit" >/dev/null 2>&1; then
    generator_negative_ok=0
  fi
done
unreachable_clone="$tmp_dir/generator-unreachable"
init_generator_clone "$unreachable_clone"
set +e
unreachable_output="$(generator_clean_check "$unreachable_clone" deadbee 2>&1)"
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
# General lifecycle cases model an empty Git result; the real-Git case below
# exercises the shipped generator predicate against an actual scratch clone.
for tool in vhs ffprobe ffmpeg ttyd curl jq make terraform docker aws git shasum date; do
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'tool=${0##*/}' \
    'FAKE_FAIL=; IFS= read -r FAKE_FAIL < .fake-fail || :' \
    'FAKE_VHS_MODE=normal; IFS= read -r FAKE_VHS_MODE < .fake-vhs-mode || :' \
    'FAKE_TF_STATE=empty; IFS= read -r FAKE_TF_STATE < .fake-tf-state || :' \
    'FAKE_DURATION=44.44; IFS= read -r FAKE_DURATION < .fake-duration || :' \
    'printf "%s %s\n" "$tool" "$*" >> .fake-calls.log' \
    'case "$tool" in' \
    '  vhs)' \
    '    if [ "$*" = --version ]; then echo "vhs 9.9.9-fake"; exit 0; fi' \
    '    [ "$FAKE_FAIL" != record ] || exit 1' \
    '    while IFS= read -r step; do' \
    '      [ -n "$step" ] || continue' \
    '      [ "$FAKE_VHS_MODE" != rc_missing ] || { [ "$step" != plan ] || continue; }' \
    '      rc=0' \
    '      if [ "$FAKE_VHS_MODE" = rc_nonzero ] && [ "$step" = plan ]; then rc=1; fi' \
    '      printf "%s\n" "$rc" > "$RUN/$step.rc"' \
    '    done < <(awk '\''/^# DEMO-SECTION / { print $3 }'\'' "$RUN/demo.tape")' \
    '    printf "%s\n" "localstack | s3 | running" > "$RUN/status.log"' \
    '    printf "%s\n" "Plan: 3 to add, 0 to change, 0 to destroy." > "$RUN/plan.log"' \
    '    printf "%s\n" "PASS: conftest-gate suite" > "$RUN/conftest.log"' \
    '    printf "%s\n" "Apply complete! Resources: 3 added, 0 changed, 0 destroyed." > "$RUN/apply.log"' \
    '    printf "%s\n" "aws_ecs_cluster.this" > "$RUN/statelist.log"' \
    '    printf "%s\n" "Destroy complete! Resources: 3 destroyed." > "$RUN/destroy.log"' \
    '    printf "%s\n" 1 > "$RUN/env.ok"' \
    '    printf "%s\n" "localstack | s3 | running" "Plan: 3 to add, 0 to change, 0 to destroy." "PASS: conftest-gate suite" "Apply complete! Resources: 3 added, 0 changed, 0 destroyed." "aws_ecs_cluster.this" "Destroy complete! Resources: 3 destroyed." > "$RUN/demo.txt"' \
    '    [ "$FAKE_VHS_MODE" != hygiene_path ] || printf "%s\n" /Users/example >> "$RUN/demo.txt"' \
    '    printf "%s\n" DISTINCTIVE_FAKE_GIF_PAYLOAD_20260906 > "$RUN/demo.gif"' \
    '    touch -t 203001010000 "$RUN/demo.gif"' \
    '    if [ "$FAKE_VHS_MODE" = stale ]; then touch -t 200001010000 "$RUN/demo.gif"; fi' \
    '    if [ "$FAKE_TF_STATE" = post_apply ]; then touch .fake-live; fi' \
    '    ;;' \
    '  ffprobe)' \
    '    case "$*" in *format=duration*) printf "%s\n" "$FAKE_DURATION" ;; *) printf "%s\n" 987 ;; esac' \
    '    ;;' \
    '  ffmpeg)' \
    '    if [ "$1" = -version ]; then echo "ffmpeg version 7.7.7-fake build"; exit 0; fi' \
    '    [ "$FAKE_FAIL" != inspect_decode ]' \
    '    ;;' \
    '  ttyd)' \
    '    [ "$FAKE_FAIL" != ttyd_empty ] || exit 0' \
    '    echo "ttyd version 8.8.8-fake"' \
    '    ;;' \
    '  curl)' \
    '    case "$*" in *-s\ localhost*) echo '\''{"version":"5.5.5-fake"}'\'' ;; *) : ;; esac' \
    '    ;;' \
    '  jq) echo "5.5.5-fake" ;;' \
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
    '        touch .fake-destroyed' \
    '        [ "$FAKE_FAIL" != teardown_destroy ] || exit 1' \
    '        ;;' \
    '    esac' \
    '    ;;' \
    '  terraform)' \
    '    case " $* " in' \
    '      *" state list "*)' \
    '        case "$FAKE_TF_STATE" in' \
    '          leftover) echo aws_leftover.example ;;' \
    '          teardown_nonempty) [ ! -e .fake-destroyed ] || echo aws_leftover.example ;;' \
    '          post_apply) [ ! -e .fake-live ] || { [ -e .fake-destroyed ] || echo aws_live.example; } ;;' \
    '          nostate) echo "No state file was found" >&2; exit 1 ;;' \
    '          nostate-plus-error) printf "%s\n" "No state file was found" "Error: backend unavailable" >&2; exit 1 ;;' \
    '        esac' \
    '        ;;' \
    '      *" version "*) echo "Terraform v6.6.6-fake" ;;' \
    '    esac' \
    '    ;;' \
    '  docker|aws) : ;;' \
    '  git)' \
    '    case "$*" in' \
    '      "status --porcelain --untracked-files=all --"*) printf "%s" "${FAKE_GIT_STATUS:-}" ;;' \
    '      "ls-files --others --ignored --exclude-standard -z --"*) printf "%s" "${FAKE_GIT_IGNORED:-}" ;;' \
    '      "rev-parse --short=7 HEAD") echo abc1234 ;;' \
    '      *) echo "unexpected fake git call: $*" >&2; exit 2 ;;' \
    '    esac' \
    '    ;;' \
    '  shasum) /usr/bin/shasum "$@" ;;' \
    '  date)' \
    '    [ "$*" = "-u +%F" ] || { echo "unexpected fake date call: $*" >&2; exit 2; }' \
    '    echo 2099-12-31' \
    '    ;;' \
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
  local case_root repo call_log before after output rc run_dir
  local fake_duration rewrite_key record_next
  case_root="$tmp_dir/lifecycle-$name"
  repo="$case_root/repo"
  mkdir -p "$case_root"
  cp -R "$lifecycle_template" "$repo"
  call_log="$repo/.fake-calls.log"
  fake_duration=${FAKE_CASE_DURATION:-44.44}
  : > "$call_log"
  printf '%s\n' "$fake_fail" > "$repo/.fake-fail"
  printf '%s\n' "$vhs_mode" > "$repo/.fake-vhs-mode"
  printf '%s\n' "$state_mode" > "$repo/.fake-tf-state"
  printf '%s\n' "$fake_duration" > "$repo/.fake-duration"
  case "$mutation" in
    stale-symlink)
      mkdir -p "$repo/.preview-runs/demo"
      ln -s /dev/null "$repo/.preview-runs/demo/stale.tfstate.tf"
      ;;
    missing-source)
      printf '%s\n' source > "$repo/envs/preview/migration.tfstate.tf"
      ;;
    missing-field)
      awk '!/^\| artifact sha256 \|/' "$repo/docs/assets/DEMO_PROVENANCE.md" > "$case_root/doc"
      cp "$case_root/doc" "$repo/docs/assets/DEMO_PROVENANCE.md"
      ;;
    delete-rewrite-*)
      rewrite_key=${mutation#delete-rewrite-}
      record_next="$case_root/record.next"
      awk -v key="$rewrite_key" '
        $1 == "rewrite_provenance_row" && $2 == key { removed++; next }
        { print }
        END { if (removed != 1) exit 1 }
      ' "$repo/demo/record.sh" > "$record_next"
      mv "$record_next" "$repo/demo/record.sh"
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
    OPERATOR_CIDR=203.0.113.128/25 \
    DEMO_INJECT_FAIL="$inject" \
      bash -p demo/env.sh 2>&1
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
boundary_calls="$boundary_root/.fake-calls.log"
: > "$boundary_calls"
boundary_before="$(shasum -a 256 "$boundary_root/docs/assets/demo.gif" \
  "$boundary_root/docs/assets/DEMO_PROVENANCE.md")"
set +e
boundary_output="$(cd "$boundary_root" && PATH="$fake_bin:$PATH" \
  TF_VAR_api_image=ambient AWS_REGION=eu-west-1 \
  bash demo/record.sh 2>&1)"
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

fixed_mismatch_root="$tmp_dir/lifecycle-fixed-mismatch"
cp -R "$lifecycle_template" "$fixed_mismatch_root"
fixed_mismatch_calls="$fixed_mismatch_root/.fake-calls.log"
: > "$fixed_mismatch_calls"
fixed_env_args=()
for assignment in $DEMO_ENV_FIXED; do
  fixed_env_args+=("$assignment")
done
set +e
fixed_mismatch_output="$(
  cd "$fixed_mismatch_root"
  /usr/bin/env -i \
    PATH="$fake_bin:$PATH" \
    HOME="$fixed_mismatch_root/home" \
    TMPDIR="$fixed_mismatch_root" \
    TERM=xterm \
    OPERATOR_CIDR=203.0.113.128/25 \
    "${fixed_env_args[@]}" \
    TF_WORKSPACE=qa \
      bash demo/record.sh 2>&1
)"
fixed_mismatch_rc=$?
set -e
if [ "$fixed_mismatch_rc" -ne 0 ] && [ ! -s "$fixed_mismatch_calls" ] && \
   grep -Fq 'constructed environment differs from DEMO_ENV_FIXED: TF_WORKSPACE' \
     <<< "$fixed_mismatch_output"; then
  pass_case "lifecycle fixed environment mismatch before tool calls"
else
  fail_case "lifecycle fixed environment mismatch before tool calls" "$fixed_mismatch_output"
fi

make_demo_root="$tmp_dir/make-demo-unset"
cp -R "$lifecycle_template" "$make_demo_root"
cp "$REPO_ROOT/Makefile" "$make_demo_root/Makefile"
make_demo_calls="$make_demo_root/.fake-calls.log"
: > "$make_demo_calls"
real_make="$(command -v make)"
set +e
make_demo_output="$(
  cd "$make_demo_root"
  env -u OPERATOR_CIDR \
    PATH="$fake_bin:$PATH" \
    HOME="$make_demo_root/home" \
    TMPDIR="$make_demo_root" \
    TERM=xterm \
      "$real_make" demo 2>&1
)"
make_demo_rc=$?
set -e
if [ "$make_demo_rc" -ne 0 ] && \
   ! grep -q '^curl ' "$make_demo_calls" && \
   grep -Fq 'demo: OPERATOR_CIDR unset' <<< "$make_demo_output"; then
  pass_case "make demo skips CIDR auto-detect and guard refuses unset"
else
  fail_case "make demo skips CIDR auto-detect and guard refuses unset" "$make_demo_output"
fi

real_git_bin="$tmp_dir/real-git-bin"
real_git_source="$tmp_dir/lifecycle-real-git-source"
real_git_root="$tmp_dir/lifecycle-real-git"
real_git_repo="$real_git_root/repo"
real_git_calls="$real_git_repo/.fake-calls.log"
mkdir -p "$real_git_bin" "$real_git_root"
for tool in vhs ffprobe ffmpeg ttyd curl jq make terraform docker aws shasum; do
  ln -s "$fake_bin/$tool" "$real_git_bin/$tool"
done
cp -R "$lifecycle_template" "$real_git_source"
(
  cd "$real_git_source"
  git init -q
  git add -A
  git -c user.name=t -c user.email=t@example.com commit -q -m x
)
git clone -q "$real_git_source" "$real_git_repo"
printf '%s\n' mutation > "$real_git_repo/demo/untracked.txt"
: > "$real_git_calls"
printf '\n' > "$real_git_repo/.fake-fail"
printf '%s\n' normal > "$real_git_repo/.fake-vhs-mode"
printf '%s\n' empty > "$real_git_repo/.fake-tf-state"
printf '%s\n' 44.44 > "$real_git_repo/.fake-duration"
real_git_before="$(shasum -a 256 "$real_git_repo/docs/assets/demo.gif" \
  "$real_git_repo/docs/assets/DEMO_PROVENANCE.md")"
set +e
real_git_output="$(
  cd "$real_git_repo"
  PATH="$real_git_bin:$PATH" \
  HOME="$real_git_root/home" \
  TMPDIR="$real_git_root" \
  TERM=xterm \
  OPERATOR_CIDR=203.0.113.128/25 \
    bash -p demo/env.sh 2>&1
)"
real_git_rc=$?
set -e
real_git_after="$(shasum -a 256 "$real_git_repo/docs/assets/demo.gif" \
  "$real_git_repo/docs/assets/DEMO_PROVENANCE.md")"
if [ "$real_git_rc" -ne 0 ] && [ "$real_git_before" = "$real_git_after" ] && \
   grep -Fq 'generator tree dirty; commit before recording' <<< "$real_git_output" && \
   ! grep -Eq '^(make|terraform) ' "$real_git_calls"; then
  pass_case "lifecycle real git rejects untracked generator before make or terraform"
else
  fail_case "lifecycle real git rejects untracked generator before make or terraform" \
    "$real_git_output"
fi

lifecycle_failures_ok=1
for lifecycle_case in \
  'preflight-leftover||normal|leftover||none|environment demo already has state' \
  'preflight-nostate-plus-error||normal|nostate-plus-error||none|terraform state list failed' \
  'preflight-versions|ttyd_empty|normal|empty||none|tool version capture incomplete' \
  'preflight-render-nonregular||normal|empty||stale-symlink|non-regular terraform input in execution root: stale.tfstate.tf' \
  'preflight-render-missing||normal|empty||missing-source|execution root differs from envs/preview: migration.tfstate.tf' \
  'record|record|normal|empty||none|vhs failed' \
  'assert-rc-nonzero||rc_nonzero|empty||none|plan.rc was not 0' \
  'assert-rc-missing||rc_missing|empty||none|step rc set differs from tape markers' \
  'inspect-stale||stale|empty||none|demo.gif mtime predates run start' \
  'inspect-duration||normal|empty||none|demo.gif duration' \
  'inspect-hygiene||hygiene_path|empty||none|demo.txt contains environment-specific text (path/access-key/email pattern); not publishing' \
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
  if [ "$name" = preflight-render-nonregular ] && \
     grep -Eq '^terraform .* init' "$LIFECYCLE_CALLS"; then
    case_ok=0
  fi
  if [ "$case_ok" -eq 1 ]; then
    pass_case "lifecycle $name"
  else
    lifecycle_failures_ok=0
    fail_case "lifecycle $name" "unexpected lifecycle or teardown count"
  fi
done

run_lifecycle state-nostate '' normal nostate '' none
nostate_state_calls="$(grep -c '^terraform .* state list$' "$LIFECYCLE_CALLS" || true)"
if [ "$LIFECYCLE_RC" -eq 0 ] && [ "$nostate_state_calls" -eq 3 ] && \
   grep -Fq 'teardown:ok' "$LIFECYCLE_RUN/lifecycle.log" && \
   grep -Fq 'publish:ok' "$LIFECYCLE_RUN/lifecycle.log"; then
  pass_case "lifecycle no-state-only diagnostic is empty in preflight and teardown"
else
  lifecycle_failures_ok=0
  fail_case "lifecycle no-state-only diagnostic is empty in preflight and teardown" \
    "$LIFECYCLE_OUTPUT"
fi

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
     "$LIFECYCLE_REPO/docs/assets/demo.gif" >/dev/null 2>&1 && \
   provenance_matches_manifest "$LIFECYCLE_REPO/docs/assets/DEMO_PROVENANCE.md" \
     "$LIFECYCLE_RUN/provenance.env" >/dev/null 2>&1; then
  pass_case "lifecycle success publishes every run-derived provenance row after teardown"
else
  lifecycle_failures_ok=0
  fail_case "lifecycle success publishes every run-derived provenance row after teardown" \
    "$LIFECYCLE_OUTPUT"
fi
if [ -s "$LIFECYCLE_CALLS" ] && \
   ! grep '^curl ' "$LIFECYCLE_CALLS" | grep -vF 'localhost:4566' >/dev/null; then
  pass_case "lifecycle fake-only curl network boundary"
else
  lifecycle_failures_ok=0
  fail_case "lifecycle fake-only curl network boundary"
fi

rewrite_deletion_ok=1
for rewrite_key in recorded_from recorded_on generator_commit recorder command environment \
  plan_apply_destroy artifact artifact_sha256; do
  run_lifecycle "rewrite-deleted-$rewrite_key" '' normal empty '' \
    "delete-rewrite-$rewrite_key"
  if [ "$LIFECYCLE_RC" -ne 0 ] || \
     provenance_matches_manifest "$LIFECYCLE_REPO/docs/assets/DEMO_PROVENANCE.md" \
       "$LIFECYCLE_RUN/provenance.env" >/dev/null 2>&1; then
    rewrite_deletion_ok=0
  fi
done
if [ "$rewrite_deletion_ok" -eq 1 ]; then
  pass_case "lifecycle provenance exact-row deletion mutation table (9 mappings)"
else
  lifecycle_failures_ok=0
  fail_case "lifecycle provenance exact-row deletion mutation table (9 mappings)"
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
