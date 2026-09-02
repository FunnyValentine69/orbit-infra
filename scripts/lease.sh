#!/usr/bin/env bash
# lease.sh — CAS-backed lease object for preview environments (ADR 0006).
#
# The lease for <env_id> lives at s3://$LEASE_BUCKET/leases/<env_id>.json.
# Every write is a compare-and-swap on the object's S3 ETag (open: creates
# generation N+1 via --if-match on the current object, or --if-none-match
# '*' when no lease exists / the current lease is closed; transition/
# set-manifest: --if-match on the ETag read just before the write). Two
# concurrent writers can never both win: the loser's put-object fails with
# PreconditionFailed and this script exits 3.
#
# Env:
#   LEASE_BUCKET     — state bucket holding leases/ (default orbit-infra-79s5rw-tfstate)
#   AWS_ENDPOINT_URL — unset for real AWS; LocalStack sets this to
#                      http://localhost:4566 (read natively by the AWS CLI)
#
# Exit codes:
#   0  ok
#   1  lease not found (get only)
#   2  other error (bad args, S3 error other than a failed precondition)
#   3  precondition failed — CAS lost the race, or `from`/state mismatch
set -euo pipefail

LEASE_BUCKET="${LEASE_BUCKET:-orbit-infra-79s5rw-tfstate}"

usage() {
  cat <<'EOF'
Usage: lease.sh <subcommand> [args]

Subcommands:
  get <env_id>
      Print the lease JSON for env_id to stdout. Exit 1 if no lease exists.

  open <env_id>
      Open (or re-open) a lease. Allowed only when no lease exists, or the
      current lease's status is "closed". Creates generation N+1: N=0 (so
      generation=1) when no lease exists, or current_generation+1 when
      re-opening a closed lease. Exit 3 if a lease exists and its status
      is not "closed", or if the CAS write loses the race.

  transition <env_id> <from> <to> [--error <text>]
      Compare-and-swap the lease's status from `from` to `to`. `to` must
      be one of: closing, closed, cleanup_failed. Exit 3 if the current
      status is not `from`, or if the CAS write loses the race.
      --error <text> is stored in the lease's `error` field (to record
      why a transition to cleanup_failed happened); omitted otherwise,
      cleared to null on any other transition.

  set-manifest <env_id> <file>
      Compare-and-swap the lease, storing the JSON in <file> under the
      lease's `manifest` field. <file> must contain valid JSON. Exit 3 if
      the CAS write loses the race.

  list
      Print every lease under leases/ as a JSON array of
      {env_id, status, generation, opened_at, updated_at, age_seconds}.

Env:
  LEASE_BUCKET      state bucket holding leases/ (default orbit-infra-79s5rw-tfstate)
  AWS_ENDPOINT_URL  unset for real AWS; LocalStack sets this

Exit codes: 0 ok, 1 lease not found (get only), 2 other error,
3 precondition failed (CAS lost the race, or from/state mismatch).
EOF
}

err() { echo "lease.sh: $*" >&2; }

lease_key() { echo "leases/$1.json"; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Reads the current lease for env_id into $LEASE_BODY_FILE / sets
# LEASE_FOUND=1 and LEASE_ETAG, or LEASE_FOUND=0 when absent (NoSuchKey).
# Any other S3 error is fatal (exit 2).
read_lease() {
  local env_id="$1"
  LEASE_BODY_FILE="$(mktemp)"
  local get_out
  if get_out=$(aws s3api get-object \
      --bucket "$LEASE_BUCKET" --key "$(lease_key "$env_id")" \
      "$LEASE_BODY_FILE" 2>&1); then
    LEASE_FOUND=1
    LEASE_ETAG=$(echo "$get_out" | jq -r '.ETag')
  else
    if echo "$get_out" | grep -qE 'NoSuchKey|Not Found|404'; then
      LEASE_FOUND=0
      LEASE_ETAG=""
    else
      err "get-object failed: $get_out"
      exit 2
    fi
  fi
}

cmd_get() {
  local env_id="${1:?env_id required}"
  read_lease "$env_id"
  if [ "$LEASE_FOUND" != "1" ]; then
    err "no lease for $env_id"
    exit 1
  fi
  cat "$LEASE_BODY_FILE"
  rm -f "$LEASE_BODY_FILE"
}

cmd_open() {
  local env_id="${1:?env_id required}"
  read_lease "$env_id"

  local generation=1
  local precondition_flag=(--if-none-match '*')

  if [ "$LEASE_FOUND" = "1" ]; then
    local status
    status=$(jq -r '.status' "$LEASE_BODY_FILE")
    if [ "$status" != "closed" ]; then
      err "cannot open $env_id: current status is '$status', not 'closed' or absent"
      rm -f "$LEASE_BODY_FILE"
      exit 3
    fi
    local cur_gen
    cur_gen=$(jq -r '.generation' "$LEASE_BODY_FILE")
    generation=$((cur_gen + 1))
    precondition_flag=(--if-match "$LEASE_ETAG")
  fi
  rm -f "$LEASE_BODY_FILE"

  local ts body_file
  ts=$(now_iso)
  body_file=$(mktemp)
  jq -n \
    --arg env_id "$env_id" \
    --arg status "open" \
    --argjson generation "$generation" \
    --arg opened_at "$ts" \
    --arg updated_at "$ts" \
    '{env_id: $env_id, status: $status, generation: $generation, opened_at: $opened_at, updated_at: $updated_at, error: null, manifest: null}' \
    > "$body_file"

  local put_out
  if put_out=$(aws s3api put-object \
      --bucket "$LEASE_BUCKET" --key "$(lease_key "$env_id")" \
      --body "$body_file" --content-type application/json \
      "${precondition_flag[@]}" 2>&1); then
    cat "$body_file"
    rm -f "$body_file"
    exit 0
  else
    rm -f "$body_file"
    if echo "$put_out" | grep -qE 'PreconditionFailed|At least one of the pre-conditions|412'; then
      err "open $env_id: lost the CAS race"
      exit 3
    fi
    err "put-object failed: $put_out"
    exit 2
  fi
}

cmd_transition() {
  local env_id="${1:?env_id required}"
  local from="${2:?from status required}"
  local to="${3:?to status required}"
  shift 3
  local error_text=""
  if [ "${1:-}" = "--error" ]; then
    error_text="${2:?--error requires text}"
  fi

  case "$to" in
    closing|closed|cleanup_failed) ;;
    *)
      err "invalid target status '$to' (must be closing, closed, or cleanup_failed)"
      exit 2
      ;;
  esac

  read_lease "$env_id"
  if [ "$LEASE_FOUND" != "1" ]; then
    err "no lease for $env_id"
    exit 3
  fi
  local status generation opened_at manifest
  status=$(jq -r '.status' "$LEASE_BODY_FILE")
  if [ "$status" != "$from" ]; then
    err "transition $env_id: current status is '$status', expected '$from'"
    rm -f "$LEASE_BODY_FILE"
    exit 3
  fi
  generation=$(jq -r '.generation' "$LEASE_BODY_FILE")
  opened_at=$(jq -r '.opened_at' "$LEASE_BODY_FILE")
  manifest=$(jq -c '.manifest' "$LEASE_BODY_FILE")
  local etag="$LEASE_ETAG"
  rm -f "$LEASE_BODY_FILE"

  local ts body_file
  ts=$(now_iso)
  body_file=$(mktemp)
  jq -n \
    --arg env_id "$env_id" \
    --arg status "$to" \
    --argjson generation "$generation" \
    --arg opened_at "$opened_at" \
    --arg updated_at "$ts" \
    --arg error_text "$error_text" \
    --argjson manifest "$manifest" \
    '{env_id: $env_id, status: $status, generation: $generation, opened_at: $opened_at, updated_at: $updated_at, error: (if $error_text == "" then null else $error_text end), manifest: $manifest}' \
    > "$body_file"

  local put_out
  if put_out=$(aws s3api put-object \
      --bucket "$LEASE_BUCKET" --key "$(lease_key "$env_id")" \
      --body "$body_file" --content-type application/json \
      --if-match "$etag" 2>&1); then
    cat "$body_file"
    rm -f "$body_file"
    exit 0
  else
    rm -f "$body_file"
    if echo "$put_out" | grep -qE 'PreconditionFailed|At least one of the pre-conditions|412'; then
      err "transition $env_id: lost the CAS race"
      exit 3
    fi
    err "put-object failed: $put_out"
    exit 2
  fi
}

cmd_set_manifest() {
  local env_id="${1:?env_id required}"
  local file="${2:?manifest file required}"
  if ! jq -e . "$file" >/dev/null 2>&1; then
    err "$file is not valid JSON"
    exit 2
  fi

  read_lease "$env_id"
  if [ "$LEASE_FOUND" != "1" ]; then
    err "no lease for $env_id"
    exit 3
  fi
  local status generation opened_at
  status=$(jq -r '.status' "$LEASE_BODY_FILE")
  generation=$(jq -r '.generation' "$LEASE_BODY_FILE")
  opened_at=$(jq -r '.opened_at' "$LEASE_BODY_FILE")
  local etag="$LEASE_ETAG"
  local error_val
  error_val=$(jq -c '.error' "$LEASE_BODY_FILE")
  rm -f "$LEASE_BODY_FILE"

  local ts body_file manifest_json
  ts=$(now_iso)
  manifest_json=$(cat "$file")
  body_file=$(mktemp)
  jq -n \
    --arg env_id "$env_id" \
    --arg status "$status" \
    --argjson generation "$generation" \
    --arg opened_at "$opened_at" \
    --arg updated_at "$ts" \
    --argjson error "$error_val" \
    --argjson manifest "$manifest_json" \
    '{env_id: $env_id, status: $status, generation: $generation, opened_at: $opened_at, updated_at: $updated_at, error: $error, manifest: $manifest}' \
    > "$body_file"

  local put_out
  if put_out=$(aws s3api put-object \
      --bucket "$LEASE_BUCKET" --key "$(lease_key "$env_id")" \
      --body "$body_file" --content-type application/json \
      --if-match "$etag" 2>&1); then
    cat "$body_file"
    rm -f "$body_file"
    exit 0
  else
    rm -f "$body_file"
    if echo "$put_out" | grep -qE 'PreconditionFailed|At least one of the pre-conditions|412'; then
      err "set-manifest $env_id: lost the CAS race"
      exit 3
    fi
    err "put-object failed: $put_out"
    exit 2
  fi
}

cmd_list() {
  local out
  out=$(aws s3api list-objects-v2 --bucket "$LEASE_BUCKET" --prefix "leases/" --output json)
  local keys
  keys=$(echo "$out" | jq -r '.Contents // [] | .[].Key')
  local now_epoch
  now_epoch=$(date -u +%s)
  local results="[]"
  local key env_id body_file lease age
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    env_id=$(basename "$key" .json)
    body_file=$(mktemp)
    aws s3api get-object --bucket "$LEASE_BUCKET" --key "$key" "$body_file" >/dev/null
    lease=$(cat "$body_file")
    rm -f "$body_file"
    local updated_epoch
    updated_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$(echo "$lease" | jq -r '.updated_at')" +%s 2>/dev/null \
      || date -u -d "$(echo "$lease" | jq -r '.updated_at')" +%s)
    age=$((now_epoch - updated_epoch))
    results=$(echo "$results" | jq --argjson entry "$(echo "$lease" | jq --argjson age "$age" '{env_id, status, generation, opened_at, updated_at, age_seconds: $age}')" '. + [$entry]')
  done <<< "$keys"
  echo "$results" | jq -c '.[]'
}

main() {
  local sub="${1:-}"
  case "$sub" in
    get) shift; cmd_get "$@" ;;
    open) shift; cmd_open "$@" ;;
    transition) shift; cmd_transition "$@" ;;
    set-manifest) shift; cmd_set_manifest "$@" ;;
    list) shift; cmd_list "$@" ;;
    --help|-h|"") usage; [ "$sub" = "" ] && exit 2 || exit 0 ;;
    *) err "unknown subcommand '$sub'"; usage; exit 2 ;;
  esac
}

main "$@"
