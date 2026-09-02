#!/usr/bin/env bash
# Runs the policy gates in order (validate -> lint -> test) and prints a
# one-line PASS/FAIL summary per gate. Exits non-zero on any failure.
# This is what CI calls in P3-1.
set -u

cd "$(dirname "$0")/.."

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

exit "$status"
