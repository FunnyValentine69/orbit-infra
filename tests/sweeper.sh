#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/sweeper"
SWEEPER="$REPO_ROOT/scripts/sweep.sh"
LEASE="$REPO_ROOT/scripts/lease.sh"
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
    if [ -z "$etag_match" ] || [ "$etag_match" != "$current" ]; then
      echo 'An error occurred (PreconditionFailed) when calling the DeleteObject operation' >&2
      exit 254
    fi
    rm -f "$store" "$etag_file"
    echo '{"DeleteMarker":true}'
    ;;
  "s3api list-object-versions")
    state_file="$FAKE_STATE_DIR/${key//\//_}.json"
    [ -f "$state_file" ] || printf '[]\n' > "$state_file"
    start=0
    if [ -n "$version_id_marker" ]; then
      start="$(jq -er --arg marker "$version_id_marker" \
        '([.[].VersionId] | index($marker)) as $index | select($index != null) | $index + 1' "$state_file")"
    fi
    page_size="${FAKE_PAGE_SIZE:-2}"
    page="$(jq -c --argjson start "$start" --argjson size "$page_size" '.[$start:($start + $size)]' "$state_file")"
    total="$(jq 'length' "$state_file")"
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
  local lease
  lease="$(jq -c --arg env_id "$env_id" '.leases[] | select(.env_id == $env_id)' "$FIXTURES/discover-cases.json")"
  reset_store
  store_lease "$lease"
  output="$(run_aws "$SWEEPER" env "$env_id")"
  grep -Fq "$expected_fragment" <<< "$output" || fail "missing Stage-1 action output for $env_id"
  [ "$(cat "$tmp_dir/close-calls.log")" = "$env_id" ] || fail "Stage 1 must call close-env.sh once without --force-retry"
}
run_stage1_case stale-open "stage 1"
run_stage1_case retry-due "stage 1"
pass "stale-open and due-retry leases invoke unforced Stage 1 from a fresh read"

reset_store
exhausted="$(jq -c '.leases[] | select(.env_id == "retry-max")' "$FIXTURES/discover-cases.json")"
store_lease "$exhausted"
budget_output="$(run_aws "$SWEEPER" env retry-max)"
grep -Fq 'automatic cleanup retry budget is exhausted' <<< "$budget_output" || fail "retry exhaustion reason missing"
[ ! -s "$tmp_dir/close-calls.log" ] || fail "sweeper forced past the Stage-1 retry budget"
pass "sweeper never forces a cleanup_failed lease past the retry budget"

reset_store
happy_fixture="$FIXTURES/aws-deleted-client-exception.json"
store_fixture "$happy_fixture"
FAKE_SCENARIO_FILE="$happy_fixture" SWEEP_DELETE_BATCH_SIZE=2 run_aws "$SWEEPER" env aws-happy >/dev/null
[ "$(lease_status aws aws-happy)" = closed ] || fail "AWS deleted task definition did not close the lease"
[ "$(jq 'length' "$fake_state/envs_preview_aws-happy.tfstate.json")" -eq 0 ] || fail "state versions/delete markers remain after Stage 2"
happy_lease="$(run_aws "$LEASE" get aws-happy)"
jq -e '.manifest.stage2_runs[-1].in_job == false and .manifest.stage2_runs[-1].target == "aws"' \
  <<< "$happy_lease" >/dev/null || fail "completed AWS Stage 2 run was not recorded"
if [ "$(grep -c '^s3api delete-objects ' "$tmp_dir/aws-calls.log")" -ne 2 ]; then
  fail "paginated state inventory must delete versions and markers in bounded batches"
fi
pass "AWS Stage 2 accepts only the exact deleted ClientException, deletes every state version, and closes"

reset_store
pending_fixture="$FIXTURES/aws-delete-in-progress.json"
store_fixture "$pending_fixture"
pending_output="$(FAKE_SCENARIO_FILE="$pending_fixture" run_aws "$SWEEPER" env aws-pending)"
[ "$(lease_status aws aws-pending)" = closing ] || fail "DELETE_IN_PROGRESS must keep closing"
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
cas_output="$(FAKE_SCENARIO_FILE="$happy_fixture" FAKE_PUT_RACE_ON_STATUS=closed \
  run_aws "$SWEEPER" env aws-happy 2>&1)"
cas_rc=$?
set -e
[ "$cas_rc" -eq 3 ] || fail "closing-to-closed CAS race must exit 3, got $cas_rc"
[ "$(lease_status aws aws-happy)" = closing ] || fail "losing closing-to-closed writer mutated lease status"
grep -Fq 'lost the CAS race' <<< "$cas_output" || fail "CAS race did not report the lease refusal"
pass "closing-to-closed CAS race exits 3 without the sweeper mutating the lease"

reset_store
old_closed="$(jq -c '.leases[] | select(.env_id == "prune-old")' "$FIXTURES/discover-cases.json")"
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
