#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
cat > "$tmp_dir/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

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
  echo '{"planned_values":{"root_module":{"resources":[]}}}'
fi
EOF
chmod +x "$tmp_dir/bin/terraform"

# The real policy-size script and its cleanup run; only Terraform is replaced
# so each failure path is deterministic and does not require LocalStack.
for failure_case in \
  "init|init diagnostic" \
  "plan|plan diagnostic" \
  "show|show diagnostic"; do
  failure_stage="${failure_case%%|*}"
  expected_diagnostic="${failure_case#*|}"
  set +e
  policy_output="$(
    PATH="$tmp_dir/bin:$PATH" \
      FAKE_TERRAFORM_FAIL_STAGE="$failure_stage" \
      POLICY_SIZE_TF_DATA_DIR="$tmp_dir/policy-size-tfdata" \
      "$REPO_ROOT/bootstrap/policy-size-check.sh" 2>&1
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
done

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

echo "PASS: policy-size contracts"
