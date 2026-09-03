#!/usr/bin/env bash
# Prove two LocalStack preview environments remain isolated while their
# apply and stage-1 close operations overlap on one emulator.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${TARGET:-}"
run_seed="$(date +%s)$$"
run_token="${run_seed: -7}"
ENV_A="${ENV_A:-cca${run_token}1}"
ENV_B="${ENV_B:-cca${run_token}2}"
OPERATOR_CIDR="${OPERATOR_CIDR:-10.255.255.255/32}"
TAG_KEY=env_id
AWS_CLI_SH="$REPO_ROOT/scripts/aws-cli.sh"
LEASE_SH="$REPO_ROOT/scripts/lease.sh"
CLOSE_ENV_SH="$REPO_ROOT/scripts/close-env.sh"
VERIFIER_SH="$REPO_ROOT/scripts/cleanup-verifier.sh"

fail() {
  echo "localstack-concurrency.sh: $*" >&2
  exit 1
}

usage_fail() {
  echo "localstack-concurrency.sh: $*" >&2
  exit 2
}

[ "$TARGET" = localstack ] || usage_fail "TARGET must be localstack"
[ "$PWD" = "$REPO_ROOT" ] || usage_fail "run from the repository root: $REPO_ROOT"
for env_id in "$ENV_A" "$ENV_B"; do
  [[ "$env_id" =~ ^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$ ]] \
    || usage_fail "environment id '$env_id' must match ^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$"
done
[ "$ENV_A" != "$ENV_B" ] || usage_fail "ENV_A and ENV_B must differ"
for command_name in jq make terraform; do
  command -v "$command_name" >/dev/null 2>&1 \
    || usage_fail "required command not found: $command_name"
done

export TARGET
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1
export AWS_EC2_METADATA_DISABLED=true
export OPERATOR_CIDR
unset AWS_PROFILE AWS_SESSION_TOKEN AWS_SECURITY_TOKEN PREVIEW_ROOT PLAN_FILE

tmp_dir="$(mktemp -d)"
acquired_a=false
acquired_b=false
cleanup_complete=false
generation_a=""
generation_b=""
child_pids=()

close_owned_environment() {
  local env_id="$1"
  local generation="$2"
  local log_file="$3"
  {
    make -s render-localstack-backend \
      TARGET=localstack ENV_ID="$env_id" PREVIEW_ROOT=".preview-runs/$env_id" \
      && PREVIEW_ROOT=".preview-runs/$env_id" \
        "$CLOSE_ENV_SH" --generation "$generation" "$env_id"
  } 2>&1 | sed -E 's/[0-9]{12}/************/g' > "$log_file"
}

cleanup() {
  local rc=$?
  local pid
  trap - EXIT
  set +e
  # bash 3.2 (macOS) treats an empty array expansion as unbound under set -u.
  if [ "${#child_pids[@]}" -gt 0 ]; then
    for pid in "${child_pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
      fi
    done
    for pid in "${child_pids[@]}"; do
      wait "$pid" 2>/dev/null
    done
  fi
  if [ "$cleanup_complete" != true ]; then
    if [ "$acquired_a" = true ]; then
      close_owned_environment "$ENV_A" "$generation_a" "$tmp_dir/trap-close-a.log" \
        || echo "localstack-concurrency.sh: cleanup failed for $ENV_A; see $tmp_dir/trap-close-a.log" >&2
    fi
    if [ "$acquired_b" = true ]; then
      close_owned_environment "$ENV_B" "$generation_b" "$tmp_dir/trap-close-b.log" \
        || echo "localstack-concurrency.sh: cleanup failed for $ENV_B; see $tmp_dir/trap-close-b.log" >&2
    fi
  fi
  if [ "$rc" -eq 0 ]; then
    rm -rf "$tmp_dir"
  else
    echo "localstack-concurrency.sh: retained diagnostics in $tmp_dir" >&2
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

expected_generation() {
  local env_id="$1"
  local err_file="$2"
  local lease_json rc status generation
  set +e
  lease_json="$("$LEASE_SH" get "$env_id" 2>"$err_file")"
  rc=$?
  set -e
  if [ "$rc" -eq 1 ] && grep -Fq "no lease for $env_id" "$err_file"; then
    echo 1
    return
  fi
  [ "$rc" -eq 0 ] || fail "could not read pre-existing lease for $env_id (rc=$rc): $(cat "$err_file")"
  status="$(jq -r '.status' <<< "$lease_json")"
  generation="$(jq -r '.generation' <<< "$lease_json")"
  [ "$status" = closed ] \
    || fail "refusing to reuse $env_id: existing lease is '$status', expected 'closed' or absent"
  [[ "$generation" =~ ^[1-9][0-9]*$ ]] \
    || fail "pre-existing closed lease for $env_id has invalid generation '$generation'"
  echo $((generation + 1))
}

assert_open_refusal() {
  local env_id="$1"
  local expected_status="$2"
  local label="$3"
  local before after refusal rc
  before="$("$LEASE_SH" get "$env_id")"
  set +e
  refusal="$("$LEASE_SH" open "$env_id" 2>&1)"
  rc=$?
  set -e
  after="$("$LEASE_SH" get "$env_id")"
  [ "$rc" -eq 3 ] \
    || fail "$label: lease open returned $rc instead of documented state-refusal exit 3: $refusal"
  grep -Fq "current status is '$expected_status'" <<< "$refusal" \
    || fail "$label: refusal did not name current status '$expected_status': $refusal"
  [ "$(jq -Sc . <<< "$before")" = "$(jq -Sc . <<< "$after")" ] \
    || fail "$label: refused lease open changed the lease"
}

tag_inventory() {
  local env_id="$1"
  local inventory
  inventory="$("$AWS_CLI_SH" resourcegroupstaggingapi get-resources \
    --tag-filters "Key=$TAG_KEY,Values=$env_id" --output json)" \
    || fail "tag inventory failed for $env_id"
  jq -e '.ResourceTagMappingList | type == "array"' <<< "$inventory" >/dev/null \
    || fail "tag inventory was malformed for $env_id"
  printf '%s\n' "$inventory"
}

assert_no_cross_reference() {
  local observed="$1"
  local other_env="$2"
  local label="$3"
  if grep -Fq -- "$other_env" <<< "$observed"; then
    fail "$label mentions the other environment id '$other_env'"
  fi
}

assert_post_close_inventory() {
  local env_id="$1"
  local inventory="$2"
  local candidates verification count
  # The tagging API is eventually consistent on both backends and LocalStack
  # retains entries for deleted resources indefinitely (observed live
  # 2026-09-03: 22 stale entries after a verified close). The verifier owns
  # every gone/pending/live/indeterminate predicate, so every candidate the
  # inventory still lists is handed to its exact probes; nothing may be live,
  # indeterminate, or pending.
  candidates="$(jq -c '.ResourceTagMappingList' <<< "$inventory" \
    | "$VERIFIER_SH" normalize-tags)"
  verification="$("$VERIFIER_SH" verify-live <(printf '%s\n' "$candidates"))"
  jq -e '.passed and .summary.live == 0 and .summary.indeterminate == 0 and .summary.pending == 0' \
    <<< "$verification" >/dev/null \
    || fail "$env_id post-close inventory did not satisfy the shared cleanup predicates: $verification"
  count="$(jq 'length' <<< "$candidates")"
  printf '%s\n' "$count"
}

expected_a="$(expected_generation "$ENV_A" "$tmp_dir/lease-a.err")"
expected_b="$(expected_generation "$ENV_B" "$tmp_dir/lease-b.err")"

lease_a="$("$LEASE_SH" open "$ENV_A")" || fail "could not open lease for $ENV_A"
generation_a="$(jq -r '.generation' <<< "$lease_a")"
[ "$generation_a" = "$expected_a" ] \
  || fail "$ENV_A opened generation $generation_a, expected $expected_a"
acquired_a=true

lease_b="$("$LEASE_SH" open "$ENV_B")" || fail "could not open lease for $ENV_B"
generation_b="$(jq -r '.generation' <<< "$lease_b")"
[ "$generation_b" = "$expected_b" ] \
  || fail "$ENV_B opened generation $generation_b, expected $expected_b"
acquired_b=true

assert_open_refusal "$ENV_A" open "$ENV_A second open"
assert_open_refusal "$ENV_B" open "$ENV_B second open"

make apply TARGET=localstack ENV_ID="$ENV_A" PREVIEW_ROOT=".preview-runs/$ENV_A" \
  OPERATOR_CIDR="$OPERATOR_CIDR" 2>&1 \
  | sed -E 's/[0-9]{12}/************/g' >"$tmp_dir/apply-a.log" &
apply_pid_a=$!
child_pids+=("$apply_pid_a")
make apply TARGET=localstack ENV_ID="$ENV_B" PREVIEW_ROOT=".preview-runs/$ENV_B" \
  OPERATOR_CIDR="$OPERATOR_CIDR" 2>&1 \
  | sed -E 's/[0-9]{12}/************/g' >"$tmp_dir/apply-b.log" &
apply_pid_b=$!
child_pids+=("$apply_pid_b")

set +e
wait "$apply_pid_a"
apply_rc_a=$?
wait "$apply_pid_b"
apply_rc_b=$?
set -e
child_pids=()
if [ "$apply_rc_a" -ne 0 ] || [ "$apply_rc_b" -ne 0 ]; then
  tail -n 80 "$tmp_dir/apply-a.log" >&2
  tail -n 80 "$tmp_dir/apply-b.log" >&2
  fail "concurrent apply failed: $ENV_A rc=$apply_rc_a, $ENV_B rc=$apply_rc_b"
fi

lease_a="$("$LEASE_SH" get "$ENV_A")"
lease_b="$("$LEASE_SH" get "$ENV_B")"
jq -e --argjson generation "$generation_a" \
  '.status == "open" and .generation == $generation' <<< "$lease_a" >/dev/null \
  || fail "$ENV_A lease is not open at generation $generation_a"
jq -e --argjson generation "$generation_b" \
  '.status == "open" and .generation == $generation' <<< "$lease_b" >/dev/null \
  || fail "$ENV_B lease is not open at generation $generation_b"

for env_id in "$ENV_A" "$ENV_B"; do
  [ -d ".preview-runs/$env_id" ] \
    || fail "missing isolated preview copy .preview-runs/$env_id"
done
state_list_a="$(make -s localstack-state-list TARGET=localstack ENV_ID="$ENV_A" PREVIEW_ROOT=".preview-runs/$ENV_A")"
state_list_b="$(make -s localstack-state-list TARGET=localstack ENV_ID="$ENV_B" PREVIEW_ROOT=".preview-runs/$ENV_B")"
[ -n "$state_list_a" ] || fail "$ENV_A Terraform state is empty after apply"
[ -n "$state_list_b" ] || fail "$ENV_B Terraform state is empty after apply"
state_show_a="$(make -s localstack-show-json TARGET=localstack ENV_ID="$ENV_A" PREVIEW_ROOT=".preview-runs/$ENV_A")"
state_show_b="$(make -s localstack-show-json TARGET=localstack ENV_ID="$ENV_B" PREVIEW_ROOT=".preview-runs/$ENV_B")"
grep -Fq -- "$ENV_A" <<< "$state_show_a" \
  || fail "$ENV_A Terraform state does not contain its own environment id"
grep -Fq -- "$ENV_B" <<< "$state_show_b" \
  || fail "$ENV_B Terraform state does not contain its own environment id"
assert_no_cross_reference "$state_list_a" "$ENV_B" "$ENV_A Terraform state list"
assert_no_cross_reference "$state_show_a" "$ENV_B" "$ENV_A Terraform state show"
assert_no_cross_reference "$state_list_b" "$ENV_A" "$ENV_B Terraform state list"
assert_no_cross_reference "$state_show_b" "$ENV_A" "$ENV_B Terraform state show"

cluster_arn_a="$(make -s localstack-output TARGET=localstack ENV_ID="$ENV_A" \
  PREVIEW_ROOT=".preview-runs/$ENV_A" TF_OUTPUT=ecs_cluster_arn)"
cluster_arn_b="$(make -s localstack-output TARGET=localstack ENV_ID="$ENV_B" \
  PREVIEW_ROOT=".preview-runs/$ENV_B" TF_OUTPUT=ecs_cluster_arn)"
cluster_name_a="${cluster_arn_a##*/}"
cluster_name_b="${cluster_arn_b##*/}"
[ "$cluster_name_a" != "$cluster_name_b" ] \
  || fail "ECS cluster names are shared: $cluster_name_a"
grep -Fq -- "$ENV_A" <<< "$cluster_name_a" \
  || fail "$ENV_A ECS cluster name does not contain its environment id"
grep -Fq -- "$ENV_B" <<< "$cluster_name_b" \
  || fail "$ENV_B ECS cluster name does not contain its environment id"

inventory_a="$(tag_inventory "$ENV_A")"
inventory_b="$(tag_inventory "$ENV_B")"
tag_count_a="$(jq '.ResourceTagMappingList | length' <<< "$inventory_a")"
tag_count_b="$(jq '.ResourceTagMappingList | length' <<< "$inventory_b")"
[ "$tag_count_a" -gt 0 ] || fail "$ENV_A tagging inventory is empty after apply"
[ "$tag_count_b" -gt 0 ] || fail "$ENV_B tagging inventory is empty after apply"
assert_no_cross_reference "$(jq -r '.ResourceTagMappingList[].ResourceARN' <<< "$inventory_a")" \
  "$ENV_B" "$ENV_A tagging inventory"
assert_no_cross_reference "$(jq -r '.ResourceTagMappingList[].ResourceARN' <<< "$inventory_b")" \
  "$ENV_A" "$ENV_B tagging inventory"

close_owned_environment "$ENV_A" "$generation_a" "$tmp_dir/close-a.log" &
close_pid_a=$!
child_pids+=("$close_pid_a")
close_owned_environment "$ENV_B" "$generation_b" "$tmp_dir/close-b.log" &
close_pid_b=$!
child_pids+=("$close_pid_b")

set +e
wait "$close_pid_a"
close_rc_a=$?
wait "$close_pid_b"
close_rc_b=$?
set -e
child_pids=()
if [ "$close_rc_a" -ne 0 ] || [ "$close_rc_b" -ne 0 ]; then
  tail -n 80 "$tmp_dir/close-a.log" >&2
  tail -n 80 "$tmp_dir/close-b.log" >&2
  fail "concurrent close failed: $ENV_A rc=$close_rc_a, $ENV_B rc=$close_rc_b"
fi
cleanup_complete=true

lease_a="$("$LEASE_SH" get "$ENV_A")"
lease_b="$("$LEASE_SH" get "$ENV_B")"
jq -e --argjson generation "$generation_a" \
  '.status == "closing" and .generation == $generation and .manifest.target == "localstack"' \
  <<< "$lease_a" >/dev/null \
  || fail "$ENV_A lease did not retain closing/generation/LocalStack manifest state"
jq -e --argjson generation "$generation_b" \
  '.status == "closing" and .generation == $generation and .manifest.target == "localstack"' \
  <<< "$lease_b" >/dev/null \
  || fail "$ENV_B lease did not retain closing/generation/LocalStack manifest state"

post_state_a="$(make -s localstack-state-list TARGET=localstack ENV_ID="$ENV_A" PREVIEW_ROOT=".preview-runs/$ENV_A")"
post_state_b="$(make -s localstack-state-list TARGET=localstack ENV_ID="$ENV_B" PREVIEW_ROOT=".preview-runs/$ENV_B")"
[ -z "$post_state_a" ] || fail "$ENV_A Terraform state is not empty after close: $post_state_a"
[ -z "$post_state_b" ] || fail "$ENV_B Terraform state is not empty after close: $post_state_b"

post_inventory_a="$(tag_inventory "$ENV_A")"
post_inventory_b="$(tag_inventory "$ENV_B")"
residual_a="$(assert_post_close_inventory "$ENV_A" "$post_inventory_a")"
residual_b="$(assert_post_close_inventory "$ENV_B" "$post_inventory_b")"

assert_open_refusal "$ENV_A" closing "$ENV_A post-close open"
assert_open_refusal "$ENV_B" closing "$ENV_B post-close open"

state_count_a="$(wc -l <<< "$state_list_a" | tr -d '[:space:]')"
state_count_b="$(wc -l <<< "$state_list_b" | tr -d '[:space:]')"
state_count=$((state_count_a + state_count_b))
tag_count=$((tag_count_a + tag_count_b))
residual_count=$((residual_a + residual_b))
echo "PASS: LocalStack concurrency environments=2 state_resources=$state_count tagged_resources=$tag_count residual_inventory_entries=$residual_count lease_refusals=4"
