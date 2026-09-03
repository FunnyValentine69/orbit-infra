#!/usr/bin/env bash
# Exercise GitHub's same-environment workflow concurrency queue.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_ID="${ENV_ID:-ord1}"
TARGET="${TARGET:-localstack}"
REPO="${REPO:-}"
REF="${REF:-main}"
CANCEL_ON_EXIT="${CANCEL_ON_EXIT:-0}"
START_TIMEOUT_SECONDS=600
TERMINAL_TIMEOUT_SECONDS="${TERMINAL_TIMEOUT_SECONDS:-12600}"
QUEUE_POLL_SECONDS=20
QUEUE_POLLS=3
DESTROY_REFUSAL='session-destroy refuses target=localstack: LocalStack state is runner-local, so session-apply performs apply -> acceptance -> close in one job'

fail() {
  echo "dispatch-ordering.sh: $*" >&2
  exit 1
}

usage_fail() {
  echo "dispatch-ordering.sh: $*" >&2
  exit 2
}

[[ "$ENV_ID" =~ ^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$ ]] \
  || usage_fail "ENV_ID must match ^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$"
case "$TARGET" in
  aws|localstack) ;;
  *) usage_fail "TARGET must be aws or localstack" ;;
esac
case "$CANCEL_ON_EXIT" in
  0|1) ;;
  *) usage_fail "CANCEL_ON_EXIT must be 0 or 1" ;;
esac
[ "$PWD" = "$REPO_ROOT" ] || usage_fail "run from the repository root: $REPO_ROOT"
for timeout_value in "$START_TIMEOUT_SECONDS" "$TERMINAL_TIMEOUT_SECONDS"; do
  [[ "$timeout_value" =~ ^[1-9][0-9]*$ ]] \
    || usage_fail "timeout values must be positive integers"
done
for command_name in gh jq; do
  command -v "$command_name" >/dev/null 2>&1 \
    || usage_fail "required command not found: $command_name"
done

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')" \
    || usage_fail "could not resolve REPO with gh repo view"
fi
[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || usage_fail "REPO must be owner/name"
gh auth status >/dev/null 2>&1 || usage_fail "gh is not authenticated"

tmp_dir="$(mktemp -d)"
run_ids=()
apply_dispatch_attempted=false
destroy_dispatched=false

run_status() {
  local workflow="$1"
  local run_id="$2"
  local runs
  runs="$(gh run list --repo "$REPO" --workflow "$workflow" --branch "$REF" \
    --event workflow_dispatch --limit 100 \
    --json databaseId,status,conclusion,createdAt)" \
    || fail "could not list $workflow runs"
  jq -r --argjson run_id "$run_id" \
    '.[] | select(.databaseId == $run_id) | .status' <<< "$runs"
}

cleanup() {
  local rc=$?
  local run_id status
  trap - EXIT
  set +e
  if [ "$TARGET" = aws ] && [ "$apply_dispatch_attempted" = true ] && \
     [ "$destroy_dispatched" != true ]; then
    echo "dispatch-ordering.sh: dispatching AWS cleanup after an incomplete test" >&2
    gh workflow run session-destroy.yml --repo "$REPO" --ref "$REF" \
      -f env_id="$ENV_ID" -f target=aws >/dev/null 2>&1 \
      || echo "dispatch-ordering.sh: could not dispatch AWS cleanup for $ENV_ID" >&2
  fi
  # bash 3.2 (macOS) treats an empty array expansion as unbound under set -u,
  # and run_ids is empty until the first dispatch succeeds.
  if [ "$CANCEL_ON_EXIT" = 1 ] && [ "${#run_ids[@]}" -gt 0 ]; then
    for run_id in "${run_ids[@]}"; do
      status="$(gh run view "$run_id" --repo "$REPO" --json status --jq '.status' 2>/dev/null)"
      case "$status" in
        completed|"") ;;
        *)
          echo "dispatch-ordering.sh: CANCEL_ON_EXIT=1; cancelling run $run_id" >&2
          gh run cancel "$run_id" --repo "$REPO" >/dev/null 2>&1
          ;;
      esac
    done
  fi
  rm -rf "$tmp_dir"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

dispatch_and_capture() {
  local workflow="$1"
  local label="$2"
  shift 2
  local before after before_ids new_runs count deadline
  before="$(gh run list --repo "$REPO" --workflow "$workflow" --branch "$REF" \
    --event workflow_dispatch --limit 100 \
    --json databaseId,status,conclusion,createdAt)" \
    || fail "could not snapshot $workflow before $label"
  before_ids="$(jq -c '[.[].databaseId]' <<< "$before")"

  if [ "$workflow" = session-apply.yml ]; then
    apply_dispatch_attempted=true
  fi
  gh workflow run "$workflow" --repo "$REPO" --ref "$REF" "$@" \
    || fail "could not dispatch $label"

  deadline=$(( $(date +%s) + 120 ))
  while [ "$(date +%s)" -le "$deadline" ]; do
    after="$(gh run list --repo "$REPO" --workflow "$workflow" --branch "$REF" \
      --event workflow_dispatch --limit 100 \
      --json databaseId,status,conclusion,createdAt)" \
      || fail "could not find the run created for $label"
    new_runs="$(jq -c --argjson before_ids "$before_ids" \
      '[.[] | select(.databaseId as $id | ($before_ids | index($id) | not))]' <<< "$after")"
    count="$(jq 'length' <<< "$new_runs")"
    if [ "$count" -eq 1 ]; then
      CAPTURED_RUN_ID="$(jq -r '.[0].databaseId' <<< "$new_runs")"
      echo "dispatch-ordering.sh: $label run_id=$CAPTURED_RUN_ID"
      return
    fi
    if [ "$count" -gt 1 ]; then
      fail "$label produced an ambiguous set of new run ids: $(jq -c 'map(.databaseId)' <<< "$new_runs")"
    fi
    sleep 2
  done
  fail "no $workflow run appeared within 120 seconds for $label"
}

wait_for_first_apply() {
  local run_id="$1"
  local deadline status conclusion
  deadline=$(( $(date +%s) + START_TIMEOUT_SECONDS ))
  while [ "$(date +%s)" -le "$deadline" ]; do
    status="$(run_status session-apply.yml "$run_id")"
    case "$status" in
      in_progress) return ;;
      queued|requested|waiting|pending|"") ;;
      completed)
        conclusion="$(gh run view "$run_id" --repo "$REPO" --json conclusion --jq '.conclusion')"
        fail "first apply reached terminal conclusion '$conclusion' before an in_progress observation; REF=$REF must resolve to main"
        ;;
      *) fail "first apply returned unexpected status '$status'" ;;
    esac
    sleep 5
  done
  fail "first apply did not become in_progress within $START_TIMEOUT_SECONDS seconds"
}

assert_three_queued_polls() {
  local first_id="$1"
  local second_id="$2"
  local poll first_status second_status
  for poll in $(seq 1 "$QUEUE_POLLS"); do
    sleep "$QUEUE_POLL_SECONDS"
    first_status="$(run_status session-apply.yml "$first_id")"
    second_status="$(run_status session-apply.yml "$second_id")"
    [ "$first_status" = in_progress ] \
      || fail "queue poll $poll: first apply is '$first_status', expected in_progress"
    [ "$second_status" = queued ] \
      || fail "queue poll $poll: second apply is '$second_status', expected queued"
    echo "dispatch-ordering.sh: queue poll $poll/$QUEUE_POLLS first=in_progress second=queued"
  done
}

assert_run_queued() {
  local workflow="$1"
  local run_id="$2"
  local label="$3"
  local deadline status
  deadline=$(( $(date +%s) + 60 ))
  while [ "$(date +%s)" -le "$deadline" ]; do
    status="$(run_status "$workflow" "$run_id")"
    case "$status" in
      queued)
        echo "dispatch-ordering.sh: $label is queued"
        return
        ;;
      requested|waiting|pending|"") ;;
      *) fail "$label is '$status', expected queued" ;;
    esac
    sleep 2
  done
  fail "$label was not observed queued within 60 seconds"
}

wait_for_all_terminal() {
  local deadline all_terminal run_id status
  deadline=$(( $(date +%s) + TERMINAL_TIMEOUT_SECONDS ))
  while [ "$(date +%s)" -le "$deadline" ]; do
    all_terminal=true
    for run_id in "${run_ids[@]}"; do
      status="$(gh run view "$run_id" --repo "$REPO" --json status --jq '.status')" \
        || fail "could not read run $run_id"
      if [ "$status" != completed ]; then
        all_terminal=false
      fi
    done
    if [ "$all_terminal" = true ]; then
      return
    fi
    sleep 20
  done
  fail "not all dispatched runs became terminal within $TERMINAL_TIMEOUT_SECONDS seconds"
}

assert_localstack_destroy_refusal() {
  local run_id="$1"
  local run_json logs
  run_json="$(gh run view "$run_id" --repo "$REPO" --json jobs,conclusion)" \
    || fail "could not inspect LocalStack destroy run $run_id"
  jq -e '.conclusion == "failure" and any(.jobs[]; .name == "validate-input" and .conclusion == "failure")' \
    <<< "$run_json" >/dev/null \
    || fail "LocalStack destroy did not fail in validate-input: $run_json"

  logs=""
  for _ in $(seq 1 10); do
    if logs="$(gh run view "$run_id" --repo "$REPO" --log-failed 2>&1)"; then
      if grep -Fq "$DESTROY_REFUSAL" <<< "$logs"; then
        return
      fi
    fi
    sleep 3
  done
  fail "LocalStack destroy logs did not contain the workflow's refusal message: $logs"
}

print_ordered_runs() {
  local run_id run_file="$tmp_dir/runs.jsonl"
  : > "$run_file"
  for run_id in "${run_ids[@]}"; do
    gh api "repos/$REPO/actions/runs/$run_id" \
      --jq '{id:.id,workflow:.name,conclusion:.conclusion,run_started_at:.run_started_at}' \
      >> "$run_file" \
      || fail "could not read run metadata for $run_id"
  done
  jq -sr 'sort_by(.run_started_at) | to_entries[] |
    "order=\(.key + 1) run_id=\(.value.id) workflow=\(.value.workflow) conclusion=\(.value.conclusion) run_started_at=\(.value.run_started_at)"' \
    "$run_file"
}

dispatch_and_capture session-apply.yml "first apply" \
  -f env_id="$ENV_ID" -f target="$TARGET" -f mode=public
first_apply_id="$CAPTURED_RUN_ID"
run_ids+=("$first_apply_id")
wait_for_first_apply "$first_apply_id"

dispatch_and_capture session-apply.yml "second apply" \
  -f env_id="$ENV_ID" -f target="$TARGET" -f mode=public
second_apply_id="$CAPTURED_RUN_ID"
run_ids+=("$second_apply_id")
assert_three_queued_polls "$first_apply_id" "$second_apply_id"

dispatch_and_capture session-destroy.yml "destroy" \
  -f env_id="$ENV_ID" -f target="$TARGET"
destroy_id="$CAPTURED_RUN_ID"
run_ids+=("$destroy_id")
destroy_dispatched=true
assert_run_queued session-destroy.yml "$destroy_id" "destroy"

wait_for_all_terminal

if [ "$TARGET" = localstack ]; then
  assert_localstack_destroy_refusal "$destroy_id"
fi

first_terminal_at="$(gh api --paginate "repos/$REPO/actions/runs/$first_apply_id/jobs?per_page=100" \
  --jq '.jobs[].completed_at | select(. != null)' | sort | tail -n 1)"
second_started_at="$(gh api "repos/$REPO/actions/runs/$second_apply_id" --jq '.run_started_at')"
[ -n "$first_terminal_at" ] || fail "first apply has no terminal job timestamp"
[ -n "$second_started_at" ] || fail "second apply has no run_started_at timestamp"
jq -en --arg second "$second_started_at" --arg terminal "$first_terminal_at" \
  '$second >= $terminal' >/dev/null \
  || fail "second apply started at $second_started_at before first apply terminated at $first_terminal_at"

print_ordered_runs
echo "PASS: dispatch ordering target=$TARGET env_id=$ENV_ID queued_polls=$QUEUE_POLLS runs=3"
