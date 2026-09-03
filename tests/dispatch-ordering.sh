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
RUN_NONCE="${DISPATCH_NONCE:-ord-$(date +%s)-$$-$RANDOM}"
first_dispatch_note="${RUN_NONCE}-a1"
second_dispatch_note="${RUN_NONCE}-a2"
destroy_dispatch_note="${RUN_NONCE}-d1"
cleanup_dispatch_note="${RUN_NONCE}-cleanup"
for dispatch_note in \
  "$first_dispatch_note" "$second_dispatch_note" \
  "$destroy_dispatch_note" "$cleanup_dispatch_note"; do
  [[ "$dispatch_note" =~ ^[a-z0-9-]{1,40}$ ]] \
    || usage_fail "generated dispatch_note must match ^[a-z0-9-]{1,40}$"
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
aws_final_cleanup_checked=false
recovery_cleanup_dispatched=false

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
     [ "$aws_final_cleanup_checked" != true ] && \
     [ "$recovery_cleanup_dispatched" != true ]; then
    recovery_cleanup_dispatched=true
    echo "dispatch-ordering.sh: dispatching AWS cleanup after an incomplete test" >&2
    gh workflow run session-destroy.yml --repo "$REPO" --ref "$REF" \
      -f env_id="$ENV_ID" -f target=aws -f dispatch_note="$cleanup_dispatch_note" \
      >/dev/null 2>&1 \
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
  local dispatch_note="$3"
  shift 3
  local before after before_ids new_runs count deadline
  before="$(gh run list --repo "$REPO" --workflow "$workflow" --branch "$REF" \
    --event workflow_dispatch --limit 100 \
    --json databaseId,status,conclusion,createdAt,displayTitle,event,headBranch)" \
    || fail "could not snapshot $workflow before $label"
  before_ids="$(jq -c '[.[].databaseId]' <<< "$before")"

  if [ "$workflow" = session-apply.yml ]; then
    apply_dispatch_attempted=true
  fi
  gh workflow run "$workflow" --repo "$REPO" --ref "$REF" \
    -f dispatch_note="$dispatch_note" "$@" \
    || fail "could not dispatch $label"

  deadline=$(( $(date +%s) + 120 ))
  while [ "$(date +%s)" -le "$deadline" ]; do
    after="$(gh run list --repo "$REPO" --workflow "$workflow" --branch "$REF" \
      --event workflow_dispatch --limit 100 \
      --json databaseId,status,conclusion,createdAt,displayTitle,event,headBranch)" \
      || fail "could not find the run created for $label"
    new_runs="$(jq -c \
      --arg dispatch_note "$dispatch_note" \
      --arg ref "$REF" \
      --argjson before_ids "$before_ids" '
        [.[]
          | select(.databaseId as $id | ($before_ids | index($id) | not))
          | select((.displayTitle // "") | contains($dispatch_note))
          | select(.event == "workflow_dispatch" and .headBranch == $ref)
        ]
      ' <<< "$after")"
    count="$(jq 'length' <<< "$new_runs")"
    if [ "$count" -eq 1 ]; then
      CAPTURED_RUN_ID="$(jq -r '.[0].databaseId' <<< "$new_runs")"
      echo "dispatch-ordering.sh: $label run_id=$CAPTURED_RUN_ID"
      return
    fi
    if [ "$count" -gt 1 ]; then
      fail "$label matched multiple new workflow_dispatch runs for note '$dispatch_note' on REF=$REF: $(jq -c 'map(.databaseId)' <<< "$new_runs")"
    fi
    sleep 2
  done
  fail "no new $workflow workflow_dispatch run matched note '$dispatch_note' and head_branch '$REF' within 120 seconds for $label"
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
    # GitHub reports a run held by the concurrency group as `pending`
    # (observed live 2026-09-03); `queued` is the runner-assignment state.
    # Either proves the run has not started; `in_progress`/`completed` fail.
    case "$second_status" in
      pending|queued) ;;
      *) fail "queue poll $poll: second apply is '$second_status', expected pending or queued" ;;
    esac
    echo "dispatch-ordering.sh: queue poll $poll/$QUEUE_POLLS first=in_progress second=$second_status"
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
      pending|queued)
        echo "dispatch-ordering.sh: $label is held ($status)"
        return
        ;;
      requested|waiting|"") ;;
      *) fail "$label is '$status', expected pending or queued" ;;
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

read_run_metadata() {
  local run_id="$1"
  local label="$2"
  local output_file="$3"
  gh api "repos/$REPO/actions/runs/$run_id" \
    --jq '{id:.id,workflow:.name,event:.event,head_branch:.head_branch,display_title:.display_title,conclusion:.conclusion,run_started_at:.run_started_at,updated_at:.updated_at}' \
    > "$output_file" \
    || fail "could not read run metadata for $label run $run_id"
  jq -e --argjson run_id "$run_id" \
    '.id == $run_id
     and .event == "workflow_dispatch"
     and (.head_branch | type == "string")
     and (.display_title | type == "string")
     and (.conclusion | type == "string")
     and (.run_started_at | type == "string")
     and (.updated_at | type == "string")' \
    "$output_file" >/dev/null \
    || fail "$label run $run_id returned incomplete terminal metadata"
}

assert_terminal_before_start() {
  local earlier_file="$1"
  local later_file="$2"
  local label="$3"
  local terminal_at started_at
  terminal_at="$(jq -r '.updated_at' "$earlier_file")"
  started_at="$(jq -r '.run_started_at' "$later_file")"
  jq -en --arg terminal "$terminal_at" --arg started "$started_at" \
    '$terminal <= $started' >/dev/null \
    || fail "$label violated: terminal=$terminal_at later_start=$started_at"
}

assert_conclusion() {
  local run_file="$1"
  local expected="$2"
  local label="$3"
  local actual
  actual="$(jq -r '.conclusion' "$run_file")"
  [ "$actual" = "$expected" ] \
    || fail "$label conclusion was '$actual', expected '$expected'"
}

verify_aws_final_cleanup() {
  local second_file="$1"
  local destroy_file="$2"
  local second_terminal destroy_started destroy_run_id destroy_conclusion
  local lease_json lease_rc lease_status
  second_terminal="$(jq -r '.updated_at' "$second_file")"
  destroy_started="$(jq -r '.run_started_at' "$destroy_file")"
  destroy_run_id="$(jq -r '.id' "$destroy_file")"
  destroy_conclusion="$(jq -r '.conclusion' "$destroy_file")"

  lease_status=unreadable
  set +e
  lease_json="$(env TARGET=aws "$REPO_ROOT/scripts/lease.sh" get "$ENV_ID" 2>/dev/null)"
  lease_rc=$?
  set -e
  if [ "$lease_rc" -eq 0 ]; then
    if ! lease_status="$(jq -er '.status | select(type == "string" and length > 0)' \
        <<< "$lease_json" 2>/dev/null)"; then
      lease_status=unreadable
    fi
  fi

  if ! jq -en --arg terminal "$second_terminal" --arg started "$destroy_started" \
      '$terminal <= $started' >/dev/null; then
    fail "AWS final cleanup unsafe for destroy run $destroy_run_id with lease status '$lease_status': second apply terminal=$second_terminal is after destroy start=$destroy_started"
  fi
  if [ "$lease_rc" -ne 0 ]; then
    fail "AWS final cleanup unsafe for destroy run $destroy_run_id with lease status '$lease_status': scripts/lease.sh get failed with rc=$lease_rc"
  fi
  if [ "$destroy_conclusion" != success ]; then
    fail "AWS final cleanup unsafe for destroy run $destroy_run_id with lease status '$lease_status': conclusion was '$destroy_conclusion', expected 'success'"
  fi

  case "$lease_status" in
    closing|closed) aws_final_cleanup_checked=true ;;
    *)
      fail "AWS final cleanup unsafe for destroy run $destroy_run_id with lease status '$lease_status': expected closing or closed after a successful destroy"
      ;;
  esac
}

print_ordered_runs() {
  jq -sr 'sort_by(.run_started_at) | to_entries[] |
    "order=\(.key + 1) run_id=\(.value.id) workflow=\(.value.workflow) conclusion=\(.value.conclusion) run_started_at=\(.value.run_started_at) updated_at=\(.value.updated_at)"' \
    "$tmp_dir/first-apply.json" "$tmp_dir/second-apply.json" "$tmp_dir/destroy.json"
}

dispatch_and_capture session-apply.yml "first apply" "$first_dispatch_note" \
  -f env_id="$ENV_ID" -f target="$TARGET" -f mode=public
first_apply_id="$CAPTURED_RUN_ID"
run_ids+=("$first_apply_id")
wait_for_first_apply "$first_apply_id"

dispatch_and_capture session-apply.yml "second apply" "$second_dispatch_note" \
  -f env_id="$ENV_ID" -f target="$TARGET" -f mode=public
second_apply_id="$CAPTURED_RUN_ID"
run_ids+=("$second_apply_id")
assert_three_queued_polls "$first_apply_id" "$second_apply_id"

dispatch_and_capture session-destroy.yml "destroy" "$destroy_dispatch_note" \
  -f env_id="$ENV_ID" -f target="$TARGET"
destroy_id="$CAPTURED_RUN_ID"
run_ids+=("$destroy_id")
assert_run_queued session-destroy.yml "$destroy_id" "destroy"

wait_for_all_terminal
read_run_metadata "$first_apply_id" "first apply" "$tmp_dir/first-apply.json"
read_run_metadata "$second_apply_id" "second apply" "$tmp_dir/second-apply.json"
read_run_metadata "$destroy_id" "destroy" "$tmp_dir/destroy.json"

if [ "$TARGET" = aws ]; then
  verify_aws_final_cleanup "$tmp_dir/second-apply.json" "$tmp_dir/destroy.json"
fi

assert_terminal_before_start \
  "$tmp_dir/first-apply.json" "$tmp_dir/second-apply.json" \
  "first apply terminal <= second apply start"
assert_terminal_before_start \
  "$tmp_dir/second-apply.json" "$tmp_dir/destroy.json" \
  "second apply terminal <= destroy start"

case "$TARGET" in
  localstack)
    assert_conclusion "$tmp_dir/first-apply.json" success "first LocalStack apply"
    assert_conclusion "$tmp_dir/second-apply.json" success "second LocalStack apply"
    assert_conclusion "$tmp_dir/destroy.json" failure "LocalStack destroy refusal"
    assert_localstack_destroy_refusal "$destroy_id"
    ;;
  aws)
    # ADR 0006: a successful AWS apply leaves its lease `open`, so the queued
    # second apply must be refused at lease open (no lease mutation, no
    # resources); only the destroy that follows closes generation 1.
    assert_conclusion "$tmp_dir/first-apply.json" success "first AWS apply"
    assert_conclusion "$tmp_dir/second-apply.json" failure "second AWS apply (open-lease refusal)"
    assert_conclusion "$tmp_dir/destroy.json" success "AWS destroy"
    ;;
esac

print_ordered_runs
echo "PASS: dispatch ordering target=$TARGET env_id=$ENV_ID nonce=$RUN_NONCE queued_polls=$QUEUE_POLLS runs=3"
