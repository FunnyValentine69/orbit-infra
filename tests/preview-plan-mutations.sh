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

script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH='' cd -- "$script_dir/.." && pwd)"
contract="$script_dir/preview-plan-contracts.sh"

tmp_parent="${TMPDIR:-/tmp}"
if primary_mktemp_result="$(
  mktemp -d "$tmp_parent/preview-plan-mutations.XXXXXX" 2>&1
)"; then
  tmp_dir="$primary_mktemp_result"
else
  primary_mktemp_error="$primary_mktemp_result"
  fallback_parent="$repo_root/.preview-runs"
  if ! mkdir -p "$fallback_parent"; then
    echo "FAIL: could not create mutation fallback directory" >&2
    exit 2
  fi
  if fallback_mktemp_result="$(
    mktemp -d "$fallback_parent/preview-plan-mutations.XXXXXX" 2>&1
  )"; then
    tmp_dir="$fallback_mktemp_result"
  else
    fallback_mktemp_error="$fallback_mktemp_result"
    echo "FAIL: could not create mutation temporary directory" >&2
    printf 'primary mktemp error:\n%s\n' "$primary_mktemp_error" >&2
    printf 'fallback mktemp error:\n%s\n' "$fallback_mktemp_error" >&2
    exit 2
  fi
fi

cleanup() {
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

unmodified_output="$(bash "$contract" "$plan_file" 2>&1)"
unmodified_rc=$?
if [ "$unmodified_rc" -ne 0 ]; then
  echo "FAIL: unmodified plan" >&2
  printf '%s\n' "$unmodified_output" >&2
  exit 1
fi
echo "PASS: unmodified plan"

mutant_count=0
killed_count=0
runner_failures=0

run_mutant() {
  local name="$1"
  local predicate="$2"
  local filter="$3"
  local mutant="$tmp_dir/$name.json"
  local output
  local rc

  mutant_count=$((mutant_count + 1))
  if ! jq "$filter" "$plan_file" > "$mutant"; then
    printf 'FAIL: mutant %s could not be created\n' "$name" >&2
    runner_failures=$((runner_failures + 1))
    return
  fi

  output="$(bash "$contract" "$mutant" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    case "$output" in
      *"FAIL: $predicate"*)
        printf 'PASS: mutant %s killed by %s\n' "$name" "$predicate"
        killed_count=$((killed_count + 1))
        return
        ;;
    esac
  fi

  printf 'FAIL: mutant %s survived %s\n' "$name" "$predicate" >&2
  runner_failures=$((runner_failures + 1))
}

run_mutant \
  data-bucket-name-removed \
  data-bucket-present \
  'del(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket.data").values.bucket)'
run_mutant \
  data-bucket-deleted \
  data-bucket-present \
  'del(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket.data"))'

run_mutant \
  lifecycle-deleted \
  lifecycle-present \
  'del(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data"))'
run_mutant \
  lifecycle-duplicated \
  lifecycle-present \
  '(.planned_values.root_module.resources) |= . + [(.[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data"))]'
run_mutant \
  lifecycle-bucket-changed \
  lifecycle-bucket \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data").values.bucket) = "mutated-data"'
run_mutant \
  lifecycle-rule-count-two \
  lifecycle-rule-count \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data").values.rule) |= . + [.[0]]'
run_mutant \
  lifecycle-rule-id-changed \
  lifecycle-rule-id \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data").values.rule[0].id) = "mutated-id"'
run_mutant \
  lifecycle-rule-status-disabled \
  lifecycle-rule-status \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data").values.rule[0].status) = "Disabled"'
run_mutant \
  lifecycle-filter-deleted \
  lifecycle-filter-empty \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data").values.rule[0].filter) = []'
run_mutant \
  lifecycle-filter-prefix \
  lifecycle-filter-empty \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data").values.rule[0].filter[0].prefix) = "x"'
run_mutant \
  lifecycle-filter-tag \
  lifecycle-filter-empty \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data").values.rule[0].filter[0].tag) = [{"key":"purpose","value":"mutation"}]'
run_mutant \
  lifecycle-abort-days-six \
  lifecycle-abort-days \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data").values.rule[0].abort_incomplete_multipart_upload[0].days_after_initiation) = 6'
run_mutant \
  lifecycle-noncurrent-added \
  lifecycle-no-noncurrent \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data").values.rule[0].noncurrent_version_expiration) = [{"noncurrent_days":1}]'
run_mutant \
  lifecycle-expiration-added \
  lifecycle-no-expiration \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data").values.rule[0].expiration) = [{"days":1}]'
run_mutant \
  lifecycle-transition-added \
  lifecycle-no-transition \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_lifecycle_configuration.data").values.rule[0].transition) = [{"days":1,"storage_class":"STANDARD_IA"}]'

run_mutant \
  policy-deleted \
  policy-present \
  'del(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_policy.data"))'
run_mutant \
  policy-bucket-changed \
  policy-bucket \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_policy.data").values.bucket) = "mutated-data"'
run_mutant \
  policy-version-changed \
  policy-document \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_policy.data").values.policy) |= (fromjson | .Version = "2008-10-17" | tojson)'
run_mutant \
  policy-sid-changed \
  policy-document \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_policy.data").values.policy) |= (fromjson | .Statement[0].Sid = "MutatedSid" | tojson)'
run_mutant \
  policy-effect-allow \
  policy-document \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_policy.data").values.policy) |= (fromjson | .Statement[0].Effect = "Allow" | tojson)'
run_mutant \
  policy-action-get-object \
  policy-document \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_policy.data").values.policy) |= (fromjson | .Statement[0].Action = "s3:GetObject" | tojson)'
run_mutant \
  policy-principal-account \
  policy-document \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_policy.data").values.policy) |= (fromjson | .Statement[0].Principal = {"AWS":"arn:aws:iam::000000000000:root"} | tojson)'
run_mutant \
  policy-condition-operator \
  policy-document \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_policy.data").values.policy) |= (fromjson | .Statement[0].Condition.StringEquals = .Statement[0].Condition.Bool | del(.Statement[0].Condition.Bool) | tojson)'
run_mutant \
  policy-condition-value \
  policy-document \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_policy.data").values.policy) |= (fromjson | .Statement[0].Condition.Bool["aws:SecureTransport"] = "true" | tojson)'
run_mutant \
  policy-object-resource-removed \
  policy-document \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_policy.data").values.policy) |= (fromjson | .Statement[0].Resource |= map(select(endswith("/*") | not)) | tojson)'
run_mutant \
  policy-extra-allow-statement \
  policy-document \
  '(.planned_values.root_module.resources[] | select(.address == "aws_s3_bucket_policy.data").values.policy) |= (fromjson | .Statement += [{"Sid":"ExtraAllow","Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"*"}] | tojson)'

run_mutant \
  listener-https-injected \
  listener-no-https \
  '(.planned_values.root_module.resources) |= . + [(.[] | select(.address == "aws_lb_listener.http") | .address = "aws_lb_listener.https_mutant" | .values.protocol = "HTTPS")]'
run_mutant \
  listener-http-redirect \
  listener-no-redirect \
  '(.planned_values.root_module.resources[] | select(.address == "aws_lb_listener.http").values.default_action[0].type) = "redirect"'

if [ "$runner_failures" -ne 0 ]; then
  printf 'FAIL: preview plan mutations (%d of %d mutants not killed)\n' \
    "$runner_failures" "$mutant_count" >&2
  exit 1
fi

printf 'PASS: preview plan mutations (%d mutants, all killed)\n' "$killed_count"
