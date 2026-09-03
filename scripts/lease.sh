#!/usr/bin/env bash
# lease.sh — CAS-backed lease object for preview environments (ADR 0006).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AWS_CLI_SH="${AWS_CLI_SH:-$SCRIPT_DIR/aws-cli.sh}"
LEASE_BUCKET="${LEASE_BUCKET:-orbit-infra-79s5rw-tfstate}"
CLEANUP_RETRY_DELAY_SECONDS="${CLEANUP_RETRY_DELAY_SECONDS:-30}"

usage() {
  cat <<'EOF'
Usage: lease.sh <subcommand> [args]

Subcommands:
  get <env_id>
  open <env_id>
  transition <env_id> <from> <to> [--error <text>]
  begin-cleanup <env_id> [--force-retry]
  set-manifest <env_id> <file>
  list

open creates generation N+1 only for an absent or closed lease. Every mutation
uses an S3 ETag compare-and-swap. begin-cleanup increments cleanup_attempt and
allows at most three automatic stage-1 executions per generation; --force-retry
is required after exhaustion and appends an audit entry.

Env: TARGET (aws|localstack, required), LEASE_BUCKET.
Exit: 0 ok, 1 get-not-found, 2 bad args/AWS error, 3 CAS or state refusal.
EOF
}

err() { echo "lease.sh: $*" >&2; }
lease_key() { echo "leases/$1.json"; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date -u +%s; }

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

aws_cmd() { "$AWS_CLI_SH" "$@"; }

# Sets LEASE_FOUND, LEASE_BODY_FILE, and LEASE_ETAG.
read_lease() {
  local env_id="$1"
  local get_out
  LEASE_BODY_FILE="$(mktemp)"
  if get_out=$(aws_cmd s3api get-object \
      --bucket "$LEASE_BUCKET" --key "$(lease_key "$env_id")" \
      "$LEASE_BODY_FILE" 2>&1); then
    LEASE_FOUND=1
    LEASE_ETAG="$(jq -r '.ETag' <<< "$get_out")"
  elif grep -qE 'NoSuchKey|Not Found|404' <<< "$get_out"; then
    LEASE_FOUND=0
    LEASE_ETAG=""
  else
    rm -f "$LEASE_BODY_FILE"
    err "get-object failed: $get_out"
    exit 2
  fi
}

put_lease() {
  local operation="$1"
  local env_id="$2"
  local body_file="$3"
  shift 3
  local put_out
  if put_out=$(aws_cmd s3api put-object \
      --bucket "$LEASE_BUCKET" --key "$(lease_key "$env_id")" \
      --body "$body_file" --content-type application/json "$@" 2>&1); then
    cat "$body_file"
    rm -f "$body_file"
    return 0
  fi
  rm -f "$body_file"
  if grep -qE 'PreconditionFailed|At least one of the pre-conditions|412' <<< "$put_out"; then
    err "$operation $env_id: lost the CAS race"
    return 3
  fi
  err "put-object failed: $put_out"
  return 2
}

cmd_get() {
  local env_id="${1:?env_id required}"
  read_lease "$env_id"
  if [ "$LEASE_FOUND" != 1 ]; then
    rm -f "$LEASE_BODY_FILE"
    err "no lease for $env_id"
    exit 1
  fi
  cat "$LEASE_BODY_FILE"
  rm -f "$LEASE_BODY_FILE"
}

cmd_open() {
  local env_id="${1:?env_id required}"
  local generation=1
  local precondition_flag=(--if-none-match '*')
  read_lease "$env_id"
  if [ "$LEASE_FOUND" = 1 ]; then
    local status
    status="$(jq -r '.status' "$LEASE_BODY_FILE")"
    if [ "$status" != closed ]; then
      rm -f "$LEASE_BODY_FILE"
      err "cannot open $env_id: current status is '$status', not 'closed' or absent"
      exit 3
    fi
    generation=$(( $(jq -r '.generation' "$LEASE_BODY_FILE") + 1 ))
    precondition_flag=(--if-match "$LEASE_ETAG")
  fi
  rm -f "$LEASE_BODY_FILE"

  local ts body_file
  ts="$(now_iso)"
  body_file="$(mktemp)"
  jq -n \
    --arg env_id "$env_id" \
    --argjson generation "$generation" \
    --arg ts "$ts" '
      {
        env_id: $env_id,
        status: "open",
        generation: $generation,
        opened_at: $ts,
        updated_at: $ts,
        error: null,
        manifest: null,
        cleanup_attempt: 0,
        next_retry_at: null,
        manual_intervention_required: false,
        cleanup_retry_audit: []
      }' > "$body_file"
  put_lease open "$env_id" "$body_file" "${precondition_flag[@]}"
}

cmd_transition() {
  local env_id="${1:?env_id required}"
  local from="${2:?from status required}"
  local to="${3:?to status required}"
  shift 3
  local error_text=""
  if [ "${1:-}" = --error ]; then
    error_text="${2:?--error requires text}"
    shift 2
  fi
  [ "$#" -eq 0 ] || { err "unexpected transition arguments"; exit 2; }
  case "$to" in closing|closed|cleanup_failed) ;; *) err "invalid target status '$to'"; exit 2 ;; esac

  read_lease "$env_id"
  if [ "$LEASE_FOUND" != 1 ]; then
    rm -f "$LEASE_BODY_FILE"
    err "no lease for $env_id"
    exit 3
  fi
  local lease_json status etag ts next_retry_at body_file attempt
  lease_json="$(cat "$LEASE_BODY_FILE")"
  status="$(jq -r '.status' <<< "$lease_json")"
  etag="$LEASE_ETAG"
  rm -f "$LEASE_BODY_FILE"
  if [ "$status" != "$from" ]; then
    err "transition $env_id: current status is '$status', expected '$from'"
    exit 3
  fi

  ts="$(now_iso)"
  next_retry_at=""
  attempt="$(jq -r '.cleanup_attempt // 0' <<< "$lease_json")"
  if [ "$to" = cleanup_failed ] && [ "$attempt" -lt 3 ]; then
    next_retry_at="$(epoch_to_iso "$(( $(now_epoch) + CLEANUP_RETRY_DELAY_SECONDS ))")"
  fi
  body_file="$(mktemp)"
  jq \
    --arg status "$to" \
    --arg updated_at "$ts" \
    --arg error_text "$error_text" \
    --arg next_retry_at "$next_retry_at" '
      .status = $status
      | .updated_at = $updated_at
      | .error = (if $error_text == "" then null else $error_text end)
      | if $status == "cleanup_failed" then
          if (.cleanup_attempt // 0) >= 3 then
            .manual_intervention_required = true
            | .next_retry_at = null
          else
            .manual_intervention_required = false
            | .next_retry_at = $next_retry_at
          end
        elif $status == "closed" then
          .manual_intervention_required = false
          | .next_retry_at = null
        else . end' <<< "$lease_json" > "$body_file"
  put_lease transition "$env_id" "$body_file" --if-match "$etag"
}

cmd_begin_cleanup() {
  local env_id="${1:?env_id required}"
  local force_retry=false
  if [ "${2:-}" = --force-retry ]; then
    force_retry=true
  elif [ -n "${2:-}" ]; then
    err "begin-cleanup accepts only --force-retry"
    exit 2
  fi

  read_lease "$env_id"
  if [ "$LEASE_FOUND" != 1 ]; then
    rm -f "$LEASE_BODY_FILE"
    err "no lease for $env_id"
    exit 3
  fi
  local lease_json status attempt next_retry_at etag ts body_file retry_epoch
  lease_json="$(cat "$LEASE_BODY_FILE")"
  status="$(jq -r '.status' <<< "$lease_json")"
  attempt="$(jq -r '.cleanup_attempt // 0' <<< "$lease_json")"
  next_retry_at="$(jq -r '.next_retry_at // empty' <<< "$lease_json")"
  etag="$LEASE_ETAG"
  rm -f "$LEASE_BODY_FILE"

  case "$status" in open|closing|cleanup_failed) ;; *) err "begin-cleanup $env_id: status '$status' cannot start stage 1"; exit 3 ;; esac
  if [ "$force_retry" != true ] && { [ "$attempt" -ge 3 ] || jq -e '.manual_intervention_required == true' <<< "$lease_json" >/dev/null; }; then
    err "begin-cleanup $env_id: automatic retry budget exhausted; use --force-retry after manual review"
    exit 3
  fi
  if [ "$force_retry" != true ] && [ "$status" = cleanup_failed ] && [ -n "$next_retry_at" ]; then
    retry_epoch="$(iso_to_epoch "$next_retry_at")"
    if [ "$(now_epoch)" -lt "$retry_epoch" ]; then
      err "begin-cleanup $env_id: retry is not due until $next_retry_at"
      exit 3
    fi
  fi

  attempt=$((attempt + 1))
  ts="$(now_iso)"
  body_file="$(mktemp)"
  jq \
    --arg updated_at "$ts" \
    --argjson attempt "$attempt" \
    --argjson forced "$force_retry" '
      .status = "closing"
      | .updated_at = $updated_at
      | .error = null
      | .cleanup_attempt = $attempt
      | .next_retry_at = null
      | .manual_intervention_required = false
      | .cleanup_retry_audit = (.cleanup_retry_audit // [])
      | if $forced then
          .cleanup_retry_audit += [{attempt: $attempt, forced_at: $updated_at}]
        else . end' <<< "$lease_json" > "$body_file"
  put_lease begin-cleanup "$env_id" "$body_file" --if-match "$etag"
}

cmd_set_manifest() {
  local env_id="${1:?env_id required}"
  local file="${2:?manifest file required}"
  if ! jq -e . "$file" >/dev/null 2>&1; then
    err "$file is not valid JSON"
    exit 2
  fi
  read_lease "$env_id"
  if [ "$LEASE_FOUND" != 1 ]; then
    rm -f "$LEASE_BODY_FILE"
    err "no lease for $env_id"
    exit 3
  fi
  local lease_json etag body_file
  lease_json="$(cat "$LEASE_BODY_FILE")"
  etag="$LEASE_ETAG"
  rm -f "$LEASE_BODY_FILE"
  body_file="$(mktemp)"
  jq \
    --arg updated_at "$(now_iso)" \
    --argjson manifest "$(cat "$file")" '
      .updated_at = $updated_at
      | .manifest = $manifest' <<< "$lease_json" > "$body_file"
  put_lease set-manifest "$env_id" "$body_file" --if-match "$etag"
}

cmd_list() {
  local out keys now results key env_id body_file lease updated_epoch age
  out="$(aws_cmd s3api list-objects-v2 --bucket "$LEASE_BUCKET" --prefix leases/ --output json)"
  keys="$(jq -r '.Contents // [] | .[].Key' <<< "$out")"
  now="$(now_epoch)"
  results='[]'
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    env_id="$(basename "$key" .json)"
    body_file="$(mktemp)"
    aws_cmd s3api get-object --bucket "$LEASE_BUCKET" --key "$key" "$body_file" >/dev/null
    lease="$(cat "$body_file")"
    rm -f "$body_file"
    updated_epoch="$(iso_to_epoch "$(jq -r '.updated_at' <<< "$lease")")"
    age=$((now - updated_epoch))
    results="$(jq -c --argjson entry "$(jq --argjson age "$age" '{env_id,status,generation,opened_at,updated_at,cleanup_attempt,manual_intervention_required,age_seconds:$age}' <<< "$lease")" '. + [$entry]' <<< "$results")"
  done <<< "$keys"
  jq -c '.[]' <<< "$results"
}

main() {
  local sub="${1:-}"
  case "$sub" in
    get) shift; cmd_get "$@" ;;
    open) shift; cmd_open "$@" ;;
    transition) shift; cmd_transition "$@" ;;
    begin-cleanup) shift; cmd_begin_cleanup "$@" ;;
    set-manifest) shift; cmd_set_manifest "$@" ;;
    list) shift; cmd_list "$@" ;;
    --help|-h) usage ;;
    "") usage; exit 2 ;;
    *) err "unknown subcommand '$sub'"; usage; exit 2 ;;
  esac
}

main "$@"
