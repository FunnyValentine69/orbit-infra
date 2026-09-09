#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MATRIX="$REPO_ROOT/docs/iam-matrix.md"
GENERATOR="$REPO_ROOT/scripts/iam-simulate-categories.py"
TAXONOMY="$REPO_ROOT/tests/fixtures/iam-simulate/categories.json"
CASE_ID_LIB="$REPO_ROOT/tests/lib/iam-simulate.sh"
VALIDATOR="$REPO_ROOT/scripts/iam-simulate-validate.py"
VECTOR_FIXTURES="$REPO_ROOT/tests/fixtures/iam-simulate"
SCHEMA_DOC="$REPO_ROOT/docs/iam-simulate-vector-schema.md"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbit-iam-simulate.XXXXXX")"
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

expect_failure() {
  local label=$1
  local expected=$2
  shift 2
  local output rc fail_line
  set +e
  output="$("$@" 2>&1)"
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<< "$output" || true)"
  if [ "$rc" -ne 0 ] && [ -n "$fail_line" ] && grep -Fq "$expected" <<< "$output"; then
    pass_case "$label mutation -> $fail_line"
  else
    fail_case "$label mutation did not fail as required" "rc=$rc output=$output"
  fi
}

validate_taxonomy() {
  local taxonomy=$1
  python3 - "$MATRIX" "$taxonomy" <<'PY'
import json
from collections import Counter
from pathlib import Path
import re
import sys


CATEGORIES = (
    "simulator-decision",
    "simulator-attribution-only",
    "live-call-only",
    "not-simulatable",
)
EXPECTED_COUNTS = {
    "simulator-decision": 231,
    "simulator-attribution-only": 8,
    "live-call-only": 6,
    "not-simulatable": 43,
}
FIELDS = {"case_id", "document", "sid", "suffix", "category", "reason"}
CASE_ENTRY = re.compile(r"(case:[^ ;=)]+) => (.*?)(?=; case:|$)")
EVIDENCE_ENTRY = re.compile(r"(case:[^ ;=)]+)=(.*?)(?=; case:|$)")
NA_LABEL = re.compile(r"N/A\((.+)\)")


def fail(message):
    raise SystemExit(f"FAIL: {message}")


def matrix_cases(path):
    cases = {}
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.startswith("| `"):
            continue
        table_line = line.replace(r"; \| case:", "; case:")
        cells = re.findall(r"`([^`]*)`", table_line)
        if len(cells) != 10 or not cells[0].startswith(("aws_", "trust:")):
            continue
        document, sid = cells[0], cells[1]
        case_entries = CASE_ENTRY.findall(cells[7])
        evidence_entries = dict(EVIDENCE_ENTRY.findall(cells[9]))
        for case_id, body in case_entries:
            prefix = f"case:{document}:{sid}:"
            if not case_id.startswith(prefix):
                fail(f"matrix case does not start with its document and Sid at line {line_no}: {case_id}")
            if case_id in cases:
                fail(f"matrix repeats case id: {case_id}")
            if case_id not in evidence_entries:
                fail(f"matrix Evidence omits case id: {case_id}")
            evidence = evidence_entries[case_id]
            na_match = NA_LABEL.fullmatch(evidence)
            if document.startswith("trust:") or na_match:
                category = "not-simulatable"
            elif document == "aws_kms_key.signing":
                category = "live-call-only"
            elif "expect not denied by this statement" in body:
                category = "simulator-attribution-only"
            else:
                category = "simulator-decision"
            cases[case_id] = {
                "document": document,
                "sid": sid,
                "suffix": case_id[len(prefix):],
                "category": category,
                "na_reason": na_match.group(1) if na_match else None,
            }
    return cases


matrix = matrix_cases(Path(sys.argv[1]))
try:
    taxonomy = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    fail(f"cannot read taxonomy: {exc}")
if not isinstance(taxonomy, list):
    fail("taxonomy top level must be an array")

by_id = {}
for index, entry in enumerate(taxonomy):
    if not isinstance(entry, dict) or set(entry) != FIELDS:
        fail(f"taxonomy entry {index} must contain exactly {sorted(FIELDS)}")
    for field in FIELDS:
        if not isinstance(entry[field], str) or not entry[field]:
            fail(f"taxonomy entry {index} has an empty or non-string {field}")
    case_id = entry["case_id"]
    if entry["category"] not in CATEGORIES:
        fail(f"taxonomy has unknown category for {case_id}: {entry['category']}")
    if case_id in by_id:
        fail(f"taxonomy case appears in two categories: {case_id}")
    by_id[case_id] = entry

extra = sorted(set(by_id) - set(matrix))
missing = sorted(set(matrix) - set(by_id))
if extra:
    fail(f"taxonomy contains case absent from matrix: {extra[0]}")
if missing:
    fail(f"taxonomy omits matrix case: {missing[0]}")

for case_id, expected in matrix.items():
    entry = by_id[case_id]
    for field in ("document", "sid", "suffix", "category"):
        if entry[field] != expected[field]:
            fail(f"taxonomy {field} mismatch for {case_id}")
    if expected["na_reason"] is not None and entry["reason"] != expected["na_reason"]:
        fail(f"taxonomy does not carry the matrix N/A reason for {case_id}")

counts = Counter(entry["category"] for entry in taxonomy)
if dict(counts) != EXPECTED_COUNTS:
    fail(f"taxonomy counts differ: {dict(counts)}")
if sum(counts.values()) != 288:
    fail(f"taxonomy category sum is {sum(counts.values())}, expected 288")
PY
}

mutate_taxonomy() {
  local mutation=$1
  local destination="$tmp_dir/taxonomy-$mutation.json"
  python3 - "$TAXONOMY" "$destination" "$mutation" <<'PY'
import json
from pathlib import Path
import sys


source = Path(sys.argv[1])
destination = Path(sys.argv[2])
mutation = sys.argv[3]
entries = json.loads(source.read_text(encoding="utf-8"))
if mutation == "added":
    entries.append({
        "case_id": "case:fixture.missing:Missing:ALL:none:missing",
        "document": "fixture.missing",
        "sid": "Missing",
        "suffix": "ALL:none:missing",
        "category": "simulator-decision",
        "reason": "synthetic added-case mutation",
    })
elif mutation == "removed":
    entries.pop()
elif mutation == "duplicate":
    duplicate = dict(entries[0])
    duplicate["category"] = (
        "not-simulatable"
        if duplicate["category"] != "not-simulatable"
        else "simulator-decision"
    )
    entries.append(duplicate)
elif mutation == "empty-reason":
    entries[0]["reason"] = ""
else:
    raise SystemExit(f"unknown taxonomy mutation: {mutation}")
destination.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8", newline="\n")
PY
  printf '%s\n' "$destination"
}

echo "== iam simulate contracts: TAXONOMY =="
group_failures=$failures
if output="$(TMPDIR="$tmp_dir" python3 "$GENERATOR" --check 2>&1)"; then
  pass_case "taxonomy generator byte check"
else
  fail_case "taxonomy generator byte check" "$output"
fi

if [ -f "$TAXONOMY" ]; then
  if output="$(validate_taxonomy "$TAXONOMY" 2>&1)"; then
    pass_case "taxonomy matrix equality, disjoint categories, reasons, and counts"
  else
    fail_case "taxonomy matrix equality, disjoint categories, reasons, and counts" "$output"
  fi

  mutated="$(mutate_taxonomy added)"
  expect_failure "taxonomy added case" "contains case absent from matrix" \
    validate_taxonomy "$mutated"
  mutated="$(mutate_taxonomy removed)"
  expect_failure "taxonomy removed case" "omits matrix case" \
    validate_taxonomy "$mutated"
  mutated="$(mutate_taxonomy duplicate)"
  expect_failure "taxonomy duplicate category" "appears in two categories" \
    validate_taxonomy "$mutated"
  mutated="$(mutate_taxonomy empty-reason)"
  expect_failure "taxonomy empty reason" "empty or non-string reason" \
    validate_taxonomy "$mutated"
else
  fail_case "taxonomy fixture exists" "$TAXONOMY is missing"
fi

if [ "$failures" -eq "$group_failures" ]; then
  echo "PASS: IAM simulate TAXONOMY group"
else
  echo "FAIL: IAM simulate TAXONOMY group" >&2
fi

assert_suffix() {
  local label=$1
  local case_id=$2
  local document=$3
  local sid=$4
  local expected=$5
  local output
  if output="$(iam_simulate_case_suffix "$case_id" "$document" "$sid" 2>&1)" && \
     [ "$output" = "$expected" ]; then
    pass_case "$label"
  else
    fail_case "$label" "$output"
  fi
}

echo "== iam simulate contracts: CASE-ID =="
group_failures=$failures
if [ -f "$CASE_ID_LIB" ]; then
  # shellcheck disable=SC1090
  source "$CASE_ID_LIB"
else
  fail_case "shared case-id parser library exists" "$CASE_ID_LIB is missing"
fi

if declare -F iam_simulate_case_suffix >/dev/null; then
  round_trip_ok=1
  round_trip_count=0
  while IFS=$'\t' read -r case_id document sid suffix; do
    round_trip_count=$((round_trip_count + 1))
    if ! actual="$(iam_simulate_case_suffix "$case_id" "$document" "$sid" 2>/dev/null)" || \
       [ "$actual" != "$suffix" ]; then
      round_trip_ok=0
      break
    fi
  done < <(
    python3 - "$TAXONOMY" <<'PY'
import json
from pathlib import Path
import sys

for entry in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")):
    print(entry["case_id"], entry["document"], entry["sid"], entry["suffix"], sep="\t")
PY
  )
  if [ "$round_trip_ok" -eq 1 ] && [ "$round_trip_count" -eq 288 ]; then
    pass_case "case-id exact-prefix round trip over 288 cases"
  else
    fail_case "case-id exact-prefix round trip over 288 cases" \
      "stopped at case $round_trip_count"
  fi

  assert_suffix "case-id ALL none suffix" \
    "case:aws_iam_role_policy.plan_reader_deny:DenySecretsAndParams:ALL:none:protected-resource" \
    "aws_iam_role_policy.plan_reader_deny" "DenySecretsAndParams" \
    "ALL:none:protected-resource"
  assert_suffix "case-id ALL resource suffix" \
    "case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:resource:nonmatching" \
    "aws_iam_role_policy.plan_reader_state" "ReadStateObjects" \
    "ALL:resource:nonmatching"
  assert_suffix "case-id aws condition-key suffix" \
    "case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:aws:RequestTag/Project:absent" \
    "aws_iam_policy.deployer_data" "LogsCreateWithTag" \
    "ALL:aws:RequestTag/Project:absent"
  assert_suffix "case-id trust colon document" \
    "case:trust:plan_reader:trust:plan_reader#0:ALL:token.actions.githubusercontent.com:aud:matching" \
    "trust:plan_reader" "trust:plan_reader#0" \
    "ALL:token.actions.githubusercontent.com:aud:matching"

  expect_failure "case-id wrong document refusal" "exact prefix mismatch" \
    iam_simulate_case_suffix \
    "case:trust:plan_reader:trust:plan_reader#0:ALL:token.actions.githubusercontent.com:aud:matching" \
    "trust" "trust:plan_reader#0"
fi

if [ "$failures" -eq "$group_failures" ]; then
  echo "PASS: IAM simulate CASE-ID group"
else
  echo "FAIL: IAM simulate CASE-ID group" >&2
fi

echo "== iam simulate contracts: SCHEMA =="
group_failures=$failures
if [ -f "$VALIDATOR" ]; then
  for fixture in valid-decision.json valid-attribution-only.json valid-custom.json valid-custom-isolated.json; do
    if output="$(python3 "$VALIDATOR" "$VECTOR_FIXTURES/$fixture" 2>&1)"; then
      pass_case "schema accepts $fixture"
    else
      fail_case "schema accepts $fixture" "$output"
    fi
  done

  examples_dir="$tmp_dir/schema-examples"
  if output="$(python3 - "$SCHEMA_DOC" "$examples_dir" 2>&1 <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
worked = source.split("## Worked matrix examples", 1)
if len(worked) != 2:
    raise SystemExit("FAIL: schema document lacks worked examples")
examples = re.findall(r"```json\n(.*?)\n```", worked[1], re.DOTALL)
if len(examples) != 3:
    raise SystemExit(f"FAIL: schema document has {len(examples)} JSON examples, expected 3")
destination = Path(sys.argv[2])
destination.mkdir()
for index, example in enumerate(examples, 1):
    (destination / f"example-{index}.json").write_text(
        example + "\n", encoding="utf-8", newline="\n"
    )
PY
  )"; then
    examples_ok=1
    for example in "$examples_dir"/*.json; do
      if ! python3 "$VALIDATOR" "$example" >/dev/null 2>&1; then
        examples_ok=0
      fi
    done
    if [ "$examples_ok" -eq 1 ]; then
      pass_case "schema document's three worked matrix examples validate"
    else
      fail_case "schema document's three worked matrix examples validate"
    fi
  else
    fail_case "schema document's three worked matrix examples validate" "$output"
  fi

  expect_failure "schema missing decision" "expect.decision is required" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-missing-decision.json"
  expect_failure "schema attribution decision" \
    "expect.decision is forbidden for attribution-only" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-attribution-decision.json"
  expect_failure "schema isolated statement on non-isolated mode" \
    "isolated_statement is forbidden for principal" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-isolated-nonisolated.json"
  expect_failure "schema isolated allowed decision" \
    "custom-isolated vectors cannot expect allowed" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-isolated-allowed.json"
  expect_failure "schema literal account id" "literal 12-digit account id" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-account-id.json"
  expect_failure "schema unknown context type" "unknown ContextKeyType" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-context-key-type.json"
  expect_failure "schema unknown case id" "case_id is absent from categories.json" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-unknown-case.json"
else
  fail_case "IAM simulate vector validator exists" "$VALIDATOR is missing"
fi

if [ "$failures" -eq "$group_failures" ]; then
  echo "PASS: IAM simulate SCHEMA group"
else
  echo "FAIL: IAM simulate SCHEMA group" >&2
fi

if [ "$failures" -eq 0 ]; then
  echo "PASS: IAM simulate contracts"
else
  echo "FAIL: IAM simulate contracts ($failures case(s))" >&2
  exit 1
fi
