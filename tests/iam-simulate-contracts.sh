#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MATRIX="$REPO_ROOT/docs/iam-matrix.md"
GENERATOR="$REPO_ROOT/scripts/iam-simulate-categories.py"
TAXONOMY="$REPO_ROOT/tests/fixtures/iam-simulate/categories.json"
CASE_ID_LIB="$REPO_ROOT/tests/lib/iam-simulate.sh"
VALIDATOR="$REPO_ROOT/scripts/iam-simulate-validate.py"
VECTOR_FIXTURES="$REPO_ROOT/tests/fixtures/iam-simulate"
VECTORS="$VECTOR_FIXTURES/vectors"
UNRESOLVED="$VECTOR_FIXTURES/unresolved.json"
SCHEMA_DOC="$REPO_ROOT/docs/iam-simulate-vector-schema.md"
PHASE2_CONTRACTS="$REPO_ROOT/tests/lib/iam-simulate-phase2.sh"
MUTATION_REGISTRY="$REPO_ROOT/tests/lib/iam-simulate-mutations.txt"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbit-iam-simulate.XXXXXX")"
results="$tmp_dir/results.txt"
mutation_observations="$tmp_dir/mutation-observations.txt"
failures=0
: >"$mutation_observations"
trap 'rm -rf "$tmp_dir"' EXIT

pass_case() {
  local message=$1 prefix label case_id diagnostic
  if [[ "$message" == *" -> FAIL:"* ]]; then
    prefix=${message%%" -> FAIL:"*}
    label=${prefix% mutation}
    diagnostic="FAIL:${message#*" -> FAIL:"}"
    case_id="$(
      LC_ALL=C tr '[:upper:]' '[:lower:]' <<<"$label" |
        sed -E 's/[^a-z0-9]+/-/g; s/^-//; s/-$//'
    )"
    printf '%s\t%s\n' "$case_id" "$diagnostic" >>"$mutation_observations"
  fi
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
  if [ "$rc" -ne 0 ] && [ -n "$fail_line" ] && grep -Fq -- "$expected" <<< "$output"; then
    pass_case "$label mutation -> $fail_line"
  else
    fail_case "$label mutation did not fail as required" "rc=$rc output=$output"
  fi
}

validate_mutation_registry() {
  python3 - "$MUTATION_REGISTRY" "${1:-}" <<'PY_REGISTRY'
from pathlib import Path
import sys

registry_path = Path(sys.argv[1])
observations_path = Path(sys.argv[2]) if sys.argv[2] else None


def fail(message):
    raise SystemExit(f"FAIL: mutation registry {message}")


try:
    lines = registry_path.read_text(encoding="utf-8").splitlines()
except OSError as exc:
    fail(f"cannot be read: {exc}")

registry = {}
for line_number, line in enumerate(lines, 1):
    if not line or line.startswith("#"):
        continue
    fields = line.split("\t")
    if len(fields) != 3:
        fail(f"line {line_number} must contain id, action, and diagnostic")
    case_id, action, diagnostic = fields
    if not case_id or not action or not diagnostic.startswith("FAIL:"):
        fail(f"line {line_number} has an invalid id, action, or diagnostic")
    if case_id in registry:
        fail(f"repeats case id: {case_id}")
    registry[case_id] = (action, diagnostic)
if not registry:
    fail("contains no cases")

if observations_path is None:
    print(f"PASS: IAM simulate mutation registry schema ({len(registry)} case(s))")
    raise SystemExit(0)

observations = {}
for line_number, line in enumerate(
    observations_path.read_text(encoding="utf-8").splitlines(), 1
):
    fields = line.split("\t", 1)
    if len(fields) != 2:
        fail(f"observation line {line_number} is malformed")
    case_id, diagnostic = fields
    if case_id in observations:
        fail(f"observed case more than once: {case_id}")
    observations[case_id] = diagnostic

missing = sorted(set(registry) - set(observations))
if missing:
    fail(f"did not execute case: {missing[0]}")
unexpected = sorted(set(observations) - set(registry))
if unexpected:
    fail(f"observed unregistered case: {unexpected[0]}")
for case_id in sorted(registry):
    expected = registry[case_id][1]
    observed = observations[case_id]
    if not observed.startswith(expected):
        fail(
            f"diagnostic mismatch for {case_id}: "
            f"expected prefix {expected!r}, observed {observed!r}"
        )
print(
    f"PASS: IAM simulate mutation registry "
    f"({len(observations)}/{len(registry)} executed; restored suite passed)"
)
PY_REGISTRY
}

validate_mutation_registry

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

  if output="$(python3 "$VALIDATOR" "$VECTOR_FIXTURES/valid-decision.json" --jsonl 2>&1)" && \
     jq -s -e '
       length == 1
       and .[0].schema_version == 1
       and .[0].document == "aws_iam_role_policy.plan_reader_deny"
       and .[0].sid == "DenyReadStateObjectsOutsideScope"
       and (.[0] | has("cases") | not)
     ' <<<"$output" >/dev/null; then
    pass_case "schema validator emits flattened cases as JSONL"
  else
    fail_case "schema validator emits flattened cases as JSONL" "$output"
  fi


  if output="$(python3 "$VALIDATOR" "$VECTORS" --jsonl 2>&1)" && \
     [ "$(wc -l <<<"$output" | tr -d ' ')" -eq 239 ] && \
     [ "$(jq -s 'map(.case_id) | unique | length' <<<"$output")" -eq 239 ]; then
    pass_case "schema validator loads the vector directory in one JSONL pass"
  else
    fail_case "schema validator loads the vector directory in one JSONL pass" "$output"
  fi

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
    "isolated_statement is forbidden for custom" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-isolated-nonisolated.json"
  expect_failure "schema isolated allowed decision" \
    "custom-isolated vectors cannot expect allowed" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-isolated-allowed.json"
  expect_failure "schema embedded custom policy" \
    "policy_input_list is forbidden for custom vectors; resolve repository policies from the plan" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-embedded-policy-input.json"
  expect_failure "schema embedded isolated statement" \
    "isolated_statement is forbidden for custom-isolated vectors; resolve repository policies from the plan" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-embedded-isolated-statement.json"
  expect_failure "schema literal account id" "literal 12-digit account id" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-account-id.json"
  expect_failure "schema unknown context type" "unknown ContextKeyType" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-context-key-type.json"
  expect_failure "schema unknown case id" "case_id is absent from categories.json" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-unknown-case.json"
  expect_failure "schema unknown custom field" "unexpected is forbidden for custom vectors" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-unknown-field.json"
  expect_failure "schema envelope header mismatch" "case_id prefix does not match envelope header" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-header-mismatch.json"
  expect_failure "schema duplicate case" "envelope repeats case_id" \
    python3 "$VALIDATOR" "$VECTOR_FIXTURES/invalid-duplicate-case.json"
else
  fail_case "IAM simulate vector validator exists" "$VALIDATOR is missing"
fi

if [ "$failures" -eq "$group_failures" ]; then
  echo "PASS: IAM simulate SCHEMA group"
else
  echo "FAIL: IAM simulate SCHEMA group" >&2
fi

validate_completeness() {
  local taxonomy=$1
  local vectors=$2
  local unresolved=$3
  python3 - "$taxonomy" "$vectors" "$unresolved" "$VALIDATOR" <<'PY_INNER'
from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import sys


ELIGIBLE = {"simulator-decision", "simulator-attribution-only"}


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


taxonomy_path = Path(sys.argv[1])
vectors_path = Path(sys.argv[2])
unresolved_path = Path(sys.argv[3])
validator = Path(sys.argv[4])
taxonomy = json.loads(taxonomy_path.read_text(encoding="utf-8"))
by_id = {entry["case_id"]: entry for entry in taxonomy}

unresolved_ids = set()
if unresolved_path.exists():
    unresolved = json.loads(unresolved_path.read_text(encoding="utf-8"))
    if not isinstance(unresolved, list):
        fail("unresolved.json top level must be an array")
    for index, entry in enumerate(unresolved):
        if not isinstance(entry, dict) or set(entry) != {"case_id", "question"}:
            fail(f"unresolved entry {index} must contain exactly case_id and question")
        case_id = entry["case_id"]
        question = entry["question"]
        if not isinstance(case_id, str) or not case_id:
            fail(f"unresolved entry {index} has an empty or non-string case_id")
        if not isinstance(question, str) or not question.strip():
            fail(f"unresolved entry {index} has an empty or non-string question")
        if case_id in unresolved_ids:
            fail(f"unresolved.json repeats case_id: {case_id}")
        category = by_id.get(case_id)
        if category is None:
            fail(f"unresolved case is absent from taxonomy: {case_id}")
        if category["category"] not in ELIGIBLE:
            fail(f"unresolved case is not simulator-eligible: {case_id}")
        unresolved_ids.add(case_id)

files = sorted(vectors_path.rglob("*.json")) if vectors_path.is_dir() else []
vectors_by_id: dict[str, list[Path]] = {}
filename_checks: list[tuple[Path, str, str, str]] = []
for path in files:
    try:
        envelope = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read vector {path}: {exc}")
    if not isinstance(envelope, dict) or not isinstance(envelope.get("cases"), list):
        checked = subprocess.run(
            [sys.executable, str(validator), str(path), "--categories", str(taxonomy_path)],
            text=True,
            capture_output=True,
            check=False,
        )
        fail(checked.stderr.strip() or checked.stdout.strip() or f"invalid vector: {path}")
    document = envelope.get("document")
    sid = envelope.get("sid")
    if not isinstance(document, str) or not document or not isinstance(sid, str) or not sid:
        checked = subprocess.run(
            [sys.executable, str(validator), str(path), "--categories", str(taxonomy_path)],
            text=True,
            capture_output=True,
            check=False,
        )
        fail(checked.stderr.strip() or checked.stdout.strip() or f"invalid vector: {path}")
    prefix = f"case:{document}:{sid}:"
    for case in envelope["cases"]:
        case_id = case.get("case_id") if isinstance(case, dict) else None
        if not isinstance(case_id, str):
            checked = subprocess.run(
                [sys.executable, str(validator), str(path), "--categories", str(taxonomy_path)],
                text=True,
                capture_output=True,
                check=False,
            )
            fail(checked.stderr.strip() or checked.stdout.strip() or f"invalid vector: {path}")
        if not case_id.startswith(prefix) or case_id == prefix:
            fail(
                "case_id prefix does not match envelope header: "
                f"{case_id} expected {prefix}"
            )
        vectors_by_id.setdefault(case_id, []).append(path)
    expected = "__".join(
        re.sub(r"[^A-Za-z0-9._-]", "_", value)
        for value in (document, sid)
    ) + ".json"
    filename_checks.append((path, expected, document, sid))

duplicates = sorted(
    case_id
    for case_id, paths in vectors_by_id.items()
    if len(set(paths)) > 1
)
if duplicates:
    fail(f"case id appears in two envelopes: {duplicates[0]}")

for path, expected, document, sid in filename_checks:
    if path.relative_to(vectors_path).as_posix() != expected:
        fail(f"vector filename mismatch for {document} {sid}: expected {expected}")

for case_id in sorted(vectors_by_id):
    entry = by_id.get(case_id)
    if entry is None:
        fail(f"vector case id is absent from taxonomy: {case_id}")
    if entry["category"] not in ELIGIBLE:
        fail(f"vector exists for non-simulator category: {case_id}")
    if case_id in unresolved_ids:
        fail(f"case id appears in both vectors and unresolved.json: {case_id}")

required = {
    case_id for case_id, entry in by_id.items() if entry["category"] in ELIGIBLE
}
missing = sorted(required - set(vectors_by_id) - unresolved_ids)
if missing:
    fail(f"simulator-eligible case lacks a vector or unresolved entry: {missing[0]}")

for path in files:
    checked = subprocess.run(
        [sys.executable, str(validator), str(path), "--categories", str(taxonomy_path)],
        text=True,
        capture_output=True,
        check=False,
    )
    if checked.returncode != 0:
        detail = checked.stderr.strip() or checked.stdout.strip()
        fail(f"vector validation failed for {path.name}: {detail}")

print(
    f"PASS: IAM simulate vector completeness "
    f"({len(vectors_by_id)} case(s) in {len(files)} envelope(s), "
    f"{len(unresolved_ids)} unresolved)"
)
PY_INNER
}

echo "== iam simulate contracts: COMPLETENESS =="
group_failures=$failures
if output="$(validate_completeness "$TAXONOMY" "$VECTORS" "$UNRESOLVED" 2>&1)"; then
  pass_case "$output"
else
  fail_case "IAM simulate vector completeness" "$output"
fi

completeness_mutants="$tmp_dir/completeness-mutants"
python3 - "$TAXONOMY" "$VECTORS" "$UNRESOLVED" "$completeness_mutants" <<'PY_INNER'
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import re
import shutil
import sys


taxonomy_path = Path(sys.argv[1])
vectors_source = Path(sys.argv[2])
unresolved_source = Path(sys.argv[3])
mutants_root = Path(sys.argv[4])
taxonomy = json.loads(taxonomy_path.read_text(encoding="utf-8"))
source_files = sorted(vectors_source.glob("*.json"))
if not source_files:
    raise SystemExit("FAIL: completeness mutation setup found no real vectors")
source_path = next(
    path
    for path in source_files
    if len(json.loads(path.read_text(encoding="utf-8"))["cases"]) > 1
)
source_envelope = json.loads(source_path.read_text(encoding="utf-8"))
source_case = deepcopy(source_envelope["cases"][0])


def sanitize(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]", "_", value)


def filename(document: str, sid: str) -> str:
    return "__".join(sanitize(value) for value in (document, sid)) + ".json"


def clone(name: str) -> tuple[Path, Path]:
    root = mutants_root / name
    vectors = root / "vectors"
    unresolved = root / "unresolved.json"
    shutil.copytree(vectors_source, vectors)
    if unresolved_source.exists():
        shutil.copy2(unresolved_source, unresolved)
    else:
        unresolved.write_text("[]\n", encoding="utf-8")
    return vectors, unresolved


def write_envelope(vectors: Path, envelope: dict) -> None:
    (vectors / filename(envelope["document"], envelope["sid"])).write_text(
        json.dumps(envelope, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )


def add_taxonomy_vector(name: str, category: str) -> None:
    vectors, _ = clone(name)
    existing_headers = {
        (envelope["document"], envelope["sid"])
        for path in vectors.glob("*.json")
        for envelope in [json.loads(path.read_text(encoding="utf-8"))]
    }
    entry = next(
        item for item in taxonomy
        if item["category"] == category
        and (item["document"], item["sid"]) not in existing_headers
    )
    case = deepcopy(source_case)
    case["case_id"] = entry["case_id"]
    write_envelope(vectors, {
        "schema_version": 1,
        "document": entry["document"],
        "sid": entry["sid"],
        "cases": [case],
    })


vectors, _ = clone("missing")
path = vectors / source_path.name
envelope = json.loads(path.read_text(encoding="utf-8"))
envelope["cases"].pop(0)
path.write_text(json.dumps(envelope, indent=2) + "\n", encoding="utf-8")

add_taxonomy_vector("live", "live-call-only")
add_taxonomy_vector("not-simulatable", "not-simulatable")

vectors, _ = clone("unknown")
unknown_entry = {
    "case_id": "case:unknown.document:UnknownSid:ALL:none:example",
    "document": "unknown.document",
    "sid": "UnknownSid",
}
case = deepcopy(source_case)
case["case_id"] = unknown_entry["case_id"]
write_envelope(vectors, {
    "schema_version": 1,
    "document": unknown_entry["document"],
    "sid": unknown_entry["sid"],
    "cases": [case],
})

vectors, _ = clone("duplicate")
nested = vectors / "nested"
nested.mkdir()
shutil.copy2(vectors / source_path.name, nested / source_path.name)

vectors, _ = clone("filename")
(vectors / source_path.name).rename(vectors / f"drift__{source_path.name}")

vectors, _ = clone("invalid-schema")
path = vectors / source_path.name
envelope = json.loads(path.read_text(encoding="utf-8"))
envelope["cases"][0].pop("expect")
path.write_text(json.dumps(envelope, indent=2) + "\n", encoding="utf-8")

vectors, _ = clone("header-mismatch")
path = vectors / source_path.name
envelope = json.loads(path.read_text(encoding="utf-8"))
envelope["cases"][0]["case_id"] = next(
    item["case_id"]
    for item in taxonomy
    if item["category"] in {"simulator-decision", "simulator-attribution-only"}
    and (item["document"], item["sid"]) != (envelope["document"], envelope["sid"])
)
path.write_text(json.dumps(envelope, indent=2) + "\n", encoding="utf-8")

vectors, unresolved = clone("unresolved-exemption")
path = vectors / source_path.name
envelope = json.loads(path.read_text(encoding="utf-8"))
removed_case = envelope["cases"].pop(0)
path.write_text(json.dumps(envelope, indent=2) + "\n", encoding="utf-8")
entries = json.loads(unresolved.read_text(encoding="utf-8"))
entries.append({
    "case_id": removed_case["case_id"],
    "question": "Mutation: can this otherwise resolved case be exempted explicitly?",
})
unresolved.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")
PY_INNER

expect_failure "completeness missing array member" "simulator-eligible case lacks a vector or unresolved entry" \
  validate_completeness "$TAXONOMY" "$completeness_mutants/missing/vectors" "$completeness_mutants/missing/unresolved.json"
expect_failure "completeness live-call vector" "vector exists for non-simulator category" \
  validate_completeness "$TAXONOMY" "$completeness_mutants/live/vectors" "$completeness_mutants/live/unresolved.json"
expect_failure "completeness not-simulatable vector" "vector exists for non-simulator category" \
  validate_completeness "$TAXONOMY" "$completeness_mutants/not-simulatable/vectors" "$completeness_mutants/not-simulatable/unresolved.json"
expect_failure "completeness unknown case id" "vector case id is absent from taxonomy" \
  validate_completeness "$TAXONOMY" "$completeness_mutants/unknown/vectors" "$completeness_mutants/unknown/unresolved.json"
expect_failure "completeness duplicate case across envelopes" "case id appears in two envelopes" \
  validate_completeness "$TAXONOMY" "$completeness_mutants/duplicate/vectors" "$completeness_mutants/duplicate/unresolved.json"
expect_failure "completeness filename derivation" "vector filename mismatch" \
  validate_completeness "$TAXONOMY" "$completeness_mutants/filename/vectors" "$completeness_mutants/filename/unresolved.json"
expect_failure "completeness schema validation" "vector validation failed" \
  validate_completeness "$TAXONOMY" "$completeness_mutants/invalid-schema/vectors" "$completeness_mutants/invalid-schema/unresolved.json"
expect_failure "completeness envelope header mismatch" "case_id prefix does not match envelope header" \
  validate_completeness "$TAXONOMY" "$completeness_mutants/header-mismatch/vectors" "$completeness_mutants/header-mismatch/unresolved.json"

if output="$(
  validate_completeness "$TAXONOMY" \
    "$completeness_mutants/unresolved-exemption/vectors" \
    "$completeness_mutants/unresolved-exemption/unresolved.json" 2>&1
)" && grep -Fq "(238 case(s) in 81 envelope(s), 1 unresolved)" <<< "$output"; then
  pass_case "completeness unresolved exemption mutation -> $output"
else
  fail_case "completeness unresolved exemption mutation did not pass as required" "$output"
fi

if [ "$failures" -eq "$group_failures" ]; then
  echo "PASS: IAM simulate COMPLETENESS group"
else
  echo "FAIL: IAM simulate COMPLETENESS group" >&2
fi

if [ -f "$PHASE2_CONTRACTS" ]; then
  # shellcheck disable=SC1090
  source "$PHASE2_CONTRACTS"
  run_iam_simulate_runner_contracts
  run_iam_simulate_role_lane_contracts
else
  fail_case "IAM simulate phase-2 contract library exists" "$PHASE2_CONTRACTS is missing"
fi

if output="$(validate_mutation_registry "$mutation_observations" 2>&1)"; then
  pass_case "${output#PASS: }"
else
  fail_case "IAM simulate mutation registry execution" "$output"
fi

if [ "$failures" -eq 0 ]; then
  echo "PASS: IAM simulate contracts"
else
  echo "FAIL: IAM simulate contracts ($failures case(s))" >&2
  exit 1
fi
