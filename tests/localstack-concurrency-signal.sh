#!/usr/bin/env bash
# Exercise the LocalStack concurrency trap without contacting LocalStack.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ "$PWD" = "$REPO_ROOT" ] || {
  echo "localstack-concurrency-signal.sh: run from the repository root: $REPO_ROOT" >&2
  exit 2
}

tmp_dir="$(mktemp -d)"
runner_pid=""
worker_pid=""
descendant_pid=""

cleanup() {
  local pid
  set +e
  for pid in "$runner_pid" "$worker_pid" "$descendant_pid"; do
    if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
    fi
  done
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

CONCURRENCY_SIGNAL_TEST=1 \
CONCURRENCY_SIGNAL_WORKER_PID_FILE="$tmp_dir/worker.pid" \
CONCURRENCY_SIGNAL_DESCENDANT_PID_FILE="$tmp_dir/descendant.pid" \
  bash tests/localstack-concurrency.sh >"$tmp_dir/stdout" 2>"$tmp_dir/stderr" &
runner_pid=$!

deadline=$((SECONDS + 10))
while [ "$SECONDS" -le "$deadline" ]; do
  if [ -s "$tmp_dir/worker.pid" ] && [ -s "$tmp_dir/descendant.pid" ]; then
    break
  fi
  if ! kill -0 "$runner_pid" 2>/dev/null; then
    wait "$runner_pid" 2>/dev/null || true
    echo "FAIL: signal-mode concurrency runner exited before its fake pipeline started" >&2
    sed -n '1,120p' "$tmp_dir/stderr" >&2
    exit 1
  fi
  sleep 1
done
[ -s "$tmp_dir/worker.pid" ] && [ -s "$tmp_dir/descendant.pid" ] || {
  echo "FAIL: signal-mode concurrency runner did not publish worker pids" >&2
  sed -n '1,120p' "$tmp_dir/stderr" >&2
  exit 1
}
worker_pid="$(cat "$tmp_dir/worker.pid")"
descendant_pid="$(cat "$tmp_dir/descendant.pid")"
[[ "$worker_pid" =~ ^[1-9][0-9]*$ && "$descendant_pid" =~ ^[1-9][0-9]*$ ]] || {
  echo "FAIL: signal-mode concurrency runner published invalid worker pids" >&2
  exit 1
}

deadline=$((SECONDS + 10))
while [ "$SECONDS" -le "$deadline" ] && kill -0 "$worker_pid" 2>/dev/null; do
  sleep 1
done
if kill -0 "$worker_pid" 2>/dev/null; then
  echo "FAIL: fake worker group leader $worker_pid did not exit before the trap test" >&2
  exit 1
fi
if ! kill -0 "$descendant_pid" 2>/dev/null; then
  echo "FAIL: fake worker descendant $descendant_pid exited with its group leader" >&2
  exit 1
fi

kill -TERM "$runner_pid"
set +e
wait "$runner_pid"
runner_rc=$?
set -e
[ "$runner_rc" -eq 143 ] || {
  echo "FAIL: SIGTERM concurrency runner exited $runner_rc instead of 143" >&2
  sed -n '1,120p' "$tmp_dir/stderr" >&2
  exit 1
}

sleep 1
for process_record in "worker|$worker_pid" "descendant|$descendant_pid"; do
  label="${process_record%%|*}"
  pid="${process_record#*|}"
  if kill -0 "$pid" 2>/dev/null; then
    state="$(ps -o stat= -p "$pid" 2>/dev/null | awk '{print $1}')"
    if [[ "$state" != Z* ]]; then
      echo "FAIL: $label process $pid survived the concurrency trap with state $state" >&2
      exit 1
    fi
  fi
done

echo "PASS: LocalStack concurrency SIGTERM trap terminates the group after its leader exits"
