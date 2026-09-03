#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ordering_script="$REPO_ROOT/tests/dispatch-ordering.sh"

if [ ! -f "$ordering_script" ]; then
  echo "tests/dispatch-ordering.sh is missing; dispatch-ordering contracts cannot run" >&2
  exit 1
fi

# Extract and execute the exact jobs aggregation filter embedded in
# read_run_metadata(), so these probes cannot drift from the live test.
jobs_aggregation_filter="$(
  awk '
    index($0, "actions/runs/$run_id/jobs") { in_jobs_api = 1; next }
    in_jobs_api && !capture && index($0, "--jq \047") {
      capture = 1
      sub(/^.*--jq \047/, "")
    }
    capture {
      final = ($0 ~ /\047\)" \\$/)
      if (final) sub(/\047\)" \\$/, "")
      print
      if (final) exit
    }
  ' "$ordering_script"
)"
if [ -z "$jobs_aggregation_filter" ]; then
  echo "dispatch-ordering.sh read_run_metadata() jobs aggregation filter could not be extracted" >&2
  exit 1
fi

contract_failures=0
report_contract_failure() {
  echo "$1" >&2
  contract_failures=$((contract_failures + 1))
}

assert_jobs_filter_rejected() {
  local label="$1"
  local expected_reason="$2"
  local payload="$3"
  local result
  if ! result="$(jq -ce "$jobs_aggregation_filter" <<< "$payload" 2>&1)"; then
    report_contract_failure "jobs aggregation filter errored instead of returning a lag reason for $label: $result"
    return
  fi
  if ! jq -e --arg expected_reason "$expected_reason" \
      '.lag_reason == $expected_reason' \
      <<< "$result" >/dev/null 2>&1; then
    report_contract_failure "jobs aggregation filter did not reject $label with lag reason '$expected_reason': $result"
  fi
}

assert_jobs_filter_rejected \
  "mixed complete-plus-null non-skipped jobs" \
  "a non-skipped job has non-string completed_at" \
  '{"total_count":2,"jobs":[{"conclusion":"success","started_at":"2026-09-03T10:00:00Z","completed_at":"2026-09-03T10:01:00Z"},{"conclusion":"failure","started_at":"2026-09-03T10:02:00Z","completed_at":null}]}'
assert_jobs_filter_rejected \
  "a non-skipped job with null started_at" \
  "a non-skipped job has non-string started_at" \
  '{"total_count":2,"jobs":[{"conclusion":"success","started_at":"2026-09-03T10:00:00Z","completed_at":"2026-09-03T10:01:00Z"},{"conclusion":"failure","started_at":null,"completed_at":"2026-09-03T10:03:00Z"}]}'
assert_jobs_filter_rejected \
  "an empty non-skipped job set" \
  "non-skipped jobs array is empty" \
  '{"total_count":1,"jobs":[{"conclusion":"skipped","started_at":null,"completed_at":null}]}'
assert_jobs_filter_rejected \
  "a total_count/jobs-length mismatch" \
  "total_count does not equal jobs length" \
  '{"total_count":2,"jobs":[{"conclusion":"success","started_at":"2026-09-03T10:00:00Z","completed_at":"2026-09-03T10:01:00Z"}]}'

complete_jobs_result="$(jq -ce "$jobs_aggregation_filter" <<'JSON'
{"total_count":3,"jobs":[{"conclusion":"success","started_at":"2026-09-03T10:00:00Z","completed_at":"2026-09-03T10:02:00Z"},{"conclusion":"failure","started_at":"2026-09-03T10:03:00Z","completed_at":"2026-09-03T10:04:00Z"},{"conclusion":"skipped","started_at":null,"completed_at":null}]}
JSON
)" || {
  echo "jobs aggregation filter errored for a fully complete payload" >&2
  exit 1
}
if ! jq -e \
    '.jobs_started_at == "2026-09-03T10:00:00Z"
     and .jobs_completed_at == "2026-09-03T10:04:00Z"
     and (.lag_reason? == null)' \
    <<< "$complete_jobs_result" >/dev/null 2>&1; then
  report_contract_failure "jobs aggregation filter rejected or misaggregated a fully complete payload: $complete_jobs_result"
fi

ordering_joined="$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$ordering_script")"
for fn in assert_terminal_before_start verify_aws_final_cleanup; do
  comparison_fn_body="$(sed -n "/^${fn}() {/,/^}/p" <<< "$ordering_joined")"
  comparison_filter="$(
    sed -n "s/^.*[[:space:]]'\([^']*\)'[[:space:]]*>\/dev\/null.*$/\1/p" \
      <<< "$comparison_fn_body"
  )"
  if [ -z "$comparison_filter" ]; then
    echo "dispatch-ordering.sh ${fn}() comparison filter could not be extracted" >&2
    exit 1
  fi
  identical_timestamp="2026-09-03T10:00:00Z"
  if jq -en --arg terminal "$identical_timestamp" --arg started "$identical_timestamp" \
      "$comparison_filter" >/dev/null; then
    report_contract_failure "dispatch-ordering.sh ${fn}() must reject identical terminal and start timestamps as inconclusive"
  fi
  if ! jq -en \
      --arg terminal "2026-09-03T10:00:00Z" \
      --arg started "2026-09-03T10:00:01Z" \
      "$comparison_filter" >/dev/null; then
    report_contract_failure "dispatch-ordering.sh ${fn}() must accept a strictly earlier terminal timestamp"
  fi
done

if [ "$contract_failures" -ne 0 ]; then
  echo "dispatch-ordering.sh contract probes failed: $contract_failures" >&2
  exit 1
fi

echo "PASS: dispatch ordering shell contracts"
