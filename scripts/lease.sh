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
  get-with-etag <env_id>
  open <env_id> [--owner <token>] [--manifest <file>]
  transition <env_id> <from> cleanup_failed --generation <n> [--claim <token>] [--error <text>]
  begin-cleanup <env_id> --generation <n> --from <open|closing|cleanup_failed> --claim <token> [--force-retry]
  complete-stage1 <env_id> --generation <n> --claim <token>
  claim-stage2 <env_id> --generation <n> --claim <token>
  release-stage2 <env_id> --generation <n> --claim <token>
  set-manifest <env_id> <file> --generation <n> [--claim <token>]
  complete-stage2 <env_id> --generation <n> --claim <token> --proof <file>
  delete-closed <env_id> <expected-etag>
  list

open creates generation N+1 only for an absent or closed lease. Its optional
owner and initial manifest are written by that same compare-and-swap PUT. Every
mutation uses an S3 ETag compare-and-swap. begin-cleanup increments cleanup_attempt,
requires the generation and source status observed by its caller, and allows at
most three automatic stage-1 executions per generation. --force-retry is
required after exhaustion; it clears an active Stage-2 claim and audits it.
It also takes over a stale Stage-1 claim and records it as cleared_stage1_claim.
Stage 1 holds an exclusive claim until complete-stage1 or a failure transition.
Only complete-stage2 can produce closed, atomically with its Stage-2 proof.

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

cmd_get_with_etag() {
  local env_id="${1:?env_id required}"
  read_lease "$env_id"
  if [ "$LEASE_FOUND" != 1 ]; then
    rm -f "$LEASE_BODY_FILE"
    err "no lease for $env_id"
    exit 1
  fi
  jq -cn \
    --arg etag "$LEASE_ETAG" \
    --argjson lease "$(cat "$LEASE_BODY_FILE")" \
    '{etag:$etag,lease:$lease}'
  rm -f "$LEASE_BODY_FILE"
}

cmd_open() {
  local env_id="${1:?env_id required}"
  shift
  local owner=""
  local manifest_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --owner)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { err "--owner requires a nonempty token"; exit 2; }
        owner="$2"
        shift 2
        ;;
      --manifest)
        [ "$#" -ge 2 ] || { err "--manifest requires a file"; exit 2; }
        manifest_file="$2"
        shift 2
        ;;
      *)
        err "unexpected open argument '$1'"
        exit 2
        ;;
    esac
  done

  local initial_manifest='null'
  if [ -n "$manifest_file" ]; then
    if ! initial_manifest="$(jq -c . "$manifest_file" 2>/dev/null)"; then
      err "$manifest_file is not valid JSON"
      exit 2
    fi
  fi

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
    --arg ts "$ts" \
    --arg owner "$owner" \
    --argjson manifest "$initial_manifest" '
      {
        env_id: $env_id,
        status: "open",
        generation: $generation,
        opened_at: $ts,
        updated_at: $ts,
        error: null,
        owner: (if $owner == "" then null else $owner end),
        manifest: $manifest,
        cleanup_attempt: 0,
        next_retry_at: null,
        manual_intervention_required: false,
        cleanup_retry_audit: [],
        stage1_claim: null,
        stage2_claim: null
      }' > "$body_file"
  put_lease open "$env_id" "$body_file" "${precondition_flag[@]}"
}

cmd_transition() {
  local env_id="${1:?env_id required}"
  local from="${2:?from status required}"
  local to="${3:?to status required}"
  shift 3
  local error_text=""
  local expected_generation=""
  local claim=""
  local claim_set=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --error)
        [ "$#" -ge 2 ] || { err "--error requires text"; exit 2; }
        error_text="$2"
        shift 2
        ;;
      --generation)
        [ "$#" -ge 2 ] || { err "--generation requires a value"; exit 2; }
        expected_generation="$2"
        shift 2
        ;;
      --claim)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { err "--claim requires a nonempty token"; exit 2; }
        claim="$2"
        claim_set=true
        shift 2
        ;;
      *) err "unexpected transition argument '$1'"; exit 2 ;;
    esac
  done
  [ "$to" = cleanup_failed ] || {
    err "invalid target status '$to' (only complete-stage2 may produce closed)"
    exit 2
  }
  [[ "$expected_generation" =~ ^[1-9][0-9]*$ ]] || {
    err "transition requires --generation <positive integer>"
    exit 2
  }

  read_lease "$env_id"
  if [ "$LEASE_FOUND" != 1 ]; then
    rm -f "$LEASE_BODY_FILE"
    err "no lease for $env_id"
    exit 3
  fi
  local lease_json status generation etag ts next_retry_at body_file attempt
  local has_stage1_claim has_stage2_claim
  lease_json="$(cat "$LEASE_BODY_FILE")"
  status="$(jq -r '.status' <<< "$lease_json")"
  generation="$(jq -r '.generation // empty' <<< "$lease_json")"
  etag="$LEASE_ETAG"
  rm -f "$LEASE_BODY_FILE"
  if [ "$status" != "$from" ] || [ "$generation" != "$expected_generation" ]; then
    err "transition $env_id: lease generation or status changed"
    exit 3
  fi
  has_stage1_claim="$(jq -r 'if (.stage1_claim // null) == null then "false" else "true" end' <<< "$lease_json")"
  has_stage2_claim="$(jq -r 'if (.stage2_claim // null) == null then "false" else "true" end' <<< "$lease_json")"
  if [ "$has_stage1_claim" = true ] && [ "$has_stage2_claim" = true ]; then
    err "transition $env_id: lease has multiple active claims"
    exit 3
  elif [ "$has_stage1_claim" = true ]; then
    if [ "$claim_set" != true ] || ! jq -e --arg claim "$claim" '
        (.stage1_claim | type) == "object"
        and .stage1_claim.token == $claim
      ' <<< "$lease_json" >/dev/null; then
      err "transition $env_id: active Stage-1 claim does not match"
      exit 3
    fi
  elif [ "$has_stage2_claim" = true ]; then
    if [ "$claim_set" != true ] || ! jq -e --arg claim "$claim" '
        (.stage2_claim | type) == "object"
        and .stage2_claim.token == $claim
      ' <<< "$lease_json" >/dev/null; then
      err "transition $env_id: active Stage-2 claim does not match"
      exit 3
    fi
  elif [ "$claim_set" = true ]; then
    err "transition $env_id: no active claim matches"
    exit 3
  fi

  ts="$(now_iso)"
  next_retry_at=""
  attempt="$(jq -r '.cleanup_attempt // 0' <<< "$lease_json")"
  if [ "$attempt" -lt 3 ]; then
    next_retry_at="$(epoch_to_iso "$(( $(now_epoch) + CLEANUP_RETRY_DELAY_SECONDS ))")"
  fi
  body_file="$(mktemp)"
  jq \
    --arg updated_at "$ts" \
    --arg error_text "$error_text" \
    --arg next_retry_at "$next_retry_at" '
      .status = "cleanup_failed"
      | .updated_at = $updated_at
      | .error = (if $error_text == "" then null else $error_text end)
      | .stage1_claim = null
      | .stage2_claim = null
      | if (.cleanup_attempt // 0) >= 3 then
          .manual_intervention_required = true
          | .next_retry_at = null
        else
          .manual_intervention_required = false
          | .next_retry_at = $next_retry_at
        end' <<< "$lease_json" > "$body_file"
  put_lease transition "$env_id" "$body_file" --if-match "$etag"
}

cmd_begin_cleanup() {
  local env_id="${1:?env_id required}"
  shift
  local force_retry=false
  local expected_generation=""
  local expected_status=""
  local claim=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --force-retry) force_retry=true; shift ;;
      --generation)
        [ "$#" -ge 2 ] || { err "--generation requires a value"; exit 2; }
        expected_generation="$2"
        shift 2
        ;;
      --from)
        [ "$#" -ge 2 ] || { err "--from requires a status"; exit 2; }
        expected_status="$2"
        shift 2
        ;;
      --claim)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { err "--claim requires a nonempty token"; exit 2; }
        claim="$2"
        shift 2
        ;;
      *) err "unexpected begin-cleanup argument '$1'"; exit 2 ;;
    esac
  done
  [[ "$expected_generation" =~ ^[1-9][0-9]*$ ]] || {
    err "begin-cleanup requires --generation <positive integer>"
    exit 2
  }
  case "$expected_status" in
    open|closing|cleanup_failed) ;;
    *) err "begin-cleanup requires --from <open|closing|cleanup_failed>"; exit 2 ;;
  esac
  [ -n "$claim" ] || { err "begin-cleanup requires --claim <token>"; exit 2; }

  read_lease "$env_id"
  if [ "$LEASE_FOUND" != 1 ]; then
    rm -f "$LEASE_BODY_FILE"
    err "no lease for $env_id"
    exit 3
  fi
  local lease_json status generation attempt next_retry_at etag ts body_file retry_epoch
  local has_stage1_claim has_stage2_claim cleared_claim cleared_stage1_claim
  lease_json="$(cat "$LEASE_BODY_FILE")"
  status="$(jq -r '.status' <<< "$lease_json")"
  generation="$(jq -r '.generation // empty' <<< "$lease_json")"
  attempt="$(jq -r '.cleanup_attempt // 0' <<< "$lease_json")"
  next_retry_at="$(jq -r '.next_retry_at // empty' <<< "$lease_json")"
  has_stage1_claim="$(jq -r 'if (.stage1_claim // null) == null then "false" else "true" end' <<< "$lease_json")"
  has_stage2_claim="$(jq -r 'if (.stage2_claim // null) == null then "false" else "true" end' <<< "$lease_json")"
  cleared_claim="$(jq -c '.stage2_claim // null' <<< "$lease_json")"
  cleared_stage1_claim="$(jq -c '.stage1_claim // null' <<< "$lease_json")"
  etag="$LEASE_ETAG"
  rm -f "$LEASE_BODY_FILE"

  if [ "$generation" != "$expected_generation" ] || [ "$status" != "$expected_status" ]; then
    err "begin-cleanup $env_id: lease generation or status changed"
    exit 3
  fi
  if [ "$has_stage1_claim" = true ] && [ "$force_retry" != true ]; then
    err "begin-cleanup $env_id: lease has an active Stage-1 claim; use --force-retry only after confirming the Stage-1 process is dead"
    exit 3
  fi
  if [ "$has_stage2_claim" = true ] && [ "$force_retry" != true ]; then
    err "begin-cleanup $env_id: Stage 2 has an active claim"
    exit 3
  fi
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
    --arg claim "$claim" \
    --argjson forced "$force_retry" \
    --argjson cleared_claim "$cleared_claim" \
    --argjson cleared_stage1_claim "$cleared_stage1_claim" '
      .status = "closing"
      | .updated_at = $updated_at
      | .error = null
      | .cleanup_attempt = $attempt
      | .next_retry_at = null
      | .manual_intervention_required = false
      | .stage1_claim = {token: $claim, claimed_at: $updated_at}
      | .stage2_claim = null
      | .cleanup_retry_audit = (.cleanup_retry_audit // [])
      | if $forced then
          .cleanup_retry_audit += [
            ({attempt: $attempt, forced_at: $updated_at}
              + if $cleared_claim == null then {}
                else {cleared_stage2_claim: $cleared_claim}
                end
              + if $cleared_stage1_claim == null then {}
                else {cleared_stage1_claim: $cleared_stage1_claim}
                end)
          ]
        else . end' <<< "$lease_json" > "$body_file"
  put_lease begin-cleanup "$env_id" "$body_file" --if-match "$etag"
}

cmd_complete_stage1() {
  local env_id="${1:?env_id required}"
  shift
  local expected_generation=""
  local claim=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --generation)
        [ "$#" -ge 2 ] || { err "--generation requires a value"; exit 2; }
        expected_generation="$2"
        shift 2
        ;;
      --claim)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { err "--claim requires a nonempty token"; exit 2; }
        claim="$2"
        shift 2
        ;;
      *) err "unexpected complete-stage1 argument '$1'"; exit 2 ;;
    esac
  done
  [[ "$expected_generation" =~ ^[1-9][0-9]*$ ]] || {
    err "complete-stage1 requires --generation <positive integer>"
    exit 2
  }
  [ -n "$claim" ] || { err "complete-stage1 requires --claim <token>"; exit 2; }

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
  if ! jq -e --argjson generation "$expected_generation" --arg claim "$claim" '
      .status == "closing"
      and .generation == $generation
      and (.stage1_claim | type) == "object"
      and .stage1_claim.token == $claim
      and (.stage2_claim // null) == null
    ' <<< "$lease_json" >/dev/null; then
    err "complete-stage1 $env_id: lease generation, status, or claim changed"
    exit 3
  fi
  body_file="$(mktemp)"
  jq --arg updated_at "$(now_iso)" '
    .updated_at = $updated_at
    | .stage1_claim = null
  ' <<< "$lease_json" > "$body_file"
  put_lease complete-stage1 "$env_id" "$body_file" --if-match "$etag"
}

cmd_claim_stage2() {
  local env_id="${1:?env_id required}"
  shift
  local expected_generation=""
  local claim=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --generation)
        [ "$#" -ge 2 ] || { err "--generation requires a value"; exit 2; }
        expected_generation="$2"
        shift 2
        ;;
      --claim)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { err "--claim requires a nonempty token"; exit 2; }
        claim="$2"
        shift 2
        ;;
      *) err "unexpected claim-stage2 argument '$1'"; exit 2 ;;
    esac
  done
  [[ "$expected_generation" =~ ^[1-9][0-9]*$ ]] || {
    err "claim-stage2 requires --generation <positive integer>"
    exit 2
  }
  [ -n "$claim" ] || { err "claim-stage2 requires --claim <token>"; exit 2; }

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
  if jq -e '(.stage1_claim // null) != null' <<< "$lease_json" >/dev/null; then
    err "claim-stage2 $env_id: lease has an active Stage-1 claim"
    exit 3
  fi
  if ! jq -e --argjson generation "$expected_generation" '
      .status == "closing"
      and .generation == $generation
      and (.stage1_claim // null) == null
      and (.stage2_claim // null) == null
    ' <<< "$lease_json" >/dev/null; then
    err "claim-stage2 $env_id: lease is not unclaimed closing generation $expected_generation"
    exit 3
  fi
  body_file="$(mktemp)"
  jq --arg token "$claim" --arg claimed_at "$(now_iso)" '
    .updated_at = $claimed_at
    | .stage2_claim = {token: $token, claimed_at: $claimed_at}
  ' <<< "$lease_json" > "$body_file"
  put_lease claim-stage2 "$env_id" "$body_file" --if-match "$etag"
}

cmd_release_stage2() {
  local env_id="${1:?env_id required}"
  shift
  local expected_generation=""
  local claim=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --generation)
        [ "$#" -ge 2 ] || { err "--generation requires a value"; exit 2; }
        expected_generation="$2"
        shift 2
        ;;
      --claim)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { err "--claim requires a nonempty token"; exit 2; }
        claim="$2"
        shift 2
        ;;
      *) err "unexpected release-stage2 argument '$1'"; exit 2 ;;
    esac
  done
  [[ "$expected_generation" =~ ^[1-9][0-9]*$ ]] || {
    err "release-stage2 requires --generation <positive integer>"
    exit 2
  }
  [ -n "$claim" ] || { err "release-stage2 requires --claim <token>"; exit 2; }

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
  if ! jq -e --argjson generation "$expected_generation" --arg claim "$claim" '
      .status == "closing"
      and .generation == $generation
      and (.stage1_claim // null) == null
      and (.stage2_claim | type) == "object"
      and .stage2_claim.token == $claim
    ' <<< "$lease_json" >/dev/null; then
    err "release-stage2 $env_id: lease generation, status, or claim changed"
    exit 3
  fi
  body_file="$(mktemp)"
  jq --arg updated_at "$(now_iso)" '
    .updated_at = $updated_at
    | .stage2_claim = null
  ' <<< "$lease_json" > "$body_file"
  put_lease release-stage2 "$env_id" "$body_file" --if-match "$etag"
}

cmd_set_manifest() {
  local env_id="${1:?env_id required}"
  local file="${2:?manifest file required}"
  shift 2
  local expected_generation=""
  local claim=""
  local claim_set=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --generation)
        [ "$#" -ge 2 ] || { err "--generation requires a value"; exit 2; }
        expected_generation="$2"
        shift 2
        ;;
      --claim)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { err "--claim requires a nonempty token"; exit 2; }
        claim="$2"
        claim_set=true
        shift 2
        ;;
      *) err "unexpected set-manifest argument '$1'"; exit 2 ;;
    esac
  done
  [[ "$expected_generation" =~ ^[1-9][0-9]*$ ]] || {
    err "set-manifest requires --generation <positive integer>"
    exit 2
  }
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
  local lease_json etag body_file has_stage1_claim has_stage2_claim status
  lease_json="$(cat "$LEASE_BODY_FILE")"
  etag="$LEASE_ETAG"
  rm -f "$LEASE_BODY_FILE"
  if ! jq -e --argjson generation "$expected_generation" '.generation == $generation' \
      <<< "$lease_json" >/dev/null; then
    err "set-manifest $env_id: lease generation changed"
    exit 3
  fi
  status="$(jq -r '.status // empty' <<< "$lease_json")"
  has_stage1_claim="$(jq -r 'if (.stage1_claim // null) == null then "false" else "true" end' <<< "$lease_json")"
  has_stage2_claim="$(jq -r 'if (.stage2_claim // null) == null then "false" else "true" end' <<< "$lease_json")"
  if [ "$has_stage1_claim" = true ] && [ "$has_stage2_claim" = true ]; then
    err "set-manifest $env_id: lease has multiple active claims"
    exit 3
  elif [ "$has_stage1_claim" = true ]; then
    if [ "$status" != closing ] || [ "$claim_set" != true ] || ! jq -e --arg claim "$claim" '
        (.stage1_claim | type) == "object"
        and .stage1_claim.token == $claim
      ' <<< "$lease_json" >/dev/null; then
      err "set-manifest $env_id: active Stage-1 claim does not match closing lease"
      exit 3
    fi
  elif [ "$has_stage2_claim" = true ]; then
    if [ "$status" != closing ] || [ "$claim_set" != true ] || ! jq -e --arg claim "$claim" '
        (.stage2_claim | type) == "object"
        and .stage2_claim.token == $claim
      ' <<< "$lease_json" >/dev/null; then
      err "set-manifest $env_id: active Stage-2 claim does not match closing lease"
      exit 3
    fi
  elif [ "$claim_set" = true ]; then
    err "set-manifest $env_id: no active claim matches"
    exit 3
  fi
  body_file="$(mktemp)"
  jq \
    --arg updated_at "$(now_iso)" \
    --argjson manifest "$(cat "$file")" '
      .updated_at = $updated_at
      | .manifest = $manifest' <<< "$lease_json" > "$body_file"
  put_lease set-manifest "$env_id" "$body_file" --if-match "$etag"
}

cmd_complete_stage2() {
  local env_id="${1:?env_id required}"
  shift
  local expected_generation=""
  local claim=""
  local proof_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --generation)
        [ "$#" -ge 2 ] || { err "--generation requires a value"; exit 2; }
        expected_generation="$2"
        shift 2
        ;;
      --claim)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { err "--claim requires a nonempty token"; exit 2; }
        claim="$2"
        shift 2
        ;;
      --proof)
        [ "$#" -ge 2 ] || { err "--proof requires a file"; exit 2; }
        proof_file="$2"
        shift 2
        ;;
      *) err "unexpected complete-stage2 argument '$1'"; exit 2 ;;
    esac
  done
  [[ "$expected_generation" =~ ^[1-9][0-9]*$ ]] || {
    err "complete-stage2 requires --generation <positive integer>"
    exit 2
  }
  [ -n "$claim" ] || { err "complete-stage2 requires --claim <token>"; exit 2; }
  [ -n "$proof_file" ] || { err "complete-stage2 requires --proof <file>"; exit 2; }
  if ! jq -e --arg env_id "$env_id" '
      type == "object"
      and (.target == "aws" or .target == "localstack")
      and (.in_job | type) == "boolean"
      and .state_key == ("envs/preview/" + $env_id + ".tfstate")
      and (.deleted_task_definition_arns | type) == "array"
      and all(.deleted_task_definition_arns[];
        type == "string" and length > 0)
      and (.verified_empty_at | type) == "string"
      and (.verified_empty_at | length) > 0
    ' "$proof_file" >/dev/null 2>&1; then
    err "$proof_file is not a valid Stage-2 proof"
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
  if ! jq -e --argjson generation "$expected_generation" --arg claim "$claim" '
      .status == "closing"
      and .generation == $generation
      and (.manifest | type) == "object"
      and (.stage1_claim // null) == null
      and (.stage2_claim | type) == "object"
      and .stage2_claim.token == $claim
    ' <<< "$lease_json" >/dev/null; then
    err "complete-stage2 $env_id: lease generation, status, or claim changed"
    exit 3
  fi
  body_file="$(mktemp)"
  jq --arg updated_at "$(now_iso)" --argjson proof "$(cat "$proof_file")" '
    .status = "closed"
    | .updated_at = $updated_at
    | .error = null
    | .manual_intervention_required = false
    | .next_retry_at = null
    | .stage1_claim = null
    | .stage2_claim = null
    | .manifest.stage2_runs = ((.manifest.stage2_runs // []) + [$proof])
  ' <<< "$lease_json" > "$body_file"
  put_lease complete-stage2 "$env_id" "$body_file" --if-match "$etag"
}

cmd_delete_closed() {
  local env_id="${1:?env_id required}"
  local expected_etag="${2:?expected ETag required}"
  [ "$#" -eq 2 ] || { err "delete-closed requires env_id and expected ETag"; exit 2; }

  read_lease "$env_id"
  if [ "$LEASE_FOUND" != 1 ]; then
    rm -f "$LEASE_BODY_FILE"
    err "delete-closed $env_id: lease no longer exists"
    exit 3
  fi
  local status
  status="$(jq -r '.status // empty' "$LEASE_BODY_FILE")"
  rm -f "$LEASE_BODY_FILE"
  if [ "$status" != closed ]; then
    err "delete-closed $env_id: current status is '$status', expected 'closed'"
    exit 3
  fi
  if [ "$LEASE_ETAG" != "$expected_etag" ]; then
    err "delete-closed $env_id: lost the CAS race"
    exit 3
  fi

  local delete_out
  if ! delete_out="$(aws_cmd s3api delete-object \
      --bucket "$LEASE_BUCKET" --key "$(lease_key "$env_id")" \
      --if-match "$expected_etag" 2>&1)"; then
    if grep -qE 'PreconditionFailed|At least one of the pre-conditions|412' <<< "$delete_out"; then
      err "delete-closed $env_id: lost the CAS race"
      exit 3
    fi
    err "delete-object failed: $delete_out"
    exit 2
  fi

  read_lease "$env_id"
  if [ "$LEASE_FOUND" = 1 ]; then
    rm -f "$LEASE_BODY_FILE"
    err "delete-closed $env_id: lease is still readable after delete"
    exit 2
  fi
  rm -f "$LEASE_BODY_FILE"
  echo "deleted closed lease: $env_id"
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
    results="$(jq -c --argjson entry "$(jq --argjson age "$age" '{env_id,status,generation,opened_at,updated_at,cleanup_attempt,next_retry_at,manual_intervention_required,age_seconds:$age}' <<< "$lease")" '. + [$entry]' <<< "$results")"
  done <<< "$keys"
  jq -c '.[]' <<< "$results"
}

main() {
  local sub="${1:-}"
  case "$sub" in
    get) shift; cmd_get "$@" ;;
    get-with-etag) shift; cmd_get_with_etag "$@" ;;
    open) shift; cmd_open "$@" ;;
    transition) shift; cmd_transition "$@" ;;
    begin-cleanup) shift; cmd_begin_cleanup "$@" ;;
    complete-stage1) shift; cmd_complete_stage1 "$@" ;;
    claim-stage2) shift; cmd_claim_stage2 "$@" ;;
    release-stage2) shift; cmd_release_stage2 "$@" ;;
    set-manifest) shift; cmd_set_manifest "$@" ;;
    complete-stage2) shift; cmd_complete_stage2 "$@" ;;
    delete-closed) shift; cmd_delete_closed "$@" ;;
    list) shift; cmd_list "$@" ;;
    --help|-h) usage ;;
    "") usage; exit 2 ;;
    *) err "unknown subcommand '$sub'"; usage; exit 2 ;;
  esac
}

main "$@"
