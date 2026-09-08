#!/usr/bin/env bash
# Generation-bound Stage-1 recovery and bounded Stage-2 sweeping for recordings.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LEASE_SH="${LEASE_SH:-$SCRIPT_DIR/lease.sh}"
CLOSE_ENV_SH="${CLOSE_ENV_SH:-$SCRIPT_DIR/close-env.sh}"
SWEEP_SH="${SWEEP_SH:-$SCRIPT_DIR/sweep.sh}"
MAX_SWEEP_PASSES=20
SWEEP_SLEEP_SECONDS="${SWEEP_LOOP_SLEEP_SECONDS:-3}"

usage() {
  echo 'Usage: lease-sweep-until-closed.sh <env_id> --owner <token> --generation <N>' >&2
}

refuse_manual() {
  echo "lease-sweep-until-closed.sh: $1; follow RUNBOOKS.md#manual-lease-recovery" >&2
  return 3
}

env_id=${1:-}
[ -n "$env_id" ] || { usage; exit 2; }
shift
owner=
generation=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --owner)
      [ "$#" -ge 2 ] && [ -n "$2" ] || { usage; exit 2; }
      owner=$2
      shift 2
      ;;
    --generation)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      generation=$2
      shift 2
      ;;
    *) usage; exit 2 ;;
  esac
done
[ -n "$owner" ] || { usage; exit 2; }
[[ "$generation" =~ ^[1-9][0-9]*$ ]] || { usage; exit 2; }

read_owned_lease() {
  local lease
  lease="$($LEASE_SH get "$env_id")" || return $?
  if ! jq -e --arg owner "$owner" --argjson generation "$generation" '
      type == "object"
      and .owner == $owner
      and .generation == $generation
      and (.status | type == "string")
    ' <<< "$lease" >/dev/null 2>&1; then
    echo "lease-sweep-until-closed.sh: lease belongs to another run" >&2
    return 3
  fi
  printf '%s\n' "$lease"
}

require_recoverable() {
  local lease=$1
  local status manual
  status="$(jq -r '.status' <<< "$lease")"
  manual="$(jq -r '.manual_intervention_required // false' <<< "$lease")"
  case "$status" in
    open|closed) ;;
    closing)
      if [ "$manual" = true ]; then
        refuse_manual "manual intervention is required for $env_id"
        return $?
      fi
      if jq -e '(.stage1_claim // null) != null' <<< "$lease" >/dev/null; then
        refuse_manual "$env_id has an active Stage-1 claim"
        return $?
      fi
      if jq -e '(.stage2_claim // null) != null' <<< "$lease" >/dev/null; then
        refuse_manual "$env_id has an active Stage-2 claim"
        return $?
      fi
      ;;
    cleanup_failed)
      refuse_manual "$env_id is cleanup_failed"
      return $?
      ;;
    *)
      refuse_manual "$env_id has unsupported status '$status'"
      return $?
      ;;
  esac
}

lease="$(read_owned_lease)" || exit $?
require_recoverable "$lease" || exit $?
status="$(jq -r '.status' <<< "$lease")"
if [ "$status" = closed ]; then
  echo 'final_status=closed'
  exit 0
fi

if [ "$status" = open ]; then
  lease="$(read_owned_lease)" || exit $?
  require_recoverable "$lease" || exit $?
  status="$(jq -r '.status' <<< "$lease")"
  [ "$status" = open ] || {
    echo "lease-sweep-until-closed.sh: lease belongs to another run" >&2
    exit 3
  }
  "$CLOSE_ENV_SH" "$env_id" --owner "$owner" \
    --generation "$generation" --from open
fi

last_status=closing
for ((attempt = 1; attempt <= MAX_SWEEP_PASSES; attempt++)); do
  lease="$(read_owned_lease)" || exit $?
  require_recoverable "$lease" || exit $?
  last_status="$(jq -r '.status' <<< "$lease")"
  if [ "$last_status" = closed ]; then
    echo 'final_status=closed'
    exit 0
  fi
  if [ "$last_status" != closing ]; then
    refuse_manual "$env_id changed to '$last_status' before sweep pass $attempt"
    exit $?
  fi

  SWEEP_IN_JOB=true "$SWEEP_SH" env "$env_id" \
    --expect-owner "$owner" --expect-generation "$generation"

  lease="$(read_owned_lease)" || exit $?
  require_recoverable "$lease" || exit $?
  last_status="$(jq -r '.status' <<< "$lease")"
  if [ "$last_status" = closed ]; then
    echo 'final_status=closed'
    exit 0
  fi
  if [ "$attempt" -lt "$MAX_SWEEP_PASSES" ]; then
    sleep "$SWEEP_SLEEP_SECONDS"
  fi
done

echo "final_status=$last_status"
echo "lease-sweep-until-closed.sh: $env_id did not close after $MAX_SWEEP_PASSES sweep passes" >&2
exit 1
