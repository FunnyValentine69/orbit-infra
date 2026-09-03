#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/cleanup"
VERIFIER="$REPO_ROOT/scripts/cleanup-verifier.sh"
AWS_WRAPPER="$REPO_ROOT/scripts/aws-cli.sh"
LEASE="$REPO_ROOT/scripts/lease.sh"

tmp_dir="$(mktemp -d)"
created_backend_hcl=false
cleanup() {
  rm -rf "$tmp_dir"
  if [ "$created_backend_hcl" = true ]; then
    rm -f "$REPO_ROOT/envs/preview/backend.aws.hcl"
  fi
}
trap cleanup EXIT

pass_count=0
pass() {
  pass_count=$((pass_count + 1))
  echo "PASS: $1"
}

assert_jq() {
  local json="$1"
  local filter="$2"
  local message="$3"
  if ! jq -e "$filter" <<< "$json" >/dev/null; then
    echo "FAIL: $message" >&2
    echo "$json" >&2
    exit 1
  fi
}

p3fix="$($VERIFIER verify-recorded "$FIXTURES/p3fix-24.json")"
assert_jq "$p3fix" '.passed and .summary.gone == 24 and (.results | length) == 24 and (.stale_tag_entries | length) == 24' \
  "24 stale tag entries must all be persisted as gone"
pass "24-entry stale tag inventory passes after exact terminal/absent probes"

predicates="$($VERIFIER verify-recorded "$FIXTURES/predicate-cases.json")"
assert_jq "$predicates" '.results[0].outcome == "gone" and .results[1].outcome == "indeterminate" and (.results | length) == 6' \
  "SG-rule NotFound and partial persistence outcomes are wrong"
pass "SG-rule NotFound is gone; unknown ARN is indeterminate without discarding earlier results"

assert_jq "$predicates" '.results[2].outcome == "gone" and .results[3].outcome == "pending" and .results[4].outcome == "live"' \
  "VPC endpoint states must map to gone/pending/live"
pass "VPC endpoint deleted/deleting/available states are typed correctly"

assert_jq "$predicates" '.results[5].outcome == "gone"' \
  "exact inactive ECS describe must override stale list discovery"
pass "stale list-clusters evidence is ignored when exact describe is INACTIVE"

ecs_missing="$($VERIFIER verify-recorded "$FIXTURES/ecs-exact-missing.json")"
assert_jq "$ecs_missing" '.passed and .summary.gone == 3 and all(.results[]; .reason == "exact-ecs-missing-failure")' \
  "only an exact MISSING failure for each requested ECS ARN may prove it gone"
pass "exact ECS MISSING failures classify requested cluster, service, and task ARNs as gone"

ecs_non_missing="$($VERIFIER verify-recorded "$FIXTURES/ecs-non-missing-failure.json")"
assert_jq "$ecs_non_missing" '(.passed | not) and .summary.indeterminate == 3 and all(.results[]; .reason == "ecs-failure-indeterminate")' \
  "non-MISSING, unmatched, and malformed ECS failures must be indeterminate"
pass "non-MISSING, unmatched, and malformed ECS failures remain indeterminate"

ecs_empty_services="$($VERIFIER verify-recorded "$FIXTURES/ecs-empty-services.json")"
assert_jq "$ecs_empty_services" '(.passed | not) and .summary.indeterminate == 1 and .results[0].reason == "ecs-absence-unconfirmed"' \
  "empty services with empty failures must not prove the requested ARN is gone"
pass "empty ECS services without an exact MISSING failure remain indeterminate"

allowance_fixture="$FIXTURES/task-definition-allowance.json"
local_allowance="$($VERIFIER task-definition-delete-allowance localstack "$allowance_fixture")"
assert_jq "$local_allowance" '.allowed and .allowance.id == "localstack-delete-task-definitions-inactive" and .allowance.error_code == "InternalFailure"' \
  "LocalStack task-definition allowance was not recorded"
if "$VERIFIER" task-definition-delete-allowance aws "$allowance_fixture" >/dev/null 2>&1; then
  echo "FAIL: real AWS must reject the LocalStack allowance" >&2
  exit 1
fi
pass "task-definition delete allowance is LocalStack-only, exact, and recorded"

mkdir -p "$tmp_dir/timeout-bin"
apply_log="$tmp_dir/timeout-env.log"
args_log="$tmp_dir/timeout-args.log"
cat > "$tmp_dir/timeout-bin/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$AWS_TIMEOUT_ARGS_LOG"
if [ -n "${AWS_PROFILE+x}" ]; then
  echo "profile-present" > "$AWS_TIMEOUT_ENV_LOG"
else
  echo "profile-unset" > "$AWS_TIMEOUT_ENV_LOG"
fi
# A grandchild that outlives a single-pid kill; the wrapper must reap the
# whole process group.
sleep 60 &
echo $! > "$AWS_TIMEOUT_CHILD_PID_FILE"
wait
EOF
chmod +x "$tmp_dir/timeout-bin/aws"
timeout_stdout="$tmp_dir/timeout.stdout"
timeout_stderr="$tmp_dir/timeout.stderr"
start_seconds=$SECONDS
set +e
AWS_PROFILE=must-not-propagate \
AWS_TIMEOUT_ENV_LOG="$apply_log" \
AWS_TIMEOUT_ARGS_LOG="$args_log" \
AWS_TIMEOUT_CHILD_PID_FILE="$tmp_dir/timeout-child.pid" \
AWS_CLI_BIN="$tmp_dir/timeout-bin/aws" \
AWS_OUTER_TIMEOUT_SECONDS=1 \
TARGET=localstack \
AWS_ENDPOINT_URL=http://localhost:4566 \
AWS_ACCESS_KEY_ID=test \
AWS_SECRET_ACCESS_KEY=test \
AWS_DEFAULT_REGION=test-region \
AWS_EC2_METADATA_DISABLED=true \
  "$AWS_WRAPPER" ec2 describe-vpcs --vpc-ids vpc-timeout >"$timeout_stdout" 2>"$timeout_stderr"
timeout_rc=$?
set -e
elapsed=$((SECONDS - start_seconds))
timeout_record=$(jq -n \
  --argjson candidate "$(jq -c '.candidate' "$FIXTURES/timeout.json")" \
  --argjson rc "$timeout_rc" \
  --rawfile stdout "$timeout_stdout" \
  --rawfile stderr "$timeout_stderr" \
  '{records:[{candidate:$candidate,response:{rc:$rc,stdout:$stdout,stderr:$stderr}}]}')
printf '%s\n' "$timeout_record" > "$tmp_dir/timeout-record.json"
timeout_result="$($VERIFIER verify-recorded "$tmp_dir/timeout-record.json")"
assert_jq "$timeout_result" '.results[0].outcome == "indeterminate" and .results[0].reason == "aws-timeout"' \
  "a timed-out exact probe must be indeterminate"
sleep 1
grandchild_pid="$(cat "$tmp_dir/timeout-child.pid")"
if kill -0 "$grandchild_pid" 2>/dev/null; then
  grandchild_stat="$(ps -o stat= -p "$grandchild_pid" 2>/dev/null | awk '{print $1}')"
  if [[ "$grandchild_stat" != Z* ]]; then
    kill "$grandchild_pid" 2>/dev/null || true
    echo "FAIL: the outer timeout must kill the whole process group (grandchild $grandchild_pid survived with state $grandchild_stat)" >&2
    exit 1
  fi
fi
pass "the outer timeout reaps the CLI's process group, not just its pid"
if [ "$timeout_rc" -ne 124 ] || [ "$elapsed" -ge 30 ] || [ "$(cat "$apply_log")" != "profile-unset" ] || \
   ! grep -Fq -- '--endpoint-url http://localhost:4566' "$args_log" || \
   ! grep -Fq -- '--cli-connect-timeout 5' "$args_log" || \
   ! grep -Fq -- '--cli-read-timeout 20' "$args_log"; then
  echo "FAIL: outer timeout/profile contract rc=$timeout_rc elapsed=$elapsed env=$(cat "$apply_log")" >&2
  exit 1
fi
pass "blocking AWS command is bounded and indeterminate with AWS_PROFILE unset"

tag_gone="$($VERIFIER verify-recorded "$FIXTURES/nonempty-tags-gone.json")"
assert_jq "$tag_gone" '.passed and .summary.gone == 1 and (.stale_tag_entries | length) == 1' \
  "nonempty stale tag inventory must reconcile to gone"
pass "nonempty tag inventory succeeds when every exact candidate is gone"
manifest_live="$($VERIFIER verify-recorded "$FIXTURES/empty-tags-live-manifest.json")"
assert_jq "$manifest_live" '(.passed | not) and .results[0].outcome == "live" and .summary.live == 1' \
  "empty tag discovery must not override a live manifest candidate"
pass "live manifest candidate fails even when tag discovery is empty"

mkdir -p "$tmp_dir/fake-bin" "$tmp_dir/fake-s3"
cat > "$tmp_dir/fake-bin/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

original_args="$*"
if [ -n "${FAKE_AWS_CALL_LOG:-}" ]; then
  printf '%s\n' "$original_args" >> "$FAKE_AWS_CALL_LOG"
fi
service="$1"
operation="$2"
shift 2
bucket=""
key=""
body=""
etag_match=""
if_none=""
destination=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bucket) bucket="$2"; shift 2 ;;
    --key) key="$2"; shift 2 ;;
    --body) body="$2"; shift 2 ;;
    --if-match) etag_match="$2"; shift 2 ;;
    --if-none-match) if_none="$2"; shift 2 ;;
    --endpoint-url|--cli-connect-timeout|--cli-read-timeout|--content-type|--prefix|--output|--tag-filters|--vpc-ids)
      shift 2
      ;;
    --*) shift ;;
    *) destination="$1"; shift ;;
  esac
done

store="$FAKE_S3_DIR/${key//\//_}"
etag_file="$store.etag"
if [ "$service $operation" = "s3api get-object" ]; then
  if [ "${FAKE_S3_FAIL:-0}" = 1 ]; then
    echo "An error occurred (ServiceUnavailable) when calling the GetObject operation: simulated outage" >&2
    exit 254
  fi
  if [ ! -f "$store" ]; then
    echo "An error occurred (NoSuchKey)" >&2
    exit 254
  fi
  cp "$store" "$destination"
  printf '{"ETag":"%s"}\n' "$(cat "$etag_file")"
  # FAKE_S3_RACE=1 simulates a concurrent writer landing right after this
  # read: the ETag handed to the caller is already stale.
  if [ "${FAKE_S3_RACE:-0}" = 1 ]; then
    printf '%s\n' "$(( $(cat "$etag_file") + 1 ))" > "$etag_file"
  fi
  exit 0
fi
if [ "$service $operation" = "s3api put-object" ]; then
  current=""
  [ ! -f "$etag_file" ] || current="$(cat "$etag_file")"
  if { [ "$if_none" = "*" ] && [ -n "$current" ]; } || \
     { [ -n "$etag_match" ] && [ "$etag_match" != "$current" ]; }; then
    echo "An error occurred (PreconditionFailed)" >&2
    exit 254
  fi
  next=$(( ${current:-0} + 1 ))
  cp "$body" "$store"
  printf '%s\n' "$next" > "$etag_file"
  printf '{"ETag":"%s"}\n' "$next"
  exit 0
fi
if [ "$service $operation" = "resourcegroupstaggingapi get-resources" ]; then
  tag_call=1
  if [ -n "${FAKE_TAG_CALLS_FILE:-}" ]; then
    if [ -f "$FAKE_TAG_CALLS_FILE" ]; then
      tag_call=$(( $(cat "$FAKE_TAG_CALLS_FILE") + 1 ))
    fi
    printf '%s\n' "$tag_call" > "$FAKE_TAG_CALLS_FILE"
    if [ "$tag_call" -eq "${FAKE_TAG_FAIL_ON_CALL:-0}" ]; then
      echo "An error occurred (AccessDeniedException): simulated delayed tag query failure" >&2
      exit 254
    fi
  fi
  if [ -n "${FAKE_TAG_RESPONSE_FIXTURE:-}" ]; then
    if jq -e '.responses | type == "array"' "$FAKE_TAG_RESPONSE_FIXTURE" >/dev/null; then
      response_index=$((tag_call - 1))
      jq -jr --argjson index "$response_index" '.responses[$index].stdout' "$FAKE_TAG_RESPONSE_FIXTURE"
      exit "$(jq -r --argjson index "$response_index" '.responses[$index].rc' "$FAKE_TAG_RESPONSE_FIXTURE")"
    fi
    jq -jr '.response.stdout' "$FAKE_TAG_RESPONSE_FIXTURE"
    exit "$(jq -r '.response.rc' "$FAKE_TAG_RESPONSE_FIXTURE")"
  fi
  echo '{"ResourceTagMappingList":[]}'
  exit 0
fi
if [ "${FAKE_ECS_WAITER:-0}" = 1 ]; then
  case "$service $operation" in
    "ecs list-services")
      echo '{"serviceArns":["service-waiter"]}'
      exit 0
      ;;
    "ecs list-tasks")
      echo '{"taskArns":[]}'
      exit 0
      ;;
    "ecs describe-services")
      if [[ "$original_args" == *"--query services[0].status"* ]]; then
        echo ACTIVE
      else
        echo '{"services":[],"failures":[{"arn":"service-waiter","reason":"MISSING"}]}'
      fi
      exit 0
      ;;
    "ecs update-service")
      echo '{}'
      exit 0
      ;;
    "ecs wait")
      printf '%s\n' "${AWS_OUTER_TIMEOUT_SECONDS:-unset}" > "$FAKE_WAITER_TIMEOUT_LOG"
      exit 0
      ;;
    "ecs describe-clusters")
      echo '{"clusters":[],"failures":[{"arn":"cluster-waiter","reason":"MISSING"}]}'
      exit 0
      ;;
  esac
fi
if [ -n "${FAKE_TASK_DEFINITION_DELETE_FIXTURE:-}" ]; then
  case "$service $operation" in
    "ecs describe-task-definition")
      arn="$(jq -r '.task_definition_arn' "$FAKE_TASK_DEFINITION_DELETE_FIXTURE")"
      jq -cn --arg arn "$arn" '{taskDefinition:{taskDefinitionArn:$arn,status:"INACTIVE"}}'
      exit 0
      ;;
    "ecs delete-task-definitions")
      jq -c '.response.stdout' "$FAKE_TASK_DEFINITION_DELETE_FIXTURE"
      exit "$(jq -r '.response.rc' "$FAKE_TASK_DEFINITION_DELETE_FIXTURE")"
      ;;
  esac
fi
if [ "$service $operation" = "ec2 describe-vpcs" ]; then
  echo "An error occurred (InvalidVpcID.NotFound) while calling DescribeVpcs" >&2
  exit 254
fi
echo "unexpected fake AWS call: $service $operation" >&2
exit 2
EOF
chmod +x "$tmp_dir/fake-bin/aws"

lease_env=(
  "TARGET=localstack"
  "AWS_ENDPOINT_URL=http://localhost:4566"
  "AWS_ACCESS_KEY_ID=test"
  "AWS_SECRET_ACCESS_KEY=test"
  "AWS_DEFAULT_REGION=test-region"
  "AWS_EC2_METADATA_DISABLED=true"
  "AWS_CLI_BIN=$tmp_dir/fake-bin/aws"
  "FAKE_S3_DIR=$tmp_dir/fake-s3"
  "LEASE_BUCKET=test-state"
  "CLEANUP_RETRY_DELAY_SECONDS=0"
)

# A new generation must publish its owner and initial manifest in the same CAS
# PUT. A second open of that environment must still be refused without a write.
atomic_env_id=atomic-open
atomic_owner=run-owner-a
atomic_manifest="$tmp_dir/atomic-open-manifest.json"
atomic_call_log="$tmp_dir/atomic-open-aws-calls.log"
jq -n '{target:"localstack",mode:"public",images:{api_image:"placeholder:local",redis_image:"redis:7-alpine",clickhouse_image:"clickhouse/clickhouse-server:24.3-alpine"}}' \
  > "$atomic_manifest"
: > "$atomic_call_log"
atomic_lease="$(env "${lease_env[@]}" FAKE_AWS_CALL_LOG="$atomic_call_log" \
  "$LEASE" open "$atomic_env_id" --owner "$atomic_owner" --manifest "$atomic_manifest")"
if ! jq -e --arg owner "$atomic_owner" --argjson manifest "$(cat "$atomic_manifest")" \
    '.owner == $owner and .manifest == $manifest' <<< "$atomic_lease" >/dev/null || \
   [ "$(grep -c '^s3api put-object ' "$atomic_call_log")" -ne 1 ]; then
  echo "FAIL: lease open must persist owner and initial manifest in one CAS PUT" >&2
  cat "$atomic_call_log" >&2
  exit 1
fi
pass "lease open persists owner and initial manifest atomically in one CAS PUT"

set +e
second_open_out="$(env "${lease_env[@]}" FAKE_AWS_CALL_LOG="$atomic_call_log" \
  "$LEASE" open "$atomic_env_id" --owner run-owner-b --manifest "$atomic_manifest" 2>&1)"
second_open_rc=$?
set -e
atomic_after_refusal="$(env "${lease_env[@]}" "$LEASE" get "$atomic_env_id")"
if [ "$second_open_rc" -ne 3 ] || \
   ! grep -Fq "current status is 'open'" <<< "$second_open_out" || \
   ! jq -e --arg owner "$atomic_owner" '.status == "open" and .generation == 1 and .owner == $owner' \
     <<< "$atomic_after_refusal" >/dev/null || \
   [ "$(grep -c '^s3api put-object ' "$atomic_call_log")" -ne 1 ]; then
  echo "FAIL: a second open must be refused without mutating the atomic lease" >&2
  exit 1
fi
pass "a second open on the same environment is refused without another PUT"

env "${lease_env[@]}" "$LEASE" open retry-case >/dev/null
retry_failures="$(jq -r '.failures' "$FIXTURES/retry-exhaustion.json")"
for _ in $(seq 1 "$retry_failures"); do
  env "${lease_env[@]}" "$LEASE" begin-cleanup retry-case >/dev/null
  env "${lease_env[@]}" "$LEASE" transition retry-case closing cleanup_failed --error "verification failed" >/dev/null
done
set +e
env "${lease_env[@]}" "$LEASE" begin-cleanup retry-case >"$tmp_dir/fourth.out" 2>"$tmp_dir/fourth.err"
fourth_rc=$?
set -e
retry_lease="$(env "${lease_env[@]}" "$LEASE" get retry-case)"
retry_expected="$(jq -c '.expected' "$FIXTURES/retry-exhaustion.json")"
retry_actual="$(jq -c '{status,cleanup_attempt,manual_intervention_required,next_retry_at}' <<< "$retry_lease")"
if [ "$retry_actual" != "$retry_expected" ]; then
  echo "FAIL: fourth automatic cleanup must be refused with cleanup_failed retained" >&2
  echo "actual:   $retry_actual" >&2
  echo "expected: $retry_expected" >&2
  exit 1
fi
if [ "$fourth_rc" -eq 0 ]; then
  echo "FAIL: fourth automatic cleanup unexpectedly started" >&2
  exit 1
fi
pass "three failed stage-1 executions exhaust the CAS-persisted automatic retry budget"

env "${lease_env[@]}" "$LEASE" begin-cleanup retry-case --force-retry >/dev/null
forced_lease="$(env "${lease_env[@]}" "$LEASE" get retry-case)"
assert_jq "$forced_lease" '.status == "closing" and .cleanup_attempt == 4 and (.cleanup_retry_audit | length) == 1' \
  "force retry must be explicit and audited"
pass "explicit force retry is CAS-persisted in the lease audit"

cat > "$tmp_dir/fake-bin/terraform" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "$tmp_dir/terraform-calls.log"
if [ "\${EXPECT_AWS_IMAGE_VARS:-0}" = 1 ] && [[ "\$*" == *" destroy "* ]]; then
  for expected in \
    "api_image=\$EXPECTED_API_IMAGE" \
    "redis_image=\$EXPECTED_REDIS_IMAGE" \
    "clickhouse_image=\$EXPECTED_CLICKHOUSE_IMAGE"; do
    if [[ "\$*" != *"-var \$expected"* ]]; then
      echo "missing destroy image variable: \$expected" >&2
      exit 91
    fi
  done
fi
case "\$*" in
  *" state list"*)
    if [ "\${FAKE_TF_NO_STATE:-0}" = 1 ]; then
      echo 'No state file was found!' >&2
      exit 1
    fi
    echo 'module.network.aws_vpc.this'
    ;;
  *" show -json"*)
    if [ "\${FAKE_TF_NO_STATE:-0}" = 1 ]; then
      echo 'terraform show must not run after a no-state result' >&2
      exit 92
    fi
    cat "$FIXTURES/close-state.json"
    ;;
  *) ;;
esac
EOF
chmod +x "$tmp_dir/fake-bin/terraform"
mkdir -p "$tmp_dir/preview"
state_marker="$tmp_dir/preview/terraform.localstack.close-case.tfstate.retained"
touch "$state_marker"
env "${lease_env[@]}" "$LEASE" open close-case >/dev/null
env "${lease_env[@]}" \
  PATH="$tmp_dir/fake-bin:$PATH" \
  PREVIEW_ROOT="$tmp_dir/preview" \
  OPERATOR_CIDR=test-cidr \
  TAG_REQUERY_OFFSETS=0 \
  CLEANUP_VERIFY_DEADLINE_SECONDS=0 \
  "$REPO_ROOT/scripts/close-env.sh" close-case >/dev/null
closed_lease="$(env "${lease_env[@]}" "$LEASE" get close-case)"
close_expected="$(jq -c '.expected' "$FIXTURES/close-expected.json")"
close_actual="$(jq -c '{status,error,cleanup_attempt,live:.manifest.verification_runs[-1].summary.live,indeterminate:.manifest.verification_runs[-1].summary.indeterminate,pending:.manifest.verification_runs[-1].summary.pending}' <<< "$closed_lease")"
if [ "$close_actual" != "$close_expected" ]; then
  echo "FAIL: successful end-to-end stage 1 must retain closing" >&2
  echo "actual:   $close_actual" >&2
  echo "expected: $close_expected" >&2
  exit 1
fi
if [ ! -f "$state_marker" ]; then
  echo "FAIL: stage 1 removed retained state evidence" >&2
  exit 1
fi
pass "end-to-end close retains state and leaves the lease closing, never closed"

# Terraform's explicit no-state result is an empty candidate set; `show -json`
# is invalid in that case and must not be attempted.
env "${lease_env[@]}" "$LEASE" open no-state-case >/dev/null
: > "$tmp_dir/terraform-calls.log"
env "${lease_env[@]}" \
  PATH="$tmp_dir/fake-bin:$PATH" PREVIEW_ROOT="$tmp_dir/preview" OPERATOR_CIDR=test-cidr \
  FAKE_TF_NO_STATE=1 TAG_REQUERY_OFFSETS=0 CLEANUP_VERIFY_DEADLINE_SECONDS=0 \
  "$REPO_ROOT/scripts/close-env.sh" no-state-case >/dev/null
no_state_lease="$(env "${lease_env[@]}" "$LEASE" get no-state-case)"
if [ "$(jq -r '.status' <<< "$no_state_lease")" != closing ] || \
   grep -Fq 'show -json' "$tmp_dir/terraform-calls.log"; then
  echo "FAIL: no-state cleanup must skip terraform show and remain closing" >&2
  exit 1
fi
pass "an explicit Terraform no-state result skips show and uses empty resources"

# ECS's services-stable waiter can consume its full 40x15-second retry window,
# so only that call receives a process timeout with room for the waiter itself.
env "${lease_env[@]}" "$LEASE" open waiter-case >/dev/null
jq -n '{candidates:[{
  resource_type:"ecs:cluster",
  id:"cluster-waiter",
  arn:"cluster-waiter",
  parent_id:null,
  sources:["prior-manifest"],
  tag_entry:null,
  force_delete:false
}]}' > "$tmp_dir/waiter-manifest.json"
env "${lease_env[@]}" "$LEASE" set-manifest waiter-case "$tmp_dir/waiter-manifest.json" >/dev/null
env "${lease_env[@]}" \
  PATH="$tmp_dir/fake-bin:$PATH" PREVIEW_ROOT="$tmp_dir/preview" OPERATOR_CIDR=test-cidr \
  FAKE_ECS_WAITER=1 \
  FAKE_WAITER_TIMEOUT_LOG="$tmp_dir/waiter-timeout.log" FAKE_AWS_CALL_LOG="$tmp_dir/waiter-aws-calls.log" \
  TAG_REQUERY_OFFSETS=0 CLEANUP_VERIFY_DEADLINE_SECONDS=0 \
  "$REPO_ROOT/scripts/close-env.sh" waiter-case >/dev/null
if [ "$(cat "$tmp_dir/waiter-timeout.log" 2>/dev/null || true)" != 660 ]; then
  echo "FAIL: services-stable must receive an explicit timeout of at least ten minutes" >&2
  cat "$tmp_dir/terraform-calls.log" >&2
  cat "$tmp_dir/waiter-aws-calls.log" >&2
  env "${lease_env[@]}" "$LEASE" get waiter-case >&2
  exit 1
fi
pass "the ECS services-stable waiter receives a 660-second outer timeout"

# DeleteTaskDefinitions can exit zero while reporting per-ARN failures in
# stdout. The requested ARN must fail stage 1 instead of being treated as a
# successful deletion request, and a malformed failures entry must fail
# closed rather than read as "no failure for our ARN".
run_delete_fixture_case() {
local delete_fixture="$1" delete_expected_message="$2" delete_pass_text="$3"
local delete_env_id delete_task_definition_arn delete_out delete_rc delete_lease delete_expected delete_actual
delete_env_id="$(jq -r '.env_id' "$delete_fixture")"
delete_task_definition_arn="$(jq -r '.task_definition_arn' "$delete_fixture")"
env "${lease_env[@]}" "$LEASE" open "$delete_env_id" >/dev/null
jq -n --arg arn "$delete_task_definition_arn" '
  {candidates:[{
    resource_type:"ecs:task-definition",
    id:$arn,
    arn:$arn,
    parent_id:null,
    sources:["prior-manifest"],
    tag_entry:null,
    force_delete:false
  }]}' > "$tmp_dir/delete-failure-manifest.json"
env "${lease_env[@]}" "$LEASE" set-manifest \
  "$delete_env_id" "$tmp_dir/delete-failure-manifest.json" >/dev/null
set +e
delete_out="$(env "${lease_env[@]}" \
  PATH="$tmp_dir/fake-bin:$PATH" PREVIEW_ROOT="$tmp_dir/preview" OPERATOR_CIDR=test-cidr \
  FAKE_TASK_DEFINITION_DELETE_FIXTURE="$delete_fixture" \
  TAG_REQUERY_OFFSETS=0 CLEANUP_VERIFY_DEADLINE_SECONDS=0 \
  "$REPO_ROOT/scripts/close-env.sh" "$delete_env_id" 2>&1)"
delete_rc=$?
set -e
delete_lease="$(env "${lease_env[@]}" "$LEASE" get "$delete_env_id")"
delete_expected="$(jq -c '.expected' "$delete_fixture")"
delete_actual="$(jq -c '{status,cleanup_attempt}' <<< "$delete_lease")"
if [ "$delete_rc" -eq 0 ] || [ "$delete_actual" != "$delete_expected" ] || \
   ! grep -Fq "$delete_expected_message" <<< "$delete_out"; then
  echo "FAIL: $delete_pass_text (fixture $(basename "$delete_fixture"))" >&2
  echo "actual:   $delete_actual (rc=$delete_rc: $delete_out)" >&2
  echo "expected: $delete_expected with message '$delete_expected_message'" >&2
  exit 1
fi
pass "$delete_pass_text"
}
run_delete_fixture_case "$FIXTURES/delete-task-definitions-failure.json" \
  'DeleteTaskDefinitions reported a failure for the requested ARN' \
  "DeleteTaskDefinitions stdout failures for the requested ARN fail closed"
run_delete_fixture_case "$FIXTURES/delete-task-definitions-malformed.json" \
  'DeleteTaskDefinitions returned malformed JSON' \
  "a malformed DeleteTaskDefinitions failures entry fails closed"

# Real-AWS cleanup fails closed before Terraform when an older or malformed
# lease does not contain the image references required by preview validation.
aws_lease_env=(
  "TARGET=aws"
  "AWS_CLI_BIN=$tmp_dir/fake-bin/aws"
  "FAKE_S3_DIR=$tmp_dir/fake-s3"
  "LEASE_BUCKET=test-state"
  "CLEANUP_RETRY_DELAY_SECONDS=0"
)
if [ ! -e "$REPO_ROOT/envs/preview/backend.aws.hcl" ]; then
  printf 'bucket = "test-state"\n' > "$REPO_ROOT/envs/preview/backend.aws.hcl"
  created_backend_hcl=true
fi
printf '{"mode":"public"}\n' > "$tmp_dir/missing-images-manifest.json"
env -u AWS_ENDPOINT_URL -u AWS_PROFILE "${aws_lease_env[@]}" "$LEASE" open aws-missing-images >/dev/null
env -u AWS_ENDPOINT_URL -u AWS_PROFILE "${aws_lease_env[@]}" \
  "$LEASE" set-manifest aws-missing-images "$tmp_dir/missing-images-manifest.json" >/dev/null
set +e
missing_images_out="$(env -u AWS_ENDPOINT_URL -u AWS_PROFILE "${aws_lease_env[@]}" \
  PATH="$tmp_dir/fake-bin:$PATH" PREVIEW_ROOT="$tmp_dir/preview" OPERATOR_CIDR=test-cidr \
  TAG_REQUERY_OFFSETS=0 CLEANUP_VERIFY_DEADLINE_SECONDS=0 \
  "$REPO_ROOT/scripts/close-env.sh" aws-missing-images 2>&1)"
missing_images_rc=$?
set -e
if [ "$missing_images_rc" -eq 0 ] || ! grep -Fq 'lease manifest lacks required AWS image reference' <<< "$missing_images_out"; then
  echo "FAIL: AWS cleanup must fail closed when lease image references are absent" >&2
  exit 1
fi
pass "AWS cleanup fails closed with a clear error when lease images are absent"

# Real-AWS destroy must reuse the exact digest-pinned image references recorded
# before apply. Terraform validates those variables even while destroying.
aws_images_fixture="$FIXTURES/aws-destroy-images.json"
aws_images_env_id="$(jq -r '.env_id' "$aws_images_fixture")"
api_image="$(jq -r '.manifest.images.api_image' "$aws_images_fixture")"
redis_image="$(jq -r '.manifest.images.redis_image' "$aws_images_fixture")"
clickhouse_image="$(jq -r '.manifest.images.clickhouse_image' "$aws_images_fixture")"
aws_lease_env=(
  "TARGET=aws"
  "AWS_CLI_BIN=$tmp_dir/fake-bin/aws"
  "FAKE_S3_DIR=$tmp_dir/fake-s3"
  "LEASE_BUCKET=test-state"
  "CLEANUP_RETRY_DELAY_SECONDS=0"
)
env -u AWS_ENDPOINT_URL -u AWS_PROFILE "${aws_lease_env[@]}" "$LEASE" open "$aws_images_env_id" >/dev/null
jq -c '.manifest' "$aws_images_fixture" > "$tmp_dir/aws-images-manifest.json"
env -u AWS_ENDPOINT_URL -u AWS_PROFILE "${aws_lease_env[@]}" \
  "$LEASE" set-manifest "$aws_images_env_id" "$tmp_dir/aws-images-manifest.json" >/dev/null

if [ ! -e "$REPO_ROOT/envs/preview/backend.aws.hcl" ]; then
  printf 'bucket = "test-state"\n' > "$REPO_ROOT/envs/preview/backend.aws.hcl"
  created_backend_hcl=true
fi
: > "$tmp_dir/terraform-calls.log"
env -u AWS_ENDPOINT_URL -u AWS_PROFILE "${aws_lease_env[@]}" \
  PATH="$tmp_dir/fake-bin:$PATH" \
  PREVIEW_ROOT="$tmp_dir/preview" \
  OPERATOR_CIDR=test-cidr \
  EXPECT_AWS_IMAGE_VARS=1 \
  EXPECTED_API_IMAGE="$api_image" \
  EXPECTED_REDIS_IMAGE="$redis_image" \
  EXPECTED_CLICKHOUSE_IMAGE="$clickhouse_image" \
  TAG_REQUERY_OFFSETS=0 \
  CLEANUP_VERIFY_DEADLINE_SECONDS=0 \
  "$REPO_ROOT/scripts/close-env.sh" "$aws_images_env_id" >/dev/null
for expected in \
  "api_image=$api_image" \
  "redis_image=$redis_image" \
  "clickhouse_image=$clickhouse_image"; do
  if ! grep -Fq -- "-var $expected" "$tmp_dir/terraform-calls.log"; then
    echo "FAIL: AWS destroy command omitted $expected" >&2
    exit 1
  fi
done
pass "AWS destroy reuses all three image references from the lease manifest"

# A zero-exit tagging response is usable only when it is an object containing
# the required array. Missing, null, wrong-type, and empty responses must all
# retain indeterminate discovery evidence and fail stage 1.
run_tag_schema_fixture_case() {
  local tag_schema_fixture="$1"
  local tag_schema_env_id tag_schema_out tag_schema_rc tag_schema_lease
  local tag_schema_expected tag_schema_actual tag_schema_offsets tag_schema_calls
  tag_schema_env_id="$(jq -r '.env_id' "$tag_schema_fixture")"
  tag_schema_offsets="$(jq -r '.tag_requery_offsets // "0"' "$tag_schema_fixture")"
  tag_schema_calls="$tmp_dir/tag-schema-calls-$tag_schema_env_id"
  rm -f "$tag_schema_calls"
  env "${lease_env[@]}" "$LEASE" open "$tag_schema_env_id" >/dev/null
  set +e
  tag_schema_out="$(env "${lease_env[@]}" \
    PATH="$tmp_dir/fake-bin:$PATH" PREVIEW_ROOT="$tmp_dir/preview" OPERATOR_CIDR=test-cidr \
    FAKE_TAG_RESPONSE_FIXTURE="$tag_schema_fixture" FAKE_TAG_CALLS_FILE="$tag_schema_calls" \
    TAG_REQUERY_OFFSETS="$tag_schema_offsets" CLEANUP_VERIFY_DEADLINE_SECONDS=0 \
    "$REPO_ROOT/scripts/close-env.sh" "$tag_schema_env_id" 2>&1)"
  tag_schema_rc=$?
  set -e
  tag_schema_lease="$(env "${lease_env[@]}" "$LEASE" get "$tag_schema_env_id")"
  tag_schema_expected="$(jq -c '.expected' "$tag_schema_fixture")"
  tag_schema_actual="$(jq -c '{
    status,
    candidate_id: .manifest.verification_runs[-1].results[]
      | select(.id == "tag-inventory-incomplete")
      | .id,
    indeterminate: .manifest.verification_runs[-1].summary.indeterminate,
    pre_observation_status: ([.manifest.tag_inventory_observations[]
      | select(.phase == "pre-destroy")][0].status),
    scheduled_observation_status: .manifest.tag_inventory_observations[-1].status
  }' <<< "$tag_schema_lease")"
  if [ "$tag_schema_rc" -eq 0 ] || [ "$tag_schema_actual" != "$tag_schema_expected" ]; then
    echo "FAIL: zero-exit malformed tag inventory must fail closed (fixture $(basename "$tag_schema_fixture"))" >&2
    echo "actual:   $tag_schema_actual (rc=$tag_schema_rc: $tag_schema_out)" >&2
    echo "expected: $tag_schema_expected" >&2
    exit 1
  fi
  pass "$(jq -r '.name' "$tag_schema_fixture") is indeterminate"
}
for tag_schema_fixture in \
  "$FIXTURES/tag-inventory-missing-key.json" \
  "$FIXTURES/tag-inventory-null.json" \
  "$FIXTURES/tag-inventory-string.json" \
  "$FIXTURES/tag-inventory-empty-stdout.json" \
  "$FIXTURES/tag-inventory-entry-missing-arn-pre.json" \
  "$FIXTURES/tag-inventory-entry-numeric-arn-scheduled.json" \
  "$FIXTURES/tag-pre-malformed-later-valid.json"; do
  run_tag_schema_fixture_case "$tag_schema_fixture"
done

# close-env must own verifier process and schema failures so its fail() path
# records cleanup_failed and a stable lease error.
cat > "$tmp_dir/fake-bin/injected-cleanup-verifier" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = verify-live ]; then
  jq -jr '.verifier.stdout' "$INJECTED_VERIFIER_FIXTURE"
  exit "$(jq -r '.verifier.rc' "$INJECTED_VERIFIER_FIXTURE")"
fi
exec "$REAL_CLEANUP_VERIFIER" "$@"
EOF
chmod +x "$tmp_dir/fake-bin/injected-cleanup-verifier"

run_verifier_fixture_case() {
  local verifier_fixture="$1"
  local verifier_env_id verifier_out verifier_rc verifier_lease
  local verifier_expected verifier_actual
  verifier_env_id="$(jq -r '.env_id' "$verifier_fixture")"
  env "${lease_env[@]}" "$LEASE" open "$verifier_env_id" >/dev/null
  set +e
  verifier_out="$(env "${lease_env[@]}" \
    PATH="$tmp_dir/fake-bin:$PATH" PREVIEW_ROOT="$tmp_dir/preview" OPERATOR_CIDR=test-cidr \
    CLEANUP_VERIFIER_SH="$tmp_dir/fake-bin/injected-cleanup-verifier" \
    REAL_CLEANUP_VERIFIER="$VERIFIER" INJECTED_VERIFIER_FIXTURE="$verifier_fixture" \
    TAG_REQUERY_OFFSETS=0 CLEANUP_VERIFY_DEADLINE_SECONDS=0 \
    "$REPO_ROOT/scripts/close-env.sh" "$verifier_env_id" 2>&1)"
  verifier_rc=$?
  set -e
  verifier_lease="$(env "${lease_env[@]}" "$LEASE" get "$verifier_env_id")"
  verifier_expected="$(jq -c '.expected' "$verifier_fixture")"
  verifier_actual="$(jq -c '{status,error}' <<< "$verifier_lease")"
  if [ "$verifier_rc" -eq 0 ] || [ "$verifier_actual" != "$verifier_expected" ]; then
    echo "FAIL: verifier invocation failure must use close-env fail() (fixture $(basename "$verifier_fixture"))" >&2
    echo "actual:   $verifier_actual (rc=$verifier_rc: $verifier_out)" >&2
    echo "expected: $verifier_expected" >&2
    exit 1
  fi
  pass "$(jq -r '.name' "$verifier_fixture") records cleanup_failed"
}
for verifier_fixture in \
  "$FIXTURES/verifier-exit-failure.json" \
  "$FIXTURES/verifier-malformed-output.json" \
  "$FIXTURES/verifier-contradictory-summary.json" \
  "$FIXTURES/verifier-invalid-outcome.json" \
  "$FIXTURES/verifier-passed-with-live.json"; do
  run_verifier_fixture_case "$verifier_fixture"
done

# A later scheduled tag query cannot be erased by an earlier successful query:
# incomplete discovery must remain indeterminate and fail stage 1.
tag_fixture="$FIXTURES/tag-requery-incomplete.json"
tag_env_id="$(jq -r '.env_id' "$tag_fixture")"
tag_offsets="$(jq -r '.tag_requery_offsets' "$tag_fixture")"
tag_fail_call="$(jq -r '.fail_on_tag_call' "$tag_fixture")"
env "${lease_env[@]}" "$LEASE" open "$tag_env_id" >/dev/null
set +e
tag_out="$(env "${lease_env[@]}" \
  PATH="$tmp_dir/fake-bin:$PATH" PREVIEW_ROOT="$tmp_dir/preview" OPERATOR_CIDR=test-cidr \
  FAKE_TAG_CALLS_FILE="$tmp_dir/tag-query-count" FAKE_TAG_FAIL_ON_CALL="$tag_fail_call" \
  TAG_REQUERY_OFFSETS="$tag_offsets" CLEANUP_VERIFY_DEADLINE_SECONDS=0 \
  "$REPO_ROOT/scripts/close-env.sh" "$tag_env_id" 2>&1)"
tag_rc=$?
set -e
tag_lease="$(env "${lease_env[@]}" "$LEASE" get "$tag_env_id")"
tag_expected="$(jq -c '.expected' "$tag_fixture")"
tag_actual="$(jq -c '{
  status,
  candidate_id: .manifest.verification_runs[-1].results[]
    | select(.id == "tag-inventory-incomplete")
    | .id,
  indeterminate: .manifest.verification_runs[-1].summary.indeterminate
}' <<< "$tag_lease")"
if [ "$tag_rc" -eq 0 ] || [ "$tag_actual" != "$tag_expected" ]; then
  echo "FAIL: a failed later tag query must retain indeterminate discovery evidence" >&2
  echo "actual:   $tag_actual (rc=$tag_rc: $tag_out)" >&2
  echo "expected: $tag_expected" >&2
  exit 1
fi
pass "a failed later tag re-query retains an indeterminate discovery candidate"

# A failed apply may only close the lease generation that its successful CAS
# open returned. A later generation belongs to a different run.
generation_fixture="$FIXTURES/lease-generation-mismatch.json"
generation_env_id="$(jq -r '.env_id' "$generation_fixture")"
supplied_generation="$(jq -r '.supplied_generation' "$generation_fixture")"
env "${lease_env[@]}" "$LEASE" open "$generation_env_id" >/dev/null
set +e
generation_out="$(env "${lease_env[@]}" \
  ENV_ID="$generation_env_id" PATH="$tmp_dir/fake-bin:$PATH" \
  PREVIEW_ROOT="$tmp_dir/preview" OPERATOR_CIDR=test-cidr \
  "$REPO_ROOT/scripts/close-env.sh" --generation "$supplied_generation" "$generation_env_id" 2>&1)"
generation_rc=$?
set -e
generation_lease="$(env "${lease_env[@]}" "$LEASE" get "$generation_env_id")"
generation_expected="$(jq -c '.expected' "$generation_fixture")"
generation_actual="$(jq -cn \
  --argjson exit_code "$generation_rc" \
  --arg status "$(jq -r '.status' <<< "$generation_lease")" \
  --argjson cleanup_attempt "$(jq -r '.cleanup_attempt' <<< "$generation_lease")" \
  '{exit_code:$exit_code,status:$status,cleanup_attempt:$cleanup_attempt}')"
if [ "$generation_actual" != "$generation_expected" ] || \
   ! grep -q 'lease generation mismatch' <<< "$generation_out"; then
  echo "FAIL: close must refuse a lease generation owned by another run" >&2
  echo "actual:   $generation_actual ($generation_out)" >&2
  echo "expected: $generation_expected" >&2
  exit 1
fi
pass "generation mismatch exits non-zero without transitioning the lease"

# An owner-bound close must refuse a lease acquired by another run with its own
# exit code and without claiming or transitioning cleanup.
owner_guard_env_id=owner-guard
env "${lease_env[@]}" "$LEASE" open "$owner_guard_env_id" \
  --owner run-owner-a --manifest "$atomic_manifest" >/dev/null
set +e
owner_guard_out="$(env "${lease_env[@]}" \
  ENV_ID="$owner_guard_env_id" PATH="$tmp_dir/fake-bin:$PATH" \
  PREVIEW_ROOT="$tmp_dir/preview" OPERATOR_CIDR=test-cidr \
  "$REPO_ROOT/scripts/close-env.sh" --generation 1 --owner run-owner-b \
  "$owner_guard_env_id" 2>&1)"
owner_guard_rc=$?
set -e
owner_guard_lease="$(env "${lease_env[@]}" "$LEASE" get "$owner_guard_env_id")"
if [ "$owner_guard_rc" -ne 4 ] || \
   ! grep -Fq 'lease owner mismatch' <<< "$owner_guard_out" || \
   ! jq -e '.status == "open" and .cleanup_attempt == 0' <<< "$owner_guard_lease" >/dev/null; then
  echo "FAIL: owner mismatch must exit 4 without transitioning the lease" >&2
  echo "rc=$owner_guard_rc output=$owner_guard_out" >&2
  exit 1
fi
pass "owner mismatch exits 4 without claiming or transitioning cleanup"

# CAS race: a second writer bumps the object's ETag between read and write;
# the stale writer must lose loudly (exit 3), never overwrite.
env "${lease_env[@]}" "$LEASE" open cas-race >/dev/null
set +e
race_out="$(env "${lease_env[@]}" FAKE_S3_RACE=1 "$LEASE" begin-cleanup cas-race 2>&1)"
race_rc=$?
set -e
if [ "$race_rc" -ne 3 ] || ! grep -q 'lost the CAS race' <<< "$race_out"; then
  echo "FAIL: a lost compare-and-swap must exit 3 and say so (rc=$race_rc: $race_out)" >&2
  exit 1
fi
if [ "$(env "${lease_env[@]}" "$LEASE" get cas-race | jq -r '.status')" != open ]; then
  echo "FAIL: the losing writer must not have changed the lease" >&2
  exit 1
fi
pass "a lost compare-and-swap race exits 3 without mutating the lease"

# A lease READ error must abort the close (never "no lease; nothing to close").
set +e
read_err_out="$(env "${lease_env[@]}" FAKE_S3_FAIL=1 \
  PATH="$tmp_dir/fake-bin:$PATH" PREVIEW_ROOT="$tmp_dir/preview" OPERATOR_CIDR=test-cidr \
  "$REPO_ROOT/scripts/close-env.sh" read-error-case 2>&1)"
read_err_rc=$?
set -e
if [ "$read_err_rc" -ne 2 ] || ! grep -q 'could not read the lease' <<< "$read_err_out"; then
  echo "FAIL: a lease read error must abort the close with a non-zero exit (rc=$read_err_rc: $read_err_out)" >&2
  exit 1
fi
pass "a lease read error aborts the close instead of reporting nothing to close"

echo "PASS: cleanup verifier suite ($pass_count cases)"
