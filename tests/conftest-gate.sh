#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POLICY="$REPO_ROOT/policy"
FIXTURES="$REPO_ROOT/tests/fixtures/conftest"

pass_count=0
pass() {
  pass_count=$((pass_count + 1))
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for fixture in good-plan.json bad-plan.json; do
  if [ ! -f "$FIXTURES/$fixture" ]; then
    fail "$FIXTURES/$fixture is missing; record it with make record-conftest-fixtures"
  fi
done

if ! verify_output="$(conftest verify --policy "$POLICY" 2>&1)"; then
  fail "conftest verify failed: $verify_output"
fi
pass "Rego unit tests"

if ! good_output="$(conftest test --policy "$POLICY" "$FIXTURES/good-plan.json" 2>&1)"; then
  fail "good plan was denied: $good_output"
fi
pass "good plan passes"

if grep -Fq 'aws_security_group.alb' <<< "$good_output"; then
  fail "good plan output named the planned ALB security group"
fi
pass "good plan does not report the planned ALB security group"

set +e
bad_output="$(conftest test --policy "$POLICY" "$FIXTURES/bad-plan.json" 2>&1)"
bad_rc=$?
set -e
if [ "$bad_rc" -ne 1 ]; then
  fail "bad plan must exit 1, got $bad_rc: $bad_output"
fi
pass "bad plan is denied"

for address in \
  aws_s3_bucket.open \
  aws_s3_bucket.half \
  aws_s3_bucket.data \
  aws_security_group.open \
  aws_security_group.alb \
  aws_security_group.zero_lb \
  aws_vpc_security_group_ingress_rule.open \
  aws_security_group_rule.legacy_open \
  aws_default_security_group.default; do
  if ! grep -Fq "$address" <<< "$bad_output"; then
    fail "bad plan output did not name $address: $bad_output"
  fi
  pass "bad plan reports $address"
done

if grep -Fq 'aws_s3_bucket.database' <<< "$bad_output"; then
  fail "bad plan output named protected aws_s3_bucket.database"
fi
pass "bad plan does not report aws_s3_bucket.database"

echo "PASS: conftest-gate suite ($pass_count cases)"
