#!/usr/bin/env bash
# Emit the canonical P5-19 IAM statement inventory and principal bindings
# from a post-bootstrap-apply Terraform plan JSON document.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <plan.json>" >&2
  exit 2
fi

plan_json="$1"
if [ ! -f "$plan_json" ]; then
  echo "FAIL: plan JSON not found: $plan_json" >&2
  exit 1
fi
if ! jq -e '.planned_values.root_module.resources | type == "array"' "$plan_json" >/dev/null 2>&1; then
  echo "FAIL: invalid Terraform plan JSON: planned_values.root_module.resources is missing" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

core_documents=(
  aws_iam_role_policy.plan_reader_deny
  aws_iam_role_policy.plan_reader_state
  aws_iam_policy.task_boundary
  aws_iam_policy.deployer_state
  aws_iam_policy.deployer_ec2
  aws_iam_policy.deployer_elb_ecs
  aws_iam_policy.deployer_data
  aws_iam_policy.deployer_iam
  aws_iam_policy.deployer_guard
  aws_iam_role_policy.publisher
)
trust_roles=(plan_reader deployer publisher)

managed_count="$(jq '[.planned_values.root_module.resources[]? | select(.type == "aws_iam_policy")] | length' "$plan_json")"
inline_count="$(jq '[.planned_values.root_module.resources[]? | select(.type == "aws_iam_role_policy")] | length' "$plan_json")"
attachment_count="$(jq '[.planned_values.root_module.resources[]? | select(.type == "aws_iam_role_policy_attachment")] | length' "$plan_json")"
if [ "$managed_count" -ne 7 ]; then
  echo "FAIL: expected 7 aws_iam_policy resources, found $managed_count" >&2
  exit 1
fi
if [ "$inline_count" -ne 3 ]; then
  echo "FAIL: expected 3 aws_iam_role_policy resources, found $inline_count" >&2
  exit 1
fi
if [ "$attachment_count" -ne 7 ]; then
  echo "FAIL: expected 7 aws_iam_role_policy_attachment resources, found $attachment_count" >&2
  exit 1
fi

# The single-quoted jq program intentionally prevents shell interpolation.
# shellcheck disable=SC2016
canonical_statements='def sortkeys:
    if type == "object" then
      to_entries | sort_by(.key) | map({key, value: (.value | sortkeys)}) | from_entries
    elif type == "array" then map(sortkeys)
    else .
    end;
  def array: if type == "array" then sort else [.] end;
  def named_array($name): {($name): .[$name] | array};
  def principal:
    if has("Principal") then
      {Principal: (.Principal | with_entries(.value |= array))}
    elif has("NotPrincipal") then
      {NotPrincipal: (.NotPrincipal | with_entries(.value |= array))}
    else "n/a"
    end;
  def action:
    if has("Action") then named_array("Action")
    elif has("NotAction") then named_array("NotAction")
    else error("statement has neither Action nor NotAction")
    end;
  def resource:
    if has("Resource") then named_array("Resource")
    elif has("NotResource") then named_array("NotResource")
    else "n/a"
    end;
  def condition:
    if has("Condition") then
      .Condition | with_entries(.value |= with_entries(.value |= array))
    else "none"
    end;
  .Statement
  | if type == "array" then . else [.] end
  | to_entries[]
  | .value as $statement
  | [$document,
     ($key_prefix + ($statement.Sid // (.key | tostring))),
     $statement.Effect,
     ($statement | principal | if type == "string" then . else sortkeys | tojson end),
     ($statement | action | tojson),
     ($statement | resource | if type == "string" then . else tojson end),
     ($statement | condition | if type == "string" then . else sortkeys | tojson end)]
  | @tsv'

: >"$tmp_dir/statements.tsv"
for address in "${core_documents[@]}"; do
  policy="$(jq -r --arg address "$address" '
    [.planned_values.root_module.resources[]? | select(.address == $address)]
    | if length == 1 then .[0].values.policy // empty else empty end
  ' "$plan_json")"
  if [ -z "$policy" ] || [ "$policy" = "null" ]; then
    echo "FAIL: $address policy document is null or unknown" >&2
    exit 1
  fi
  if ! jq -Ser --arg document "$address" --arg key_prefix "" \
    "$canonical_statements" <<<"$policy" >>"$tmp_dir/statements.tsv"; then
    echo "FAIL: could not canonicalise $address policy document" >&2
    exit 1
  fi
done

kms_policy="$(jq -r '
  [.planned_values.root_module.resources[]? | select(.address == "aws_kms_key.signing")]
  | if length == 1 then .[0].values.policy // empty else empty end
' "$plan_json")"
if [ -z "$kms_policy" ] || [ "$kms_policy" = "null" ]; then
  echo "FAIL: aws_kms_key.signing policy is missing or unknown" >&2
  exit 1
fi
if ! jq -Ser --arg document "aws_kms_key.signing" --arg key_prefix "" \
  "$canonical_statements" <<<"$kms_policy" >>"$tmp_dir/statements.tsv"; then
  echo "FAIL: could not canonicalise aws_kms_key.signing policy" >&2
  exit 1
fi

trust_count="$(jq '[.planned_values.root_module.resources[]? | select(.type == "aws_iam_role")] | length' "$plan_json")"
if [ "$trust_count" -ne 3 ]; then
  echo "FAIL: expected 3 aws_iam_role resources, found $trust_count" >&2
  exit 1
fi
for role in "${trust_roles[@]}"; do
  trust_policy="$(jq -r --arg address "aws_iam_role.$role" '
    [.planned_values.root_module.resources[]? | select(.address == $address)]
    | if length == 1 then .[0].values.assume_role_policy // empty else empty end
  ' "$plan_json")"
  if [ -z "$trust_policy" ] || [ "$trust_policy" = "null" ]; then
    echo "FAIL: trust policies unknown at plan time: apply bootstrap to LocalStack first" >&2
    exit 1
  fi
  if ! jq -Ser --arg document "trust:$role" --arg key_prefix "trust:$role#" \
    "$canonical_statements" <<<"$trust_policy" >>"$tmp_dir/statements.tsv"; then
    echo "FAIL: could not canonicalise trust:$role policy" >&2
    exit 1
  fi
done

statement_count="$(wc -l <"$tmp_dir/statements.tsv" | tr -d ' ')"
if [ "$statement_count" -ne 85 ]; then
  echo "FAIL: expected 85 IAM statement rows, found $statement_count" >&2
  exit 1
fi

echo "# statements"
while IFS=$'\t' read -r document key effect principal action resource condition; do
  # shellcheck disable=SC2016
  printf '| `%s` | `%s` | `%s` | `%s` | `%s` | `%s` | `%s` |\n' \
    "$document" "$key" "$effect" "$principal" "$action" "$resource" "$condition"
done <"$tmp_dir/statements.tsv"

echo "# bindings"

for address in \
  aws_iam_role_policy.plan_reader_deny \
  aws_iam_role_policy.plan_reader_state \
  aws_iam_role_policy.publisher; do
  role="$(jq -er --arg address "$address" '
    [.planned_values.root_module.resources[]? | select(.address == $address)]
    | if length == 1 then .[0].values.role else empty end
  ' "$plan_json")" || {
    echo "FAIL: binding missing for $address" >&2
    exit 1
  }
  # shellcheck disable=SC2016
  printf '| `inline` | `%s` | `%s` | `n/a` | `n/a` |\n' "$address" "$role"
done

for address in \
  aws_iam_role_policy_attachment.plan_reader_readonly \
  aws_iam_role_policy_attachment.deployer_state \
  aws_iam_role_policy_attachment.deployer_ec2 \
  aws_iam_role_policy_attachment.deployer_elb_ecs \
  aws_iam_role_policy_attachment.deployer_data \
  aws_iam_role_policy_attachment.deployer_iam \
  aws_iam_role_policy_attachment.deployer_guard; do
  binding="$(jq -er --arg address "$address" '
    [.planned_values.root_module.resources[]? | select(.address == $address)]
    | if length == 1 then [.[0].values.role, .[0].values.policy_arn] | @tsv else empty end
  ' "$plan_json")" || {
    echo "FAIL: binding missing for $address" >&2
    exit 1
  }
  IFS=$'\t' read -r role policy_arn <<<"$binding"
  if [ -z "$role" ] || [ -z "$policy_arn" ] || [ "$role" = "null" ] || [ "$policy_arn" = "null" ]; then
    echo "FAIL: binding values unknown for $address" >&2
    exit 1
  fi
  # shellcheck disable=SC2016
  printf '| `attachment` | `%s` | `%s` | `%s` | `n/a` |\n' \
    "$address" "$role" "$policy_arn"
done

for role in "${trust_roles[@]}"; do
  binding="$(jq -er --arg address "aws_iam_role.$role" '
    [.planned_values.root_module.resources[]? | select(.address == $address)]
    | if length == 1 then
        [.[0].values.name,
         (.[0].values.permissions_boundary as $boundary
          | if $boundary == null or $boundary == "" then "none" else $boundary end)]
        | @tsv
      else empty end
  ' "$plan_json")" || {
    echo "FAIL: role binding missing for aws_iam_role.$role" >&2
    exit 1
  }
  IFS=$'\t' read -r role_name boundary <<<"$binding"
  # shellcheck disable=SC2016
  printf '| `role` | `aws_iam_role.%s` | `%s` | `n/a` | `%s` |\n' \
    "$role" "$role_name" "$boundary"
done
