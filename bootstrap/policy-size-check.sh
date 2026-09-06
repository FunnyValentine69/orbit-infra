#!/usr/bin/env bash
# Renders a LocalStack plan of bootstrap/ and checks every planned IAM
# policy document against AWS's size quotas:
#   - aws_iam_policy (customer-managed): 6,144 non-whitespace characters
#   - aws_iam_role_policy (inline), aggregated per role: 10,240
#     non-whitespace characters
# Whitespace is stripped before counting, matching how AWS counts policy
# document size (PR#2 Tier 2b F3).
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

MANAGED_LIMIT=6144
INLINE_AGGREGATE_LIMIT=10240

if [ -e bootstrap/backend_override.tf ] || [ -L bootstrap/backend_override.tf ]; then
  echo "FAIL: bootstrap/backend_override.tf already exists; refusing to overwrite or remove it" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
override_created=0
# Invoked indirectly by the EXIT trap below.
# shellcheck disable=SC2329
cleanup() {
  if [ "$override_created" = 1 ]; then
    rm -f bootstrap/backend_override.tf
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT
if ! ( set -o noclobber; cat bootstrap/localstack.backend_override.tf.example > bootstrap/backend_override.tf ); then
  echo "FAIL: bootstrap/backend_override.tf already exists; refusing to overwrite or remove it" >&2
  exit 1
fi
override_created=1

export TF_DATA_DIR="${POLICY_SIZE_TF_DATA_DIR:-.terraform-localstack}"
if ! terraform -chdir=bootstrap init -reconfigure -input=false >"$tmp_dir/init.log" 2>&1; then
  cat "$tmp_dir/init.log" >&2
  exit 1
fi
if ! terraform -chdir=bootstrap plan -var target=localstack -var budget_email=unused \
  -out="$tmp_dir/plan.out" >"$tmp_dir/plan.log" 2>&1; then
  cat "$tmp_dir/plan.log" >&2
  if grep -Eiq 'connection (refused|reset)|could not connect|failed to connect|connect:|dial tcp' "$tmp_dir/plan.log"; then
    echo "HINT: policy-size requires a reachable LocalStack endpoint (AWS_ENDPOINT_URL)." >&2
  fi
  exit 1
fi
if ! terraform -chdir=bootstrap show -json "$tmp_dir/plan.out" >"$tmp_dir/show.log" 2>&1; then
  cat "$tmp_dir/show.log" >&2
  exit 1
fi
mv "$tmp_dir/show.log" "$tmp_dir/plan.json"
if [ -n "${POLICY_SIZE_PLAN_JSON_OUT:-}" ]; then
  cp "$tmp_dir/plan.json" "$POLICY_SIZE_PLAN_JSON_OUT"
fi

status=0

# Expected resource counts are derived from the source, not hardcoded, so
# the assertion below tracks bootstrap/*.tf rather than a stale number.
expected_managed=$(grep -h -c '^resource "aws_iam_policy" "' bootstrap/*.tf | awk -F: '{sum+=$1} END {print sum+0}')
expected_inline_resources=$(grep -h -c '^resource "aws_iam_role_policy" "' bootstrap/*.tf | awk -F: '{sum+=$1} END {print sum+0}')

# Customer-managed aws_iam_policy resources: 6,144 non-whitespace char cap.
if ! jq -r '
  .planned_values.root_module.resources[]?
  | select(.type == "aws_iam_policy")
  | [.address, .values.policy] | @tsv
' "$tmp_dir/plan.json" >"$tmp_dir/managed.tsv"; then
  echo "FAIL: jq failed while extracting aws_iam_policy documents from the plan" >&2
  exit 1
fi

managed_checked=0
while IFS=$'\t' read -r address policy_json; do
  [ -z "$address" ] && continue
  if [ -z "$policy_json" ] || [ "$policy_json" = "null" ]; then
    echo "FAIL: $address policy document is not known at plan time; reference ARNs deterministically (see bootstrap/README.md)"
    status=1
    continue
  fi
  managed_checked=$((managed_checked + 1))
  stripped_len=$(printf '%s' "$policy_json" | tr -d '[:space:]' | wc -c | tr -d ' ')
  if [ "$stripped_len" -gt "$MANAGED_LIMIT" ]; then
    echo "FAIL: $address is ${stripped_len} non-whitespace chars (limit ${MANAGED_LIMIT})"
    status=1
  else
    echo "PASS: $address is ${stripped_len} non-whitespace chars (limit ${MANAGED_LIMIT})"
  fi
done <"$tmp_dir/managed.tsv"

if [ "$managed_checked" -ne "$expected_managed" ]; then
  echo "FAIL: checked ${managed_checked} aws_iam_policy resources, expected ${expected_managed} (grep count of bootstrap/*.tf)"
  status=1
fi

# Inline aws_iam_role_policy resources: 10,240 non-whitespace char cap,
# aggregated per role (a role may carry more than one inline policy, e.g.
# plan-reader's deny + state documents; AWS enforces the cap on the sum).
if ! jq -r '
  .planned_values.root_module.resources[]?
  | select(.type == "aws_iam_role_policy")
  | [.address, .values.role, .values.policy] | @tsv
' "$tmp_dir/plan.json" >"$tmp_dir/inline.tsv"; then
  echo "FAIL: jq failed while extracting aws_iam_role_policy documents from the plan" >&2
  exit 1
fi

: >"$tmp_dir/inline-lens.tsv"
inline_checked=0
while IFS=$'\t' read -r address role policy_json; do
  [ -z "$address" ] && continue
  if [ -z "$role" ] || [ "$role" = "null" ] || [ -z "$policy_json" ] || [ "$policy_json" = "null" ]; then
    echo "FAIL: $address policy document is not known at plan time; reference ARNs deterministically (see bootstrap/README.md)"
    status=1
    continue
  fi
  inline_checked=$((inline_checked + 1))
  len=$(printf '%s' "$policy_json" | tr -d '[:space:]' | wc -c | tr -d ' ')
  printf '%s\t%s\n' "$role" "$len" >>"$tmp_dir/inline-lens.tsv"
done <"$tmp_dir/inline.tsv"

if [ "$inline_checked" -ne "$expected_inline_resources" ]; then
  echo "FAIL: checked ${inline_checked} aws_iam_role_policy resources, expected ${expected_inline_resources} (grep count of bootstrap/*.tf)"
  status=1
fi

if ! awk -F'\t' '{sum[$1]+=$2} END {for (r in sum) print r"\t"sum[r]}' "$tmp_dir/inline-lens.tsv" >"$tmp_dir/inline-sums.tsv"; then
  echo "FAIL: awk failed while aggregating inline policy lengths per role" >&2
  exit 1
fi

while IFS=$'\t' read -r role_name total_len; do
  [ -z "$role_name" ] && continue
  if [ "$total_len" -gt "$INLINE_AGGREGATE_LIMIT" ]; then
    echo "FAIL: role ${role_name} inline-policy aggregate is ${total_len} non-whitespace chars (limit ${INLINE_AGGREGATE_LIMIT})"
    status=1
  else
    echo "PASS: role ${role_name} inline-policy aggregate is ${total_len} non-whitespace chars (limit ${INLINE_AGGREGATE_LIMIT})"
  fi
done <"$tmp_dir/inline-sums.tsv"

exit "$status"
