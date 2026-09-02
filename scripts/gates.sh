#!/usr/bin/env bash
# Runs the policy gates in order (validate -> lint -> test -> no-nat-gateway)
# and prints a one-line PASS/FAIL summary per gate. Exits non-zero on any
# failure. CI calls this from Phase 3 onward (terraform-plan.yml).
set -u

cd "$(dirname "$0")/.." || exit 1

status=0

run_gate() {
  local name="$1"
  shift
  if make "$name" >/tmp/gates-"$name".log 2>&1; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    cat /tmp/gates-"$name".log
    status=1
  fi
}

run_gate validate
run_gate lint
run_gate test

# No module or environment may declare a NAT gateway (ADR 0002 no-NAT
# invariant); terraform test cannot assert against an absent resource
# type, so this is checked structurally instead.
if command grep -rn aws_nat_gateway modules/ envs/ --include=*.tf >/tmp/gates-no-nat-gateway.log 2>&1; then
  echo "FAIL: no-nat-gateway"
  cat /tmp/gates-no-nat-gateway.log
  status=1
else
  echo "PASS: no-nat-gateway"
fi

exit "$status"
