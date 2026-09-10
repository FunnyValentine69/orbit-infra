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
CUSTOM_EVIDENCE_REPORT="$REPO_ROOT/docs/assets/iam-simulation-custom-report.json"
ROLE_EVIDENCE_REPORT="$REPO_ROOT/docs/assets/iam-simulation-role-report.json"
RENDERED_EVIDENCE_REPORT="$REPO_ROOT/docs/assets/IAM_SIMULATION_REPORT.md"
EVIDENCE_PROVENANCE="$REPO_ROOT/docs/assets/IAM_SIMULATION_PROVENANCE.md"
EVIDENCE_POINTER="docs/assets/IAM_SIMULATION_REPORT.md"
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

validate_evidence_join() {
  local matrix=$1 custom_report=$2 role_report=$3 rendered_report=$4 provenance=$5
  python3 - \
    "$matrix" "$VECTORS" "$custom_report" "$role_report" \
    "$rendered_report" "$provenance" "$EVIDENCE_POINTER" <<'PY_EVIDENCE'
from __future__ import annotations

from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import sys


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def load_json(path: Path, description: str):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {description}: {exc}")


def load_records(path: Path, description: str) -> dict[str, list[dict]]:
    payload = load_json(path, description)
    if not isinstance(payload, dict) or not isinstance(payload.get("records"), list):
        fail(f"{description} must contain a records array")
    records: dict[str, list[dict]] = defaultdict(list)
    for index, record in enumerate(payload["records"]):
        if not isinstance(record, dict) or not isinstance(record.get("case_id"), str):
            fail(f"{description} record {index} lacks a case_id")
        records[record["case_id"]].append(record)
    return records


def load_vectors(root: Path) -> dict[str, dict]:
    vectors = {}
    for path in sorted(root.glob("*.json")):
        payload = load_json(path, f"vector envelope {path.name}")
        cases = payload.get("cases")
        if not isinstance(cases, list):
            fail(f"vector envelope {path.name} lacks a cases array")
        for vector in cases:
            case_id = vector.get("case_id") if isinstance(vector, dict) else None
            if not isinstance(case_id, str) or case_id in vectors:
                fail(f"Evidence join found an invalid or duplicate vector case_id: {case_id}")
            vectors[case_id] = vector
    return vectors


def rendered_resource_matches(template: str, observed: str) -> bool:
    pattern = re.escape(template)
    pattern = pattern.replace(re.escape("${ACCOUNT_ID}"), "000000000000")
    pattern = pattern.replace(re.escape("${SUFFIX}"), r"[a-z0-9]+")
    return re.fullmatch(pattern, observed) is not None


def expected_resource_decision(expectation: dict, resource: str):
    per_resource = expectation.get("resource_decisions")
    if not isinstance(per_resource, dict):
        return expectation.get("decision")
    matches = [
        decision for template, decision in per_resource.items()
        if rendered_resource_matches(template, resource)
    ]
    return matches[0] if len(matches) == 1 else None


def details_cover_vector(vector: dict, details: list[dict]) -> bool:
    actions = vector.get("action_names")
    resources = vector.get("resource_arns") or ["*"]
    if not isinstance(actions, list) or len(details) != len(actions) * len(resources):
        return False
    unmatched = list(details)
    for action in actions:
        for resource_template in resources:
            matches = [
                detail for detail in unmatched
                if isinstance(detail, dict)
                and detail.get("action_name") == action
                and isinstance(detail.get("resource_arn"), str)
                and rendered_resource_matches(resource_template, detail["resource_arn"])
            ]
            if len(matches) != 1:
                return False
            unmatched.remove(matches[0])
    return not unmatched


def observation_matches(vector: dict, evidence: dict) -> bool:
    expectation = vector.get("expect")
    if not isinstance(expectation, dict):
        return False
    required = expectation.get("matched_sid_required", [])
    forbidden = expectation.get("matched_sid_forbidden", [])
    details = evidence.get("details")
    if isinstance(details, list):
        if not details_cover_vector(vector, details):
            return False
        for detail in details:
            if vector.get("assertion_kind") == "decision":
                expected = expected_resource_decision(expectation, detail["resource_arn"])
                if detail.get("decision_observed") != expected:
                    return False
            matched = detail.get("matched_sids")
            if not isinstance(matched, list) or any(not isinstance(sid, str) for sid in matched):
                return False
            matched_set = set(matched)
            if not set(required) <= matched_set or set(forbidden) & matched_set:
                return False
        return True
    expected_decision = expectation.get("decision")
    per_resource = expectation.get("resource_decisions")
    observed = evidence.get("decision_observed")
    if isinstance(per_resource, dict) and isinstance(observed, dict):
        if not observed:
            return False
        observed_resources = set()
        for pair_or_resource, decision in observed.items():
            resource = pair_or_resource.split("|", 1)[-1]
            observed_resources.add(resource)
            if expected_resource_decision(expectation, resource) != decision:
                return False
        for template in per_resource:
            if not any(rendered_resource_matches(template, resource) for resource in observed_resources):
                return False
    elif expected_decision is not None:
        decisions = list(observed.values()) if isinstance(observed, dict) else [observed]
        if not decisions or any(decision != expected_decision for decision in decisions):
            return False
    matched = evidence.get("matched_sids")
    if not isinstance(matched, list) or any(not isinstance(sid, str) for sid in matched):
        return False
    matched_set = set(matched)
    return set(required) <= matched_set and not (set(forbidden) & matched_set)


def custom_matches(vector: dict, record: dict) -> bool:
    expectation = vector.get("expect")
    return (
        "runner_failure" not in record
        and isinstance(expectation, dict)
        and observation_matches(vector, record)
    )


def role_matches(vector: dict, record: dict) -> bool:
    evidence = record.get("scp_excluded")
    expectation = vector.get("expect")
    return (
        "runner_failure" not in record
        and isinstance(evidence, dict)
        and isinstance(expectation, dict)
        and observation_matches(vector, evidence)
    )


matrix_path = Path(sys.argv[1])
vectors = load_vectors(Path(sys.argv[2]))
custom_path = Path(sys.argv[3])
role_path = Path(sys.argv[4])
rendered_path = Path(sys.argv[5])
provenance_path = Path(sys.argv[6])
expected_pointer = sys.argv[7]
custom_records = load_records(custom_path, "custom evidence report")
role_records = load_records(role_path, "role evidence report")
try:
    matrix_text = matrix_path.read_text(encoding="utf-8")
    rendered_text = rendered_path.read_text(encoding="utf-8")
    provenance_text = provenance_path.read_text(encoding="utf-8")
except OSError as exc:
    fail(f"cannot read Evidence input: {exc}")
recorded_on_matches = re.findall(
    r"^\| recorded_on \| (\d{4}-\d{2}-\d{2}) \|$", provenance_text, re.MULTILINE
)
if len(recorded_on_matches) != 1:
    fail("provenance must contain exactly one recorded_on date")
recorded_on = recorded_on_matches[0]
generator_matches = re.findall(
    r"^\| generator commit \| ([0-9a-f]+) \|$", provenance_text, re.MULTILINE
)
if len(generator_matches) != 1:
    fail("provenance must contain exactly one generator commit")
generator_commit = generator_matches[0]
report_recorded_on = re.findall(
    r"^\| recorded_on \| (\d{4}-\d{2}-\d{2}) \|$", rendered_text, re.MULTILINE
)
report_generator = re.findall(
    r"^\| generator commit \| ([0-9a-f]+) \|$", rendered_text, re.MULTILINE
)
if bool(report_recorded_on) != bool(report_generator):
    fail("Evidence report publication metadata set is incomplete")
if len(report_recorded_on) > 1 or len(report_generator) > 1:
    fail("Evidence report repeats publication metadata")
if report_recorded_on and report_recorded_on[0] != recorded_on:
    fail(
        "Evidence publication recorded_on mismatch: "
        f"report={report_recorded_on[0]} provenance={recorded_on}"
    )
if report_generator and report_generator[0] != generator_commit:
    fail(
        "Evidence publication generator commit mismatch: "
        f"report={report_generator[0]} provenance={generator_commit}"
    )
expected_label = f"AWS-SIMULATED {recorded_on} {expected_pointer}"

digest_paths = {
    "custom report sha256": custom_path,
    "role report sha256": role_path,
    "Markdown report sha256": rendered_path,
}
computed_digests = {}
for name, digest_path in digest_paths.items():
    try:
        computed_digests[name] = hashlib.sha256(digest_path.read_bytes()).hexdigest()
    except OSError as exc:
        fail(f"cannot digest {name}: {exc}")
provenance_digests = {}
for name in digest_paths:
    matches = re.findall(
        rf"^\| {re.escape(name)} \| `?([0-9a-f]{{64}})`? \|$",
        provenance_text,
        re.MULTILINE,
    )
    if len(matches) > 1:
        fail(f"provenance repeats {name}")
    if matches:
        provenance_digests[name] = matches[0]
if provenance_digests and set(provenance_digests) != set(digest_paths):
    missing = sorted(set(digest_paths) - set(provenance_digests))[0]
    fail(f"provenance digest set is incomplete: missing {missing}")
for name, recorded_digest in provenance_digests.items():
    if recorded_digest != computed_digests[name]:
        fail(
            f"provenance digest mismatch for {name}: "
            f"recorded={recorded_digest} computed={computed_digests[name]}"
        )

case_entry = re.compile(r"(case:[^ ;=)]+) => (.*?)(?=; case:|$)")
evidence_entry = re.compile(r"(case:[^ ;=)]+)=(.*?)(?=; case:|$)")
rows = []
for line_number, line in enumerate(matrix_text.splitlines(), 1):
    if not line.startswith("| `"):
        continue
    cells = re.findall(r"`([^`]*)`", line.replace(r"; \| case:", "; case:"))
    if len(cells) != 10 or not cells[0].startswith(("aws_", "trust:")):
        continue
    case_ids = [case_id for case_id, _ in case_entry.findall(cells[7])]
    labels = dict(evidence_entry.findall(cells[9]))
    rows.append((line_number, cells[0], cells[1], case_ids, labels))


def matching_path(case_id: str) -> str | None:
    vector = vectors.get(case_id)
    if vector is None:
        return None
    custom = custom_records.get(case_id, [])
    role = role_records.get(case_id, [])
    if len(custom) == 1 and custom_matches(vector, custom[0]):
        return "custom"
    if len(role) == 1 and role_matches(vector, role[0]):
        return "role"
    return None


promoted_cases = 0
promoted_rows = 0
kept_rows = 0
for line_number, document, sid, case_ids, labels in rows:
    for case_id in case_ids:
        label = labels.get(case_id, "")
        if not label.startswith("AWS-SIMULATED "):
            continue
        parts = label.split(" ", 2)
        if len(parts) != 3 or parts[2] != expected_pointer:
            pointer = parts[2] if len(parts) == 3 else "<missing>"
            fail(f"Evidence pointer mismatch for {case_id}: {pointer}")
        if parts[1] != recorded_on:
            fail(
                f"Evidence date mismatch for {case_id}: "
                f"matrix={parts[1]} provenance={recorded_on}"
            )
        if len(custom_records.get(case_id, [])) > 1 or len(role_records.get(case_id, [])) > 1:
            fail(f"promoted case appears more than once in an evidence lane: {case_id}")
        if not custom_records.get(case_id) and not role_records.get(case_id):
            fail(f"promoted case has no evidence record: {case_id}")
        if matching_path(case_id) is None:
            fail(f"promoted case is not execution-matching: {case_id}")
        promoted_cases += 1

    row_is_promotable = bool(case_ids) and all(matching_path(case_id) for case_id in case_ids)
    row_labels = [labels.get(case_id, "") for case_id in case_ids]
    if row_is_promotable:
        if any(label != expected_label for label in row_labels):
            fail(f"Evidence row is below its computed minimum at line {line_number}: {document} {sid}")
        promoted_rows += 1
    else:
        if any(label.startswith("AWS-SIMULATED ") for label in row_labels):
            fail(f"Evidence row is above its computed minimum at line {line_number}: {document} {sid}")
        kept_rows += 1

digest_status = "verified" if provenance_digests else "deferred-to-P5-52"
print(
    "PASS: IAM simulation Evidence join "
    f"({len(rows)} rows: {promoted_rows} promoted, {kept_rows} kept; "
    f"{promoted_cases} promoted cases; "
    f"custom_sha256={computed_digests['custom report sha256']} "
    f"role_sha256={computed_digests['role report sha256']} "
    f"markdown_sha256={computed_digests['Markdown report sha256']}; "
    f"provenance_digests={digest_status})"
)
PY_EVIDENCE
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
  run_iam_simulate_report_contracts
else
  fail_case "IAM simulate phase-2 contract library exists" "$PHASE2_CONTRACTS is missing"
fi

echo "== iam simulate contracts: EVIDENCE =="
group_failures=$failures
if output="$(
  validate_evidence_join \
    "$MATRIX" "$CUSTOM_EVIDENCE_REPORT" "$ROLE_EVIDENCE_REPORT" \
    "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE" 2>&1
)"; then
  pass_case "${output#PASS: }"
else
  fail_case "IAM simulation Evidence join" "$output"
fi

if [ "$failures" -eq "$group_failures" ]; then
  evidence_mutants="$tmp_dir/evidence-mutants"
  python3 - \
    "$MATRIX" "$CUSTOM_EVIDENCE_REPORT" "$ROLE_EVIDENCE_REPORT" \
    "$EVIDENCE_PROVENANCE" "$evidence_mutants" "$EVIDENCE_POINTER" \
    "$VECTORS" <<'PY_EVIDENCE_MUTANTS'
from copy import deepcopy
import json
from pathlib import Path
import re
import sys


matrix_path = Path(sys.argv[1])
custom_path = Path(sys.argv[2])
role_path = Path(sys.argv[3])
provenance_path = Path(sys.argv[4])
mutants_root = Path(sys.argv[5])
pointer = sys.argv[6]
vector_root = Path(sys.argv[7])
matrix = matrix_path.read_text(encoding="utf-8")
custom = json.loads(custom_path.read_text(encoding="utf-8"))
role = json.loads(role_path.read_text(encoding="utf-8"))
provenance = provenance_path.read_text(encoding="utf-8")
dates = re.findall(
    r"^\| recorded_on \| (\d{4}-\d{2}-\d{2}) \|$", provenance, re.MULTILINE
)
if len(dates) != 1:
    raise SystemExit("FAIL: Evidence mutation setup requires one recorded_on date")
label = f"AWS-SIMULATED {dates[0]} {pointer}"
promoted = re.findall(
    rf"(case:[^ ;=)]+)={re.escape(label)}(?=; case:|`)", matrix
)
if not promoted:
    raise SystemExit("FAIL: Evidence mutation setup found no promoted cases")
custom_by_id = {record["case_id"]: record for record in custom["records"]}
role_by_id = {record["case_id"]: record for record in role["records"]}
role_ids = set(role_by_id)
vectors = {
    vector["case_id"]: vector
    for path in sorted(vector_root.rglob("*.json"))
    for vector in json.loads(path.read_text(encoding="utf-8"))["cases"]
}


def write_mutant(name, matrix_text=None, custom_payload=None, role_payload=None):
    root = mutants_root / name
    root.mkdir(parents=True)
    (root / "matrix.md").write_text(matrix if matrix_text is None else matrix_text, encoding="utf-8")
    (root / "custom.json").write_text(
        json.dumps(custom if custom_payload is None else custom_payload, indent=2) + "\n",
        encoding="utf-8",
    )
    (root / "role.json").write_text(
        json.dumps(role if role_payload is None else role_payload, indent=2) + "\n",
        encoding="utf-8",
    )


failed_case = "case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:none:matching"
failed_anchor = f"{failed_case}=CODE-ONLY"
failed_source = custom_by_id.get(failed_case)
if matrix.count(failed_anchor) != 1 or failed_source is None:
    raise SystemExit("FAIL: failed-case Evidence mutation anchor changed")
write_mutant("failed", matrix.replace(failed_anchor, f"{failed_case}={label}", 1))
doctored_pass_custom = deepcopy(custom)
doctored_pass_record = next(
    record for record in doctored_pass_custom["records"]
    if record["case_id"] == failed_case
)
if doctored_pass_record.get("pass") is not False:
    raise SystemExit("FAIL: doctored-pass Evidence mutation requires a failed source record")
doctored_pass_record["pass"] = True
write_mutant(
    "doctored-pass",
    matrix.replace(failed_anchor, f"{failed_case}={label}", 1),
    custom_payload=doctored_pass_custom,
)

missing_case = next(
    (case_id for case_id in promoted if case_id not in role_ids and case_id in custom_by_id),
    None,
)
if missing_case is None:
    raise SystemExit("FAIL: missing-record Evidence mutation lacks a custom-only promoted case")
missing_custom = deepcopy(custom)
missing_custom["records"] = [
    record for record in missing_custom["records"] if record["case_id"] != missing_case
]
write_mutant("missing", custom_payload=missing_custom)
runner_failure_custom = deepcopy(custom)
runner_failure_record = next(
    record for record in runner_failure_custom["records"]
    if record["case_id"] == missing_case
)
runner_failure_record["pass"] = True
runner_failure_record["runner_failure"] = "doctored runner failure"
write_mutant("runner-failure", custom_payload=runner_failure_custom)

duplicate_case = next((case_id for case_id in promoted if case_id in custom_by_id), None)
if duplicate_case is None:
    raise SystemExit("FAIL: duplicate Evidence mutation lacks a custom report record")
duplicate_custom = deepcopy(custom)
duplicate_custom["records"].append(deepcopy(custom_by_id[duplicate_case]))
write_mutant("duplicate", custom_payload=duplicate_custom)

first_case = promoted[0]
first_anchor = f"{first_case}={label}"
if matrix.count(first_anchor) != 1:
    raise SystemExit("FAIL: pointer/date Evidence mutation anchor changed")
empty_hash_custom = deepcopy(custom)
empty_hash_record = next(
    record for record in empty_hash_custom["records"]
    if record["case_id"] == first_case
)
empty_hash_record["document_hashes_submitted"]["policy_input_list"] = []
write_mutant("empty-hash", custom_payload=empty_hash_custom)
stale_label = f"AWS-SIMULATED {dates[0]} docs/assets/stale-IAM_SIMULATION_REPORT.md"
write_mutant("pointer", matrix.replace(first_anchor, f"{first_case}={stale_label}", 1))
wrong_label = f"AWS-SIMULATED 2026-09-08 {pointer}"
write_mutant("date", matrix.replace(first_anchor, f"{first_case}={wrong_label}", 1))

above_case = "case:aws_iam_policy.deployer_data:EcrVerificationAuth:ALL:none:matching"
excluded_case = "case:aws_iam_policy.deployer_data:EcrVerificationAuth:ALL:none:non-resource"
above_anchor = f"{above_case}=CODE-ONLY"
if matrix.count(above_anchor) != 1 or custom_by_id.get(above_case, {}).get("pass") is not True:
    raise SystemExit("FAIL: row-minimum Evidence mutation anchor changed")
row_custom = deepcopy(custom)
forged_excluded = deepcopy(custom_by_id[above_case])
forged_excluded["case_id"] = excluded_case
forged_excluded["pass"] = True
row_custom["records"].append(forged_excluded)
write_mutant(
    "row",
    matrix.replace(above_anchor, f"{above_case}={label}", 1),
    custom_payload=row_custom,
)

forbidden_case = (
    "case:aws_iam_role_policy.plan_reader_deny:"
    "DenyListBucketOutsideScope:ALL:none:non-protected-resource"
)
forbidden_sid = "DenyListBucketOutsideScope"
forbidden_source = role_by_id.get(forbidden_case)
if (
    forbidden_source is None
    or custom_by_id.get(forbidden_case, {}).get("pass") is not False
    or forbidden_source.get("scp_excluded", {}).get("decision_observed") != "allowed"
    or forbidden_sid in forbidden_source.get("scp_excluded", {}).get("matched_sids", [])
):
    raise SystemExit("FAIL: forbidden-Sid Evidence mutation anchor changed")
forbidden_role = deepcopy(role)
forbidden_record = next(
    record for record in forbidden_role["records"] if record["case_id"] == forbidden_case
)
forbidden_record["scp_excluded"]["matched_sids"].append(forbidden_sid)
write_mutant("role-forbidden-sid", role_payload=forbidden_role)

required_case = (
    "case:aws_iam_policy.deployer_data:"
    "ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching"
)
required_sid = "ClickhouseSecretCreateWithTag"
required_source = role_by_id.get(required_case)
if (
    custom_by_id.get(required_case, {}).get("pass") is not True
    or required_source is None
    or required_source.get("scp_excluded", {}).get("decision_observed") != "allowed"
    or required_sid not in required_source.get("scp_excluded", {}).get("matched_sids", [])
):
    raise SystemExit("FAIL: required-Sid Evidence mutation anchor changed")
required_custom = deepcopy(custom)
required_custom_record = next(
    record for record in required_custom["records"] if record["case_id"] == required_case
)
required_custom_record["matched_sids"] = [
    sid for sid in required_custom_record["matched_sids"] if sid != required_sid
]
required_role = deepcopy(role)
required_record = next(
    record for record in required_role["records"] if record["case_id"] == required_case
)
required_record["scp_excluded"]["matched_sids"] = [
    sid
    for sid in required_record["scp_excluded"]["matched_sids"]
    if sid != required_sid
]
write_mutant(
    "role-required-sid",
    custom_payload=required_custom,
    role_payload=required_role,
)

per_pair_case = (
    "case:aws_iam_policy.task_boundary:"
    "EcsExec:ALL:none:in-boundary"
)
per_pair_vector = vectors.get(per_pair_case)
per_pair_source = custom_by_id.get(per_pair_case)
if (
    per_pair_case not in promoted
    or per_pair_case in role_ids
    or per_pair_vector is None
    or per_pair_source is None
    or per_pair_vector.get("resource_arns") != ["*"]
    or per_pair_vector.get("expect", {}).get("matched_sid_required") != ["EcsExec"]
    or len(per_pair_vector.get("action_names", [])) < 2
):
    raise SystemExit("FAIL: per-pair Sid Evidence mutation anchor changed")
per_pair_custom = deepcopy(custom)
per_pair_record = next(
    record for record in per_pair_custom["records"]
    if record["case_id"] == per_pair_case
)
per_pair_record["details"] = [
    {
        "action_name": action,
        "resource_arn": "*",
        "decision_observed": "allowed",
        "matched_sids": ["EcsExec"],
    }
    for action in per_pair_vector["action_names"]
]
per_pair_record["details"][-1]["matched_sids"] = []
write_mutant("per-pair-sid", custom_payload=per_pair_custom)
PY_EVIDENCE_MUTANTS

  restore_evidence_join() {
    local label=$1 output
    if output="$(
      validate_evidence_join \
        "$MATRIX" "$CUSTOM_EVIDENCE_REPORT" "$ROLE_EVIDENCE_REPORT" \
        "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE" 2>&1
    )"; then
      pass_case "$label restored PASS"
    else
      fail_case "$label did not restore" "$output"
    fi
  }

  expect_failure "evidence failed case promoted" "promoted case is not execution-matching" \
    validate_evidence_join \
      "$evidence_mutants/failed/matrix.md" \
      "$evidence_mutants/failed/custom.json" \
      "$evidence_mutants/failed/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE"
  restore_evidence_join "evidence failed case promoted"
  expect_failure "evidence doctored pass refusal" "promoted case is not execution-matching" \
    validate_evidence_join \
      "$evidence_mutants/doctored-pass/matrix.md" \
      "$evidence_mutants/doctored-pass/custom.json" \
      "$evidence_mutants/doctored-pass/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE"
  restore_evidence_join "evidence doctored pass refusal"
  expect_failure "evidence runner failure refusal" "promoted case is not execution-matching" \
    validate_evidence_join \
      "$evidence_mutants/runner-failure/matrix.md" \
      "$evidence_mutants/runner-failure/custom.json" \
      "$evidence_mutants/runner-failure/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE"
  restore_evidence_join "evidence runner failure refusal"
  expect_failure "evidence per-pair required Sid" \
    "promoted case is not execution-matching" \
    validate_evidence_join \
      "$evidence_mutants/per-pair-sid/matrix.md" \
      "$evidence_mutants/per-pair-sid/custom.json" \
      "$evidence_mutants/per-pair-sid/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE"
  restore_evidence_join "evidence per-pair required Sid"

  set +e
  output="$(
    TMPDIR="$tmp_dir" \
      IAM_MATRIX_CUSTOM_EVIDENCE_REPORT="$evidence_mutants/empty-hash/custom.json" \
      IAM_MATRIX_SKIP_NEGATIVES=1 \
      bash "$REPO_ROOT/tests/iam-matrix-contracts.sh" 2>&1
  )"
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -ne 0 ] && \
     grep -Fq 'FAIL: promoted custom record has an empty policy_input_list hash list:' <<<"$output"; then
    pass_case "evidence promoted empty hash list mutation -> $fail_line"
  else
    fail_case "evidence promoted empty hash list mutation did not fail as required" \
      "rc=$rc output=$output"
  fi
  if output="$(
    TMPDIR="$tmp_dir" IAM_MATRIX_SKIP_NEGATIVES=1 \
      bash "$REPO_ROOT/tests/iam-matrix-contracts.sh" 2>&1
  )" && grep -Fq \
      'PASS: IAM matrix promoted records carry policy hashes (216 cases)' \
      <<<"$output"; then
    pass_case "evidence promoted empty hash list mutation restored PASS"
  else
    fail_case "evidence promoted empty hash list mutation restoration" "$output"
  fi
  expect_failure "evidence missing record" "promoted case has no evidence record" \
    validate_evidence_join \
      "$evidence_mutants/missing/matrix.md" \
      "$evidence_mutants/missing/custom.json" \
      "$evidence_mutants/missing/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE"
  restore_evidence_join "evidence missing record"
  expect_failure "evidence duplicate record" "promoted case appears more than once" \
    validate_evidence_join \
      "$evidence_mutants/duplicate/matrix.md" \
      "$evidence_mutants/duplicate/custom.json" \
      "$evidence_mutants/duplicate/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE"
  restore_evidence_join "evidence duplicate record"
  expect_failure "evidence stale pointer" "Evidence pointer mismatch" \
    validate_evidence_join \
      "$evidence_mutants/pointer/matrix.md" \
      "$evidence_mutants/pointer/custom.json" \
      "$evidence_mutants/pointer/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE"
  restore_evidence_join "evidence stale pointer"
  expect_failure "evidence wrong date" "Evidence date mismatch" \
    validate_evidence_join \
      "$evidence_mutants/date/matrix.md" \
      "$evidence_mutants/date/custom.json" \
      "$evidence_mutants/date/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE"
  restore_evidence_join "evidence wrong date"
  expect_failure "evidence row above minimum" "Evidence row is above its computed minimum" \
    validate_evidence_join \
      "$evidence_mutants/row/matrix.md" \
      "$evidence_mutants/row/custom.json" \
      "$evidence_mutants/row/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE"
  restore_evidence_join "evidence row above minimum"

  validate_evidence_role_refusal() {
    local label=$1 case_id=$2
    shift 2
    local output rc fail_line
    set +e
    output="$(validate_evidence_join "$@" 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && \
       grep -Fq "promoted case is not execution-matching: $case_id" <<<"$output"; then
      return 0
    fi
    printf 'FAIL: %s did not enforce expected refusal: rc=%s observed=%s\n' \
      "$label" "$rc" "${fail_line:-<none>}" >&2
    return 1
  }

  run_evidence_role_check_mutation() {
    local mutation=$1 fixture=$2 case_id=$3 label=$4
    local original="$evidence_mutants/role-matches-original.sh"
    local mutant="$evidence_mutants/role-matches-$mutation-mutant.sh"
    local output
    if output="$(validate_evidence_role_refusal \
      "$label" "$case_id" \
      "$evidence_mutants/$fixture/matrix.md" \
      "$evidence_mutants/$fixture/custom.json" \
      "$evidence_mutants/$fixture/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE" 2>&1)"; then
      pass_case "$label refuses mismatching role record"
    else
      fail_case "$label refusal" "$output"
      return
    fi
    if ! output="$(python3 "$REPO_ROOT/tests/lib/iam-simulate-fixtures.py" \
      mutate-evidence-role-check "$original" "$mutant" "$mutation" 2>&1)"; then
      fail_case "$label mutation setup" "$output"
      return
    fi
    # shellcheck disable=SC1090
    source "$mutant"
    expect_failure "$label" "$label did not enforce expected refusal" \
      validate_evidence_role_refusal \
        "$label" "$case_id" \
        "$evidence_mutants/$fixture/matrix.md" \
        "$evidence_mutants/$fixture/custom.json" \
        "$evidence_mutants/$fixture/role.json" \
        "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE"
    # shellcheck disable=SC1090
    source "$original"
    if output="$(validate_evidence_role_refusal \
      "$label" "$case_id" \
      "$evidence_mutants/$fixture/matrix.md" \
      "$evidence_mutants/$fixture/custom.json" \
      "$evidence_mutants/$fixture/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE" 2>&1)"; then
      pass_case "$label mutation restored PASS"
    else
      fail_case "$label mutation restoration" "$output"
    fi
  }

  evidence_role_function="$evidence_mutants/role-matches-original.sh"
  declare -f validate_evidence_join >"$evidence_role_function"
  run_evidence_role_check_mutation \
    forbidden role-forbidden-sid \
    "case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:non-protected-resource" \
    "evidence role forbidden Sid check"
  run_evidence_role_check_mutation \
    required role-required-sid \
    "case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching" \
    "evidence role required Sid check"

  publication_pair="$evidence_mutants/publication-pair"
  if output="$(run_report_renderer \
    "$IAM_SIM_REPORT_RENDERER" "$CUSTOM_EVIDENCE_REPORT" \
    "$ROLE_EVIDENCE_REPORT" "$publication_pair" 2>&1)"; then
    python3 - \
      "$MATRIX" "$publication_pair/IAM_SIMULATION_REPORT.md" \
      "$publication_pair/IAM_SIMULATION_PROVENANCE.md" \
      "$evidence_mutants/publication-metadata" <<'PY_PUBLICATION'
from pathlib import Path
import re
import sys

matrix_path, report_path, provenance_path, output_root = map(Path, sys.argv[1:])
output_root.mkdir()
matrix = matrix_path.read_text(encoding="utf-8")
report = report_path.read_text(encoding="utf-8")
provenance = provenance_path.read_text(encoding="utf-8")
recorded_on = re.findall(
    r"^\| recorded_on \| (\d{4}-\d{2}-\d{2}) \|$", provenance, re.MULTILINE
)
generator = re.findall(
    r"^\| generator commit \| ([0-9a-f]+) \|$", provenance, re.MULTILINE
)
if len(recorded_on) != 1 or len(generator) != 1:
    raise SystemExit("FAIL: publication metadata mutation setup lacks provenance fields")
current_matrix = re.sub(
    r"AWS-SIMULATED \d{4}-\d{2}-\d{2} ",
    f"AWS-SIMULATED {recorded_on[0]} ",
    matrix,
)
(output_root / "matrix.md").write_text(current_matrix, encoding="utf-8")
(output_root / "report.md").write_text(report, encoding="utf-8")
(output_root / "provenance-generator.md").write_text(
    provenance.replace(
        f"| generator commit | {generator[0]} |",
        "| generator commit | deadbee |",
        1,
    ),
    encoding="utf-8",
)
mutated_date = "2099-12-31"
(output_root / "matrix-date.md").write_text(
    current_matrix.replace(
        f"AWS-SIMULATED {recorded_on[0]} ",
        f"AWS-SIMULATED {mutated_date} ",
    ),
    encoding="utf-8",
)
(output_root / "provenance-date.md").write_text(
    provenance.replace(
        f"| recorded_on | {recorded_on[0]} |",
        f"| recorded_on | {mutated_date} |",
        1,
    ),
    encoding="utf-8",
)
PY_PUBLICATION
    metadata_root="$evidence_mutants/publication-metadata"
    if output="$(validate_evidence_join \
      "$metadata_root/matrix.md" "$CUSTOM_EVIDENCE_REPORT" \
      "$ROLE_EVIDENCE_REPORT" "$metadata_root/report.md" \
      "$publication_pair/IAM_SIMULATION_PROVENANCE.md" 2>&1)"; then
      pass_case "Evidence publication metadata pair agrees"
    else
      fail_case "Evidence publication metadata pair" "$output"
    fi
    expect_failure "evidence publication generator binding" \
      "Evidence publication generator commit mismatch" \
      validate_evidence_join \
        "$metadata_root/matrix.md" "$CUSTOM_EVIDENCE_REPORT" \
        "$ROLE_EVIDENCE_REPORT" "$metadata_root/report.md" \
        "$metadata_root/provenance-generator.md"
    restore_evidence_join "evidence publication generator binding"
    expect_failure "evidence publication date binding" \
      "Evidence publication recorded_on mismatch" \
      validate_evidence_join \
        "$metadata_root/matrix-date.md" "$CUSTOM_EVIDENCE_REPORT" \
        "$ROLE_EVIDENCE_REPORT" "$metadata_root/report.md" \
        "$metadata_root/provenance-date.md"
    restore_evidence_join "evidence publication date binding"
  else
    fail_case "Evidence publication metadata mutation setup" "$output"
  fi

fi

if [ "$failures" -eq "$group_failures" ]; then
  echo "PASS: IAM simulate EVIDENCE group"
else
  echo "FAIL: IAM simulate EVIDENCE group" >&2
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
