#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MATRIX="$REPO_ROOT/docs/evidence/iam-matrix.md"
GENERATOR="$REPO_ROOT/scripts/iam-simulate-categories.py"
TAXONOMY="$REPO_ROOT/tests/fixtures/iam-simulate/categories.json"
CASE_ID_LIB="$REPO_ROOT/tests/lib/iam-simulate.sh"
VALIDATOR="$REPO_ROOT/scripts/iam-simulate-validate.py"
VECTOR_FIXTURES="$REPO_ROOT/tests/fixtures/iam-simulate"
VECTORS="$VECTOR_FIXTURES/vectors"
UNRESOLVED="$VECTOR_FIXTURES/unresolved.json"
SCHEMA_DOC="$REPO_ROOT/docs/evidence/iam-simulate-vector-schema.md"
PHASE2_CONTRACTS="$REPO_ROOT/tests/lib/iam-simulate-phase2.sh"
MUTATION_REGISTRY="$REPO_ROOT/tests/lib/iam-simulate-mutations.txt"
CUSTOM_EVIDENCE_REPORT="$REPO_ROOT/docs/assets/iam-simulation-custom-report.json"
ROLE_EVIDENCE_REPORT="$REPO_ROOT/docs/assets/iam-simulation-role-report.json"
RENDERED_EVIDENCE_REPORT="$REPO_ROOT/docs/assets/IAM_SIMULATION_REPORT.md"
EVIDENCE_PROVENANCE="$REPO_ROOT/docs/assets/IAM_SIMULATION_PROVENANCE.md"
EVIDENCE_POINTER="docs/assets/IAM_SIMULATION_REPORT.md"
IAM_SIM_CORE="$REPO_ROOT/scripts/iam_simulate_core.py"
EVIDENCE_GENERATOR_FILES=(
  "scripts/iam-simulate.sh"
  "scripts/iam-simulate-roles.sh"
  "scripts/iam-simulate-report.sh"
  "scripts/iam_simulate_core.py"
  "scripts/artifact-hygiene.sh"
)
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbit-iam-simulate.XXXXXX")"
results="$tmp_dir/results.txt"
mutation_observations="$tmp_dir/mutation-observations.txt"
mutation_dispatches="$tmp_dir/mutation-dispatches.txt"
failures=0
: >"$mutation_observations"
: >"$mutation_dispatches"
trap 'rm -rf "$tmp_dir"' EXIT

mutation_case_id_from_label() {
  LC_ALL=C tr '[:upper:]' '[:lower:]' <<<"$1" |
    sed -E 's/[^a-z0-9]+/-/g; s/^-//; s/-$//'
}

pass_case() {
  local message=$1 prefix label case_id diagnostic
  if [[ "$message" == *" -> FAIL:"* ]]; then
    prefix=${message%%" -> FAIL:"*}
    label=${prefix% mutation}
    diagnostic="FAIL:${message#*" -> FAIL:"}"
    case_id="$(mutation_case_id_from_label "$label")"
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
  local output rc fail_line case_id action helper
  case_id="$(mutation_case_id_from_label "$label")"
  set +e
  if grep -Fxq "$case_id" "$mutation_dispatches"; then
    output="$("$@" 2>&1)"
  elif action="$(registry_action "$case_id")" && [[ "$action" != *:* ]]; then
    helper=${action%%:*}
    if [ "$1" = "$helper" ]; then
      shift
      output="$(dispatch_registered_mutation "$case_id" "$@" 2>&1)"
    else
      output="$("$@" 2>&1)"
    fi
  else
    output="$("$@" 2>&1)"
  fi
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
  python3 - "$MUTATION_REGISTRY" "${1:-}" "${2:-}" "${3:-}" "${4:-}" <<'PY_REGISTRY'
from pathlib import Path
import re
import sys

registry_path = Path(sys.argv[1])
observations_path = Path(sys.argv[2]) if sys.argv[2] else None
check_helpers = sys.argv[3] == "check-helpers"
helper_names_arg = sys.argv[4]
dispatches_path = Path(sys.argv[5]) if sys.argv[5] else None


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
    if not re.fullmatch(
        r"(?:[A-Za-z_][A-Za-z0-9_]*(?::[A-Za-z0-9_.+-]+)?|sed:[A-Za-z0-9_-]+)",
        action,
    ):
        fail(f"line {line_number} action does not match the closed dispatcher grammar: {action}")
    if case_id in registry:
        fail(f"repeats case id: {case_id}")
    registry[case_id] = (action, diagnostic)
if not registry:
    fail("contains no cases")

if check_helpers:
    helper_names = set(helper_names_arg.splitlines())
    for case_id, (action, _) in registry.items():
        if action.startswith("sed:"):
            continue
        helper = action.split(":", 1)[0]
        if helper not in helper_names:
            fail(f"action does not dispatch for {case_id}: {action}")
    registered_helpers = {
        action.split(":", 1)[0]
        for action, _ in registry.values()
        if not action.startswith("sed:")
    }
    unregistered = sorted(
        helper for helper in helper_names
        if helper.startswith(("mutate_", "registry_mutation_"))
        and helper not in registered_helpers
    )
    if unregistered:
        fail(f"helper has no registry row: {unregistered[0]}")

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
if dispatches_path is None:
    fail("execution validation requires dispatcher observations")
dispatches = dispatches_path.read_text(encoding="utf-8").splitlines()
missing_dispatches = sorted(set(registry) - set(dispatches))
if missing_dispatches:
    fail(f"did not dispatch cases: {', '.join(missing_dispatches)}")
unexpected_dispatches = sorted(set(dispatches) - set(registry))
if unexpected_dispatches:
    fail(f"dispatched unregistered case: {unexpected_dispatches[0]}")
print(
    f"PASS: IAM simulate mutation registry "
    f"({len(observations)}/{len(registry)} executed; restored suite passed)"
)
PY_REGISTRY
}


registry_action() {
  local case_id=$1 registry=${MUTATION_REGISTRY_OVERRIDE:-$MUTATION_REGISTRY}
  awk -F '\t' -v case_id="$case_id" '
    !/^#/ && $1 == case_id { print $2; found += 1 }
    END { if (found != 1) exit 1 }
  ' "$registry"
}

apply_registered_sed() {
  local label=$1 source=$2 destination=$3
  # shellcheck disable=SC2016 # Sed table matches literal shell source.
  case "$label" in
    drop-shared-report-record) sed '/shared_call_case_ids/ d' "$source" >"$destination" ;;
    change-colliding-expectation) sed '0,/"decision":"explicitDeny"/s//"decision":"allowed"/' "$source" >"$destination" ;;
    drop-delete-role-policy-call) sed '/iam delete-role-policy/ d' "$source" >"$destination" ;;
    drop-first-dry-run-call) sed '1d' "$source" >"$destination" ;;
    remove-renderer-account-redacted-check) sed 's/if report.get("account_redacted") is not True:  # role-account-redacted-guard/if False:  # role-account-redacted-guard/' "$source" >"$destination" ;;
    remove-renderer-hygiene-call) sed 's/if ! "$HYGIENE" "${hygiene_inputs\[@\]}"; then  # artifact-hygiene-publication-guard/if false; then  # artifact-hygiene-publication-guard/' "$source" >"$destination" ;;
    remove-renderer-json-hygiene-input) sed 's/hygiene_inputs=("$custom_report")/hygiene_inputs=()/' "$source" >"$destination" ;;
    remove-request-id-ignorecase) sed 's/, re\.IGNORECASE)/)/' "$source" >"$destination" ;;
    *) echo "FAIL: mutation registry sed label does not dispatch: $label" >&2; return 1 ;;
  esac
  if [ -x "$source" ]; then
    chmod +x "$destination"
  fi
}

registry_function_is_noop() {
  local body
  body="$(declare -f "$1" | sed -E '1d; /^[[:space:]]*[{][[:space:]]*$/d; /^[[:space:]]*[}][[:space:]]*$/d; s/[[:space:];]//g; /^$/d')"
  case "$body" in
    :|true|return|return0) return 0 ;;
    *) return 1 ;;
  esac
}

dispatch_registered_mutation() {
  local case_id=$1 action helper submode
  shift
  if ! action="$(registry_action "$case_id")"; then
    echo "FAIL: mutation registry case does not dispatch: $case_id" >&2
    return 1
  fi
  if [[ "$action" == sed:* ]]; then
    printf '%s\n' "$case_id" >>"$mutation_dispatches"
    apply_registered_sed "${action#sed:}" "$@"
    return
  fi
  helper=${action%%:*}
  submode=""
  [ "$helper" = "$action" ] || submode=${action#*:}
  if ! declare -F "$helper" >/dev/null; then
    echo "FAIL: mutation registry action does not dispatch for $case_id: $action" >&2
    return 1
  fi
  if registry_function_is_noop "$helper"; then
    echo "FAIL: mutation registry action is a no-op for $case_id: $helper" >&2
    return 1
  fi
  printf '%s\n' "$case_id" >>"$mutation_dispatches"
  if [ -n "$submode" ]; then
    "$helper" "$submode" "$@"
  else
    "$helper" "$@"
  fi
}

registry_silent_probe() {
  local submode=$1
  [ "$submode" = expected ]
}

# shellcheck disable=SC2329 # Called indirectly by dispatch_registered_mutation.
registry_mutation_probe() {
  local submode=$1
  case "$submode" in
    expected) echo "FAIL: registry mutation probe expected diagnostic" >&2; return 1 ;;
    drift) echo "FAIL: registry mutation probe drifted diagnostic" >&2; return 1 ;;
    *) echo "FAIL: registry mutation probe unknown submode: $submode" >&2; return 1 ;;
  esac
}

run_schema_mutation() {
  local fixture=$1
  python3 "$VALIDATOR" "$VECTOR_FIXTURES/$fixture"
}

mutate_evidence_suffix_check() {
  python3 "$REPO_ROOT/tests/lib/iam-simulate-fixtures.py" \
    mutate-evidence-suffix-check "$@"
}

mutate_evidence_role_check() {
  local submode=$1
  shift
  python3 "$REPO_ROOT/tests/lib/iam-simulate-fixtures.py" \
    mutate-evidence-role-check "$1" "$2" "$submode"
}

validate_generator_drift_scope() {
  local required candidate
  for required in scripts/iam-simulate.sh scripts/iam-simulate-roles.sh; do
    for candidate in "$@"; do
      if [ "$candidate" = "$required" ]; then
        continue 2
      fi
    done
    echo "FAIL: Evidence generator drift scope omits $required" >&2
    return 1
  done
}

mutate_generator_drift_scope() {
  validate_generator_drift_scope \
    scripts/iam-simulate-report.sh \
    scripts/iam_simulate_core.py \
    scripts/artifact-hygiene.sh
}

validate_plan_role_projections() {
  validate_plan_role_projections_with_core "$IAM_SIM_CORE" "$@"
}

validate_plan_role_projections_with_core() {
  python3 - "$1" "$2" "$3" <<'PY_ROLE_PROJECTIONS'
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
core_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("iam_simulate_core_projection_contract", core_path)
if spec is None or spec.loader is None:
    raise SystemExit(f"FAIL: cannot load IAM simulator core: {core_path}")
core = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = core
spec.loader.exec_module(core)
plan = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
role_report = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
try:
    count = core.validate_role_report_projections(plan, role_report)
except core.RunnerFailure as exc:
    raise SystemExit(f"FAIL: {exc}") from exc
print(f"PASS: IAM simulation role projections bind to plan source bytes ({count} projections)")
PY_ROLE_PROJECTIONS
}

run_iam_matrix_evidence_mutation() {
  local submode=$1 custom_report=$2
  if [ "$submode" != empty-hash ]; then
    echo "FAIL: unknown IAM matrix Evidence mutation: $submode" >&2
    return 1
  fi
  TMPDIR="$tmp_dir" IAM_MATRIX_CUSTOM_EVIDENCE_REPORT="$custom_report" \
    IAM_MATRIX_SKIP_NEGATIVES=1 \
    bash "$REPO_ROOT/tests/iam-matrix-contracts.sh"
}

run_iam_matrix_plan_evidence_mutation() {
  local custom_report=$1 role_report=$2
  TMPDIR="$tmp_dir" \
    IAM_MATRIX_CUSTOM_EVIDENCE_REPORT="$custom_report" \
    IAM_MATRIX_ROLE_EVIDENCE_REPORT="$role_report" \
    IAM_MATRIX_SKIP_NEGATIVES=1 \
    bash "$REPO_ROOT/tests/iam-matrix-contracts.sh" \
      "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json"
}

mutate_report_aggregate() {
  local submode=$1 source=$2 destination=$3
  python3 - "$submode" "$source" "$destination" <<'PY_AGGREGATE_MUTANT'
from copy import deepcopy
import json
from pathlib import Path
import sys

submode = sys.argv[1]
source = Path(sys.argv[2])
destination = Path(sys.argv[3])
consumer, lane, field = submode.split("-", 2)
payload = json.loads(source.read_text(encoding="utf-8"))
custom_case = "case:aws_iam_policy.task_boundary:EcsExec:ALL:none:in-boundary"
renderer_role_case = (
    "case:aws_iam_policy.deployer_data:"
    "ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching"
)
evidence_role_case = (
    "case:aws_iam_role_policy.plan_reader_deny:"
    "DenyListBucketOutsideScope:ALL:none:non-protected-resource"
)
case_id = custom_case if lane == "custom" else (
    renderer_role_case if consumer == "renderer" else evidence_role_case
)


def mutate(observation):
    details = observation.get("details")
    if not isinstance(details, list) or not details:
        raise SystemExit("FAIL: aggregate mutation target lacks details")
    if field == "decision":
        observation["decision_observed"] = "doctoredDecision"
    elif field == "sids":
        sids = observation.get("matched_sids")
        if not isinstance(sids, list):
            raise SystemExit("FAIL: aggregate mutation target lacks matched_sids")
        observation["matched_sids"] = sorted([*sids, "DoctoredAggregateSid"])
    else:
        raise SystemExit(f"FAIL: unknown aggregate mutation field: {field}")


records = [record for record in payload["records"] if record.get("case_id") == case_id]
if len(records) != 1:
    raise SystemExit(f"FAIL: aggregate mutation found {len(records)} records for {case_id}")
if lane == "custom":
    mutate(records[0])
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
else:
    destination.mkdir(parents=True, exist_ok=True)
    for view in ("custom_lane", "scp_excluded"):
        variant = deepcopy(payload)
        record = next(item for item in variant["records"] if item["case_id"] == case_id)
        mutate(record[view])
        (destination / f"{view}.json").write_text(
            json.dumps(variant, indent=2) + "\n", encoding="utf-8"
        )
print(case_id)
PY_AGGREGATE_MUTANT
}


mutate_modern_evidence() {
  local submode=$1 custom_source=$2 role_source=$3 provenance_source=$4 destination=$5
  python3 - \
    "$submode" "$custom_source" "$role_source" \
    "$provenance_source" "$destination" <<'PY_MODERN_MUTANT'
import hashlib
import json
from pathlib import Path
import re
import sys

submode = sys.argv[1]
custom_source, role_source, provenance_source, destination = map(Path, sys.argv[2:])
destination.mkdir(parents=True)
custom = json.loads(custom_source.read_text(encoding="utf-8"))
role = json.loads(role_source.read_text(encoding="utf-8"))
provenance = provenance_source.read_text(encoding="utf-8")
custom_path = destination / "custom.json"
role_path = destination / "role.json"
provenance_path = destination / "provenance.md"

if submode == "custom-binding":
    custom["recorded_at"] = "2026-09-10T12:00:00Z"
    role["recorded_at"] = "2026-09-10T12:00:01Z"
elif submode == "role-chronology":
    role["recorded_at"] = "2026-09-09T23:59:59Z"
elif submode == "recorded-at-type":
    custom["recorded_at"] = 42
elif submode != "digest-downgrade":
    raise SystemExit(f"FAIL: unknown modern Evidence mutation: {submode}")

custom_path.write_text(json.dumps(custom, indent=2, sort_keys=True) + "\n", encoding="utf-8")
role_path.write_text(json.dumps(role, indent=2, sort_keys=True) + "\n", encoding="utf-8")
if submode == "digest-downgrade":
    provenance = re.sub(
        r"(?m)^\| (?:custom report sha256|role report sha256|Markdown report sha256) "
        r"\| [0-9a-f]{64} \|\n?",
        "",
        provenance,
    )
else:
    for name, path in (
        ("custom report sha256", custom_path),
        ("role report sha256", role_path),
    ):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        pattern = rf"(?m)^\| {re.escape(name)} \| [0-9a-f]{{64}} \|$"
        provenance, count = re.subn(pattern, f"| {name} | {digest} |", provenance)
        if count != 1:
            raise SystemExit(f"FAIL: modern Evidence mutation found {count} {name} rows")
provenance_path.write_text(provenance, encoding="utf-8")
PY_MODERN_MUTANT
}


validate_mutation_registry

validate_evidence_join() {
  local matrix=$1 custom_report=$2 role_report=$3 rendered_report=$4 provenance=$5
  python3 - \
    "$matrix" "$VECTORS" "$custom_report" "$role_report" \
    "$rendered_report" "$provenance" "$EVIDENCE_POINTER" "$REPO_ROOT" \
    "${EVIDENCE_GENERATOR_FILES[@]}" <<'PY_EVIDENCE'
from __future__ import annotations

from collections import defaultdict
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def load_json(path: Path, description: str):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {description}: {exc}")


def index_records(payload, description: str) -> dict[str, list[dict]]:
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


def load_report_suffix(path: Path) -> str:
    payload = load_json(path, "role evidence report")
    suffixes = set()

    def visit(value):
        if isinstance(value, dict):
            for item in value.values():
                visit(item)
        elif isinstance(value, list):
            for item in value:
                visit(item)
        elif isinstance(value, str):
            prefix = "arn:aws:iam::000000000000:role/"
            if value.startswith(prefix):
                role_name = value.removeprefix(prefix)
                match = re.fullmatch(r"orbit-infra-(.+)-plan-reader", role_name)
                if match is not None:
                    suffixes.add(match.group(1))
            if value.startswith("{"):
                try:
                    nested = json.loads(value)
                except json.JSONDecodeError:
                    return
                visit(nested)

    visit(payload)
    if len(suffixes) != 1:
        fail(
            "role evidence report must record exactly one plan-reader suffix, "
            f"found {sorted(suffixes)}"
        )
    return next(iter(suffixes))


def rendered_resource_matches(template: str, observed: str) -> bool:
    pattern = re.escape(template)
    pattern = pattern.replace(re.escape("${ACCOUNT_ID}"), "000000000000")
    pattern = pattern.replace(re.escape("${SUFFIX}"), re.escape(report_suffix))
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


def aggregates_match_details(observation: dict) -> bool:
    details = observation.get("details")
    if not isinstance(details, list):
        return True
    if not details:
        return False
    decisions = {}
    matched_sids = set()
    actions = set()
    resources = set()
    for detail in details:
        if not isinstance(detail, dict):
            return False
        action = detail.get("action_name")
        resource = detail.get("resource_arn")
        decision = detail.get("decision_observed")
        sids = detail.get("matched_sids")
        if (
            not isinstance(action, str)
            or not action
            or not isinstance(resource, str)
            or not resource
            or not isinstance(decision, str)
            or not decision
            or not isinstance(sids, list)
            or any(not isinstance(sid, str) or not sid for sid in sids)
        ):
            return False
        pair = (action, resource)
        if pair in decisions:
            return False
        decisions[pair] = decision
        matched_sids.update(sids)
        actions.add(action)
        resources.add(resource)
    if len(resources) > 1 and len(actions) == 1:
        action = next(iter(actions))
        aggregate_decision = {
            resource: decisions[(action, resource)]
            for resource in sorted(resources)
        }
    elif len(set(decisions.values())) == 1:
        aggregate_decision = next(iter(decisions.values()))
    else:
        aggregate_decision = {
            f"{action}|{resource}": decision
            for (action, resource), decision in sorted(decisions.items())
        }
    return (
        observation.get("decision_observed") == aggregate_decision
        and observation.get("matched_sids") == sorted(matched_sids)
    )


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
        if not aggregates_match_details(evidence):
            return False
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
    custom_lane = record.get("custom_lane")
    expectation = vector.get("expect")
    return (
        "runner_failure" not in record
        and isinstance(evidence, dict)
        and isinstance(custom_lane, dict)
        and isinstance(expectation, dict)
        and aggregates_match_details(custom_lane)
        and aggregates_match_details(evidence)
        and observation_matches(vector, evidence)
    )


def submitted_hashes(record: dict, lane: str) -> list[str] | None:
    entries = record.get("document_hashes_submitted", {}).get(lane)
    if not isinstance(entries, list):
        return None
    hashes = [entry.get("sha256") for entry in entries if isinstance(entry, dict)]
    if len(hashes) != len(entries) or any(not isinstance(value, str) for value in hashes):
        return None
    return hashes


def role_hash_chain(custom: dict, role: dict) -> str | None:
    custom_hashes = submitted_hashes(custom, "policy_input_list")
    role_hashes = submitted_hashes(role, "custom_lane")
    if (
        custom_hashes is None
        or role_hashes is None
        or len(custom_hashes) != len(set(custom_hashes))
        or len(role_hashes) != len(set(role_hashes))
        or set(custom_hashes) != set(role_hashes)
    ):
        return "custom-to-role"
    projection_ref = role.get("projection")
    if not isinstance(projection_ref, dict):
        return "source-document"
    projection_id = projection_ref.get("projection_id")
    projections = [
        item for item in role_payload.get("projection", {}).get("roles", [])
        if isinstance(item, dict) and item.get("projection_id") == projection_id
    ]
    if len(projections) != 1:
        return "source-document"
    projection = projections[0]
    sources = projection.get("source_documents")
    if not isinstance(sources, list):
        return "source-document"
    source_hashes = {
        item.get("sha256") for item in sources
        if isinstance(item, dict) and isinstance(item.get("address"), str)
        and isinstance(item.get("sha256"), str)
    }
    if not set(custom_hashes) <= source_hashes:
        return "source-document"
    policy_document = projection.get("policy_document")
    policy_sha256 = projection_ref.get("policy_sha256")
    if not isinstance(policy_document, str) or not isinstance(policy_sha256, str):
        return "projection-policy"
    document_hash = hashlib.sha256(policy_document.encode("utf-8")).hexdigest()
    if "recorded_at" in role_payload:
        redacted_policy_sha256 = projection.get("redacted_policy_sha256")
        if (
            not isinstance(redacted_policy_sha256, str)
            or document_hash != redacted_policy_sha256
        ):
            return "projection-policy"
    elif document_hash != policy_sha256:
        return "projection-policy"
    put_hashes = submitted_hashes(role, "put_role_policy")
    if put_hashes != [policy_sha256]:
        return "put-role-policy"
    return None


matrix_path = Path(sys.argv[1])
vectors = load_vectors(Path(sys.argv[2]))
custom_path = Path(sys.argv[3])
role_path = Path(sys.argv[4])
rendered_path = Path(sys.argv[5])
provenance_path = Path(sys.argv[6])
expected_pointer = sys.argv[7]
repo_root = Path(sys.argv[8])
generator_files = sys.argv[9:]
custom_payload = load_json(custom_path, "custom evidence report")
role_payload = load_json(role_path, "role evidence report")
custom_records = index_records(custom_payload, "custom evidence report")
role_records = index_records(role_payload, "role evidence report")
report_suffix = load_report_suffix(role_path)
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
supplied_reports = [
    ("custom", custom_payload),
    ("role", role_payload),
]
modern_fields = ["recorded_at" in payload for _, payload in supplied_reports]
modern = any(modern_fields)
if modern:
    if not all(modern_fields):
        fail("all supplied reports must carry recorded_at or all must be legacy")
    parsed_recorded_at = {}
    for label, payload in supplied_reports:
        try:
            parsed_recorded_at[label] = datetime.strptime(
                payload["recorded_at"], "%Y-%m-%dT%H:%M:%SZ"
            )
        except (TypeError, ValueError):
            fail(f"{label} report recorded_at must be UTC YYYY-MM-DDTHH:MM:SSZ")
    if parsed_recorded_at["role"] < parsed_recorded_at["custom"]:
        fail("role report recorded_at precedes custom report recorded_at")
    if parsed_recorded_at["custom"].strftime("%Y-%m-%d") != recorded_on:
        fail("provenance recorded_on does not match custom report recorded_at date")
    expected_custom_digest = hashlib.sha256(custom_path.read_bytes()).hexdigest()
    if role_payload.get("custom_report_sha256") != expected_custom_digest:
        fail(
            "role report custom_report_sha256 does not match the exact custom report bytes"
        )
generator_matches = re.findall(
    r"^\| generator commit \| ([0-9a-f]+) \|$", provenance_text, re.MULTILINE
)
if len(generator_matches) != 1:
    fail("provenance must contain exactly one generator commit")
generator_commit = generator_matches[0]
if subprocess.run(
    ["git", "cat-file", "-e", f"{generator_commit}^{{commit}}"],
    cwd=repo_root,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
).returncode != 0:
    fail(f"Evidence generator commit is unknown: {generator_commit}")
if subprocess.run(
    ["git", "merge-base", "--is-ancestor", generator_commit, "HEAD"],
    cwd=repo_root,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
).returncode != 0:
    fail(f"Evidence generator commit is not an ancestor of HEAD: {generator_commit}")
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
if (modern or provenance_digests) and set(provenance_digests) != set(digest_paths):
    missing = next(name for name in digest_paths if name not in provenance_digests)
    fail(f"provenance digest set is incomplete: missing {missing}")
for name, recorded_digest in provenance_digests.items():
    if recorded_digest != computed_digests[name]:
        fail(
            f"provenance digest mismatch for {name}: "
            f"recorded={recorded_digest} computed={computed_digests[name]}"
        )
if (modern or provenance_digests) and subprocess.run(
    [
        "git", "diff", "--quiet", generator_commit, "HEAD", "--",
        *generator_files,
    ],
    cwd=repo_root,
).returncode != 0:
    fail(f"Evidence generator drift since generator commit: {generator_commit}")

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
        if len(custom) != 1:
            return None
        broken_link = role_hash_chain(custom[0], role[0])
        if broken_link is not None:
            fail(f"Evidence role hash chain {broken_link} mismatch for case: {case_id}")
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
    "simulator-decision": 233,
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
if sum(counts.values()) != 290:
    fail(f"taxonomy category sum is {sum(counts.values())}, expected 290")
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

  mutated="$(dispatch_registered_mutation taxonomy-added-case)"
  expect_failure "taxonomy added case" "contains case absent from matrix" \
    validate_taxonomy "$mutated"
  mutated="$(dispatch_registered_mutation taxonomy-removed-case)"
  expect_failure "taxonomy removed case" "omits matrix case" \
    validate_taxonomy "$mutated"
  mutated="$(dispatch_registered_mutation taxonomy-duplicate-category)"
  expect_failure "taxonomy duplicate category" "appears in two categories" \
    validate_taxonomy "$mutated"
  mutated="$(dispatch_registered_mutation taxonomy-empty-reason)"
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
  if [ "$round_trip_ok" -eq 1 ] && [ "$round_trip_count" -eq 290 ]; then
    pass_case "case-id exact-prefix round trip over 290 cases"
  else
    fail_case "case-id exact-prefix round trip over 290 cases" \
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
     [ "$(wc -l <<<"$output" | tr -d ' ')" -eq 241 ] && \
     [ "$(jq -s 'map(.case_id) | unique | length' <<<"$output")" -eq 241 ]; then
    pass_case "schema validator loads the vector directory in one JSONL pass"
  else
    fail_case "schema validator loads the vector directory in one JSONL pass" "$output"
  fi

  if output="$(python3 - \
    "$VECTORS/aws_iam_policy.deployer_data__SnsSubscriptionManage.json" 2>&1 <<'PY_SNS_RESOURCE_CASE'
import json
from pathlib import Path
import sys


payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
case_id = (
    "case:aws_iam_policy.deployer_data:SnsSubscriptionManage:"
    "ALL:resource:supplied"
)
matches = [case for case in payload.get("cases", []) if case.get("case_id") == case_id]
if len(matches) != 1:
    raise SystemExit(
        f"FAIL: SNS resource-supplied decision case count is {len(matches)}, expected 1"
    )
expected = {
    "case_id": case_id,
    "simulation_mode": "custom",
    "assertion_kind": "decision",
    "action_names": [
        "sns:GetSubscriptionAttributes",
        "sns:SetSubscriptionAttributes",
        "sns:Unsubscribe",
    ],
    "resource_arns": [
        "arn:aws:sns:us-east-1:${ACCOUNT_ID}:orbit-infra-${SUFFIX}-preview"
    ],
    "context_entries": [{
        "ContextKeyName": "aws:ResourceTag/Project",
        "ContextKeyValues": ["orbit-infra"],
        "ContextKeyType": "string",
    }],
    "expect": {
        "decision": "implicitDeny",
        "matched_sid_required": [],
        "matched_sid_forbidden": ["SnsSubscriptionManage"],
    },
}
if matches[0] != expected:
    raise SystemExit("FAIL: SNS resource-supplied decision case differs from contract")
print("PASS: SNS resource-supplied star-only decision case")
PY_SNS_RESOURCE_CASE
  )"; then
    pass_case "${output#PASS: }"
  else
    fail_case "SNS resource-supplied star-only decision case" "$output"
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
    dispatch_registered_mutation schema-missing-decision
  expect_failure "schema attribution decision" \
    "expect.decision is forbidden for attribution-only" \
    dispatch_registered_mutation schema-attribution-decision
  expect_failure "schema isolated statement on non-isolated mode" \
    "isolated_statement is forbidden for custom" \
    dispatch_registered_mutation schema-isolated-statement-on-non-isolated-mode
  expect_failure "schema isolated allowed decision" \
    "custom-isolated vectors cannot expect allowed" \
    dispatch_registered_mutation schema-isolated-allowed-decision
  expect_failure "schema embedded custom policy" \
    "policy_input_list is forbidden for custom vectors; resolve repository policies from the plan" \
    dispatch_registered_mutation schema-embedded-custom-policy
  expect_failure "schema embedded isolated statement" \
    "isolated_statement is forbidden for custom-isolated vectors; resolve repository policies from the plan" \
    dispatch_registered_mutation schema-embedded-isolated-statement
  expect_failure "schema literal account id" "literal 12-digit account id" \
    dispatch_registered_mutation schema-literal-account-id
  expect_failure "schema unknown context type" "unknown ContextKeyType" \
    dispatch_registered_mutation schema-unknown-context-type
  expect_failure "schema unknown case id" "case_id is absent from categories.json" \
    dispatch_registered_mutation schema-unknown-case-id
  expect_failure "schema unknown custom field" "unexpected is forbidden for custom vectors" \
    dispatch_registered_mutation schema-unknown-custom-field
  expect_failure "schema envelope header mismatch" "case_id prefix does not match envelope header" \
    dispatch_registered_mutation schema-envelope-header-mismatch
  expect_failure "schema duplicate case" "envelope repeats case_id" \
    dispatch_registered_mutation schema-duplicate-case
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
)" && grep -Fq "(240 case(s) in 81 envelope(s), 1 unresolved)" <<< "$output"; then
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
if output="$(python3 - "$REPO_ROOT/docs/RUNBOOKS.md" 2>&1 <<'PY_ROLE_HASH_DOC'
from pathlib import Path
import sys


text = Path(sys.argv[1]).read_text(encoding="utf-8")
required = (
    "`redacted_policy_sha256`",
    "redacted `policy_document`",
    "`policy_sha256`",
)
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"FAIL: RUNBOOKS role-report hash field note is missing {missing[0]}")
print("PASS: RUNBOOKS distinguishes raw and redacted role-policy digests")
PY_ROLE_HASH_DOC
)"; then
  pass_case "${output#PASS: }"
else
  fail_case "RUNBOOKS role-report field note" "$output"
fi

if output="$(python3 - \
  "$REPO_ROOT/TODO.md" "$MATRIX" "$REPO_ROOT/bootstrap/roles.tf" \
  2>&1 <<'PY_PACKET_DOCS'
from pathlib import Path
import re
import sys


todo, matrix, roles = (
    Path(path).read_text(encoding="utf-8") for path in sys.argv[1:]
)
for item in ("P5-38", "P5-39", "P5-40", "P5-41"):
    matches = re.findall(rf"(?m)^- \[ \] {item}:.*$", todo)
    if (
        len(matches) != 1
        or "parked behind P0-3b" not in matches[0]
        or "real-AWS evidence required" not in matches[0]
    ):
        raise SystemExit(
            f"FAIL: TODO {item} is not parked behind P0-3b with a real-AWS reason"
        )
if not re.search(r"(?m)^- \[ \] P5-68:.*\.terraform/modules/.*$", todo):
    raise SystemExit(
        "FAIL: TODO P5-68 does not file the Terraform module-cache exemption ordering finding"
    )
follow_ups = {
    "P5-38": "context population is unverified",
    "P5-39": "route53:VPCs population is unverified",
    "P5-40": "operation-to-namespace resolution is unverified",
    "P5-41": "per-session network ARNs are runtime-only",
}
for item, reason in follow_ups.items():
    if f"TODO {item}; deferred P0-3b: {reason}" not in matrix:
        raise SystemExit(
            f"FAIL: IAM matrix Follow-up for {item} lacks its P0-3b reason"
        )
if "iam-condition-keys.md" in roles or roles.count("docs/evidence/iam-matrix.md") != 18:
    raise SystemExit(
        "FAIL: bootstrap role comments do not cite docs/evidence/iam-matrix.md at all 18 sites"
    )
print("PASS: P0-3b deferrals, P5-68 filing, and matrix citations")
PY_PACKET_DOCS
)"; then
  pass_case "${output#PASS: }"
else
  fail_case "P0-3b deferrals and packet documentation" "$output"
fi
if output="$(validate_generator_drift_scope "${EVIDENCE_GENERATOR_FILES[@]}" 2>&1)"; then
  pass_case "Evidence generator drift scope includes both simulator runners"
else
  fail_case "Evidence generator runner drift scope" "$output"
fi
expect_failure "evidence generator runner drift scope" \
  "Evidence generator drift scope omits scripts/iam-simulate.sh" \
  dispatch_registered_mutation evidence-generator-runner-drift-scope

recorded_projection_plan="$tmp_dir/role-projection-recorded-plan.json"
cp -- "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" "$recorded_projection_plan"

account_projection_plan="$tmp_dir/role-projection-live-account-plan.json"
account_projection_report="$tmp_dir/role-projection-redacted-report.json"
account_projection_core_mutant="$tmp_dir/iam-simulate-core-unredacted-projection.py"
account_projection_custom="$tmp_dir/role-projection-live-account-custom.json"
account_projection_missing="$tmp_dir/role-projection-redacted-hash-missing.json"
renderer_live_hash_case="case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching"
renderer_mutation_case="case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:absent"
renderer_hash_render="$tmp_dir/renderer-redacted-hash-live"
python3 "$REPO_ROOT/tests/lib/iam-simulate-fixtures.py" \
  build-role-projection-account-redaction \
  "$recorded_projection_plan" \
  "$ROLE_EVIDENCE_REPORT" "$account_projection_plan" \
  "$account_projection_report" \
  "$CUSTOM_EVIDENCE_REPORT" "$account_projection_custom"
if output="$(validate_plan_role_projections \
  "$account_projection_plan" "$account_projection_report" 2>&1)"; then
  pass_case "role projection comparison accepts report-redacted account ids"
else
  fail_case "role projection report account redaction" "$output"
fi
dispatch_registered_mutation evidence-role-projection-account-redaction \
  "$IAM_SIM_CORE" "$account_projection_core_mutant"
expect_failure "evidence role projection account redaction" \
  "role projection source policy differs for deployer:aws_iam_policy.deployer_data" \
  validate_plan_role_projections_with_core "$account_projection_core_mutant" \
    "$account_projection_plan" "$account_projection_report"
if output="$(validate_plan_role_projections \
  "$account_projection_plan" "$account_projection_report" 2>&1)"; then
  pass_case "evidence role projection account redaction mutation restored PASS"
else
  fail_case "evidence role projection account redaction mutation restoration" "$output"
fi

dispatch_registered_mutation evidence-role-projection-redacted-hash-required \
  "$account_projection_report" "$account_projection_missing"
expect_failure "evidence role projection redacted hash required" \
  "role projection redacted sha256 differs for plan-reader:combined" \
  validate_plan_role_projections \
    "$account_projection_plan" "$account_projection_missing"

if output="$(
  {
    run_report_renderer "$IAM_SIM_REPORT_RENDERER" \
      "$account_projection_custom" "$account_projection_report" \
      "$renderer_hash_render"
    validate_renderer_role_passing \
      "$renderer_hash_render/IAM_SIMULATION_REPORT.md" "$renderer_live_hash_case"
  } 2>&1
)"; then
  pass_case "renderer accepts live-account redacted projection hash chain"
else
  fail_case "renderer live-account redacted projection hash chain" "$output"
fi

while IFS='|' read -r mutation_id mutation_source mutation_custom mutation diagnostic; do
  mutation_role="$tmp_dir/$mutation_id.json"
  mutation_render="$tmp_dir/rendered-$mutation_id"
  dispatch_registered_mutation "$mutation_id" \
    "$mutation_source" "$mutation_role"
  if output="$(
    run_report_renderer "$IAM_SIM_REPORT_RENDERER" \
      "$mutation_custom" "$mutation_role" "$mutation_render"
    python3 "$REPO_ROOT/tests/lib/iam-simulate-fixtures.py" \
      validate-renderer-role-outcome \
      "$mutation_render/IAM_SIMULATION_REPORT.md" "$renderer_mutation_case"
  )"; then
    pass_case "$mutation_id mutation -> FAIL: $diagnostic: $renderer_mutation_case"
  else
    fail_case "$mutation_id" "$output"
  fi
done <<HASH_MUTATIONS
renderer-role-redacted-digest-doctored|$account_projection_report|$account_projection_custom|digest|renderer accepted doctored redacted_policy_sha256
renderer-role-redacted-document-doctored|$account_projection_report|$account_projection_custom|document|renderer accepted doctored redacted policy_document
renderer-role-redacted-hash-missing-live|$account_projection_report|$account_projection_custom|missing|renderer accepted live-account report without redacted_policy_sha256
renderer-role-redacted-hash-missing-placeholder|$ROLE_EVIDENCE_REPORT|$CUSTOM_EVIDENCE_REPORT|missing|renderer accepted recorded_at report without redacted_policy_sha256
HASH_MUTATIONS

placeholder_missing_role="$tmp_dir/renderer-redacted-hash-placeholder-missing.json"
placeholder_missing_render="$tmp_dir/renderer-redacted-hash-placeholder-missing"
branch_mutant="$tmp_dir/iam-simulate-report-redacted-hash-branch-mutant.sh"
dispatch_registered_mutation renderer-role-redacted-hash-missing-placeholder \
  "$ROLE_EVIDENCE_REPORT" "$placeholder_missing_role"
dispatch_registered_mutation renderer-role-redacted-hash-recorded-at-branch \
  "$IAM_SIM_REPORT_RENDERER" "$branch_mutant"
if output="$(
  {
    run_report_renderer "$branch_mutant" \
      "$CUSTOM_EVIDENCE_REPORT" "$placeholder_missing_role" \
      "$placeholder_missing_render"
    validate_renderer_role_passing \
      "$placeholder_missing_render/IAM_SIMULATION_REPORT.md" "$renderer_mutation_case"
  } 2>&1
)"; then
  pass_case "renderer role redacted hash recorded at branch mutation -> FAIL: renderer accepted recorded_at report without redacted_policy_sha256: $renderer_mutation_case"
else
  fail_case "renderer role redacted hash recorded at branch" "$output"
fi

if output="$(validate_plan_role_projections \
  "$recorded_projection_plan" \
  "$ROLE_EVIDENCE_REPORT" 2>&1)"; then
  pass_case "${output#PASS: }"
else
  fail_case "IAM simulation role projections bind to plan source bytes" "$output"
fi
projection_source_plan="$tmp_dir/role-projection-source-bytes-plan.json"
projection_source_id="$(dispatch_registered_mutation \
  evidence-role-projection-source-hashes \
  "$recorded_projection_plan" \
  "$projection_source_plan")"
expect_failure "evidence role projection source hashes" \
  "role projection source documents differ for $projection_source_id" \
  validate_plan_role_projections "$projection_source_plan" "$ROLE_EVIDENCE_REPORT"
if output="$(validate_plan_role_projections \
  "$recorded_projection_plan" \
  "$ROLE_EVIDENCE_REPORT" 2>&1)"; then
  pass_case "evidence role projection source hashes mutation restored PASS"
else
  fail_case "evidence role projection source hashes mutation restoration" "$output"
fi

projection_mutant="$tmp_dir/role-projection-source-binding-mutant.json"
projection_id="$(dispatch_registered_mutation \
  evidence-role-projection-source-binding \
  "$ROLE_EVIDENCE_REPORT" "$projection_mutant")"
expect_failure "evidence role projection source binding" \
  "role projection source policy differs for $projection_id" \
  validate_plan_role_projections \
    "$recorded_projection_plan" "$projection_mutant"
if output="$(validate_plan_role_projections \
  "$recorded_projection_plan" \
  "$ROLE_EVIDENCE_REPORT" 2>&1)"; then
  pass_case "evidence role projection source binding mutation restored PASS"
else
  fail_case "evidence role projection source binding mutation restoration" "$output"
fi

if output="$(
  validate_evidence_join \
    "$MATRIX" "$CUSTOM_EVIDENCE_REPORT" "$ROLE_EVIDENCE_REPORT" \
    "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE" 2>&1
)"; then
  pass_case "${output#PASS: }"
else
  fail_case "IAM simulation Evidence join" "$output"
fi

rebind_role_report_to_custom() {
  local custom_report=$1 role_source=$2 role_out=$3
  local custom_sha256 role_tmp
  custom_sha256="$(shasum -a 256 "$custom_report" | awk '{print $1}')"
  role_tmp="${role_out}.tmp"
  mkdir -p "$(dirname "$role_out")"
  jq --arg custom_sha256 "$custom_sha256" \
    '.custom_report_sha256 = $custom_sha256' \
    "$role_source" >"$role_tmp"
  mv -- "$role_tmp" "$role_out"
}

write_bound_evidence_provenance() {
  local custom_report=$1 role_report=$2 rendered_report=$3 provenance_out=$4
  local provenance_source=${5:-$EVIDENCE_PROVENANCE}
  local custom_sha256 role_sha256 markdown_sha256 provenance_tmp
  custom_sha256="$(shasum -a 256 "$custom_report" | awk '{print $1}')"
  role_sha256="$(shasum -a 256 "$role_report" | awk '{print $1}')"
  markdown_sha256="$(shasum -a 256 "$rendered_report" | awk '{print $1}')"
  provenance_tmp="${provenance_out}.tmp"
  mkdir -p "$(dirname "$provenance_out")"
  awk \
    -v custom_sha256="$custom_sha256" \
    -v role_sha256="$role_sha256" \
    -v markdown_sha256="$markdown_sha256" '
      /^\| custom report sha256 \| [0-9a-f]{64} \|$/ {
        print "| custom report sha256 | " custom_sha256 " |"
        custom_count++
        next
      }
      /^\| role report sha256 \| [0-9a-f]{64} \|$/ {
        print "| role report sha256 | " role_sha256 " |"
        role_count++
        next
      }
      /^\| Markdown report sha256 \| [0-9a-f]{64} \|$/ {
        print "| Markdown report sha256 | " markdown_sha256 " |"
        markdown_count++
        next
      }
      { print }
      END {
        if (custom_count != 1 || role_count != 1 || markdown_count != 1) {
          exit 1
        }
      }
    ' "$provenance_source" >"$provenance_tmp"
  mv -- "$provenance_tmp" "$provenance_out"
}

validate_renderer_aggregate_refusal() {
  local scope=$1 custom_report=$2 role_input=$3 output_root=$4 case_id=$5
  local role_report rendered expected_yes expected_no output
  local -a role_reports
  if [ "$scope" = custom ]; then
    role_reports=("$role_input")
    expected_yes=0
    expected_no=1
  else
    role_reports=("$role_input"/*.json)
    expected_yes=1
    expected_no=1
  fi
  for role_report in "${role_reports[@]}"; do
    rendered="$output_root/$(basename "$role_report" .json)"
    if ! output="$(
      run_report_renderer \
        "$IAM_SIM_REPORT_RENDERER" "$custom_report" \
        "$role_report" "$rendered" \
        2>&1
    )"; then
      printf '%s\n' "$output" >&2
      return 1
    fi
    if ! python3 - \
      "$rendered/IAM_SIMULATION_REPORT.md" "$case_id" \
      "$expected_yes" "$expected_no" <<'PY_RENDERED_AGGREGATE'
from pathlib import Path
import sys

report = Path(sys.argv[1]).read_text(encoding="utf-8")
case_id = sys.argv[2]
rows = [line for line in report.splitlines() if line.startswith(f"| {case_id} |")]
yes = sum(line.endswith("| yes |") for line in rows)
no = sum(line.endswith("| no |") for line in rows)
if (yes, no) != (int(sys.argv[3]), int(sys.argv[4])):
    raise SystemExit(
        f"FAIL: renderer aggregate refusal differs: case={case_id} yes={yes} no={no}"
    )
PY_RENDERED_AGGREGATE
    then
      return 1
    fi
  done
}


validate_evidence_aggregate_refusal() {
  local scope=$1 custom_report=$2 role_input=$3 case_id=$4
  local role_report provenance output rc
  local -a role_reports
  if [ "$scope" = custom ]; then
    role_reports=("$role_input")
  else
    role_reports=("$role_input"/*.json)
  fi
  for role_report in "${role_reports[@]}"; do
    provenance="$tmp_dir/evidence-aggregate-$(basename "$custom_report")-$(basename "$role_report").md"
    write_bound_evidence_provenance \
      "$custom_report" "$role_report" "$RENDERED_EVIDENCE_REPORT" \
      "$provenance"
    set +e
    output="$(
      validate_evidence_join \
        "$MATRIX" "$custom_report" "$role_report" \
        "$RENDERED_EVIDENCE_REPORT" "$provenance" 2>&1
    )"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] || ! grep -Fq \
      "FAIL: promoted case is not execution-matching: $case_id" <<<"$output"; then
      printf 'FAIL: Evidence aggregate refusal differs: rc=%s output=%s\n' \
        "$rc" "$output" >&2
      return 1
    fi
  done
  printf 'FAIL: promoted case is not execution-matching: %s\n' "$case_id"
}

aggregate_mutants="$tmp_dir/aggregate-mutants"
for consumer in renderer evidence; do
  for lane in custom role; do
    for field in decision sids; do
      label="$consumer $lane aggregate $field"
      mutation_id="${consumer}-${lane}-aggregate-${field}"
      mutation_root="$aggregate_mutants/$mutation_id"
      if [ "$lane" = custom ]; then
        custom_mutant="$mutation_root.json"
        role_mutant="$mutation_root-role.json"
        case_id="$(dispatch_registered_mutation \
          "$mutation_id" "$CUSTOM_EVIDENCE_REPORT" "$custom_mutant")"
        rebind_role_report_to_custom \
          "$custom_mutant" "$ROLE_EVIDENCE_REPORT" "$role_mutant"
      else
        custom_mutant="$CUSTOM_EVIDENCE_REPORT"
        role_mutant="$mutation_root"
        case_id="$(dispatch_registered_mutation \
          "$mutation_id" "$ROLE_EVIDENCE_REPORT" "$role_mutant")"
      fi
      if [ "$consumer" = renderer ]; then
        if output="$(validate_renderer_aggregate_refusal \
          "$lane" "$custom_mutant" "$role_mutant" \
          "$aggregate_mutants/rendered-$mutation_id" "$case_id" 2>&1)"; then
          pass_case "$label mutation -> FAIL: renderer accepted doctored $lane aggregate $field: $case_id"
        else
          fail_case "$label mutation" "$output"
        fi
      elif output="$(validate_evidence_aggregate_refusal \
        "$lane" "$custom_mutant" "$role_mutant" "$case_id" 2>&1)"; then
        pass_case "$label mutation -> $output"
      else
        fail_case "$label mutation" "$output"
      fi
    done
  done
done

if output="$(validate_evidence_join \
  "$MATRIX" "$CUSTOM_EVIDENCE_REPORT" "$ROLE_EVIDENCE_REPORT" \
  "$RENDERED_EVIDENCE_REPORT" "$EVIDENCE_PROVENANCE" 2>&1)"; then
  pass_case "Evidence aggregate mutations restored PASS"
else
  fail_case "Evidence aggregate mutation restoration" "$output"
fi

modern_evidence="$tmp_dir/modern-evidence"
modern_custom="$modern_evidence/custom.json"
modern_role="$modern_evidence/role.json"
modern_matrix="$modern_evidence/matrix.md"
modern_render="$modern_evidence/rendered"
mkdir -p "$modern_evidence"
python3 "$REPO_ROOT/tests/lib/iam-simulate-fixtures.py" build-modern-evidence \
  "$CUSTOM_EVIDENCE_REPORT" "$ROLE_EVIDENCE_REPORT" \
  "$modern_custom" "$modern_role"
sed 's/AWS-SIMULATED 2026-09-12 /AWS-SIMULATED 2026-09-10 /g' \
  "$MATRIX" >"$modern_matrix"
if [ "$(grep -o 'AWS-SIMULATED 2026-09-10 ' "$modern_matrix" | wc -l | tr -d ' ')" -ne 220 ]; then
  fail_case "modern Evidence matrix fixture" "expected 220 synthetic 2026-09-10 labels"
fi
if output="$(
  "$IAM_SIM_REPORT_RENDERER" \
    --custom-report "$modern_custom" --role-report "$modern_role" \
    --out-dir "$modern_render" 2>&1
)" && join_output="$(validate_evidence_join \
  "$modern_matrix" "$modern_custom" "$modern_role" \
  "$modern_render/IAM_SIMULATION_REPORT.md" \
  "$modern_render/IAM_SIMULATION_PROVENANCE.md" 2>&1)" && \
  python3 - "$modern_custom" "$modern_role" \
    "$modern_render/IAM_SIMULATION_PROVENANCE.md" <<'PY_MODERN_EVIDENCE'
import hashlib
import json
from pathlib import Path
import re
import sys

custom_path, role_path, provenance_path = map(Path, sys.argv[1:])
custom = json.loads(custom_path.read_text(encoding="utf-8"))
role = json.loads(role_path.read_text(encoding="utf-8"))
provenance = provenance_path.read_text(encoding="utf-8")
if custom.get("recorded_at") != "2026-09-10T00:00:00Z":
    raise SystemExit("FAIL: modern custom report recorded_at fixture changed")
if role.get("custom_report_sha256") != hashlib.sha256(custom_path.read_bytes()).hexdigest():
    raise SystemExit("FAIL: modern role report custom_report_sha256 does not bind exact bytes")
if not re.search(r"(?m)^\| recorded_on \| 2026-09-10 \|$", provenance):
    raise SystemExit("FAIL: modern provenance recorded_on differs from custom lane date")
PY_MODERN_EVIDENCE
then
  pass_case "IAM simulation modern Evidence join -> $join_output"
else
  fail_case "IAM simulation modern Evidence join" "${output:-${join_output:-validation failed}}"
fi

if [ "$failures" -eq "$group_failures" ]; then
  while IFS='|' read -r mutation_id mutation_label mutation_diagnostic; do
    mutation_root="$modern_evidence/$mutation_id"
    dispatch_registered_mutation "$mutation_id" \
      "$modern_custom" "$modern_role" \
      "$modern_render/IAM_SIMULATION_PROVENANCE.md" "$mutation_root"
    expect_failure "$mutation_label" "$mutation_diagnostic" \
      validate_evidence_join \
        "$modern_matrix" "$mutation_root/custom.json" "$mutation_root/role.json" \
        "$modern_render/IAM_SIMULATION_REPORT.md" "$mutation_root/provenance.md"
  done <<'MODERN_EVIDENCE_MUTATIONS'
evidence-modern-custom-report-binding|evidence modern custom report binding|role report custom_report_sha256 does not match the exact custom report bytes
evidence-modern-role-chronology|evidence modern role chronology|role report recorded_at precedes custom report recorded_at
evidence-modern-recorded-at-type|evidence modern recorded at type|custom report recorded_at must be UTC YYYY-MM-DDTHH:MM:SSZ
evidence-modern-digest-downgrade|evidence modern digest downgrade|provenance digest set is incomplete: missing custom report sha256
MODERN_EVIDENCE_MUTATIONS

  for digest_mutation in doctored missing; do
    digest_provenance="$modern_evidence/provenance-$digest_mutation.md"
    dispatch_registered_mutation "evidence-provenance-digest-$digest_mutation" \
      "$modern_render/IAM_SIMULATION_PROVENANCE.md" "$digest_provenance"
    if [ "$digest_mutation" = doctored ]; then
      digest_diagnostic="provenance digest mismatch for custom report sha256:"
    else
      digest_diagnostic="provenance digest set is incomplete: missing custom report sha256"
    fi
    expect_failure "evidence provenance digest $digest_mutation" \
      "$digest_diagnostic" validate_evidence_join \
      "$modern_matrix" "$modern_custom" "$modern_role" \
      "$modern_render/IAM_SIMULATION_REPORT.md" "$digest_provenance"
  done

  for recording_mutation in recorded-at custom-report-binding; do
    recording_custom="$modern_evidence/custom-$recording_mutation.json"
    recording_role="$modern_evidence/role-$recording_mutation.json"
    if [ "$recording_mutation" = recorded-at ]; then
      recording_case="renderer-recorded-at-date"
      recording_diagnostic="role report recorded_at precedes custom report recorded_at"
      recording_label="renderer recorded at date"
    else
      recording_case="renderer-custom-report-binding"
      recording_diagnostic="role report custom_report_sha256 does not match the exact custom report bytes"
      recording_label="renderer custom report binding"
    fi
    dispatch_registered_mutation "$recording_case" \
      "$modern_custom" "$modern_role" "$recording_custom" "$recording_role"
    expect_failure "$recording_label" "$recording_diagnostic" \
      "$IAM_SIM_REPORT_RENDERER" --custom-report "$recording_custom" \
      --role-report "$recording_role" \
      --out-dir "$modern_evidence/rendered-$recording_mutation"
  done
  expect_failure "renderer recorded on modern refusal" \
    "--recorded-on is only valid for legacy reports without recorded_at" \
    dispatch_registered_mutation renderer-recorded-on-modern-refusal \
      "$modern_custom" "$modern_role" \
      "$modern_evidence/rendered-modern-override"

  for chain_link in custom-to-role source-document projection-policy put-role-policy; do
    chain_role="$modern_evidence/role-$chain_link.json"
    chain_provenance="$modern_evidence/provenance-$chain_link.md"
    cp -- "$modern_render/IAM_SIMULATION_PROVENANCE.md" "$chain_provenance"
    chain_case="$(dispatch_registered_mutation "evidence-role-hash-$chain_link" \
      "$modern_custom" "$modern_role" "$chain_role" "$chain_provenance")"
    expect_failure "evidence role hash $chain_link" \
      "Evidence role hash chain $chain_link mismatch for case: $chain_case" \
      validate_evidence_join "$modern_matrix" "$modern_custom" "$chain_role" \
      "$modern_render/IAM_SIMULATION_REPORT.md" "$chain_provenance"
    chain_rendered="$modern_evidence/rendered-role-hash-$chain_link"
    if output="$(run_report_renderer \
      "$IAM_SIM_REPORT_RENDERER" "$modern_custom" "$chain_role" \
      "$chain_rendered" 2>&1)" && \
       python3 "$REPO_ROOT/tests/lib/iam-simulate-fixtures.py" \
         validate-renderer-role-outcome \
         "$chain_rendered/IAM_SIMULATION_REPORT.md" "$chain_case"; then
      pass_case "renderer re-derives role hash $chain_link agreement"
    else
      fail_case "renderer role hash $chain_link agreement" "$output"
    fi
  done

  for generator_mutation in unknown stale; do
    generator_provenance="$modern_evidence/provenance-generator-$generator_mutation.md"
    generator_report="$modern_evidence/report-generator-$generator_mutation.md"
    dispatch_registered_mutation "evidence-generator-commit-$generator_mutation" \
      "$modern_render/IAM_SIMULATION_PROVENANCE.md" "$generator_provenance" \
      "$modern_render/IAM_SIMULATION_REPORT.md" "$generator_report"
    if [ "$generator_mutation" = unknown ]; then
      generator_diagnostic="Evidence generator commit is unknown:"
    else
      generator_diagnostic="Evidence generator drift since generator commit:"
    fi
    expect_failure "evidence generator commit $generator_mutation" \
      "$generator_diagnostic" validate_evidence_join \
      "$modern_matrix" "$modern_custom" "$modern_role" \
      "$generator_report" "$generator_provenance"
  done
fi

if [ "$failures" -eq "$group_failures" ]; then
  evidence_mutants="$tmp_dir/evidence-mutants"
  python3 - \
    "$MATRIX" "$CUSTOM_EVIDENCE_REPORT" "$ROLE_EVIDENCE_REPORT" \
    "$EVIDENCE_PROVENANCE" "$evidence_mutants" "$EVIDENCE_POINTER" \
    "$VECTORS" <<'PY_EVIDENCE_MUTANTS'
from copy import deepcopy
import hashlib
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


def replace_suffix(value, old, new):
    if isinstance(value, str):
        return value.replace(old, new)
    if isinstance(value, list):
        return [replace_suffix(item, old, new) for item in value]
    if isinstance(value, dict):
        return {
            replace_suffix(key, old, new): replace_suffix(item, old, new)
            for key, item in value.items()
        }
    return value


hyphenated_custom = replace_suffix(custom, "79s5rw", "team-a")
hyphenated_role = replace_suffix(role, "79s5rw", "team-a")
for projection in hyphenated_role["projection"]["roles"]:
    projection_sha256 = hashlib.sha256(
        projection["policy_document"].encode("utf-8")
    ).hexdigest()
    projection["policy_sha256"] = projection_sha256
    projection["redacted_policy_sha256"] = projection_sha256
    for record in hyphenated_role["records"]:
        if record["projection"]["projection_id"] != projection["projection_id"]:
            continue
        record["projection"]["policy_sha256"] = projection_sha256
        record["document_hashes_submitted"]["put_role_policy"] = [
            {"sha256": projection_sha256}
        ]
write_mutant(
    "hyphenated-suffix",
    custom_payload=hyphenated_custom,
    role_payload=hyphenated_role,
)


failed_case = (
    "case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:"
    "ALL:none:non-protected-resource"
)
failed_anchor = f"{failed_case}={label}"
failed_source = custom_by_id.get(failed_case)
if (
    matrix.count(failed_anchor) != 1
    or failed_source is None
    or failed_source.get("pass") is not False
    or failed_case not in role_by_id
):
    raise SystemExit("FAIL: failed-case Evidence mutation anchor changed")
failed_role = deepcopy(role)
failed_role["records"] = [
    record for record in failed_role["records"]
    if record["case_id"] != failed_case
]
write_mutant("failed", role_payload=failed_role)
doctored_pass_custom = deepcopy(custom)
doctored_pass_record = next(
    record for record in doctored_pass_custom["records"]
    if record["case_id"] == failed_case
)
doctored_pass_record["pass"] = True
write_mutant(
    "doctored-pass",
    custom_payload=doctored_pass_custom,
    role_payload=failed_role,
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
second_hash_case = "case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:outside-boundary"
second_hash_custom = deepcopy(custom)
second_hash_record = next(
    record for record in second_hash_custom["records"]
    if record["case_id"] == second_hash_case
)
second_hash_entries = second_hash_record["document_hashes_submitted"]["policy_input_list"]
if len(second_hash_entries) != 2:
    raise SystemExit("FAIL: second policy hash Evidence mutation anchor changed")
second_hash_entries[1]["sha256"] = "0" * 64
write_mutant("second-hash", custom_payload=second_hash_custom)
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
forbidden_details = (
    forbidden_source.get("scp_excluded", {}).get("details")
    if forbidden_source is not None
    else None
)
if (
    forbidden_source is None
    or custom_by_id.get(forbidden_case, {}).get("pass") is not False
    or forbidden_source.get("scp_excluded", {}).get("decision_observed") != "allowed"
    or forbidden_sid in forbidden_source.get("scp_excluded", {}).get("matched_sids", [])
    or not isinstance(forbidden_details, list)
    or not forbidden_details
    or any(
        forbidden_sid in detail.get("matched_sids", [])
        for detail in forbidden_details
    )
):
    raise SystemExit("FAIL: forbidden-Sid Evidence mutation anchor changed")
forbidden_role = deepcopy(role)
forbidden_record = next(
    record for record in forbidden_role["records"] if record["case_id"] == forbidden_case
)
forbidden_record["scp_excluded"]["matched_sids"] = sorted([
    *forbidden_record["scp_excluded"]["matched_sids"], forbidden_sid
])
forbidden_record["scp_excluded"]["details"][0]["matched_sids"] = sorted([
    *forbidden_record["scp_excluded"]["details"][0]["matched_sids"], forbidden_sid
])
write_mutant("role-forbidden-sid", role_payload=forbidden_role)

required_case = (
    "case:aws_iam_policy.deployer_data:"
    "ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching"
)
required_sid = "ClickhouseSecretCreateWithTag"
required_custom_source = custom_by_id.get(required_case)
required_custom_details = (
    required_custom_source.get("details")
    if required_custom_source is not None
    else None
)
required_source = role_by_id.get(required_case)
required_details = (
    required_source.get("scp_excluded", {}).get("details")
    if required_source is not None
    else None
)
if (
    required_custom_source is None
    or required_custom_source.get("pass") is not True
    or not isinstance(required_custom_details, list)
    or not required_custom_details
    or any(
        required_sid not in detail.get("matched_sids", [])
        for detail in required_custom_details
    )
    or required_source is None
    or required_source.get("scp_excluded", {}).get("decision_observed") != "allowed"
    or required_sid not in required_source.get("scp_excluded", {}).get("matched_sids", [])
    or not isinstance(required_details, list)
    or not required_details
    or any(
        required_sid not in detail.get("matched_sids", [])
        for detail in required_details
    )
):
    raise SystemExit("FAIL: required-Sid Evidence mutation anchor changed")
required_custom = deepcopy(custom)
required_custom_record = next(
    record for record in required_custom["records"] if record["case_id"] == required_case
)
required_custom_record["matched_sids"] = [
    sid for sid in required_custom_record["matched_sids"] if sid != required_sid
]
required_custom_record["details"][0]["matched_sids"] = [
    sid
    for sid in required_custom_record["details"][0]["matched_sids"]
    if sid != required_sid
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
for detail in required_record["scp_excluded"]["details"]:
    detail["matched_sids"] = [
        sid for sid in detail["matched_sids"] if sid != required_sid
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

  for mutant_root in "$evidence_mutants"/*; do
    rebound_role="${mutant_root}/role-rebound.json"
    rebind_role_report_to_custom \
      "$mutant_root/custom.json" "$mutant_root/role.json" "$rebound_role"
    mv -- "$rebound_role" "$mutant_root/role.json"
    write_bound_evidence_provenance \
      "$mutant_root/custom.json" "$mutant_root/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$mutant_root/provenance.md"
  done

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
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/failed/provenance.md"
  restore_evidence_join "evidence failed case promoted"
  expect_failure "evidence doctored pass refusal" "promoted case is not execution-matching" \
    validate_evidence_join \
      "$evidence_mutants/doctored-pass/matrix.md" \
      "$evidence_mutants/doctored-pass/custom.json" \
      "$evidence_mutants/doctored-pass/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/doctored-pass/provenance.md"
  restore_evidence_join "evidence doctored pass refusal"
  expect_failure "evidence runner failure refusal" "promoted case is not execution-matching" \
    validate_evidence_join \
      "$evidence_mutants/runner-failure/matrix.md" \
      "$evidence_mutants/runner-failure/custom.json" \
      "$evidence_mutants/runner-failure/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/runner-failure/provenance.md"
  restore_evidence_join "evidence runner failure refusal"
  expect_failure "evidence per-pair required Sid" \
    "promoted case is not execution-matching" \
    validate_evidence_join \
      "$evidence_mutants/per-pair-sid/matrix.md" \
      "$evidence_mutants/per-pair-sid/custom.json" \
      "$evidence_mutants/per-pair-sid/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/per-pair-sid/provenance.md"
  restore_evidence_join "evidence per-pair required Sid"

  evidence_suffix_original="$evidence_mutants/suffix-original.sh"
  evidence_suffix_mutant="$evidence_mutants/suffix-mutant.sh"
  if output="$(validate_evidence_join \
    "$evidence_mutants/hyphenated-suffix/matrix.md" \
    "$evidence_mutants/hyphenated-suffix/custom.json" \
    "$evidence_mutants/hyphenated-suffix/role.json" \
    "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/hyphenated-suffix/provenance.md" 2>&1)"; then
    pass_case "evidence join accepts the recorded hyphenated suffix team-a"
  else
    fail_case "evidence join hyphenated suffix" "$output"
  fi
  declare -f validate_evidence_join >"$evidence_suffix_original"
  dispatch_registered_mutation evidence-hyphenated-suffix \
    "$evidence_suffix_original" "$evidence_suffix_mutant"
  # shellcheck disable=SC1090
  source "$evidence_suffix_mutant"
  expect_failure "evidence hyphenated suffix" \
    "promoted case is not execution-matching" \
    validate_evidence_join \
      "$evidence_mutants/hyphenated-suffix/matrix.md" \
      "$evidence_mutants/hyphenated-suffix/custom.json" \
      "$evidence_mutants/hyphenated-suffix/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/hyphenated-suffix/provenance.md"
  # shellcheck disable=SC1090
  source "$evidence_suffix_original"
  if output="$(validate_evidence_join \
    "$evidence_mutants/hyphenated-suffix/matrix.md" \
    "$evidence_mutants/hyphenated-suffix/custom.json" \
    "$evidence_mutants/hyphenated-suffix/role.json" \
    "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/hyphenated-suffix/provenance.md" 2>&1)"; then
    pass_case "evidence hyphenated suffix mutation restored PASS"
  else
    fail_case "evidence hyphenated suffix mutation restoration" "$output"
  fi

  set +e
  output="$(dispatch_registered_mutation \
    evidence-promoted-empty-hash-list \
    "$evidence_mutants/empty-hash/custom.json" 2>&1)"
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
      'PASS: IAM matrix promoted record hash-list lengths match vectors (220 cases)' \
      <<<"$output"; then
    pass_case "evidence promoted empty hash list mutation restored PASS"
  else
    fail_case "evidence promoted empty hash list mutation restoration" "$output"
  fi

  set +e
  output="$(dispatch_registered_mutation \
    evidence-promoted-second-policy-hash \
    "$evidence_mutants/second-hash/custom.json" \
    "$evidence_mutants/second-hash/role.json" 2>&1)"
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -ne 0 ] && grep -Fq \
      'FAIL: promoted policy_input_list hashes mismatch for case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:outside-boundary' \
      <<<"$output"; then
    pass_case "evidence promoted second policy hash mutation -> $fail_line"
  else
    fail_case "evidence promoted second policy hash mutation did not fail as required" \
      "rc=$rc output=$output"
  fi
  if output="$(run_iam_matrix_plan_evidence_mutation \
    "$CUSTOM_EVIDENCE_REPORT" "$ROLE_EVIDENCE_REPORT" 2>&1)" && \
     grep -Fq \
       'PASS: IAM matrix promoted ordered policy and boundary hashes bind to plan/vector bytes (220 cases)' \
       <<<"$output"; then
    pass_case "evidence promoted second policy hash mutation restored PASS"
  else
    fail_case "evidence promoted second policy hash mutation restoration" "$output"
  fi
  expect_failure "evidence missing record" "promoted case has no evidence record" \
    validate_evidence_join \
      "$evidence_mutants/missing/matrix.md" \
      "$evidence_mutants/missing/custom.json" \
      "$evidence_mutants/missing/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/missing/provenance.md"
  restore_evidence_join "evidence missing record"
  expect_failure "evidence duplicate record" "promoted case appears more than once" \
    validate_evidence_join \
      "$evidence_mutants/duplicate/matrix.md" \
      "$evidence_mutants/duplicate/custom.json" \
      "$evidence_mutants/duplicate/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/duplicate/provenance.md"
  restore_evidence_join "evidence duplicate record"
  expect_failure "evidence stale pointer" "Evidence pointer mismatch" \
    validate_evidence_join \
      "$evidence_mutants/pointer/matrix.md" \
      "$evidence_mutants/pointer/custom.json" \
      "$evidence_mutants/pointer/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/pointer/provenance.md"
  restore_evidence_join "evidence stale pointer"
  expect_failure "evidence wrong date" "Evidence date mismatch" \
    validate_evidence_join \
      "$evidence_mutants/date/matrix.md" \
      "$evidence_mutants/date/custom.json" \
      "$evidence_mutants/date/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/date/provenance.md"
  restore_evidence_join "evidence wrong date"
  expect_failure "evidence row above minimum" "Evidence row is above its computed minimum" \
    validate_evidence_join \
      "$evidence_mutants/row/matrix.md" \
      "$evidence_mutants/row/custom.json" \
      "$evidence_mutants/row/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/row/provenance.md"
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
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/$fixture/provenance.md" 2>&1)"; then
      pass_case "$label refuses mismatching role record"
    else
      fail_case "$label refusal" "$output"
      return
    fi
    if ! output="$(dispatch_registered_mutation \
      "evidence-role-$mutation-sid-check" "$original" "$mutant" 2>&1)"; then
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
        "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/$fixture/provenance.md"
    # shellcheck disable=SC1090
    source "$original"
    if output="$(validate_evidence_role_refusal \
      "$label" "$case_id" \
      "$evidence_mutants/$fixture/matrix.md" \
      "$evidence_mutants/$fixture/custom.json" \
      "$evidence_mutants/$fixture/role.json" \
      "$RENDERED_EVIDENCE_REPORT" "$evidence_mutants/$fixture/provenance.md" 2>&1)"; then
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
      "$evidence_mutants/publication-metadata" "$REPO_ROOT" <<'PY_PUBLICATION'
from pathlib import Path
import re
import subprocess
import sys

matrix_path, report_path, provenance_path, output_root = map(Path, sys.argv[1:5])
repo_root = Path(sys.argv[5])
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
parent_generator = subprocess.check_output(
    ["git", "rev-parse", f"{generator[0]}^"],
    cwd=repo_root,
    text=True,
).strip()[:7]
(output_root / "provenance-generator.md").write_text(
    provenance.replace(
        f"| generator commit | {generator[0]} |",
        f"| generator commit | {parent_generator} |",
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
    publication_date_custom="$metadata_root/custom-date.json"
    publication_date_role_source="$metadata_root/role-date-source.json"
    publication_date_role="$metadata_root/role-date.json"
    publication_date_provenance="$metadata_root/provenance-date-bound.md"
    jq '.recorded_at = "2099-12-31T00:00:00Z"' \
      "$CUSTOM_EVIDENCE_REPORT" >"$publication_date_custom"
    jq '.recorded_at = "2099-12-31T00:00:01Z"' \
      "$ROLE_EVIDENCE_REPORT" >"$publication_date_role_source"
    rebind_role_report_to_custom \
      "$publication_date_custom" "$publication_date_role_source" \
      "$publication_date_role"
    write_bound_evidence_provenance \
      "$publication_date_custom" "$publication_date_role" \
      "$metadata_root/report.md" "$publication_date_provenance" \
      "$metadata_root/provenance-date.md"
    expect_failure "evidence publication date binding" \
      "Evidence publication recorded_on mismatch" \
      validate_evidence_join \
        "$metadata_root/matrix-date.md" "$publication_date_custom" \
        "$publication_date_role" "$metadata_root/report.md" \
        "$publication_date_provenance"
    restore_evidence_join "evidence publication date binding"
  else
    fail_case "Evidence publication metadata mutation setup" "$output"
  fi

fi

if output="$(python3 - "$EVIDENCE_PROVENANCE" 2>&1 <<'PY_PROVENANCE_WORDING'
from pathlib import Path
import sys

provenance = Path(sys.argv[1]).read_text(encoding="utf-8")
required = (
    "Policy evaluation ran in `us-east-1`; account identifiers are rendered with the placeholder",
    "000000000000",
)
missing = [value for value in required if value not in provenance]
if missing:
    raise SystemExit(
        "FAIL: committed IAM simulation provenance omits required content: "
        f"{missing[0]}"
    )
print("PASS: committed IAM simulation provenance matches the renderer wording contract")
PY_PROVENANCE_WORDING
)"; then
  pass_case "${output#PASS: }"
else
  fail_case "committed IAM simulation artifact wording" "$output"
fi

if [ "$failures" -eq "$group_failures" ]; then
  echo "PASS: IAM simulate EVIDENCE group"
else
  echo "FAIL: IAM simulate EVIDENCE group" >&2
fi

registry_noop_probe() {
  :
}

registry_noop_mutant="$tmp_dir/mutation-registry-noop-mutant.txt"
python3 - "$MUTATION_REGISTRY" "$registry_noop_mutant" <<'PY_REGISTRY_NOOP_MUTANT'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
old = "mutation-registry-valid-helper-edit\tregistry_mutation_probe:expected\t"
new = "mutation-registry-valid-helper-edit\tregistry_noop_probe\t"
if source.count(old) != 1:
    raise SystemExit("FAIL: mutation registry no-op mutation anchor changed")
Path(sys.argv[2]).write_text(source.replace(old, new, 1), encoding="utf-8")
PY_REGISTRY_NOOP_MUTANT
set +e
output="$(MUTATION_REGISTRY_OVERRIDE="$registry_noop_mutant" \
  dispatch_registered_mutation mutation-registry-valid-helper-edit 2>&1)"
rc=$?
set -e
if [ "$rc" -ne 0 ] && \
   [ "$output" = "FAIL: mutation registry action is a no-op for mutation-registry-valid-helper-edit: registry_noop_probe" ]; then
  pass_case "mutation registry no-op action refusal"
else
  fail_case "mutation registry no-op action refusal" "rc=$rc output=$output"
fi

registry_dispatch_mutant="$tmp_dir/mutation-registry-action-mutant.txt"
python3 - "$MUTATION_REGISTRY" "$registry_dispatch_mutant" <<'PY_REGISTRY_ACTION_MUTANT'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
old = "mutation-registry-valid-helper-edit\tregistry_mutation_probe:expected\t"
new = "mutation-registry-valid-helper-edit\tregistry_silent_probe:expected\t"
if source.count(old) != 1:
    raise SystemExit("FAIL: mutation registry valid-helper mutation anchor changed")
Path(sys.argv[2]).write_text(source.replace(old, new, 1), encoding="utf-8")
PY_REGISTRY_ACTION_MUTANT
set +e
output="$(MUTATION_REGISTRY_OVERRIDE="$registry_dispatch_mutant" \
  dispatch_registered_mutation mutation-registry-valid-helper-edit 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
  pass_case "mutation registry valid helper edit mutation -> FAIL: mutation registry valid helper edit changed observed diagnostic: observed=<none>"
else
  fail_case "mutation registry valid helper edit mutation did not change the diagnostic" \
    "rc=$rc output=$output"
fi

registry_probe_original="$(declare -f registry_mutation_probe)"
registry_mutation_probe() {
  echo "FAIL: registry mutation probe transformed diagnostic" >&2
  return 1
}
set +e
output="$(dispatch_registered_mutation mutation-registry-helper-transformation 2>&1)"
rc=$?
set -e
eval "$registry_probe_original"
if [ "$rc" -ne 0 ] && \
   [ "$output" = "FAIL: registry mutation probe transformed diagnostic" ]; then
  pass_case "mutation registry helper transformation mutation -> FAIL: mutation registry helper transformation changed without registry row: $output"
else
  fail_case "mutation registry helper transformation mutation did not change the diagnostic" \
    "rc=$rc output=$output"
fi

helper_names="$(compgen -A function)"
if output="$(validate_mutation_registry \
  "$mutation_observations" check-helpers "$helper_names" \
  "$mutation_dispatches" 2>&1)"; then
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
