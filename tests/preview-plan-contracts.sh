#!/usr/bin/env bash
set -u

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <plan.json>" >&2
  exit 2
fi

plan_file="$1"
if [ ! -f "$plan_file" ]; then
  echo "FAIL: preview plan file not found: $plan_file" >&2
  exit 2
fi

if [ ! -s "$plan_file" ] \
  || ! jq -e . "$plan_file" >/dev/null 2>&1 \
  || ! jq -e '(.planned_values.root_module | type) == "object"' "$plan_file" >/dev/null 2>&1
then
  echo "FAIL: preview plan file is empty, not JSON, or has no planned_values: $plan_file" >&2
  exit 2
fi

assertions="$({
  jq -S -r '
    def empty_value:
      . == null or . == "" or . == [] or . == {};

    def empty_filter($filter):
      ($filter | type) == "array"
      and ($filter | length) == 1
      and ($filter[0] | type) == "object"
      and ($filter[0] | to_entries | all(.value | empty_value));

    def normalize_policy:
      if type == "object" and (.Statement | type) == "array" then
        .Statement |= map(
          if has("Resource") and (.Resource | type) == "array" then
            .Resource |= sort
          else
            .
          end
        )
      else
        .
      end;

    def all_resources:
      [.planned_values.root_module | recurse(.child_modules[]?) | .resources[]?];

    (all_resources) as $resources
    | (.variables.name.value // null) as $name
    | (.variables.env_id.value // null) as $env_id
    | (if ($name | type) == "string" then ($name[0:15] | sub("-+$"; "")) else null end) as $lb_name_part
    | (if ($name | type) == "string" then ($name[0:16] | sub("-+$"; "")) else null end) as $tg_name_part
    | [$resources[] | select(.address == "aws_lb.this")] as $load_balancers
    | [$resources[] | select(.address == "aws_lb_target_group.api")] as $target_groups
    | ($load_balancers[0].values.name // null) as $lb_name
    | ($target_groups[0].values.name // null) as $tg_name
    | [$resources[] | select(.address == "aws_s3_bucket.data")] as $buckets
    | ($buckets[0].values.bucket // null) as $bucket
    | [
        $resources[]
        | select(.address == "aws_s3_bucket_lifecycle_configuration.data")
      ] as $lifecycle
    | [
        $resources[]
        | select(.address == "aws_s3_bucket_policy.data")
      ] as $policies
    | ($lifecycle[0].values.rule // []) as $rules
    | ($rules[0] // {}) as $rule
    | (try ($policies[0].values.policy | fromjson) catch null) as $actual_policy
    | ([
        .prior_state.values.root_module
        | recurse(.child_modules[]?)
        | .resources[]?
        | select(.address == "data.aws_partition.current")
        | .values.partition
        | select(type == "string" and length > 0)
      ]) as $partitions
    | ($partitions[0] // null) as $partition
    | {
        Version: "2012-10-17",
        Statement: [{
          Sid: "DenyInsecureTransport",
          Effect: "Deny",
          Principal: "*",
          Action: "s3:*",
          Resource: [
            "arn:\($partition):s3:::\($bucket)",
            "arn:\($partition):s3:::\($bucket)/*"
          ],
          Condition: {
            Bool: {
              "aws:SecureTransport": "false"
            }
          }
        }]
      } as $expected_policy
    | [
        {
          name: "lb-name",
          passed: (
            ($load_balancers | length) == 1
            and ($name | type) == "string"
            and ($env_id | type) == "string"
            and ($lb_name_part | type) == "string"
            and ($lb_name_part | length) > 0
            and ($lb_name | type) == "string"
            and ($lb_name | length) >= 1
            and ($lb_name | length) <= 32
            and ($lb_name | test("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"))
            and $lb_name == "\($lb_name_part)-\($env_id)-alb"
          )
        },
        {
          name: "tg-name",
          passed: (
            ($target_groups | length) == 1
            and ($name | type) == "string"
            and ($env_id | type) == "string"
            and ($tg_name_part | type) == "string"
            and ($tg_name_part | length) > 0
            and ($tg_name | type) == "string"
            and ($tg_name | length) >= 1
            and ($tg_name | length) <= 32
            and ($tg_name | test("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"))
            and $tg_name == "\($tg_name_part)-\($env_id)-tg"
          )
        },
        {
          name: "data-bucket-present",
          passed: (
            ($buckets | length) == 1
            and ($bucket | type) == "string"
            and ($bucket | length) > 0
          )
        },
        {
          name: "lifecycle-present",
          passed: (($lifecycle | length) == 1)
        },
        {
          name: "lifecycle-bucket",
          passed: (
            $bucket != null
            and $lifecycle[0].values.bucket == $bucket
          )
        },
        {
          name: "lifecycle-rule-count",
          passed: (($rules | length) == 1)
        },
        {
          name: "lifecycle-rule-id",
          passed: ($rule.id == "data-retention")
        },
        {
          name: "lifecycle-rule-status",
          passed: ($rule.status == "Enabled")
        },
        {
          name: "lifecycle-filter-empty",
          passed: empty_filter($rule.filter // [])
        },
        {
          name: "lifecycle-abort-days",
          passed: (
            $rule.abort_incomplete_multipart_upload[0].days_after_initiation == 7
          )
        },
        {
          name: "lifecycle-no-noncurrent",
          passed: (([
            $lifecycle[]?.values.rule[]?.noncurrent_version_expiration[]?
          ] | length) == 0)
        },
        {
          name: "lifecycle-expiration-days",
          passed: (([
            $lifecycle[]?.values.rule[]?.expiration[]?
          ]) as $expirations
          | ($expirations | length) == 1
          and ($expirations[0].days == 30)
          and (($expirations[0].date // "") == "")
          and (($expirations[0].expired_object_delete_marker // false) != true))
        },
        {
          name: "lifecycle-no-transition",
          passed: (([
            $lifecycle[]?.values.rule[]?.transition[]?
          ] | length) == 0)
        },
        {
          name: "policy-present",
          passed: (($policies | length) == 1)
        },
        {
          name: "policy-bucket",
          passed: (
            $bucket != null
            and $policies[0].values.bucket == $bucket
          )
        },
        {
          name: "partition-known",
          passed: (($partitions | length) == 1)
        },
        {
          name: "policy-document",
          passed: (
            ($actual_policy | normalize_policy)
            == ($expected_policy | normalize_policy)
          )
        },
        {
          name: "listener-no-https",
          passed: (([
            $resources[]
            | select(
                .type == "aws_lb_listener"
                and .values.protocol == "HTTPS"
              )
          ] | length) == 0)
        },
        {
          name: "listener-no-redirect",
          passed: (([
            $resources[]
            | select(.type == "aws_lb_listener")
            | .values.default_action[]?
            | select(.type == "redirect")
          ] | length) == 0)
        }
      ]
    | .[]
    | [.name, (if .passed then "true" else "false" end)]
    | @tsv
  ' "$plan_file"
} 2>&1)"
jq_rc=$?

if [ "$jq_rc" -ne 0 ]; then
  echo "FAIL: preview plan JSON could not be evaluated" >&2
  printf '%s\n' "$assertions" >&2
  exit 2
fi

total=0
failures=0
while IFS=$'\t' read -r name passed; do
  [ -n "$name" ] || continue
  total=$((total + 1))
  if [ "$passed" = "true" ]; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s\n' "$name" >&2
    failures=$((failures + 1))
  fi
done <<< "$assertions"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: preview plan contracts (%d of %d assertions failed)\n' \
    "$failures" "$total" >&2
  exit 1
fi

if [ "$total" -eq 0 ]; then
  echo "FAIL: preview plan contracts evaluated no assertions" >&2
  exit 1
fi

printf 'PASS: preview plan contracts (%d assertions)\n' "$total"
