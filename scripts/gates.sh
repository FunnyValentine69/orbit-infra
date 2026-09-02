#!/usr/bin/env bash
# Runs the policy gates in order (validate -> lint -> test -> no-nat-gateway)
# and prints a one-line PASS/FAIL summary per gate. Exits non-zero on any
# failure. CI calls this from Phase 3 onward (terraform-plan.yml).
set -u

cd "$(dirname "$0")/.." || exit 1

status=0

log_dir="$(mktemp -d)"
trap 'rm -rf "$log_dir"' EXIT

run_gate() {
  local name="$1"
  shift
  if make "$name" >"$log_dir/gates-$name.log" 2>&1; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    cat "$log_dir/gates-$name.log"
    status=1
  fi
}

run_gate validate
run_gate lint
run_gate test

# No module or environment may declare a NAT gateway (ADR 0002 no-NAT
# invariant); terraform test cannot assert against an absent resource
# type, so this is checked structurally instead.
no_nat_log="$log_dir/no-nat-gateway.log"
command grep -rn aws_nat_gateway modules/ envs/ --include=*.tf >"$no_nat_log" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "FAIL: no-nat-gateway"
  cat "$no_nat_log"
  status=1
elif [ "$rc" -eq 1 ]; then
  echo "PASS: no-nat-gateway"
else
  echo "FAIL: no-nat-gateway (grep error, exit $rc)"
  cat "$no_nat_log"
  status=1
fi
rm -f "$no_nat_log"

exit "$status"
