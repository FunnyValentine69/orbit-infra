#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
isolated_repo="$tmp_dir/repo"
mkdir -p "$isolated_repo/bootstrap"
cp "$REPO_ROOT/bootstrap/policy-size-check.sh" "$isolated_repo/bootstrap/"
cp "$REPO_ROOT"/bootstrap/*.tf "$isolated_repo/bootstrap/"
cp "$REPO_ROOT/bootstrap/localstack.backend_override.tf.example" "$isolated_repo/bootstrap/"
override_file="$isolated_repo/bootstrap/backend_override.tf"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

atomic_override_copy='( set -o noclobber; cat bootstrap/localstack.backend_override.tf.example > bootstrap/backend_override.tf )'
if ! grep -Fq "$atomic_override_copy" "$isolated_repo/bootstrap/policy-size-check.sh"; then
  echo "policy-size override copy must use a noclobber subshell" >&2
  exit 1
fi
echo "PASS: structural noclobber override creation"

mkdir -p "$tmp_dir/bin"
cat > "$tmp_dir/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_TERRAFORM_CALL_LOG:?}"

case "$*" in
  *" init "*|*" init") stage=init ;;
  *" plan "*) stage=plan ;;
  *" show "*) stage=show ;;
  *) echo "unexpected terraform call: $*" >&2; exit 2 ;;
esac

if [ "$stage" = "${FAKE_TERRAFORM_FAIL_STAGE:?}" ]; then
  if [ "$stage" = plan ]; then
    echo "plan diagnostic: dial tcp localhost:4566: connect: connection refused" >&2
  else
    echo "$stage diagnostic" >&2
  fi
  exit 1
fi

if [ "$stage" = show ]; then
  cat "${FAKE_TERRAFORM_PLAN_JSON:?}"
fi
EOF
chmod +x "$tmp_dir/bin/terraform"

# Group 1: an operator-owned override is an immediate refusal. Terraform must
# not run, and the sentinel must remain present and byte-identical.
sentinel="$tmp_dir/backend-override-sentinel.tf"
printf '%s\n' '# sentinel: operator-owned override' > "$sentinel"
cp "$sentinel" "$override_file"
terraform_call_log="$tmp_dir/terraform-calls.log"
: > "$terraform_call_log"
set +e
override_output="$(
  PATH="$tmp_dir/bin:$PATH" \
    FAKE_TERRAFORM_CALL_LOG="$terraform_call_log" \
    FAKE_TERRAFORM_FAIL_STAGE=none \
    FAKE_TERRAFORM_PLAN_JSON="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
    POLICY_SIZE_TF_DATA_DIR="$tmp_dir/policy-size-tfdata" \
    "$isolated_repo/bootstrap/policy-size-check.sh" 2>&1
)"
override_rc=$?
set -e
if [ "$override_rc" -eq 0 ] || \
   ! grep -Fq 'bootstrap/backend_override.tf already exists; refusing to overwrite or remove it' <<< "$override_output"; then
  echo "policy-size must refuse an existing backend override immediately: $override_output" >&2
  exit 1
fi
if [ -s "$terraform_call_log" ]; then
  echo "policy-size must make zero Terraform calls when an override exists" >&2
  exit 1
fi
if [ ! -f "$override_file" ] || ! cmp -s "$sentinel" "$override_file"; then
  echo "policy-size must leave the existing override byte-identical and present" >&2
  exit 1
fi
rm -f "$override_file"

dangling_target="../operator-owned-missing-backend.tf"
ln -s "$dangling_target" "$override_file"
if [ -e "$override_file" ] || [ ! -L "$override_file" ]; then
  echo "policy-size dangling-symlink fixture must start dangling" >&2
  exit 1
fi
: > "$terraform_call_log"
set +e
dangling_output="$(
  PATH="$tmp_dir/bin:$PATH" \
    FAKE_TERRAFORM_CALL_LOG="$terraform_call_log" \
    FAKE_TERRAFORM_FAIL_STAGE=none \
    FAKE_TERRAFORM_PLAN_JSON="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
    POLICY_SIZE_TF_DATA_DIR="$tmp_dir/policy-size-tfdata" \
    "$isolated_repo/bootstrap/policy-size-check.sh" 2>&1
)"
dangling_rc=$?
set -e
if [ "$dangling_rc" -eq 0 ] || \
   ! grep -Fq 'bootstrap/backend_override.tf already exists; refusing to overwrite or remove it' <<< "$dangling_output"; then
  echo "policy-size must refuse a dangling backend override symlink immediately: $dangling_output" >&2
  exit 1
fi
if [ -s "$terraform_call_log" ]; then
  echo "policy-size must make zero Terraform calls when a dangling override symlink exists" >&2
  exit 1
fi
if [ -e "$override_file" ] || [ ! -L "$override_file" ] || \
   [ "$(readlink "$override_file")" != "$dangling_target" ]; then
  echo "policy-size must leave the dangling override symlink present with its target unchanged" >&2
  exit 1
fi
echo "PASS: sentinel dangling-backend-override -> $(grep -m1 '^FAIL:' <<< "$dangling_output")"
rm -f "$override_file"

# Group 2: with no existing override, the real script and cleanup run; only
# Terraform is replaced so each path is deterministic without LocalStack.
for failure_case in \
  "init|init diagnostic" \
  "plan|plan diagnostic" \
  "show|show diagnostic"; do
  failure_stage="${failure_case%%|*}"
  expected_diagnostic="${failure_case#*|}"
  set +e
  policy_output="$(
    PATH="$tmp_dir/bin:$PATH" \
      FAKE_TERRAFORM_CALL_LOG="$terraform_call_log" \
      FAKE_TERRAFORM_FAIL_STAGE="$failure_stage" \
      FAKE_TERRAFORM_PLAN_JSON="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      POLICY_SIZE_TF_DATA_DIR="$tmp_dir/policy-size-tfdata" \
      "$isolated_repo/bootstrap/policy-size-check.sh" 2>&1
  )"
  policy_rc=$?
  set -e
  if [ "$policy_rc" -eq 0 ] || ! grep -Fq "$expected_diagnostic" <<< "$policy_output"; then
    echo "policy-size must print $failure_stage diagnostics before cleanup: $policy_output" >&2
    exit 1
  fi
  if [ "$failure_stage" = plan ] && \
     ! grep -Fq 'requires a reachable LocalStack endpoint (AWS_ENDPOINT_URL)' <<< "$policy_output"; then
    echo "policy-size connection failures must name the LocalStack endpoint contract: $policy_output" >&2
    exit 1
  fi
  if [ -e "$override_file" ]; then
    echo "policy-size must remove its temporary override after $failure_stage failure" >&2
    exit 1
  fi
done

rendered_plan="$tmp_dir/rendered-plan.json"
set +e
success_output="$(
  PATH="$tmp_dir/bin:$PATH" \
    FAKE_TERRAFORM_CALL_LOG="$terraform_call_log" \
    FAKE_TERRAFORM_FAIL_STAGE=none \
    FAKE_TERRAFORM_PLAN_JSON="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
    POLICY_SIZE_TF_DATA_DIR="$tmp_dir/policy-size-tfdata" \
    POLICY_SIZE_PLAN_JSON_OUT="$rendered_plan" \
    "$isolated_repo/bootstrap/policy-size-check.sh" 2>&1
)"
success_rc=$?
set -e
if [ "$success_rc" -ne 0 ] || ! grep -Fq 'PASS: aws_iam_policy.task_boundary' <<< "$success_output"; then
  echo "policy-size success path must validate the complete authored plan: $success_output" >&2
  exit 1
fi
if [ -e "$override_file" ]; then
  echo "policy-size must remove its temporary override after success" >&2
  exit 1
fi
if ! cmp -s "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" "$rendered_plan"; then
  echo "POLICY_SIZE_PLAN_JSON_OUT must copy the rendered plan before cleanup" >&2
  exit 1
fi

# Exercise the real gates script in an isolated tree. The fakes replace the
# expensive/external commands while preserving the default and skip behavior.
gate_root="$tmp_dir/gates-root"
mkdir -p "$gate_root/scripts" "$gate_root/bootstrap" "$gate_root/modules" "$gate_root/envs" "$gate_root/bin"
cp "$REPO_ROOT/scripts/gates.sh" "$gate_root/scripts/gates.sh"
cat > "$gate_root/bin/make" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$gate_root/bootstrap/policy-size-check.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo invoked >> "${POLICY_SIZE_CALL_LOG:?}"
EOF
chmod +x "$gate_root/bin/make" "$gate_root/bootstrap/policy-size-check.sh"

policy_size_call_log="$tmp_dir/policy-size-calls.log"
: > "$policy_size_call_log"
default_gates_output="$(
  cd "$gate_root"
  env -u GATES_POLICY_SIZE PATH="$gate_root/bin:$PATH" \
    POLICY_SIZE_CALL_LOG="$policy_size_call_log" bash scripts/gates.sh
)"
if ! grep -Fq 'PASS: policy-size' <<< "$default_gates_output" || \
   [ "$(wc -l < "$policy_size_call_log" | tr -d ' ')" != 1 ]; then
  echo "gates.sh must require and run policy-size by default: $default_gates_output" >&2
  exit 1
fi

: > "$policy_size_call_log"
skipped_gates_output="$(
  cd "$gate_root"
  PATH="$gate_root/bin:$PATH" POLICY_SIZE_CALL_LOG="$policy_size_call_log" \
    GATES_POLICY_SIZE=skip bash scripts/gates.sh
)"
if ! grep -Fq 'SKIP: policy-size (needs LocalStack; run in plan-localstack)' <<< "$skipped_gates_output" || \
   [ -s "$policy_size_call_log" ]; then
  echo "GATES_POLICY_SIZE=skip must skip policy-size explicitly: $skipped_gates_output" >&2
  exit 1
fi

plan_workflow="$REPO_ROOT/.github/workflows/terraform-plan.yml"
plan_localstack_job="$(sed -n '/^  plan-localstack:/,/^  infracost:/p' "$plan_workflow")"
health_line="$(grep -n 'name: Wait for LocalStack health' <<< "$plan_localstack_job" | cut -d: -f1)"
policy_size_line="$(grep -n 'bootstrap/policy-size-check.sh' <<< "$plan_localstack_job" | cut -d: -f1)"
if [ -z "$health_line" ] || [ -z "$policy_size_line" ] || [ "$policy_size_line" -le "$health_line" ]; then
  echo "terraform-plan plan-localstack must run policy-size after the LocalStack health wait" >&2
  exit 1
fi

echo "PASS: policy-size contracts (2 groups: existing override, no existing override)"
