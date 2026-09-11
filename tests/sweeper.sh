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
    if [[ "$key" == leases/* ]] && [ -n "${FAKE_LEASE_GET_COUNT_FILE:-}" ]; then
      lease_get_count=1
      if [ -f "$FAKE_LEASE_GET_COUNT_FILE" ]; then
        lease_get_count=$(( $(cat "$FAKE_LEASE_GET_COUNT_FILE") + 1 ))
      fi
      printf '%s\n' "$lease_get_count" > "$FAKE_LEASE_GET_COUNT_FILE"
      if [ "${FAKE_MANUAL_ON_CLAIM_READ:-0}" = 1 ] && [ "$lease_get_count" -eq 2 ]; then
        jq '.manual_intervention_required = true
          | .error = "automatic retry budget exhausted"' "$store" > "$store.next"
        mv "$store.next" "$store"
        printf '%s\n' "$(( $(cat "$etag_file") + 1 ))" > "$etag_file"
        printf '%s\n' 'MANUAL_RACE' >> "$FAKE_AWS_CALL_LOG"
      fi
      # get-object #1 on a lease key is the sweep's own classification read;
      # get-object #2 is claim-stage2's fresh read (see FAKE_MANUAL_ON_CLAIM_READ
      # above). Signal there so TERM lands mid-claim, before refusal returns.
      if [ "${FAKE_SIGNAL_ON_CLAIM_READ:-0}" = 1 ] && [ "$lease_get_count" -eq 2 ]; then
        printf '%s\n' 'SIGNAL claim-read' >> "$FAKE_AWS_CALL_LOG"
        kill -TERM "$(cat "$FAKE_SWEEP_PID_FILE")"
      fi
    fi
    cp "$store" "$destination"
    printf '{"ETag":"%s"}\n' "$(cat "$etag_file")"
    ;;
  "s3api put-object")
    current=""
    [ ! -f "$etag_file" ] || current="$(cat "$etag_file")"
    if [ -n "${FAKE_LEASE_BODY_LOG:-}" ] && [[ "$key" == leases/* ]]; then
      jq -c . "$body" >> "$FAKE_LEASE_BODY_LOG"
    fi
    if [ "${FAKE_PRUNE_CAS_LOSS:-0}" = 1 ] && \
       [ "$(jq -r '.status // empty' "$body")" = deleted ]; then
      jq '.status = "open" | .generation += 1' "$store" > "$store.next"
      mv "$store.next" "$store"
      current=$((current + 1))
      printf '%s\n' "$current" > "$etag_file"
    fi
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
    if { [ "${FAKE_SIGNAL_AFTER_CLAIM_PUT:-0}" = 1 ] &&
         jq -e '(.stage2_claim | type) == "object"' "$body" >/dev/null; } || \
       { [ "${FAKE_SIGNAL_DURING_COMPLETE:-0}" = 1 ] &&
         [ "$(jq -r '.status // empty' "$body")" = closed ]; }; then
      printf '%s\n' 'SIGNAL committed-put' >> "$FAKE_AWS_CALL_LOG"
      kill -TERM "$(cat "$FAKE_SWEEP_PID_FILE")"
    fi
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
    if [ -n "${FAKE_LIST_OBJECT_VERSIONS_FIXTURE:-}" ]; then
      jq -c '.response' "$FAKE_LIST_OBJECT_VERSIONS_FIXTURE"
      exit 0
    fi
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
    if [ -n "${FAKE_DELETE_OBJECTS_FIXTURE:-}" ]; then
      jq -c '.response' "$FAKE_DELETE_OBJECTS_FIXTURE"
      exit 0
    fi
    payload="${delete_arg#file://}"
    deleted="$(jq -c '.Objects' "$payload")"
    key="$(jq -r '.Objects[0].Key' "$payload")"
    key="${key%.tflock}"
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
    if [ "${FAKE_SIGNAL_ON_DESCRIBE:-0}" = 1 ]; then
      printf '%s\n' 'SIGNAL describe-task-definition' >> "$FAKE_AWS_CALL_LOG"
      kill -TERM "$(cat "$FAKE_SWEEP_PID_FILE")"
    fi
    expected="$(jq -r '.task_definition_arn' "$FAKE_SCENARIO_FILE")"
    [ "$task_definition" = "$expected" ] || {
      echo "unexpected task definition" >&2
      exit 2
    }
    if [ "${FAKE_VERIFICATION_CHANGE_AFTER_DESCRIBE:-0}" = 1 ]; then
      env_id="$(jq -r '.env_id' "$FAKE_SCENARIO_FILE")"
      lease_store="$FAKE_S3_DIR/leases_${env_id}.json.body"
      lease_etag="$FAKE_S3_DIR/leases_${env_id}.json.etag"
      jq --argjson run "$(jq -c '.late_verification_run' "$FAKE_SCENARIO_FILE")" \
        '.manifest.verification_runs[-1] = $run' "$lease_store" > "$lease_store.next"
      mv "$lease_store.next" "$lease_store"
      printf '%s\n' "$(( $(cat "$lease_etag") + 1 ))" > "$lease_etag"
    fi
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
if [ "${FAKE_CLOSE_BEGIN_CLEANUP:-0}" = 1 ]; then
  generation=""
  from=""
  owner=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --generation) generation="$2"; shift 2 ;;
      --from) from="$2"; shift 2 ;;
      --owner) owner="$2"; shift 2 ;;
      *) env_id="$1"; shift ;;
    esac
  done
  exec "$LEASE_SH" begin-cleanup "$env_id" \
    --expect-owner "$owner" \
    --generation "$generation" --from "$from" --claim closing-budget-cap
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

cat > "$tmp_dir/bin/recording-lease" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_LEASE_ARGV_LOG"
exec "$REAL_LEASE_SH" "$@"
EOF
chmod +x "$tmp_dir/bin/recording-lease"

cat > "$tmp_dir/bin/stage2-probe-lease" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_STAGE2_PROBE_LOG"
exit 3
EOF
chmod +x "$tmp_dir/bin/stage2-probe-lease"

cat > "$tmp_dir/bin/run-sweep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$$" > "$FAKE_SWEEP_PID_FILE"
exec "$SWEEPER" env "$FAKE_SWEEP_ENV_ID"
EOF
chmod +x "$tmp_dir/bin/run-sweep"

common_env=(
  "AWS_CLI_BIN=$tmp_dir/bin/aws"
  "AWS_CLI_SH=$AWS_WRAPPER"
  "CLOSE_ENV_SH=$tmp_dir/bin/close-env"
  "FAKE_AWS_CALL_LOG=$tmp_dir/aws-calls.log"
  "FAKE_CLOSE_LOG=$tmp_dir/close-calls.log"
  "FAKE_LEASE_BODY_LOG=$tmp_dir/lease-bodies.log"
  "FAKE_LEASE_GET_COUNT_FILE=$tmp_dir/lease-get-count"
  "FAKE_DELETE_CALLS_FILE=$tmp_dir/delete-calls"
  "FAKE_S3_DIR=$fake_s3"
  "FAKE_STATE_DIR=$fake_state"
  "LEASE_BUCKET=test-state"
  "LEASE_SH=$LEASE"
  "STATE_BUCKET=test-state"
  "SWEEPER=$SWEEPER"
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

run_aws_with_recording_lease() {
  env -u AWS_ENDPOINT_URL -u AWS_PROFILE \
    "${common_env[@]}" \
    LEASE_SH="$tmp_dir/bin/recording-lease" \
    REAL_LEASE_SH="$LEASE" \
    FAKE_LEASE_ARGV_LOG="$tmp_dir/lease-argv.log" \
    TARGET=aws "$@"
}

reset_store() {
  rm -f "$fake_s3"/* "$fake_state"/* "$tmp_dir/delete-calls" \
    "$tmp_dir/lease-get-count" "$tmp_dir/sweep.pid"
  : > "$tmp_dir/aws-calls.log"
  : > "$tmp_dir/close-calls.log"
  : > "$tmp_dir/lease-bodies.log"
}

test_epoch_to_iso() {
  local epoch="$1"
  date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ
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
      owner:"test-owner",
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
  if jq -e 'has("verification_run")' "$fixture" >/dev/null; then
    lease="$(jq -c --argjson run "$(jq -c '.verification_run' "$fixture")" \
      '.manifest.verification_runs = [$run]' <<< "$lease")"
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

assert_stage2_failure_lease() {
  local lease_json="$1"
  local expected_error="$2"
  local message="$3"
  if ! jq -e --arg error "$expected_error" '
      .status == "closing"
      and .stage2_attempt == 1
      and .stage2_claim == null
      and .cleanup_attempt == 1
      and .next_retry_at == null
      and .manual_intervention_required == false
      and .error == $error
      and ((.manifest.stage2_runs // []) | length) == 0
    ' <<< "$lease_json" >/dev/null; then
    fail "$message"
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
    and has("cleanup_attempt") and has("stage2_attempt") and has("stage2_claim")
    and has("next_retry_at")
    and has("manual_intervention_required") and has("classification") and has("reason")
    and .classification == $expected[.env_id].classification
    and .reason == $expected[.env_id].reason)
' <<< "$discover_json" >/dev/null; then
  fail "discover did not classify every status/age boundary correctly: $discover_json"
fi
pass "discover emits the lease inventory and classifies status/age boundaries"

if ! jq -e '
  map(select(.env_id == "stage2-claim"))
  | length == 1
  and .[0].classification == "stage2"
  and .[0].stage2_attempt == 2
  and .[0].stage2_claim.token == "live-stage2-token"
' <<< "$discover_json" >/dev/null; then
  fail "discover did not classify a live Stage-2 claim ahead of the non-task-pending rule: $discover_json"
fi
pass "discover classifies a live Stage-2 claim before the non-task-pending rule"

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
  [ "$(cat "$tmp_dir/close-calls.log")" = "--owner test-owner --generation $generation --from $status $env_id" ] || \
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
non_task_pending_fixture="$FIXTURES/aws-non-task-pending.json"
store_fixture "$non_task_pending_fixture"
non_task_pending_output="$(FAKE_SCENARIO_FILE="$non_task_pending_fixture" \
  run_aws "$SWEEPER" env non-task)"
non_task_pending_lease="$(run_aws "$LEASE" get non-task)"
grep -Fq 'running stage 1 for non-task (stage1-retry)' <<< "$non_task_pending_output" || \
  fail "pending non-task resource did not classify the closing lease for Stage 1 retry"
[ "$(cat "$tmp_dir/close-calls.log")" = "--owner test-owner --generation 1 --from closing non-task" ] || \
  fail "pending non-task Stage 1 retry did not preserve generation and closing status"
jq -e '.status == "closing" and .stage2_claim == null' <<< "$non_task_pending_lease" >/dev/null || \
  fail "pending non-task classification mutated the lease"
[ "$(jq 'length' "$fake_state/envs_preview_non-task.tfstate.json")" -eq 1 ] || \
  fail "pending non-task classification touched retained state"
if grep -Eq '^s3api (list-object-versions|delete-objects) ' "$tmp_dir/aws-calls.log"; then
  fail "pending non-task classification reached state-version operations"
fi
pass "closing lease with a pending non-task result returns to Stage 1"

# A closing lease that reaches the Stage-1 cap must publish an operator signal
# on the first sweep and become a write-free manual no-op on the next sweep.
reset_store
store_fixture "$non_task_pending_fixture"
closing_cap_seed="$(run_aws "$LEASE" get non-task | jq -c '.cleanup_attempt = 3')"
store_lease "$closing_cap_seed"
set +e
closing_cap_output="$(FAKE_SCENARIO_FILE="$non_task_pending_fixture" \
  FAKE_CLOSE_BEGIN_CLEANUP=1 run_aws "$SWEEPER" env non-task 2>&1)"
closing_cap_rc=$?
set -e
closing_cap_lease="$(run_aws "$LEASE" get non-task)"
if [ "$closing_cap_rc" -ne 3 ] || \
   ! grep -Fq 'automatic retry budget exhausted' <<< "$closing_cap_output" || \
   ! jq -e '
     .status == "closing"
     and .cleanup_attempt == 3
     and .stage1_claim == null
     and .stage2_claim == null
     and .manual_intervention_required == true
     and .error == "automatic retry budget exhausted"
   ' <<< "$closing_cap_lease" >/dev/null; then
  fail "closing Stage-1 cap did not publish the manual-intervention signal"
fi
: > "$tmp_dir/aws-calls.log"
: > "$tmp_dir/close-calls.log"
rm -f "$tmp_dir/lease-get-count"
closing_cap_second_output="$(FAKE_SCENARIO_FILE="$non_task_pending_fixture" \
  FAKE_CLOSE_BEGIN_CLEANUP=1 run_aws "$SWEEPER" env non-task)"
grep -Fq 'manual intervention is required' <<< "$closing_cap_second_output" || \
  fail "flagged closing lease did not classify as the manual no-op"
[ ! -s "$tmp_dir/close-calls.log" ] || fail "manual closing no-op invoked Stage 1"
if grep -q '^s3api put-object ' "$tmp_dir/aws-calls.log"; then
  fail "manual closing no-op wrote the lease"
fi
pass "closing Stage-1 cap escalates once and then classifies as a write-free manual no-op"

stale_claimed_at="$(test_epoch_to_iso "$(( $(date -u +%s) - 7201 ))")"
young_claimed_at="$(test_epoch_to_iso "$(( $(date -u +%s) - 600 ))")"

# A stale claim reaches Stage 2, is replaced under CAS, is audited, and hands
# back cleanly when the task definition is still pending.
reset_store
pending_fixture="$FIXTURES/aws-delete-in-progress.json"
store_fixture "$pending_fixture"
stale_pending_seed="$(run_aws "$LEASE" get aws-pending | jq -c \
  --arg claimed_at "$stale_claimed_at" \
  '.stage2_claim = {token:"old-stage2-token",claimed_at:$claimed_at}')"
store_lease "$stale_pending_seed"
stale_takeover_output="$(FAKE_SCENARIO_FILE="$pending_fixture" \
  run_aws "$SWEEPER" env aws-pending)"
stale_takeover_lease="$(run_aws "$LEASE" get aws-pending)"
if ! jq -e '
    .status == "closing"
    and .cleanup_attempt == 1
    and .stage2_claim == null
    and .cleanup_retry_audit[-1].cleared_stage2_claim.token == "old-stage2-token"
    and (.cleanup_retry_audit[-1].takeover_at | type == "string" and length > 0)
  ' <<< "$stale_takeover_lease" >/dev/null || \
   ! jq -se '
     map(select((.stage2_claim | type) == "object"))
     | length == 1 and .[0].stage2_claim.token != "old-stage2-token"
   ' "$tmp_dir/lease-bodies.log" >/dev/null; then
  fail "stale Stage-2 claim was not replaced, audited, and handed back"
fi
grep -Fq 'DELETE_IN_PROGRESS' <<< "$stale_takeover_output" || \
  fail "stale takeover did not execute the Stage-2 task-definition check"
pass "stale Stage-2 claim is taken over under CAS and audited"

# A young claim, a simultaneous Stage-1 claim, and omission of the explicit
# takeover option each refuse without any lease write.
reset_store
store_fixture "$pending_fixture"
young_claim_seed="$(run_aws "$LEASE" get aws-pending | jq -c \
  --arg claimed_at "$young_claimed_at" \
  '.stage2_claim = {token:"young-stage2-token",claimed_at:$claimed_at}')"
store_lease "$young_claim_seed"
set +e
FAKE_SCENARIO_FILE="$pending_fixture" \
  run_aws "$SWEEPER" env aws-pending >"$tmp_dir/young-claim.out" 2>&1
young_claim_rc=$?
set -e
[ "$young_claim_rc" -eq 3 ] || fail "young Stage-2 takeover must exit 3"
[ "$(cat "$fake_s3/leases_aws-pending.json.body")" = "$young_claim_seed" ] || \
  fail "young Stage-2 takeover mutated the lease"
[ ! -s "$tmp_dir/lease-bodies.log" ] || fail "young Stage-2 takeover attempted a lease write"

young_claim_before="$(cat "$fake_s3/leases_aws-pending.json.body")"
set +e
missing_takeover_output="$(run_aws "$LEASE" claim-stage2 aws-pending \
  --expect-owner test-owner --generation 1 --token prospective-without-takeover 2>&1)"
missing_takeover_rc=$?
set -e
if [ "$missing_takeover_rc" -ne 3 ] || \
   [ "$(cat "$fake_s3/leases_aws-pending.json.body")" != "$young_claim_before" ]; then
  fail "existing Stage-2 claim must refuse when --takeover-stale is omitted: $missing_takeover_output"
fi

reset_store
store_fixture "$pending_fixture"
stage1_and_stage2_seed="$(run_aws "$LEASE" get aws-pending | jq -c \
  --arg claimed_at "$stale_claimed_at" \
  '.stage1_claim = {token:"active-stage1",claimed_at:$claimed_at}
   | .stage2_claim = {token:"old-stage2-token",claimed_at:$claimed_at}')"
store_lease "$stage1_and_stage2_seed"
set +e
FAKE_SCENARIO_FILE="$pending_fixture" \
  run_aws "$SWEEPER" env aws-pending >"$tmp_dir/dual-claim.out" 2>&1
stage1_and_stage2_rc=$?
set -e
[ "$stage1_and_stage2_rc" -eq 3 ] || fail "Stage-2 takeover with a Stage-1 claim must exit 3"
[ "$(cat "$fake_s3/leases_aws-pending.json.body")" = "$stage1_and_stage2_seed" ] || \
  fail "Stage-2 takeover with a Stage-1 claim mutated the lease"
[ ! -s "$tmp_dir/lease-bodies.log" ] || fail "refused dual-claim takeover attempted a write"
pass "young, dual-claim, and unflagged Stage-2 takeovers refuse without writes"

# A takeover whose replacement token equals the existing stale Stage-2 claim's
# token must refuse before any put, leaving the lease byte-identical.
reset_store
store_fixture "$pending_fixture"
same_token_seed="$(run_aws "$LEASE" get aws-pending | jq -c \
  --arg claimed_at "$stale_claimed_at" \
  '.stage2_claim = {token:"same-token",claimed_at:$claimed_at}')"
store_lease "$same_token_seed"
same_token_before="$(cat "$fake_s3/leases_aws-pending.json.body")"
set +e
same_token_output="$(run_aws "$LEASE" claim-stage2 aws-pending \
  --expect-owner test-owner --generation 1 --token same-token --takeover-stale 7200 2>&1)"
same_token_rc=$?
set -e
[ "$same_token_rc" -eq 3 ] || fail "same-token Stage-2 takeover must exit 3"
grep -Fq 'replacement token must differ from the existing Stage-2 claim' <<< "$same_token_output" || \
  fail "same-token Stage-2 takeover did not emit the refusal message: $same_token_output"
[ "$(cat "$fake_s3/leases_aws-pending.json.body")" = "$same_token_before" ] || \
  fail "same-token Stage-2 takeover mutated the lease"
[ ! -s "$tmp_dir/lease-bodies.log" ] || fail "same-token Stage-2 takeover attempted a lease write"
pass "Stage-2 takeover with a replacement token equal to the existing claim refuses without writes"

# The claim's fresh read must observe a manual escalation that lands after the
# initial classification and refuse before any workload or state call.
reset_store
happy_fixture="$FIXTURES/aws-deleted-client-exception.json"
store_fixture "$happy_fixture"
set +e
manual_race_output="$(FAKE_SCENARIO_FILE="$happy_fixture" FAKE_MANUAL_ON_CLAIM_READ=1 \
  run_aws "$SWEEPER" env aws-happy 2>&1)"
manual_race_rc=$?
set -e
manual_race_lease="$(cat "$fake_s3/leases_aws-happy.json.body")"
manual_race_tail="$(awk 'seen { print } /^MANUAL_RACE$/ { seen=1 }' "$tmp_dir/aws-calls.log")"
if [ "$manual_race_rc" -ne 3 ] || \
   ! jq -e '.status == "closing" and .stage2_claim == null
     and .manual_intervention_required == true' <<< "$manual_race_lease" >/dev/null || \
   grep -Eq '^ecs |^s3api (put-object|list-object-versions|delete-objects) ' <<< "$manual_race_tail"; then
  fail "claim-stage2 did not fail closed on the classification-to-claim manual race: $manual_race_output"
fi
pass "claim-stage2 fresh read refuses a concurrent manual escalation"

reset_store
store_fixture "$happy_fixture"
generation_bound_seed="$(run_aws "$LEASE" get aws-happy | jq -c \
  '.owner = "generation-bound-owner"')"
store_lease "$generation_bound_seed"
: > "$tmp_dir/lease-argv.log"
FAKE_SCENARIO_FILE="$happy_fixture" run_aws_with_recording_lease "$SWEEPER" \
  env aws-happy --expect-owner generation-bound-owner \
  --expect-generation 1 >/dev/null
if ! grep -Eq \
    '^claim-stage2 aws-happy --expect-owner [^ ]+ --generation 1 --token [^ ]+ --takeover-stale [0-9]+$' \
    "$tmp_dir/lease-argv.log"; then
  fail "generation-bound sweep did not pass expected generation 1 to claim-stage2"
fi

: > "$tmp_dir/stage2-probe.log"
sweeper_tail="$(tail -n 1 "$SWEEPER")"
[ "$sweeper_tail" = 'main "$@"' ] || \
  fail 'sweep.sh library seam requires final line main "$@"'
sed '$d' "$SWEEPER" > "$tmp_dir/sweep-library.sh"
set +e
(
  LEASE_SH="$tmp_dir/bin/stage2-probe-lease"
  FAKE_STAGE2_PROBE_LOG="$tmp_dir/stage2-probe.log"
  TARGET=aws
  export LEASE_SH FAKE_STAGE2_PROBE_LOG TARGET
  # shellcheck source=/dev/null
  source "$tmp_dir/sweep-library.sh"
  SCRIPT_DIR="$REPO_ROOT/scripts"
  CLOSE_ENV_SH="$SCRIPT_DIR/close-env.sh"
  AWS_CLI_SH="$SCRIPT_DIR/aws-cli.sh"
  export CLOSE_ENV_SH AWS_CLI_SH
  [[ "$SCRIPT_DIR" == */scripts ]] || \
    fail "sweep.sh library seam SCRIPT_DIR does not end in /scripts: $SCRIPT_DIR"
  [ -f "$SCRIPT_DIR/close-env.sh" ] || \
    fail "sweep.sh library seam close-env.sh is missing: $SCRIPT_DIR/close-env.sh"
  stage2 aws-happy '{"generation":2,"owner":"probe-owner"}' 1 >/dev/null 2>&1
)
stage2_probe_rc=$?
set -e
if [ "$stage2_probe_rc" -ne 3 ] || \
   ! grep -Eq \
     '^claim-stage2 aws-happy --expect-owner [^ ]+ --generation 1 --token [^ ]+ --takeover-stale [0-9]+$' \
     "$tmp_dir/stage2-probe.log"; then
  fail "Stage 2 did not override the initial lease generation with expected generation 1"
fi
pass "generation-bound sweep forwards the expected generation to the Stage-2 claim"

# A stale claim with pending non-task evidence must take the Stage-2 path first,
# hand back there, then finish state deletion after Stage 1 evidence is resolved.
reset_store
store_fixture "$non_task_pending_fixture"
stale_non_task_seed="$(run_aws "$LEASE" get non-task | jq -c \
  --arg claimed_at "$stale_claimed_at" \
  '.stage2_claim = {token:"stale-non-task-token",claimed_at:$claimed_at}')"
store_lease "$stale_non_task_seed"
stale_non_task_output="$(FAKE_SCENARIO_FILE="$non_task_pending_fixture" \
  run_aws "$SWEEPER" env non-task)"
stale_non_task_lease="$(run_aws "$LEASE" get non-task)"
if ! jq -e '
    .status == "closing"
    and .stage2_claim == null
    and .cleanup_retry_audit[-1].cleared_stage2_claim.token == "stale-non-task-token"
  ' <<< "$stale_non_task_lease" >/dev/null || \
   ! grep -Fq 'stage 1 re-verification required' <<< "$stale_non_task_output" || \
   [ -s "$tmp_dir/close-calls.log" ]; then
  fail "stale claimed non-task lease bypassed Stage-2 takeover and hand-back"
fi
resolved_non_task="$(jq -c '
  .manifest.verification_runs[-1].summary.pending = 0
  | .manifest.verification_runs[-1].results = [
      .manifest.verification_runs[-1].results[] | select(.outcome != "pending")
    ]
' <<< "$stale_non_task_lease")"
store_lease "$resolved_non_task"
: > "$tmp_dir/aws-calls.log"
rm -f "$tmp_dir/lease-get-count"
FAKE_SCENARIO_FILE="$non_task_pending_fixture" run_aws "$SWEEPER" env non-task >/dev/null
[ "$(lease_status aws non-task)" = closed ] || \
  fail "resolved non-task evidence did not reach state deletion and close"
[ "$(jq 'length' "$fake_state/envs_preview_non-task.tfstate.json")" -eq 0 ] || \
  fail "resolved non-task follow-up retained state"
pass "claimed closing lease reaches Stage 2 before non-task hand-back and later closes"

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

# The prospective claim token is installed before the claim call so a deferred
# TERM can always release a claim written immediately before or during work.
reset_store
store_fixture "$happy_fixture"
set +e
signal_describe_output="$(FAKE_SCENARIO_FILE="$happy_fixture" \
  FAKE_SIGNAL_ON_DESCRIBE=1 \
  FAKE_SWEEP_ENV_ID=aws-happy \
  FAKE_SWEEP_PID_FILE="$tmp_dir/sweep.pid" \
  run_aws "$tmp_dir/bin/run-sweep" 2>&1)"
signal_describe_rc=$?
set -e
signal_describe_lease="$(cat "$fake_s3/leases_aws-happy.json.body")"
signal_describe_tail="$(awk 'seen { print } /^SIGNAL describe-task-definition$/ { seen=1 }' \
  "$tmp_dir/aws-calls.log")"
if [ "$signal_describe_rc" -ne 143 ] || \
   ! jq -e '.status == "closing" and .stage2_claim == null' \
     <<< "$signal_describe_lease" >/dev/null || \
   [ "$(wc -l <<< "$signal_describe_tail" | tr -d ' ')" -ne 2 ] || \
   ! sed -n '1p' <<< "$signal_describe_tail" | \
     grep -Eq '^s3api get-object .*--key leases/aws-happy.json ' || \
   ! sed -n '2p' <<< "$signal_describe_tail" | \
     grep -Eq '^s3api put-object .*--key leases/aws-happy.json .*--if-match ' || \
   grep -Eq '^ecs |^s3api (list-object-versions|delete-objects) ' <<< "$signal_describe_tail"; then
  fail "TERM during Stage 2 must permit only the claim release and exit 143: $signal_describe_output"
fi
pass "TERM during Stage-2 workload releases the claim and exits 143"

reset_store
store_fixture "$happy_fixture"
set +e
signal_claim_output="$(FAKE_SCENARIO_FILE="$happy_fixture" \
  FAKE_SIGNAL_AFTER_CLAIM_PUT=1 \
  FAKE_SWEEP_ENV_ID=aws-happy \
  FAKE_SWEEP_PID_FILE="$tmp_dir/sweep.pid" \
  run_aws "$tmp_dir/bin/run-sweep" 2>&1)"
signal_claim_rc=$?
set -e
signal_claim_lease="$(cat "$fake_s3/leases_aws-happy.json.body")"
signal_claim_token="$(jq -sr '
  [.[] | select((.stage2_claim | type) == "object")][0].stage2_claim.token
' "$tmp_dir/lease-bodies.log")"
signal_claim_tail="$(awk 'seen { print } /^SIGNAL committed-put$/ { seen=1 }' \
  "$tmp_dir/aws-calls.log")"
if [ "$signal_claim_rc" -ne 143 ] || [ -z "$signal_claim_token" ] || \
   ! jq -e '.status == "closing" and .stage2_claim == null' \
     <<< "$signal_claim_lease" >/dev/null || \
   ! grep -Fq "$signal_claim_token" <<< "$signal_claim_output" || \
   [ "$(wc -l <<< "$signal_claim_tail" | tr -d ' ')" -ne 2 ] || \
   ! sed -n '1p' <<< "$signal_claim_tail" | \
     grep -Eq '^s3api get-object .*--key leases/aws-happy.json ' || \
   ! sed -n '2p' <<< "$signal_claim_tail" | \
     grep -Eq '^s3api put-object .*--key leases/aws-happy.json .*--if-match ' || \
   grep -Eq '^ecs |^s3api (list-object-versions|delete-objects) ' <<< "$signal_claim_tail"; then
  fail "TERM after the committed claim PUT did not release the prospective token: $signal_claim_output"
fi
pass "TERM after the claim CAS sees and releases the prospective token"

reset_store
store_fixture "$happy_fixture"
set +e
signal_complete_output="$(FAKE_SCENARIO_FILE="$happy_fixture" \
  FAKE_SIGNAL_DURING_COMPLETE=1 \
  FAKE_SWEEP_ENV_ID=aws-happy \
  FAKE_SWEEP_PID_FILE="$tmp_dir/sweep.pid" \
  run_aws "$tmp_dir/bin/run-sweep" 2>&1)"
signal_complete_rc=$?
set -e
signal_complete_lease="$(cat "$fake_s3/leases_aws-happy.json.body")"
if [ "$signal_complete_rc" -ne 143 ] || \
   ! jq -e '.status == "closed" and .stage2_claim == null' \
     <<< "$signal_complete_lease" >/dev/null || \
   ! grep -Fq 'release refused' <<< "$signal_complete_output"; then
  fail "TERM across complete-stage2 must preserve closed and log the harmless release refusal"
fi
pass "TERM across the claim-ending CAS cannot strand or restore a claim"

# TERM delivered while claim-stage2's own fresh read is in flight, for a
# takeover whose prospective token equals the incumbent's, must not release
# the incumbent claim this process never acquired.
reset_store
store_fixture "$happy_fixture"
refused_claim_token="refused-takeover-token"
refused_claim_seed="$(jq -c \
  --arg claimed_at "$stale_claimed_at" --arg token "$refused_claim_token" \
  '.stage2_claim = {token:$token,claimed_at:$claimed_at}' \
  "$fake_s3/leases_aws-happy.json.body")"
store_lease "$refused_claim_seed"
set +e
refused_claim_output="$(FAKE_SCENARIO_FILE="$happy_fixture" \
  FAKE_SIGNAL_ON_CLAIM_READ=1 \
  FAKE_SWEEP_ENV_ID=aws-happy \
  FAKE_SWEEP_PID_FILE="$tmp_dir/sweep.pid" \
  SWEEP_STAGE2_TOKEN_OVERRIDE="$refused_claim_token" \
  run_aws "$tmp_dir/bin/run-sweep" 2>&1)"
refused_claim_rc=$?
set -e
refused_claim_lease="$(cat "$fake_s3/leases_aws-happy.json.body")"
refused_claim_tail="$(awk 'seen { print } /^SIGNAL claim-read$/ { seen=1 }' \
  "$tmp_dir/aws-calls.log")"
if [ "$refused_claim_rc" -ne 143 ] || \
   ! jq -e --arg token "$refused_claim_token" \
     '.stage2_claim.token == $token' <<< "$refused_claim_lease" >/dev/null || \
   grep -Fq 's3api put-object' <<< "$refused_claim_tail" || \
   ! grep -Fq 'replacement token must differ from the existing Stage-2 claim' \
     <<< "$refused_claim_output" || \
   ! grep -Fq 'stage2: no acquired claim to release' <<< "$refused_claim_output"; then
  fail "TERM during a refused claim released or altered the incumbent claim: $refused_claim_output"
fi
pass "TERM during a refused claim leaves the incumbent claim untouched"

reset_store
non_task_reread_fixture="$FIXTURES/aws-non-task-pending-reread.json"
store_fixture "$non_task_reread_fixture"
non_task_reread_output="$(FAKE_SCENARIO_FILE="$non_task_reread_fixture" \
  FAKE_VERIFICATION_CHANGE_AFTER_DESCRIBE=1 run_aws "$SWEEPER" env pending-race)"
non_task_reread_lease="$(run_aws "$LEASE" get pending-race)"
grep -Fq 'remains closing while non-task resources are pending; stage 1 re-verification required' \
  <<< "$non_task_reread_output" || fail "post-claim non-task pending guard reason missing"
jq -e '.status == "closing" and .stage2_claim == null
  and .manifest.verification_runs[-1].summary.pending == 1' \
  <<< "$non_task_reread_lease" >/dev/null || \
  fail "post-claim non-task pending guard did not release the Stage 2 claim"
[ "$(jq 'length' "$fake_state/envs_preview_pending-race.tfstate.json")" -eq 1 ] || \
  fail "post-claim non-task pending guard touched retained state"
if grep -Eq '^s3api (list-object-versions|delete-objects) ' "$tmp_dir/aws-calls.log"; then
  fail "post-claim non-task pending guard reached state-version operations"
fi
pass "Stage 2 re-read releases its claim when non-task pending evidence appears"

reset_store
pending_fixture="$FIXTURES/aws-delete-in-progress.json"
store_fixture "$pending_fixture"
pending_output="$(FAKE_SCENARIO_FILE="$pending_fixture" run_aws "$SWEEPER" env aws-pending)"
pending_release_gets="$(grep -c '^s3api get-object .*--key leases/aws-pending.json ' "$tmp_dir/aws-calls.log")"
pending_lease="$(run_aws "$LEASE" get aws-pending)"
jq -e '.status == "closing" and .stage2_claim == null' <<< "$pending_lease" >/dev/null || \
  fail "DELETE_IN_PROGRESS must keep closing without stranding a Stage 2 claim"
grep -Fq 'DELETE_IN_PROGRESS' <<< "$pending_output" || fail "pending task definition ARN/status was not printed"
[ "$(jq 'length' "$fake_state/envs_preview_aws-pending.tfstate.json")" -eq 1 ] || fail "pending Stage 2 touched retained state"
[ "$pending_release_gets" -eq 3 ] || fail "pending hand-back invoked an exit-handler release after its explicit release"
pass "DELETE_IN_PROGRESS remains pending with state retained and one release"

reset_store
malformed_fixture="$FIXTURES/aws-malformed-describe.json"
store_fixture "$malformed_fixture"
set +e
malformed_output="$(FAKE_SCENARIO_FILE="$malformed_fixture" run_aws "$SWEEPER" env aws-bad 2>&1)"
malformed_rc=$?
set -e
malformed_failure_gets="$(grep -c '^s3api get-object .*--key leases/aws-bad.json ' "$tmp_dir/aws-calls.log")"
[ "$malformed_rc" -eq 1 ] || fail "malformed describe must exit 1, got $malformed_rc"
malformed_lease="$(run_aws "$LEASE" get aws-bad)"
assert_stage2_failure_lease "$malformed_lease" "task-definition describe was indeterminate" \
  "malformed describe did not retain closing with one Stage-2 failure"
grep -Fq 'indeterminate' <<< "$malformed_output" || fail "malformed describe failure reason missing"
[ "$(jq 'length' "$fake_state/envs_preview_aws-bad.tfstate.json")" -eq 1 ] || fail "indeterminate Stage 2 touched retained state"
[ "$malformed_failure_gets" -eq 3 ] || fail "Stage-2 failure invoked an exit-handler release after fail-stage2"
pass "malformed DescribeTaskDefinition records one Stage-2 failure without an extra release"

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
assert_stage2_failure_lease "$describe_error_lease" "task-definition describe was indeterminate" \
  "non-deleted ClientException did not retain closing with one Stage-2 failure"
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
bad_candidate_lease="$(run_aws "$LEASE" get aws-happy)"
assert_stage2_failure_lease "$bad_candidate_lease" "Stage 2 task-definition candidates are malformed" \
  "malformed candidate did not retain closing with one Stage-2 failure"
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
assert_stage2_failure_lease "$verification_failed_lease" \
  "last Stage-1 verification did not pass with zero live and indeterminate results" \
  "passed:false Stage-1 verification did not retain closing with one Stage-2 failure"
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
assert_stage2_failure_lease "$delete_errors_lease" \
  "state deletion failed before all versions were removed" \
  "delete-objects Errors did not retain closing with one Stage-2 failure"
[ "$(jq 'length' "$fake_state/envs_preview_aws-happy.tfstate.json")" -eq 3 ] || \
  fail "delete-objects Errors did not retain remaining versions"
grep -Fq 'delete-objects reported 1 object-version errors' <<< "$delete_errors_output" || \
  fail "delete-objects Errors branch did not report the object-version error"
pass "delete-objects rc zero with Errors fails closed and retains versions"

reset_store
store_fixture "$happy_fixture"
null_versions_fixture="$FIXTURES/list-null-versions.json"
set +e
null_versions_output="$(FAKE_SCENARIO_FILE="$happy_fixture" \
  FAKE_LIST_OBJECT_VERSIONS_FIXTURE="$null_versions_fixture" \
  run_aws "$SWEEPER" env aws-happy 2>&1)"
null_versions_rc=$?
set -e
null_versions_lease="$(run_aws "$LEASE" get aws-happy)"
if [ "$null_versions_rc" -ne 1 ] || \
   ! jq -e '.status == "closing"
     and .stage2_attempt == 1
     and .stage2_claim == null
     and .cleanup_attempt == 1
     and .next_retry_at == null
     and .manual_intervention_required == false
     and .error == "state deletion failed while listing retained versions"
     and ((.manifest.stage2_runs // []) | length) == 0' \
     <<< "$null_versions_lease" >/dev/null || \
   ! grep -Fq 'list-object-versions returned malformed output' <<< "$null_versions_output"; then
  fail "present-null Versions must fail closed before Stage 2 completion"
fi
pass "$(jq -r '.name' "$null_versions_fixture")"

reset_store
store_fixture "$happy_fixture"
null_deleted_fixture="$FIXTURES/delete-null-entry.json"
set +e
null_deleted_output="$(FAKE_SCENARIO_FILE="$happy_fixture" \
  FAKE_DELETE_OBJECTS_FIXTURE="$null_deleted_fixture" SWEEP_DELETE_BATCH_SIZE=2 \
  run_aws "$SWEEPER" env aws-happy 2>&1)"
null_deleted_rc=$?
set -e
null_deleted_lease="$(run_aws "$LEASE" get aws-happy)"
if [ "$null_deleted_rc" -ne 1 ] || \
   ! jq -e '.status == "closing"
     and .stage2_attempt == 1
     and .stage2_claim == null
     and .cleanup_attempt == 1
     and .next_retry_at == null
     and .manual_intervention_required == false
     and .error == "state deletion failed before all versions were removed"
     and ((.manifest.stage2_runs // []) | length) == 0' \
     <<< "$null_deleted_lease" >/dev/null || \
   ! grep -Fq 'delete-objects returned malformed output' <<< "$null_deleted_output"; then
  fail "Deleted:[null] must fail closed before Stage 2 completion"
fi
pass "$(jq -r '.name' "$null_deleted_fixture")"

reset_store
store_fixture "$happy_fixture"
incomplete_ack_fixture="$FIXTURES/delete-incomplete-ack.json"
set +e
incomplete_ack_output="$(FAKE_SCENARIO_FILE="$happy_fixture" \
  FAKE_DELETE_OBJECTS_FIXTURE="$incomplete_ack_fixture" SWEEP_DELETE_BATCH_SIZE=2 \
  run_aws "$SWEEPER" env aws-happy 2>&1)"
incomplete_ack_rc=$?
set -e
incomplete_ack_lease="$(run_aws "$LEASE" get aws-happy)"
if [ "$incomplete_ack_rc" -ne 1 ] || \
   ! jq -e '.status == "closing"
     and .stage2_attempt == 1
     and .stage2_claim == null
     and .cleanup_attempt == 1
     and .next_retry_at == null
     and .manual_intervention_required == false
     and .error == "state deletion failed before all versions were removed"
     and ((.manifest.stage2_runs // []) | length) == 0' \
     <<< "$incomplete_ack_lease" >/dev/null || \
   ! grep -Fq 'delete-objects acknowledgement did not match requested object versions' \
     <<< "$incomplete_ack_output" || \
   [ "$(grep -c '^s3api delete-objects ' "$tmp_dir/aws-calls.log")" -ne 1 ]; then
  fail "an incomplete DeleteObjects acknowledgement must stop before another batch or Stage 2 completion"
fi
pass "$(jq -r '.name' "$incomplete_ack_fixture")"

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
assert_stage2_failure_lease "$post_delete_lease" "state deletion failed: versions remain" \
  "post-delete retained version did not retain closing with one Stage-2 failure"
grep -Fq 'state deletion failed: versions remain' <<< "$post_delete_output" || \
  fail "post-delete retained version failure reason missing"
pass "post-delete re-list with a retained version fails closed"

reset_store
store_fixture "$happy_fixture"
partial_failure_seed="$(run_aws "$LEASE" get aws-happy | jq -c '
  .cleanup_attempt = 3
  | .next_retry_at = "2033-05-18T04:00:00Z"')"
store_lease "$partial_failure_seed"
set +e
delete_failure_output="$(FAKE_SCENARIO_FILE="$happy_fixture" FAKE_DELETE_FAIL_CALL=2 SWEEP_DELETE_BATCH_SIZE=2 \
  run_aws "$SWEEPER" env aws-happy 2>&1)"
delete_failure_rc=$?
set -e
[ "$delete_failure_rc" -eq 1 ] || fail "partial state deletion failure must exit 1"
delete_failure_lease="$(run_aws "$LEASE" get aws-happy)"
jq -e '
  .status == "closing"
  and .stage2_attempt == 1
  and .stage2_claim == null
  and .cleanup_attempt == 3
  and .next_retry_at == "2033-05-18T04:00:00Z"
  and .manual_intervention_required == false
  and .error == "state deletion failed before all versions were removed"
  and ((.manifest.stage2_runs // []) | length) == 0
' <<< "$delete_failure_lease" >/dev/null || \
  fail "partial state deletion failure consumed the Stage-1 budget or did not release its claim"
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

seed_lock_key_inventory() {
  jq '. + [
    {Key:"envs/preview/aws-happy.tfstate.tflock",VersionId:"lock-version-1",type:"version"},
    {Key:"envs/preview/aws-happy.tfstate.tflock",VersionId:"lock-marker-1",type:"delete-marker"},
    {Key:"envs/preview/aws-happy-two.tfstate",VersionId:"sibling-state-1",type:"version"},
    {Key:"envs/preview/aws-happy-two.tfstate.tflock",VersionId:"sibling-lock-1",type:"version"}
  ]' "$fake_state/envs_preview_aws-happy.tfstate.json" \
    > "$fake_state/envs_preview_aws-happy.tfstate.json.next"
  mv "$fake_state/envs_preview_aws-happy.tfstate.json.next" \
    "$fake_state/envs_preview_aws-happy.tfstate.json"
}

assert_lock_key_postcondition() {
  local state_file="$1"
  if jq -e 'any(.[];
      .Key == "envs/preview/aws-happy.tfstate"
      or .Key == "envs/preview/aws-happy.tfstate.tflock")' \
      "$state_file" >/dev/null; then
    echo "mutant survived the lock-key check" >&2
    return 1
  fi
  jq -e '
    map({Key,VersionId}) == [
      {Key:"envs/preview/aws-happy-two.tfstate",VersionId:"sibling-state-1"},
      {Key:"envs/preview/aws-happy-two.tfstate.tflock",VersionId:"sibling-lock-1"}
    ]
  ' "$state_file" >/dev/null
}

reset_store
store_fixture "$happy_fixture"
seed_lock_key_inventory
FAKE_SCENARIO_FILE="$happy_fixture" SWEEP_DELETE_BATCH_SIZE=2 \
  run_aws "$SWEEPER" env aws-happy >/dev/null
[ "$(lease_status aws aws-happy)" = closed ] || fail "lock-key Stage 2 did not close the lease"
assert_lock_key_postcondition "$fake_state/envs_preview_aws-happy.tfstate.json" || \
  fail "production Stage 2 left its state or lock versions, or touched a sibling environment"

lock_mutant="$tmp_dir/sweep-single-key-mutant.sh"
# shellcheck disable=SC2016 # Match the literal jq selector, including its $key variable.
selector_count="$(grep -c 'select(.Key == $key or .Key == ($key + ".tflock"))' "$SWEEPER")"
[ "$selector_count" -eq 2 ] || fail "production Stage-2 selector must cover versions and delete markers"
# shellcheck disable=SC2016 # Mutate the literal jq selector, not a shell expansion.
sed 's/select(.Key == $key or .Key == ($key + ".tflock"))/select(.Key == $key)/g' \
  "$SWEEPER" > "$lock_mutant"
chmod +x "$lock_mutant"
# shellcheck disable=SC2016 # Count the literal single-key jq selector in the mutant.
[ "$(grep -c 'select(.Key == $key)' "$lock_mutant")" -eq 2 ] || \
  fail "lock-key mutation oracle did not revert both selectors"
reset_store
store_fixture "$happy_fixture"
seed_lock_key_inventory
FAKE_SCENARIO_FILE="$happy_fixture" SWEEP_DELETE_BATCH_SIZE=2 \
  run_aws "$lock_mutant" env aws-happy >/dev/null
set +e
lock_mutant_output="$(assert_lock_key_postcondition \
  "$fake_state/envs_preview_aws-happy.tfstate.json" 2>&1)"
lock_mutant_rc=$?
set -e
if [ "$lock_mutant_rc" -ne 1 ] || \
   ! grep -Fq 'mutant survived the lock-key check' <<< "$lock_mutant_output" || \
   [ "$(lease_status aws aws-happy)" != closed ] || \
   [ "$(jq '[.[] | select(.Key == "envs/preview/aws-happy.tfstate.tflock")] | length' \
       "$fake_state/envs_preview_aws-happy.tfstate.json")" -ne 2 ]; then
  fail "single-key mutant was not closed-with-locks-retained and rejected by the postcondition"
fi
pass "Stage 2 deletes exact state and lock versions while the executable single-key mutant fails"

reset_store
old_closed="$(jq -c '.leases[] | select(.env_id == "prune-old")
  | .generation = 1
  | .opened_at = "2033-05-01T03:32:20Z"' "$FIXTURES/discover-cases.json")"
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
grep -E '^s3api put-object .*--if-match ' "$tmp_dir/aws-calls.log" >/dev/null || \
  fail "prune CAS-loss case did not exercise the tombstone If-Match request"
if grep -q '^s3api delete-object ' "$tmp_dir/aws-calls.log"; then
  fail "prune CAS-loss case used object deletion instead of a tombstone PUT"
fi
pass "prune tombstone CAS loss exits 3 without replacing the concurrently reopened lease"

reset_store
fresh_closed="$(jq -c '.leases[] | select(.env_id == "closed-seven")' "$FIXTURES/discover-cases.json")"
store_lease "$old_closed"
store_lease "$fresh_closed"
run_aws "$SWEEPER" env prune-old >/dev/null
prune_put_count="$(grep -Ec '^s3api put-object .*--if-match ' "$tmp_dir/aws-calls.log" || true)"
[ "$prune_put_count" -eq 1 ] || fail "lease prune did not make exactly one ETag-conditional tombstone PUT"
if grep -q '^s3api delete-object ' "$tmp_dir/aws-calls.log"; then
  fail "lease prune deleted the object instead of replacing it with a tombstone"
fi
pruned_lease="$(run_aws "$LEASE" get prune-old)"
if ! jq -e '
    .status == "deleted"
    and .generation == 1
    and (.deleted_at | type == "string" and length > 0)
    and (keys | sort == ["deleted_at","env_id","generation","opened_at","status","updated_at"])
  ' <<< "$pruned_lease" >/dev/null; then
  fail "closed lease older than seven days was not replaced by its generation tombstone: $pruned_lease"
fi
: > "$tmp_dir/aws-calls.log"
tombstone_output="$(run_aws "$SWEEPER" env prune-old)"
grep -Fq 'generation tombstone' <<< "$tombstone_output" || \
  fail "generation tombstone did not classify with the explicit skip reason"
if grep -q '^s3api put-object ' "$tmp_dir/aws-calls.log"; then
  fail "generation tombstone skip attempted a write"
fi
reopened_after_prune="$(run_aws "$LEASE" open prune-old --owner test-owner)"
jq -e '.status == "open" and .generation == 2' <<< "$reopened_after_prune" >/dev/null || \
  fail "prune tombstone did not reopen at generation two"
run_aws "$SWEEPER" env closed-seven >/dev/null
[ "$(lease_status aws closed-seven)" = closed ] || fail "seven-day boundary lease was pruned early"
pass "prune leaves a conditional tombstone, skips it explicitly, and reopens at generation two"

echo "PASS: sweeper suite ($pass_count cases)"
