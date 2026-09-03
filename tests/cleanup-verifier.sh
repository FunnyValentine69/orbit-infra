#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/cleanup"
VERIFIER="$REPO_ROOT/scripts/cleanup-verifier.sh"
AWS_WRAPPER="$REPO_ROOT/scripts/aws-cli.sh"
LEASE="$REPO_ROOT/scripts/lease.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

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
sleep 60
EOF
chmod +x "$tmp_dir/timeout-bin/aws"
timeout_stdout="$tmp_dir/timeout.stdout"
timeout_stderr="$tmp_dir/timeout.stderr"
start_seconds=$SECONDS
set +e
AWS_PROFILE=must-not-propagate \
AWS_TIMEOUT_ENV_LOG="$apply_log" \
AWS_TIMEOUT_ARGS_LOG="$args_log" \
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
  echo '{"ResourceTagMappingList":[]}'
  exit 0
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
case "\$*" in
  *" state list"*) echo 'module.network.aws_vpc.this' ;;
  *" show -json"*) cat "$FIXTURES/close-state.json" ;;
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

echo "PASS: cleanup verifier suite ($pass_count cases)"
