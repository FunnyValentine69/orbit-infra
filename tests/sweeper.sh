#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/sweeper"
SWEEPER="${SWEEPER:-$REPO_ROOT/scripts/sweep.sh}"
LEASE="${LEASE:-$REPO_ROOT/scripts/lease.sh}"
AWS_WRAPPER="$REPO_ROOT/scripts/aws-cli.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
fake_s3="$tmp_dir/fake-s3"
fake_state="$tmp_dir/fake-state"
mkdir -p "$tmp_dir/bin" "$fake_s3" "$fake_state"

pass_count=0
pass() {
  pass_count=$((pass_count + 1))
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cat > "$tmp_dir/bin/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

original_args="$*"
printf '%s\n' "$original_args" >> "$FAKE_AWS_CALL_LOG"

service="$1"
operation="$2"
shift 2
bucket=""
key=""
body=""
etag_match=""
if_none=""
destination=""
delete_arg=""
key_marker=""
version_id_marker=""
task_definition=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bucket) bucket="$2"; shift 2 ;;
    --key) key="$2"; shift 2 ;;
    --body) body="$2"; shift 2 ;;
    --if-match) etag_match="$2"; shift 2 ;;
    --if-none-match) if_none="$2"; shift 2 ;;
    --delete) delete_arg="$2"; shift 2 ;;
    --key-marker) key_marker="$2"; shift 2 ;;
    --version-id-marker) version_id_marker="$2"; shift 2 ;;
    --task-definition) task_definition="$2"; shift 2 ;;
    --prefix) key="$2"; shift 2 ;;
    --endpoint-url|--cli-connect-timeout|--cli-read-timeout|--content-type|--output)
      shift 2
      ;;
    --no-paginate) shift ;;
    --*) shift ;;
    *) destination="$1"; shift ;;
  esac
done

store="$FAKE_S3_DIR/${key//\//_}.body"
etag_file="$FAKE_S3_DIR/${key//\//_}.etag"

case "$service $operation" in
  "s3api list-objects-v2")
    contents='[]'
    for lease_file in "$FAKE_S3_DIR"/leases_*.body; do
      [ -e "$lease_file" ] || continue
      env_id="$(jq -r '.env_id' "$lease_file")"
      contents="$(jq -c --arg key "leases/${env_id}.json" '. + [{Key:$key}]' <<< "$contents")"
    done
    jq -cn --argjson contents "$contents" '{Contents:$contents}'
    ;;
  "s3api get-object")
    if [ ! -f "$store" ]; then
      echo 'An error occurred (NoSuchKey) when calling the GetObject operation' >&2
      exit 254
    fi
    cp "$store" "$destination"
    printf '{"ETag":"%s"}\n' "$(cat "$etag_file")"
    ;;
  "s3api put-object")
    current=""
    [ ! -f "$etag_file" ] || current="$(cat "$etag_file")"
    if { [ "$if_none" = "*" ] && [ -n "$current" ]; } || \
       { [ -n "$etag_match" ] && [ "$etag_match" != "$current" ]; }; then
      echo 'An error occurred (PreconditionFailed) when calling the PutObject operation' >&2
      exit 254
    fi
    if [ -n "${FAKE_PUT_RACE_ON_STATUS:-}" ] && \
       [ "$(jq -r '.status // empty' "$body")" = "$FAKE_PUT_RACE_ON_STATUS" ]; then
      printf '%s\n' "$(( ${current:-0} + 1 ))" > "$etag_file"
      echo 'An error occurred (PreconditionFailed) when calling the PutObject operation' >&2
      exit 254
    fi
    if [ "${FAKE_STAGE2_COMPLETION_RACE:-0}" = 1 ] && \
       [ "$(jq -r '.status // empty' "$body")" = closed ]; then
      env_id="$(jq -r '.env_id' "$store")"
      jq '.manifest.concurrent_stage2_write = true' "$store" > "$store.next"
      mv "$store.next" "$store"
      current=$((current + 1))
      printf '%s\n' "$current" > "$etag_file"
      state_file="$FAKE_STATE_DIR/envs_preview_${env_id}.tfstate.json"
      jq '. + [{Key:("envs/preview/" + $env_id + ".tfstate"),VersionId:"late-version",type:"version"}]' \
        --arg env_id "$env_id" "$state_file" > "$state_file.next"
      mv "$state_file.next" "$state_file"
      echo 'An error occurred (PreconditionFailed) when calling the PutObject operation' >&2
      exit 254
    fi
    next=$(( ${current:-0} + 1 ))
    cp "$body" "$store"
    printf '%s\n' "$next" > "$etag_file"
    printf '{"ETag":"%s"}\n' "$next"
    ;;
  "s3api delete-object")
    current=""
    [ ! -f "$etag_file" ] || current="$(cat "$etag_file")"
    if [ -z "$current" ]; then
      echo 'An error occurred (NoSuchKey) when calling the DeleteObject operation' >&2
      exit 254
    fi
    if [ "${FAKE_PRUNE_CAS_LOSS:-0}" = 1 ]; then
      jq '.status = "open" | .generation += 1' "$store" > "$store.next"
      mv "$store.next" "$store"
      current=$((current + 1))
      printf '%s\n' "$current" > "$etag_file"
    fi
    if [ -n "$etag_match" ] && [ "$etag_match" != "$current" ]; then
      echo 'An error occurred (PreconditionFailed) when calling the DeleteObject operation: 412' >&2
      exit 254
    fi
    rm -f "$store" "$etag_file"
    echo '{"DeleteMarker":true}'
    ;;
  "s3api list-object-versions")
    state_file="$FAKE_STATE_DIR/${key//\//_}.json"
    [ -f "$state_file" ] || printf '[]\n' > "$state_file"
    state_entries="$(cat "$state_file")"
    if [ -n "${FAKE_LIST_VERSIONS_AFTER_DELETE:-}" ] && \
       [ -s "$FAKE_DELETE_CALLS_FILE" ]; then
      state_entries="$(jq -ce '
        .post_delete_state_versions
        | select(type == "array")
      ' "$FAKE_LIST_VERSIONS_AFTER_DELETE")"
    fi
    start=0
    if [ -n "$version_id_marker" ]; then
      start="$(jq -er --arg marker "$version_id_marker" \
        '([.[].VersionId] | index($marker)) as $index | select($index != null) | $index + 1' \
        <<< "$state_entries")"
    fi
    page_size="${FAKE_PAGE_SIZE:-2}"
    page="$(jq -c --argjson start "$start" --argjson size "$page_size" \
      '.[$start:($start + $size)]' <<< "$state_entries")"
    total="$(jq 'length' <<< "$state_entries")"
    page_count="$(jq 'length' <<< "$page")"
    if [ $((start + page_count)) -lt "$total" ]; then
      truncated=true
      next_version="$(jq -r '.[-1].VersionId' <<< "$page")"
      jq -cn --arg key "$key" --arg next_version "$next_version" --argjson page "$page" '
        {
          Versions: [$page[] | select(.type == "version") | {Key,VersionId}],
          DeleteMarkers: [$page[] | select(.type == "delete-marker") | {Key,VersionId}],
          IsTruncated: true,
          NextKeyMarker: $key,
          NextVersionIdMarker: $next_version
        }'
    else
      jq -cn --argjson page "$page" '
        {
          Versions: [$page[] | select(.type == "version") | {Key,VersionId}],
          DeleteMarkers: [$page[] | select(.type == "delete-marker") | {Key,VersionId}],
          IsTruncated: false
        }'
    fi
    ;;
  "s3api delete-objects")
    delete_calls=1
    if [ -f "$FAKE_DELETE_CALLS_FILE" ]; then
      delete_calls=$(( $(cat "$FAKE_DELETE_CALLS_FILE") + 1 ))
    fi
    printf '%s\n' "$delete_calls" > "$FAKE_DELETE_CALLS_FILE"
    if [ "$delete_calls" -eq "${FAKE_DELETE_FAIL_CALL:-0}" ]; then
      echo 'An error occurred (ServiceUnavailable) when calling the DeleteObjects operation' >&2
      exit 254
    fi
    if [ -n "${FAKE_DELETE_OBJECTS_ERRORS:-}" ]; then
      errors="$(jq -ce 'select(type == "array" and length > 0)' \
        <<< "$FAKE_DELETE_OBJECTS_ERRORS")"
      jq -cn --argjson errors "$errors" '{Deleted:[],Errors:$errors}'
      exit 0
    fi
    payload="${delete_arg#file://}"
    deleted="$(jq -c '.Objects' "$payload")"
    key="$(jq -r '.Objects[0].Key' "$payload")"
    state_file="$FAKE_STATE_DIR/${key//\//_}.json"
    jq --argjson deleted "$deleted" '
      map(. as $entry
        | select(any($deleted[]; .Key == $entry.Key and .VersionId == $entry.VersionId) | not))' \
      "$state_file" > "$state_file.next"
    mv "$state_file.next" "$state_file"
    if [ "${FAKE_LEASE_CHANGE_AFTER_DELETE:-0}" = 1 ] && [ "$delete_calls" -eq 1 ]; then
      env_id="${key#envs/preview/}"
      env_id="${env_id%.tfstate}"
      lease_store="$FAKE_S3_DIR/leases_${env_id}.json.body"
      lease_etag="$FAKE_S3_DIR/leases_${env_id}.json.etag"
      jq '.status = "closed"' "$lease_store" > "$lease_store.next"
      mv "$lease_store.next" "$lease_store"
      printf '%s\n' "$(( $(cat "$lease_etag") + 1 ))" > "$lease_etag"
    fi
    jq -cn --argjson deleted "$deleted" '{Deleted:$deleted,Errors:[]}'
    ;;
  "ecs describe-task-definition")
    expected="$(jq -r '.task_definition_arn' "$FAKE_SCENARIO_FILE")"
    [ "$task_definition" = "$expected" ] || {
      echo "unexpected task definition" >&2
      exit 2
    }
    jq -jr '.describe.stdout' "$FAKE_SCENARIO_FILE"
    jq -jr '.describe.stderr' "$FAKE_SCENARIO_FILE" >&2
    exit "$(jq -r '.describe.rc' "$FAKE_SCENARIO_FILE")"
    ;;
  *)
    echo "unexpected fake AWS call: $service $operation ($original_args)" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$tmp_dir/bin/aws"

cat > "$tmp_dir/bin/close-env" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_CLOSE_LOG"
if [[ "$*" == *--force-retry* ]]; then
  echo "sweeper must never force stage 1" >&2
  exit 90
fi
if [ "${FAKE_REOPEN_BEFORE_CLOSE:-0}" = 1 ]; then
  env_id="${*: -1}"
  lease_store="$FAKE_S3_DIR/leases_${env_id}.json.body"
  lease_etag="$FAKE_S3_DIR/leases_${env_id}.json.etag"
  jq '
    .generation += 1
    | .status = "open"
    | .cleanup_attempt = 0
    | .next_retry_at = null
    | .manual_intervention_required = false
    | .stage2_claim = null
  ' "$lease_store" > "$lease_store.next"
  mv "$lease_store.next" "$lease_store"
  printf '%s\n' "$(( $(cat "$lease_etag") + 1 ))" > "$lease_etag"
  exec "$REAL_CLOSE_ENV_SH" "$@"
fi
EOF
chmod +x "$tmp_dir/bin/close-env"

common_env=(
  "AWS_CLI_BIN=$tmp_dir/bin/aws"
  "AWS_CLI_SH=$AWS_WRAPPER"
  "CLOSE_ENV_SH=$tmp_dir/bin/close-env"
  "FAKE_AWS_CALL_LOG=$tmp_dir/aws-calls.log"
  "FAKE_CLOSE_LOG=$tmp_dir/close-calls.log"
  "FAKE_DELETE_CALLS_FILE=$tmp_dir/delete-calls"
  "FAKE_S3_DIR=$fake_s3"
  "FAKE_STATE_DIR=$fake_state"
  "LEASE_BUCKET=test-state"
  "LEASE_SH=$LEASE"
  "STATE_BUCKET=test-state"
  "SWEEP_NOW_EPOCH=2000000000"
)

run_aws() {
  env -u AWS_ENDPOINT_URL -u AWS_PROFILE \
    "${common_env[@]}" TARGET=aws "$@"
}

run_localstack() {
  env -u AWS_PROFILE \
    "${common_env[@]}" \
    TARGET=localstack \
    AWS_ENDPOINT_URL=http://localhost:4566 \
    AWS_ACCESS_KEY_ID=test \
    AWS_SECRET_ACCESS_KEY=test \
    AWS_DEFAULT_REGION=test-region \
    AWS_EC2_METADATA_DISABLED=true \
    "$@"
}

reset_store() {
  rm -f "$fake_s3"/* "$fake_state"/* "$tmp_dir/delete-calls"
  : > "$tmp_dir/aws-calls.log"
  : > "$tmp_dir/close-calls.log"
}

store_lease() {
  local lease_json="$1"
  local env_id
  env_id="$(jq -r '.env_id' <<< "$lease_json")"
  printf '%s\n' "$lease_json" > "$fake_s3/leases_${env_id}.json.body"
  printf '1\n' > "$fake_s3/leases_${env_id}.json.etag"
}

store_fixture() {
  local fixture="$1"
  local env_id target arn lease state_key
  env_id="$(jq -r '.env_id' "$fixture")"
  target="$(jq -r '.target' "$fixture")"
  arn="$(jq -r '.task_definition_arn' "$fixture")"
  lease="$(jq -cn --arg env_id "$env_id" --arg target "$target" --arg arn "$arn" '
    {
      env_id:$env_id,
      status:"closing",
      generation:1,
      updated_at:"2033-05-18T03:32:20Z",
      cleanup_attempt:1,
      next_retry_at:null,
      manual_intervention_required:false,
      manifest:{
        target:$target,
        candidates:[{
          resource_type:"ecs:task-definition",
          id:$arn,
          arn:$arn,
          parent_id:null,
          sources:["terraform-state"],
          tag_entry:null,
          force_delete:false
        }],
        allowances:[],
        verification_runs:[{
          passed:true,
          summary:{gone:1,pending:0,live:0,indeterminate:0},
          results:[{resource_type:"ecs:task-definition",id:$arn,outcome:"gone"}]
        }]
      }
    }')"
  if [ "$target" = localstack ]; then
    lease="$(jq -c --arg arn "$arn" '.manifest.allowances = [{
      id:"localstack-delete-task-definitions-inactive",
      arn:$arn,
      error_code:"InternalFailure",
      recorded_at:"2033-05-18T03:30:00Z"
    }]' <<< "$lease")"
  fi
  if jq -e 'has("manifest_allowances")' "$fixture" >/dev/null; then
    lease="$(jq -c --argjson allowances "$(jq -c '.manifest_allowances' "$fixture")" \
      '.manifest.allowances = $allowances' <<< "$lease")"
  fi
  if jq -e 'has("verification_passed")' "$fixture" >/dev/null; then
    lease="$(jq -c --argjson passed "$(jq -c '.verification_passed' "$fixture")" \
      '.manifest.verification_runs[-1].passed = $passed' <<< "$lease")"
  fi
  store_lease "$lease"
  state_key="envs_preview_${env_id}.tfstate.json"
  jq -c '.state_versions' "$fixture" > "$fake_state/$state_key"
}

lease_status() {
  local target="$1"
  local env_id="$2"
  if [ "$target" = aws ]; then
    run_aws "$LEASE" get "$env_id" | jq -r '.status'
  else
    run_localstack "$LEASE" get "$env_id" | jq -r '.status'
  fi
}

reset_store
while IFS= read -r lease; do
  store_lease "$lease"
done < <(jq -c '.leases[]' "$FIXTURES/discover-cases.json")
discover_output="$(run_aws "$SWEEPER" discover)"
discover_json="$(jq -sc . <<< "$discover_output")"
expected="$(jq -c '.expected' "$FIXTURES/discover-cases.json")"
if ! jq -e --argjson expected "$expected" '
  length == ($expected | length)
  and all(.[];
    has("env_id") and has("status") and has("generation") and has("updated_at")
    and has("cleanup_attempt") and has("next_retry_at")
    and has("manual_intervention_required") and has("classification") and has("reason")
    and .classification == $expected[.env_id].classification
    and .reason == $expected[.env_id].reason)
' <<< "$discover_json" >/dev/null; then
  fail "discover did not classify every status/age boundary correctly: $discover_json"
fi
pass "discover emits the lease inventory and classifies status/age boundaries"

reset_store
bad_inventory="$(jq -c '.leases[0] | .env_id = "bad_id"' "$FIXTURES/discover-cases.json")"
store_lease "$bad_inventory"
set +e
bad_inventory_output="$(run_aws "$SWEEPER" discover 2>&1)"
bad_inventory_rc=$?
set -e
[ "$bad_inventory_rc" -eq 2 ] || fail "invalid inventory env_id must exit 2"
grep -Fq 'malformed record' <<< "$bad_inventory_output" || fail "invalid inventory env_id reason missing"
pass "discover rejects environment IDs outside the preview contract"

run_stage1_case() {
  local env_id="$1"
  local expected_fragment="$2"
  local lease generation status
  lease="$(jq -c --arg env_id "$env_id" '.leases[] | select(.env_id == $env_id)' "$FIXTURES/discover-cases.json")"
  generation="$(jq -r '.generation' <<< "$lease")"
  status="$(jq -r '.status' <<< "$lease")"
  reset_store
  store_lease "$lease"
  output="$(run_aws "$SWEEPER" env "$env_id")"
  grep -Fq "$expected_fragment" <<< "$output" || fail "missing Stage-1 action output for $env_id"
  [ "$(cat "$tmp_dir/close-calls.log")" = "--generation $generation --from $status $env_id" ] || \
    fail "Stage 1 must pass its classified generation and status without --force-retry"
}
run_stage1_case stale-open "stage 1"
run_stage1_case retry-due "stage 1"
pass "stale-open and due-retry leases invoke unforced Stage 1 from a fresh read"

reset_store
stale_replaced="$(jq -c '.leases[] | select(.env_id == "stale-open")' "$FIXTURES/discover-cases.json")"
store_lease "$stale_replaced"
printf '[{"sentinel":"untouched"}]\n' > "$fake_state/envs_preview_stale-open.tfstate.json"
set +e
stale_replaced_output="$(FAKE_REOPEN_BEFORE_CLOSE=1 REAL_CLOSE_ENV_SH="$REPO_ROOT/scripts/close-env.sh" \
  OPERATOR_CIDR=test-cidr run_aws "$SWEEPER" env stale-open 2>&1)"
stale_replaced_rc=$?
set -e
stale_replaced_lease="$(run_aws "$LEASE" get stale-open)"
[ "$stale_replaced_rc" -eq 3 ] || fail "generation-replaced stale-open must exit 3"
jq -e '.generation == 2 and .status == "open" and .cleanup_attempt == 0' \
  <<< "$stale_replaced_lease" >/dev/null || fail "Stage 1 claimed the replacement generation"
jq -e '. == [{sentinel:"untouched"}]' "$fake_state/envs_preview_stale-open.tfstate.json" >/dev/null || \
  fail "generation-replaced Stage 1 touched retained resources"
if grep -Eq '^s3api put-object |^ecs |^resourcegroupstaggingapi ' "$tmp_dir/aws-calls.log"; then
  fail "generation-replaced Stage 1 reached a lease mutation or resource API"
fi
grep -Eq 'lease (generation|status) mismatch' <<< "$stale_replaced_output" || \
  fail "generation-replaced Stage 1 refusal reason missing"
pass "stale-open generation replacement is refused before Stage 1 touches resources"

reset_store
exhausted="$(jq -c '.leases[] | select(.env_id == "retry-max")' "$FIXTURES/discover-cases.json")"
store_lease "$exhausted"
budget_output="$(run_aws "$SWEEPER" env retry-max)"
grep -Fq 'automatic cleanup retry budget is exhausted' <<< "$budget_output" || fail "retry exhaustion reason missing"
[ ! -s "$tmp_dir/close-calls.log" ] || fail "sweeper forced past the Stage-1 retry budget"
pass "sweeper never forces a cleanup_failed lease past the retry budget"

reset_store
manual_lease="$(jq -c '.leases[] | select(.env_id == "retry-manual")' "$FIXTURES/discover-cases.json")"
store_lease "$manual_lease"
manual_output="$(run_aws "$SWEEPER" env retry-manual)"
manual_after="$(run_aws "$LEASE" get retry-manual)"
grep -Fq 'manual intervention is required' <<< "$manual_output" || fail "manual-intervention no-op reason missing"
[ ! -s "$tmp_dir/close-calls.log" ] || fail "manual-intervention lease invoked Stage 1"
[ "$manual_after" = "$manual_lease" ] || fail "manual-intervention no-op mutated the lease"
pass "manual-intervention lease is a reasoned no-op through sweep env"

reset_store
happy_fixture="$FIXTURES/aws-deleted-client-exception.json"
store_fixture "$happy_fixture"
FAKE_SCENARIO_FILE="$happy_fixture" SWEEP_DELETE_BATCH_SIZE=2 run_aws "$SWEEPER" env aws-happy >/dev/null
[ "$(lease_status aws aws-happy)" = closed ] || fail "AWS deleted task definition did not close the lease"
[ "$(jq 'length' "$fake_state/envs_preview_aws-happy.tfstate.json")" -eq 0 ] || fail "state versions/delete markers remain after Stage 2"
happy_lease="$(run_aws "$LEASE" get aws-happy)"
happy_arn="$(jq -r '.task_definition_arn' "$happy_fixture")"
jq -e --arg arn "$happy_arn" '
  .manifest.stage2_runs[-1].in_job == false
  and .manifest.stage2_runs[-1].target == "aws"
  and .manifest.stage2_runs[-1].state_key == "envs/preview/aws-happy.tfstate"
  and .manifest.stage2_runs[-1].deleted_task_definition_arns == [$arn]
  and (.manifest.stage2_runs[-1].verified_empty_at | type == "string" and length > 0)
' <<< "$happy_lease" >/dev/null || fail "completed AWS Stage 2 proof was not recorded"
if [ "$(grep -c '^s3api delete-objects ' "$tmp_dir/aws-calls.log")" -ne 2 ]; then
  fail "paginated state inventory must delete versions and markers in bounded batches"
fi
pass "AWS Stage 2 accepts only the exact deleted ClientException, deletes every state version, and closes"

reset_store
pending_fixture="$FIXTURES/aws-delete-in-progress.json"
store_fixture "$pending_fixture"
pending_output="$(FAKE_SCENARIO_FILE="$pending_fixture" run_aws "$SWEEPER" env aws-pending)"
pending_lease="$(run_aws "$LEASE" get aws-pending)"
jq -e '.status == "closing" and .stage2_claim == null' <<< "$pending_lease" >/dev/null || \
  fail "DELETE_IN_PROGRESS must keep closing without stranding a Stage 2 claim"
grep -Fq 'DELETE_IN_PROGRESS' <<< "$pending_output" || fail "pending task definition ARN/status was not printed"
[ "$(jq 'length' "$fake_state/envs_preview_aws-pending.tfstate.json")" -eq 1 ] || fail "pending Stage 2 touched retained state"
pass "DELETE_IN_PROGRESS remains pending with state retained"

reset_store
malformed_fixture="$FIXTURES/aws-malformed-describe.json"
store_fixture "$malformed_fixture"
set +e
malformed_output="$(FAKE_SCENARIO_FILE="$malformed_fixture" run_aws "$SWEEPER" env aws-bad 2>&1)"
malformed_rc=$?
set -e
[ "$malformed_rc" -eq 1 ] || fail "malformed describe must exit 1, got $malformed_rc"
[ "$(lease_status aws aws-bad)" = cleanup_failed ] || fail "malformed describe did not record cleanup_failed"
grep -Fq 'indeterminate' <<< "$malformed_output" || fail "malformed describe failure reason missing"
[ "$(jq 'length' "$fake_state/envs_preview_aws-bad.tfstate.json")" -eq 1 ] || fail "indeterminate Stage 2 touched retained state"
pass "malformed DescribeTaskDefinition fails closed through a lease transition"

reset_store
describe_error_fixture="$FIXTURES/aws-clientexception-mismatch.json"
store_fixture "$describe_error_fixture"
set +e
describe_error_output="$(FAKE_SCENARIO_FILE="$describe_error_fixture" \
  run_aws "$SWEEPER" env aws-denied 2>&1)"
describe_error_rc=$?
set -e
describe_error_lease="$(run_aws "$LEASE" get aws-denied)"
[ "$describe_error_rc" -eq 1 ] || fail "non-deleted ClientException must exit 1"
jq -e '.status == "cleanup_failed" and .error == "task-definition describe was indeterminate"' \
  <<< "$describe_error_lease" >/dev/null || fail "non-deleted ClientException did not record cleanup_failed"
[ "$(jq 'length' "$fake_state/envs_preview_aws-denied.tfstate.json")" -eq 1 ] || \
  fail "non-deleted ClientException touched retained state"
grep -Fq 'task-definition describe was indeterminate' <<< "$describe_error_output" || \
  fail "non-deleted ClientException failure reason missing"
pass "non-deleted ClientException fails closed with its error recorded"

reset_store
store_fixture "$happy_fixture"
bad_candidate="$(run_aws "$LEASE" get aws-happy | jq -c '
  .manifest.candidates[0].id = "not-an-arn"
  | .manifest.candidates[0].arn = "not-an-arn"')"
store_lease "$bad_candidate"
set +e
bad_candidate_output="$(FAKE_SCENARIO_FILE="$happy_fixture" run_aws "$SWEEPER" env aws-happy 2>&1)"
bad_candidate_rc=$?
set -e
[ "$bad_candidate_rc" -eq 1 ] || fail "malformed candidate must exit 1, got $bad_candidate_rc"
[ "$(lease_status aws aws-happy)" = cleanup_failed ] || fail "malformed candidate did not record cleanup_failed"
grep -Fq 'candidates are malformed' <<< "$bad_candidate_output" || fail "malformed candidate reason missing"
if grep -q '^ecs describe-task-definition ' "$tmp_dir/aws-calls.log"; then
  fail "malformed candidate reached the ECS API"
fi
[ "$(jq 'length' "$fake_state/envs_preview_aws-happy.tfstate.json")" -eq 3 ] || \
  fail "malformed candidate touched retained state"
pass "Stage 2 validates task-definition ARNs before probing ECS"

reset_store
local_fixture="$FIXTURES/localstack-inactive-allowance.json"
store_fixture "$local_fixture"
FAKE_SCENARIO_FILE="$local_fixture" SWEEP_IN_JOB=true run_localstack "$SWEEPER" env local-allow >/dev/null
[ "$(lease_status localstack local-allow)" = closed ] || fail "LocalStack allowance did not close the lease"
local_lease="$(run_localstack "$LEASE" get local-allow)"
jq -e '
  .manifest.stage2_allowances == [{
    id:"localstack-delete-task-definitions-inactive",
    arn:"arn:aws:ecs:region:account:task-definition/stage-two:4",
    recorded_at:.manifest.stage2_allowances[0].recorded_at
  }]
  and .manifest.stage2_runs[-1].in_job == true
' <<< "$local_lease" >/dev/null || fail "LocalStack Stage-2 allowance/in-job evidence missing"
[ "$(jq 'length' "$fake_state/envs_preview_local-allow.tfstate.json")" -eq 0 ] || fail "LocalStack state versions remain"
pass "recorded LocalStack allowance permits INACTIVE and records in-job Stage 2 evidence"

reset_store
aws_allowance_fixture="$FIXTURES/aws-inactive-with-localstack-allowance.json"
store_fixture "$aws_allowance_fixture"
aws_allowance_output="$(FAKE_SCENARIO_FILE="$aws_allowance_fixture" \
  run_aws "$SWEEPER" env aws-allow)"
aws_allowance_lease="$(run_aws "$LEASE" get aws-allow)"
jq -e '.status == "closing" and ((.manifest.stage2_allowances // []) | length) == 0' \
  <<< "$aws_allowance_lease" >/dev/null || fail "AWS target consumed the LocalStack allowance"
grep -Fq 'status=INACTIVE' <<< "$aws_allowance_output" || fail "AWS INACTIVE task definition was not pending"
[ "$(jq 'length' "$fake_state/envs_preview_aws-allow.tfstate.json")" -eq 1 ] || \
  fail "AWS target with LocalStack allowance touched retained state"
pass "AWS target ignores the LocalStack allowance and retains closing state"

reset_store
local_no_allowance_fixture="$FIXTURES/localstack-inactive-no-allowance.json"
store_fixture "$local_no_allowance_fixture"
local_no_allowance_output="$(FAKE_SCENARIO_FILE="$local_no_allowance_fixture" \
  run_localstack "$SWEEPER" env local-none)"
local_no_allowance_lease="$(run_localstack "$LEASE" get local-none)"
jq -e '.status == "closing"
  and .manifest.allowances == []
  and ((.manifest.stage2_allowances // []) | length) == 0' \
  <<< "$local_no_allowance_lease" >/dev/null || fail "unrecorded LocalStack allowance was synthesized"
grep -Fq 'status=INACTIVE' <<< "$local_no_allowance_output" || fail "LocalStack INACTIVE task definition was not pending"
[ "$(jq 'length' "$fake_state/envs_preview_local-none.tfstate.json")" -eq 1 ] || \
  fail "LocalStack without an allowance touched retained state"
pass "LocalStack INACTIVE without a recorded allowance remains pending"

reset_store
verification_failed_fixture="$FIXTURES/aws-verification-failed.json"
store_fixture "$verification_failed_fixture"
set +e
verification_failed_output="$(FAKE_SCENARIO_FILE="$verification_failed_fixture" \
  run_aws "$SWEEPER" env verify-fail 2>&1)"
verification_failed_rc=$?
set -e
verification_failed_lease="$(run_aws "$LEASE" get verify-fail)"
[ "$verification_failed_rc" -eq 1 ] || fail "passed:false Stage-1 verification must exit 1"
jq -e '.status == "cleanup_failed"
  and .error == "last Stage-1 verification did not pass with zero live and indeterminate results"' \
  <<< "$verification_failed_lease" >/dev/null || fail "passed:false Stage-1 verification did not fail closed"
[ "$(jq 'length' "$fake_state/envs_preview_verify-fail.tfstate.json")" -eq 1 ] || \
  fail "passed:false Stage-1 verification touched retained state"
grep -Fq 'last Stage-1 verification did not pass' <<< "$verification_failed_output" || \
  fail "passed:false Stage-1 verification failure reason missing"
pass "Stage 2 refuses a last verification run with passed false"

reset_store
store_fixture "$happy_fixture"
delete_errors_fixture="$FIXTURES/delete-objects-errors.json"
set +e
delete_errors_output="$(FAKE_SCENARIO_FILE="$happy_fixture" \
  FAKE_DELETE_OBJECTS_ERRORS="$(jq -c '.errors' "$delete_errors_fixture")" \
  run_aws "$SWEEPER" env aws-happy 2>&1)"
delete_errors_rc=$?
set -e
delete_errors_lease="$(run_aws "$LEASE" get aws-happy)"
[ "$delete_errors_rc" -eq 1 ] || fail "delete-objects Errors must exit 1"
jq -e '.status == "cleanup_failed"
  and .error == "state deletion failed before all versions were removed"
  and ((.manifest.stage2_runs // []) | length) == 0' \
  <<< "$delete_errors_lease" >/dev/null || fail "delete-objects Errors reached closed"
[ "$(jq 'length' "$fake_state/envs_preview_aws-happy.tfstate.json")" -eq 3 ] || \
  fail "delete-objects Errors did not retain remaining versions"
grep -Fq 'delete-objects reported 1 object-version errors' <<< "$delete_errors_output" || \
  fail "delete-objects Errors branch did not report the object-version error"
pass "delete-objects rc zero with Errors fails closed and retains versions"

reset_store
post_delete_fixture="$FIXTURES/aws-post-delete-relist.json"
store_fixture "$post_delete_fixture"
set +e
post_delete_output="$(FAKE_SCENARIO_FILE="$post_delete_fixture" \
  FAKE_LIST_VERSIONS_AFTER_DELETE="$post_delete_fixture" \
  run_aws "$SWEEPER" env aws-relist 2>&1)"
post_delete_rc=$?
set -e
post_delete_lease="$(run_aws "$LEASE" get aws-relist)"
[ "$post_delete_rc" -eq 1 ] || fail "post-delete retained version must exit 1"
jq -e '.status == "cleanup_failed"
  and .error == "state deletion failed: versions remain"
  and ((.manifest.stage2_runs // []) | length) == 0' \
  <<< "$post_delete_lease" >/dev/null || fail "post-delete retained version reached closed"
grep -Fq 'state deletion failed: versions remain' <<< "$post_delete_output" || \
  fail "post-delete retained version failure reason missing"
pass "post-delete re-list with a retained version fails closed"

reset_store
store_fixture "$happy_fixture"
set +e
delete_failure_output="$(FAKE_SCENARIO_FILE="$happy_fixture" FAKE_DELETE_FAIL_CALL=2 SWEEP_DELETE_BATCH_SIZE=2 \
  run_aws "$SWEEPER" env aws-happy 2>&1)"
delete_failure_rc=$?
set -e
[ "$delete_failure_rc" -eq 1 ] || fail "partial state deletion failure must exit 1"
[ "$(lease_status aws aws-happy)" = cleanup_failed ] || fail "partial state deletion failure did not record cleanup_failed"
[ "$(jq 'length' "$fake_state/envs_preview_aws-happy.tfstate.json")" -gt 0 ] || fail "failure fixture did not fail after a partial delete"
grep -Fq 'state deletion failed' <<< "$delete_failure_output" || fail "state deletion failure reason missing"
pass "partial state deletion failure never sets closed"

reset_store
store_fixture "$happy_fixture"
set +e
delete_race_output="$(FAKE_SCENARIO_FILE="$happy_fixture" FAKE_LEASE_CHANGE_AFTER_DELETE=1 \
  SWEEP_DELETE_BATCH_SIZE=2 run_aws "$SWEEPER" env aws-happy 2>&1)"
delete_race_rc=$?
set -e
[ "$delete_race_rc" -eq 3 ] || fail "lease change during state deletion must exit 3"
[ "$(lease_status aws aws-happy)" = closed ] || fail "concurrent lease change fixture did not land"
[ "$(jq 'length' "$fake_state/envs_preview_aws-happy.tfstate.json")" -eq 1 ] || \
  fail "sweeper deleted another state batch after the lease changed"
grep -Fq 'lease changed while Stage 2 was running' <<< "$delete_race_output" || \
  fail "state-delete lease race did not report the refusal"
pass "Stage 2 re-reads the lease before every state deletion batch"

reset_store
store_fixture "$happy_fixture"
set +e
cas_output="$(FAKE_SCENARIO_FILE="$happy_fixture" FAKE_STAGE2_COMPLETION_RACE=1 \
  run_aws "$SWEEPER" env aws-happy 2>&1)"
cas_rc=$?
set -e
cas_lease="$(run_aws "$LEASE" get aws-happy)"
[ "$cas_rc" -eq 3 ] || fail "closing-to-closed CAS race must exit 3, got $cas_rc"
jq -e '.status == "closing"
  and .manifest.concurrent_stage2_write == true
  and ((.manifest.stage2_runs // []) | length) == 0' \
  <<< "$cas_lease" >/dev/null || fail "losing atomic completion mutated the lease or its proof"
jq -e 'any(.[]; .VersionId == "late-version")' \
  "$fake_state/envs_preview_aws-happy.tfstate.json" >/dev/null || \
  fail "atomic completion race deleted the concurrently added state version"
grep -Fq 'lost the CAS race' <<< "$cas_output" || fail "CAS race did not report the lease refusal"
pass "atomic Stage 2 completion refuses an ETag race and leaves the new state version untouched"

reset_store
old_closed="$(jq -c '.leases[] | select(.env_id == "prune-old")' "$FIXTURES/discover-cases.json")"
store_lease "$old_closed"
expected_reopened="$(jq -c '.status = "open" | .generation += 1' <<< "$old_closed")"
set +e
prune_race_output="$(FAKE_PRUNE_CAS_LOSS=1 run_aws "$SWEEPER" env prune-old 2>&1)"
prune_race_rc=$?
set -e
set +e
prune_race_lease="$(run_aws "$LEASE" get prune-old 2>&1)"
prune_race_get_rc=$?
set -e
[ "$prune_race_get_rc" -eq 0 ] || \
  fail "prune CAS-loss lease read-back failed with rc $prune_race_get_rc: $prune_race_lease"
[ "$prune_race_rc" -eq 3 ] || fail "prune If-Match 412 must exit 3, got $prune_race_rc"
jq -e --argjson expected "$expected_reopened" '. == $expected' \
  <<< "$prune_race_lease" >/dev/null || fail "prune loser deleted or otherwise mutated the reopened lease"
grep -Fq 'lost the CAS race' <<< "$prune_race_output" || fail "prune If-Match 412 reason missing"
grep -E '^s3api delete-object .*--if-match ' "$tmp_dir/aws-calls.log" >/dev/null || \
  fail "prune CAS-loss case did not exercise the If-Match request"
pass "prune If-Match 412 exits 3 without deleting the concurrently changed lease"

reset_store
fresh_closed="$(jq -c '.leases[] | select(.env_id == "closed-seven")' "$FIXTURES/discover-cases.json")"
store_lease "$old_closed"
store_lease "$fresh_closed"
run_aws "$SWEEPER" env prune-old >/dev/null
set +e
run_aws "$LEASE" get prune-old >/dev/null 2>&1
pruned_get_rc=$?
set -e
[ "$pruned_get_rc" -eq 1 ] || fail "closed lease older than seven days was not pruned"
run_aws "$SWEEPER" env closed-seven >/dev/null
[ "$(lease_status aws closed-seven)" = closed ] || fail "seven-day boundary lease was pruned early"
grep -E '^s3api delete-object .*--if-match ' "$tmp_dir/aws-calls.log" >/dev/null || fail "lease prune did not use an ETag precondition"
pass "prune removes only closed leases older than seven days with an ETag precondition"

echo "PASS: sweeper suite ($pass_count cases)"
