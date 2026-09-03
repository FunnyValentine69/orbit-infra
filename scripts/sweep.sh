#!/usr/bin/env bash
# Stage-1 retry, Stage-2 close, and closed-lease pruning for ADR 0006.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LEASE_SH="${LEASE_SH:-$SCRIPT_DIR/lease.sh}"
CLOSE_ENV_SH="${CLOSE_ENV_SH:-$SCRIPT_DIR/close-env.sh}"
AWS_CLI_SH="${AWS_CLI_SH:-$SCRIPT_DIR/aws-cli.sh}"
LEASE_BUCKET="${LEASE_BUCKET:-orbit-infra-79s5rw-tfstate}"
STATE_BUCKET="${STATE_BUCKET:-$LEASE_BUCKET}"
TARGET="${TARGET:-}"
SWEEP_IN_JOB="${SWEEP_IN_JOB:-false}"
SWEEP_DELETE_BATCH_SIZE="${SWEEP_DELETE_BATCH_SIZE:-1000}"
STAGE1_STALE_SECONDS=86400
PRUNE_AFTER_SECONDS=604800
DELETED_TASK_DEFINITION_ERROR='An error occurred (ClientException) when calling the DescribeTaskDefinition operation: Unable to describe task definition.'

export LEASE_BUCKET TARGET

usage() {
  cat <<'EOF'
Usage:
  sweep.sh discover
  sweep.sh env <env_id>

Env: TARGET (aws|localstack, required), LEASE_BUCKET, STATE_BUCKET.
EOF
}

err() { echo "sweep.sh: $*" >&2; }
aws_cmd() { "$AWS_CLI_SH" "$@"; }

epoch_to_iso() {
  local epoch="$1"
  date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ
}

iso_to_epoch() {
  local timestamp="$1"
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null \
    || date -u -d "$timestamp" +%s
}

now_epoch() {
  if [ -n "${SWEEP_NOW_EPOCH:-}" ]; then
    printf '%s\n' "$SWEEP_NOW_EPOCH"
  else
    date -u +%s
  fi
}

now_iso() { epoch_to_iso "$(now_epoch)"; }

validate_contract() {
  case "$TARGET" in
    aws|localstack) ;;
    *) err "TARGET is required and must be aws or localstack"; exit 2 ;;
  esac
  case "$SWEEP_IN_JOB" in
    true|false) ;;
    *) err "SWEEP_IN_JOB must be true or false"; exit 2 ;;
  esac
  if ! [[ "$SWEEP_DELETE_BATCH_SIZE" =~ ^[1-9][0-9]*$ ]] || \
     [ "$SWEEP_DELETE_BATCH_SIZE" -gt 1000 ]; then
    err "SWEEP_DELETE_BATCH_SIZE must be an integer from 1 through 1000"
    exit 2
  fi
  if [ -n "${SWEEP_NOW_EPOCH:-}" ] && ! [[ "$SWEEP_NOW_EPOCH" =~ ^[0-9]+$ ]]; then
    err "SWEEP_NOW_EPOCH must be a nonnegative integer"
    exit 2
  fi
}

validate_env_id() {
  local env_id="$1"
  if ! [[ "$env_id" =~ ^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$ ]]; then
    err "env_id '$env_id' does not match the preview environment contract"
    exit 2
  fi
}

validate_inventory_lease() {
  local lease="$1"
  jq -e '
    type == "object"
    and (.env_id | type == "string" and test("^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$"))
    and (.status | type == "string")
    and (.generation | type == "number" and . >= 1 and floor == .)
    and (.updated_at | type == "string")
    and ((.cleanup_attempt // 0) | type == "number" and . >= 0 and floor == .)
    and ((.next_retry_at == null) or (.next_retry_at | type == "string"))
    and ((.manual_intervention_required // false) | type == "boolean")
  ' <<< "$lease" >/dev/null 2>&1
}

classify_lease() {
  local lease="$1"
  local status updated_at updated_epoch age attempt manual next_retry retry_epoch
  status="$(jq -r '.status' <<< "$lease")"
  updated_at="$(jq -r '.updated_at' <<< "$lease")"
  if ! updated_epoch="$(iso_to_epoch "$updated_at" 2>/dev/null)"; then
    err "lease $(jq -r '.env_id' <<< "$lease") has an invalid updated_at"
    return 2
  fi
  age=$(( $(now_epoch) - updated_epoch ))
  attempt="$(jq -r '.cleanup_attempt // 0' <<< "$lease")"
  manual="$(jq -r '.manual_intervention_required // false' <<< "$lease")"
  next_retry="$(jq -r '.next_retry_at // empty' <<< "$lease")"

  CLASSIFICATION=skip
  CLASSIFICATION_REASON="unexpected lease status '$status'"
  case "$status" in
    open)
      if [ "$age" -gt "$STAGE1_STALE_SECONDS" ]; then
        CLASSIFICATION=stage1-stale-open
        CLASSIFICATION_REASON=""
      else
        CLASSIFICATION_REASON="open lease is not older than 24 hours"
      fi
      ;;
    cleanup_failed)
      if [ "$manual" = true ]; then
        CLASSIFICATION_REASON="manual intervention is required"
      elif [ "$attempt" -ge 3 ]; then
        CLASSIFICATION_REASON="automatic cleanup retry budget is exhausted"
      elif [ -z "$next_retry" ]; then
        CLASSIFICATION_REASON="cleanup retry has no next_retry_at"
      elif ! retry_epoch="$(iso_to_epoch "$next_retry" 2>/dev/null)"; then
        err "lease $(jq -r '.env_id' <<< "$lease") has an invalid next_retry_at"
        return 2
      elif [ "$(now_epoch)" -ge "$retry_epoch" ]; then
        CLASSIFICATION=stage1-retry
        CLASSIFICATION_REASON=""
      else
        CLASSIFICATION_REASON="cleanup retry is not due"
      fi
      ;;
    closing)
      CLASSIFICATION=stage2
      CLASSIFICATION_REASON=""
      ;;
    closed)
      if [ "$age" -gt "$PRUNE_AFTER_SECONDS" ]; then
        CLASSIFICATION=prune
        CLASSIFICATION_REASON=""
      else
        CLASSIFICATION_REASON="closed lease is within the seven-day retention window"
      fi
      ;;
  esac
}

get_lease() {
  local env_id="$1"
  local output rc
  set +e
  output="$("$LEASE_SH" get "$env_id" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$output" >&2
    return "$rc"
  fi
  printf '%s\n' "$output"
}

require_closing_generation_claim() {
  local lease="$1"
  local generation="$2"
  local claim="$3"
  if ! jq -e --argjson generation "$generation" --arg claim "$claim" '
      .status == "closing"
      and .generation == $generation
      and (.stage2_claim | type) == "object"
      and .stage2_claim.token == $claim
    ' <<< "$lease" >/dev/null 2>&1; then
    err "lease changed while Stage 2 was running"
    return 3
  fi
}

transition_stage2_failure() {
  local env_id="$1"
  local generation="$2"
  local claim="$3"
  local message="$4"
  local rc
  err "$message"
  set +e
  "$LEASE_SH" transition "$env_id" closing cleanup_failed \
    --generation "$generation" --claim "$claim" --error "$message" >/dev/null
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || exit "$rc"
  exit 1
}

set_manifest() {
  local env_id="$1"
  local generation="$2"
  local claim="$3"
  local manifest="$4"
  local manifest_file rc
  manifest_file="$(mktemp)"
  printf '%s\n' "$manifest" > "$manifest_file"
  set +e
  "$LEASE_SH" set-manifest "$env_id" "$manifest_file" \
    --generation "$generation" --claim "$claim" >/dev/null
  rc=$?
  set -e
  rm -f "$manifest_file"
  return "$rc"
}

record_stage2_allowance() {
  local env_id="$1"
  local generation="$2"
  local claim="$3"
  local arn="$4"
  local lease manifest
  lease="$(get_lease "$env_id")" || return $?
  require_closing_generation_claim "$lease" "$generation" "$claim" || return $?
  manifest="$(jq -c --arg arn "$arn" --arg at "$(now_iso)" '
    .manifest
    | .stage2_allowances = ((.stage2_allowances // []) + [{
        id:"localstack-delete-task-definitions-inactive",
        arn:$arn,
        recorded_at:$at
      }] | unique_by([.id,.arn]))
  ' <<< "$lease")" || return 2
  set_manifest "$env_id" "$generation" "$claim" "$manifest"
}

list_state_versions() {
  local state_key="$1"
  local key_marker=""
  local version_marker=""
  local prior_token=""
  local response page_entries is_truncated next_key next_version token
  local entries='[]'
  local args

  while :; do
    args=(s3api list-object-versions --bucket "$STATE_BUCKET" --prefix "$state_key" --output json --no-paginate)
    if [ -n "$key_marker" ]; then
      args+=(--key-marker "$key_marker")
      [ -z "$version_marker" ] || args+=(--version-id-marker "$version_marker")
    fi
    if ! response="$(aws_cmd "${args[@]}" 2>&1)"; then
      err "could not list retained state versions"
      return 1
    fi
    if ! jq -e '
      type == "object"
      and (.IsTruncated | type == "boolean")
      and ((.Versions // []) | type == "array")
      and ((.DeleteMarkers // []) | type == "array")
      and all((.Versions // [])[], (.DeleteMarkers // [])[];
        type == "object" and (.Key | type == "string") and (.VersionId | type == "string"))
    ' <<< "$response" >/dev/null 2>&1; then
      err "list-object-versions returned malformed output"
      return 1
    fi
    page_entries="$(jq -c --arg key "$state_key" '
      [(.Versions // [])[] | select(.Key == $key) | {Key,VersionId}]
      + [(.DeleteMarkers // [])[] | select(.Key == $key) | {Key,VersionId}]
    ' <<< "$response")"
    entries="$(jq -c --argjson page "$page_entries" '. + $page' <<< "$entries")"
    is_truncated="$(jq -r '.IsTruncated' <<< "$response")"
    [ "$is_truncated" = true ] || break
    if ! next_key="$(jq -er '.NextKeyMarker | select(type == "string" and length > 0)' <<< "$response")"; then
      err "truncated state-version response has no NextKeyMarker"
      return 1
    fi
    next_version="$(jq -r '.NextVersionIdMarker // empty' <<< "$response")"
    token="${next_key}|${next_version}"
    if [ "$token" = "$prior_token" ]; then
      err "state-version pagination did not advance"
      return 1
    fi
    prior_token="$token"
    key_marker="$next_key"
    version_marker="$next_version"
  done
  jq -c 'unique_by([.Key,.VersionId])' <<< "$entries"
}

delete_state_versions() {
  local env_id="$1"
  local generation="$2"
  local claim="$3"
  local entries="$4"
  local remaining batch payload response error_count lease
  remaining="$entries"
  while [ "$(jq 'length' <<< "$remaining")" -gt 0 ]; do
    batch="$(jq -c --argjson size "$SWEEP_DELETE_BATCH_SIZE" '.[:$size]' <<< "$remaining")"
    lease="$(get_lease "$env_id")" || return $?
    require_closing_generation_claim "$lease" "$generation" "$claim" || return $?
    payload="$(mktemp)"
    jq -n --argjson objects "$batch" '{Objects:$objects,Quiet:false}' > "$payload"
    if ! response="$(aws_cmd s3api delete-objects \
        --bucket "$STATE_BUCKET" --delete "file://$payload" --output json 2>&1)"; then
      rm -f "$payload"
      err "delete-objects failed for retained state: $(sed -E 's/[0-9]{12}/************/g' <<< "$response")"
      return 1
    fi
    rm -f "$payload"
    if ! jq -e '
      type == "object"
      and ((.Deleted // []) | type == "array")
      and ((.Errors // []) | type == "array")
    ' <<< "$response" >/dev/null 2>&1; then
      err "delete-objects returned malformed output"
      return 1
    fi
    error_count="$(jq '(.Errors // []) | length' <<< "$response")"
    if [ "$error_count" -ne 0 ]; then
      err "delete-objects reported $error_count object-version errors"
      return 1
    fi
    remaining="$(jq -c --argjson size "$SWEEP_DELETE_BATCH_SIZE" '.[$size:]' <<< "$remaining")"
  done
}

stage2() {
  local env_id="$1"
  local initial_lease="$2"
  local generation claim manifest_target arns arn describe_out describe_rc status
  local pending=false allowance_recorded=false lease latest_run state_key entries remaining rc
  local deleted_arns='[]' verified_empty_at proof_file
  generation="$(jq -r '.generation' <<< "$initial_lease")"
  claim="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
  initial_lease="$("$LEASE_SH" claim-stage2 "$env_id" \
    --generation "$generation" --claim "$claim")"
  manifest_target="$(jq -r '.manifest.target // empty' <<< "$initial_lease")"
  if [ "$manifest_target" != "$TARGET" ]; then
    transition_stage2_failure "$env_id" "$generation" "$claim" "Stage 2 target does not match the lease manifest"
  fi
  if ! arns="$(jq -r '
      (.manifest.candidates // [])
      | if type != "array" then error("candidates must be an array") else . end
      | .[]
      | select(.resource_type == "ecs:task-definition")
      | if ((.id | type) == "string" and (.id | length) > 0
          and (.arn | type) == "string" and (.arn | length) > 0
          and (.arn | test("^arn:[^:]+:ecs:[^:]+:[^:]+:task-definition/[A-Za-z0-9_-]+:[0-9]+$"))
          and .id == .arn)
        then .arn
        else error("task-definition candidate must have matching id and arn")
        end
    ' <<< "$initial_lease" | sort -u)"; then
    transition_stage2_failure "$env_id" "$generation" "$claim" "Stage 2 task-definition candidates are malformed"
  fi

  while IFS= read -r arn; do
    [ -n "$arn" ] || continue
    set +e
    describe_out="$(aws_cmd ecs describe-task-definition --task-definition "$arn" --output json 2>&1)"
    describe_rc=$?
    set -e
    if [ "$describe_rc" -ne 0 ]; then
      if [ "$describe_out" = "$DELETED_TASK_DEFINITION_ERROR" ]; then
        deleted_arns="$(jq -c --arg arn "$arn" '. + [$arn] | unique' <<< "$deleted_arns")"
        echo "deleted task definition: $arn"
        continue
      fi
      transition_stage2_failure "$env_id" "$generation" "$claim" "task-definition describe was indeterminate"
    fi
    if ! jq -e --arg arn "$arn" '
        type == "object"
        and (.taskDefinition | type == "object")
        and .taskDefinition.taskDefinitionArn == $arn
        and (.taskDefinition.status | type == "string")
      ' <<< "$describe_out" >/dev/null 2>&1; then
      transition_stage2_failure "$env_id" "$generation" "$claim" "task-definition describe was indeterminate"
    fi
    status="$(jq -r '.taskDefinition.status' <<< "$describe_out")"
    if [ "$TARGET" = localstack ] && [ "$status" = INACTIVE ] && \
       jq -e --arg arn "$arn" '
         any((.manifest.allowances // [])[];
           .id == "localstack-delete-task-definitions-inactive"
           and .arn == $arn
           and (.recorded_at | type == "string" and length > 0))
       ' <<< "$initial_lease" >/dev/null; then
      set +e
      record_stage2_allowance "$env_id" "$generation" "$claim" "$arn"
      rc=$?
      set -e
      [ "$rc" -eq 0 ] || exit "$rc"
      allowance_recorded=true
      echo "deleted-by-allowance task definition: $arn"
      continue
    fi
    case "$status" in
      ACTIVE|INACTIVE|DELETE_IN_PROGRESS)
        echo "pending task definition: $arn status=$status"
        pending=true
        ;;
      *)
        transition_stage2_failure "$env_id" "$generation" "$claim" "task-definition describe was indeterminate"
        ;;
    esac
  done <<< "$arns"

  if [ "$pending" = true ]; then
    "$LEASE_SH" release-stage2 "$env_id" \
      --generation "$generation" --claim "$claim" >/dev/null
    echo "sweep.sh: $env_id remains closing while task-definition deletion is pending"
    return 0
  fi
  if [ "$allowance_recorded" = true ]; then
    initial_lease="$(get_lease "$env_id")" || exit $?
    require_closing_generation_claim "$initial_lease" "$generation" "$claim" || exit $?
  fi

  lease="$(get_lease "$env_id")" || exit $?
  require_closing_generation_claim "$lease" "$generation" "$claim" || exit $?
  if ! latest_run="$(jq -ce '.manifest.verification_runs[-1]' <<< "$lease" 2>/dev/null)" || \
     ! jq -e '
       type == "object"
       and .passed == true
       and (.summary | type == "object")
       and .summary.live == 0
       and .summary.indeterminate == 0
     ' <<< "$latest_run" >/dev/null 2>&1; then
    transition_stage2_failure "$env_id" "$generation" "$claim" "last Stage-1 verification did not pass with zero live and indeterminate results"
  fi

  state_key="envs/preview/${env_id}.tfstate"
  lease="$(get_lease "$env_id")" || exit $?
  require_closing_generation_claim "$lease" "$generation" "$claim" || exit $?
  if ! entries="$(list_state_versions "$state_key")"; then
    transition_stage2_failure "$env_id" "$generation" "$claim" "state deletion failed while listing retained versions"
  fi
  set +e
  delete_state_versions "$env_id" "$generation" "$claim" "$entries"
  rc=$?
  set -e
  if [ "$rc" -eq 3 ]; then
    exit 3
  fi
  if [ "$rc" -ne 0 ]; then
    transition_stage2_failure "$env_id" "$generation" "$claim" "state deletion failed before all versions were removed"
  fi
  if ! remaining="$(list_state_versions "$state_key")"; then
    transition_stage2_failure "$env_id" "$generation" "$claim" "state deletion failed during final verification"
  fi
  if [ "$(jq 'length' <<< "$remaining")" -ne 0 ]; then
    transition_stage2_failure "$env_id" "$generation" "$claim" "state deletion failed: versions remain"
  fi
  verified_empty_at="$(now_iso)"

  proof_file="$(mktemp)"
  jq -n \
    --arg target "$TARGET" \
    --argjson in_job "$SWEEP_IN_JOB" \
    --arg state_key "$state_key" \
    --argjson deleted_arns "$deleted_arns" \
    --arg verified_empty_at "$verified_empty_at" '
      {
        target:$target,
        in_job:$in_job,
        state_key:$state_key,
        deleted_task_definition_arns:$deleted_arns,
        verified_empty_at:$verified_empty_at
      }
    ' > "$proof_file"
  set +e
  "$LEASE_SH" complete-stage2 "$env_id" \
    --generation "$generation" --claim "$claim" --proof "$proof_file" >/dev/null
  rc=$?
  set -e
  rm -f "$proof_file"
  [ "$rc" -eq 0 ] || exit "$rc"
  echo "sweep.sh: $env_id Stage 2 complete; lease is closed"
}

prune_closed_lease() {
  local env_id="$1"
  local record lease etag rc
  set +e
  record="$("$LEASE_SH" get-with-etag "$env_id" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 1 ]; then
    echo "sweep.sh: no lease for $env_id; nothing to prune"
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$record" >&2
    return "$rc"
  fi
  if ! jq -e 'type == "object" and (.etag | type == "string") and (.lease | type == "object")' \
      <<< "$record" >/dev/null 2>&1; then
    err "get-with-etag returned malformed output"
    return 2
  fi
  lease="$(jq -c '.lease' <<< "$record")"
  etag="$(jq -r '.etag' <<< "$record")"
  validate_inventory_lease "$lease" || { err "lease $env_id is malformed"; return 2; }
  classify_lease "$lease" || return $?
  if [ "$CLASSIFICATION" != prune ]; then
    echo "sweep.sh: no-op $env_id: $CLASSIFICATION_REASON"
    return 0
  fi
  "$LEASE_SH" delete-closed "$env_id" "$etag"
}

cmd_discover() {
  local lease inventory
  if ! inventory="$("$LEASE_SH" list)"; then
    err "lease inventory failed"
    return 2
  fi
  while IFS= read -r lease; do
    [ -n "$lease" ] || continue
    if ! validate_inventory_lease "$lease"; then
      err "lease inventory contains a malformed record"
      return 2
    fi
    classify_lease "$lease" || return $?
    jq -c \
      --arg classification "$CLASSIFICATION" \
      --arg reason "$CLASSIFICATION_REASON" '
        {
          env_id,
          status,
          generation,
          updated_at,
          cleanup_attempt:(.cleanup_attempt // 0),
          next_retry_at:(.next_retry_at // null),
          manual_intervention_required:(.manual_intervention_required // false),
          classification:$classification,
          reason:(if $reason == "" then null else $reason end)
        }
      ' <<< "$lease"
  done <<< "$inventory"
}

cmd_env() {
  local env_id="$1"
  local lease rc generation status
  validate_env_id "$env_id"
  set +e
  lease="$(get_lease "$env_id")"
  rc=$?
  set -e
  if [ "$rc" -eq 1 ]; then
    echo "sweep.sh: no lease for $env_id; nothing to do"
    return 0
  fi
  [ "$rc" -eq 0 ] || return "$rc"
  validate_inventory_lease "$lease" || { err "lease $env_id is malformed"; return 2; }
  classify_lease "$lease" || return $?
  case "$CLASSIFICATION" in
    stage1-stale-open|stage1-retry)
      generation="$(jq -r '.generation' <<< "$lease")"
      status="$(jq -r '.status' <<< "$lease")"
      echo "sweep.sh: running stage 1 for $env_id ($CLASSIFICATION)"
      "$CLOSE_ENV_SH" --generation "$generation" --from "$status" "$env_id"
      ;;
    stage2)
      stage2 "$env_id" "$lease"
      ;;
    prune)
      prune_closed_lease "$env_id"
      ;;
    skip)
      echo "sweep.sh: no-op $env_id: $CLASSIFICATION_REASON"
      ;;
    *)
      err "internal classification error: $CLASSIFICATION"
      return 2
      ;;
  esac
}

main() {
  validate_contract
  case "${1:-}" in
    discover)
      [ "$#" -eq 1 ] || { usage >&2; exit 2; }
      cmd_discover
      ;;
    env)
      [ "$#" -eq 2 ] || { usage >&2; exit 2; }
      cmd_env "$2"
      ;;
    --help|-h) usage ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
