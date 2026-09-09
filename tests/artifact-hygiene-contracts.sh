#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/artifact-hygiene.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/artifact-hygiene"
CLEAN="$FIXTURES/clean.md"
FORBID_FILE="$FIXTURES/forbid-list.txt"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbit-artifact-hygiene.XXXXXX")"
results="$tmp_dir/results.txt"
failures=0
trap 'rm -rf "$tmp_dir"' EXIT

pass_case() {
  printf 'PASS: %s\n' "$1" | tee -a "$results"
}

fail_case() {
  printf 'FAIL: %s%s\n' "$1" "${2:+ -> $2}" | tee -a "$results" >&2
  failures=$((failures + 1))
}

# run_one <script> <expected: pass|fail> <check-label-or-empty> <args...>
# Prints a one-line verdict to stdout: "ok" or "bad: <detail>".
run_one() {
  local script=$1 expectation=$2 check_label=$3
  shift 3
  local output rc
  set +e
  output="$(bash "$script" "$@" 2>&1)"
  rc=$?
  set -e
  if [ "$expectation" = "pass" ]; then
    if [ "$rc" -eq 0 ] && grep -q '^PASS:' <<< "$output"; then
      echo "ok"
    else
      echo "bad: expected PASS, got rc=$rc output=$output"
    fi
  else
    local fail_line
    fail_line="$(grep -m1 '^FAIL:' <<< "$output" || true)"
    # Match the check-name field specifically (": <label> -"), never a
    # substring anywhere in the line -- fixture file names like
    # bad-iam-arn.md or bad-account-id.md would otherwise spuriously
    # satisfy an unrelated label via a plain substring grep.
    if [ "$rc" -ne 0 ] && [ -n "$fail_line" ] && grep -Fq ": ${check_label} -" <<< "$fail_line"; then
      echo "ok"
    else
      echo "bad: expected FAIL citing '$check_label', got rc=$rc output=$output"
    fi
  fi
}

# check_suite <script> — runs the full fixture matrix against <script>.
# Returns 0 if every assertion holds, 1 if any assertion fails, and
# prints one verdict line per assertion to the caller-supplied fd 3.
check_suite() {
  local script=$1
  local suite_ok=0
  local verdict

  verdict="$(run_one "$script" pass "" "$CLEAN")"
  echo "clean fixture: $verdict" >&3
  [ "$verdict" = "ok" ] || suite_ok=1

  verdict="$(run_one "$script" fail "account-id" "$FIXTURES/bad-account-id.md")"
  echo "account-id fixture: $verdict" >&3
  [ "$verdict" = "ok" ] || suite_ok=1

  verdict="$(run_one "$script" fail "iam-arn" "$FIXTURES/bad-iam-arn.md")"
  echo "iam-arn fixture: $verdict" >&3
  [ "$verdict" = "ok" ] || suite_ok=1

  verdict="$(run_one "$script" fail "principal-id" "$FIXTURES/bad-principal-id.md")"
  echo "principal-id fixture: $verdict" >&3
  [ "$verdict" = "ok" ] || suite_ok=1

  verdict="$(run_one "$script" fail "request-id" "$FIXTURES/bad-request-id.md")"
  echo "request-id fixture: $verdict" >&3
  [ "$verdict" = "ok" ] || suite_ok=1

  verdict="$(run_one "$script" fail "principal-id" "$FIXTURES/bad-assumed-role.md")"
  echo "assumed-role fixture: $verdict" >&3
  [ "$verdict" = "ok" ] || suite_ok=1

  verdict="$(run_one "$script" fail "request-id" "$FIXTURES/bad-bare-uuid.md")"
  echo "bare-uuid fixture: $verdict" >&3
  [ "$verdict" = "ok" ] || suite_ok=1

  verdict="$(run_one "$script" pass "" "$FIXTURES/bad-forbidden-term.md")"
  echo "forbidden-term fixture without --forbid-file: $verdict" >&3
  [ "$verdict" = "ok" ] || suite_ok=1

  verdict="$(run_one "$script" fail "forbid-list" --forbid-file "$FORBID_FILE" "$FIXTURES/bad-forbidden-term.md")"
  echo "forbidden-term fixture with --forbid-file: $verdict" >&3
  [ "$verdict" = "ok" ] || suite_ok=1

  return "$suite_ok"
}

# --- baseline: the real script must satisfy every assertion ---
if check_suite "$SCRIPT" 3>&1; then
  pass_case "baseline: real script satisfies the full fixture matrix"
else
  fail_case "baseline: real script failed the fixture matrix"
fi

# --- mutation proofs: neuter one check at a time in a scratch copy;
# the fixture matrix must then FAIL (proving the check is necessary);
# the untouched real script must still PASS the matrix afterward. ---
run_mutation_proof() {
  local label=$1 pattern=$2 replacement=$3
  local mutant="$tmp_dir/artifact-hygiene.$label.mutant.sh"
  sed "s/${pattern}/${replacement}/" "$SCRIPT" > "$mutant"
  chmod +x "$mutant"

  if check_suite "$mutant" 3>/dev/null; then
    fail_case "$label mutation did not break the fixture matrix (check not proven necessary)"
  else
    pass_case "$label neutered -> fixture matrix correctly FAILs"
  fi

  if check_suite "$SCRIPT" 3>/dev/null; then
    pass_case "$label restored -> fixture matrix correctly PASSes"
  else
    fail_case "$label restored real script unexpectedly failed the fixture matrix"
  fi
}

run_mutation_proof \
  "account-id" \
  "if account_id != PLACEHOLDER_ACCOUNT:  # account-id-guard" \
  "if False:  # account-id-guard"

run_mutation_proof \
  "iam-arn" \
  "if account_id != PLACEHOLDER_ACCOUNT:  # iam-arn-guard" \
  "if False:  # iam-arn-guard"

run_mutation_proof \
  "principal-id" \
  "if PRINCIPAL_ID.search(content):" \
  "if False:"

run_mutation_proof \
  "request-id" \
  "if REQUEST_ID_KEY.search(content):" \
  "if False:"

run_mutation_proof \
  "forbid-list" \
  "if term in content:" \
  "if False:"

run_mutation_proof \
  "assumed-role" \
  "if ASSUMED_ROLE.search(content):" \
  "if False:"

run_mutation_proof \
  "bare-uuid" \
  "if BARE_UUID.search(sanitized):" \
  "if False:"

# sha256 exemption: without stripping 64-hex tokens first, the clean
# fixture's legitimate hash lines start tripping the account-id and
# request-id (UUID) checks.
run_mutation_proof \
  "sha256-exemption" \
  "sanitized = HEX64.sub(\"\", content)" \
  "sanitized = content"

echo "---"
if [ "$failures" -eq 0 ]; then
  echo "artifact-hygiene-contracts: ALL PASS"
  exit 0
else
  echo "artifact-hygiene-contracts: $failures FAILURE(S)" >&2
  exit 1
fi
