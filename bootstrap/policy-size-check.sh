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

tmp_dir="$(mktemp -d)"
cp bootstrap/localstack.backend_override.tf.example bootstrap/backend_override.tf
trap 'rm -f bootstrap/backend_override.tf; rm -rf "$tmp_dir"' EXIT

export TF_DATA_DIR=.terraform-localstack
terraform -chdir=bootstrap init -reconfigure -input=false >"$tmp_dir/init.log" 2>&1
terraform -chdir=bootstrap plan -var target=localstack -var budget_email=unused \
  -out="$tmp_dir/plan.out" >"$tmp_dir/plan.log" 2>&1
terraform -chdir=bootstrap show -json "$tmp_dir/plan.out" >"$tmp_dir/plan.json"

status=0

# Customer-managed aws_iam_policy resources: 6,144 non-whitespace char cap.
while IFS=$'\t' read -r address policy_json; do
  [ -z "$address" ] && continue
  stripped_len=$(printf '%s' "$policy_json" | tr -d '[:space:]' | wc -c | tr -d ' ')
  if [ "$stripped_len" -gt "$MANAGED_LIMIT" ]; then
    echo "FAIL: $address is ${stripped_len} non-whitespace chars (limit ${MANAGED_LIMIT})"
    status=1
  else
    echo "PASS: $address is ${stripped_len} non-whitespace chars (limit ${MANAGED_LIMIT})"
  fi
done < <(jq -r '
  .planned_values.root_module.resources[]?
  | select(.type == "aws_iam_policy")
  | [.address, .values.policy] | @tsv
' "$tmp_dir/plan.json")

# Inline aws_iam_role_policy resources: 10,240 non-whitespace char cap,
# aggregated per role (a role may carry more than one inline policy, e.g.
# plan-reader's deny + state documents; AWS enforces the cap on the sum).
: >"$tmp_dir/inline-lens.tsv"
while IFS=$'\t' read -r role policy_json; do
  [ -z "$role" ] && continue
  len=$(printf '%s' "$policy_json" | tr -d '[:space:]' | wc -c | tr -d ' ')
  printf '%s\t%s\n' "$role" "$len" >>"$tmp_dir/inline-lens.tsv"
done < <(jq -r '
  .planned_values.root_module.resources[]?
  | select(.type == "aws_iam_role_policy")
  | [.values.role, .values.policy] | @tsv
' "$tmp_dir/plan.json")

while IFS=$'\t' read -r role_name total_len; do
  [ -z "$role_name" ] && continue
  if [ "$total_len" -gt "$INLINE_AGGREGATE_LIMIT" ]; then
    echo "FAIL: role ${role_name} inline-policy aggregate is ${total_len} non-whitespace chars (limit ${INLINE_AGGREGATE_LIMIT})"
    status=1
  else
    echo "PASS: role ${role_name} inline-policy aggregate is ${total_len} non-whitespace chars (limit ${INLINE_AGGREGATE_LIMIT})"
  fi
done < <(awk -F'\t' '{sum[$1]+=$2} END {for (r in sum) print r"\t"sum[r]}' "$tmp_dir/inline-lens.tsv")

exit "$status"
