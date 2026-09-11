#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${IAM_SIM_REPORT_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
HYGIENE="$REPO_ROOT/scripts/artifact-hygiene.sh"

usage() {
  echo "usage: $0 --custom-report <json> [--role-report <json>] [--recorded-on <date>] --out-dir <dir>" >&2
  exit 2
}

custom_report=""
role_report=""
recorded_on_override=""
out_dir=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --custom-report)
      [ "$#" -ge 2 ] || usage
      custom_report=$2
      shift 2
      ;;
    --role-report)
      [ "$#" -ge 2 ] || usage
      role_report=$2
      shift 2
      ;;
    --recorded-on)
      [ "$#" -ge 2 ] || usage
      recorded_on_override=$2
      shift 2
      ;;
    --out-dir)
      [ "$#" -ge 2 ] || usage
      out_dir=$2
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[ -n "$custom_report" ] && [ -n "$out_dir" ] || usage
[ -f "$custom_report" ] || {
  echo "FAIL: custom report not found: $custom_report" >&2
  exit 1
}
if [ -n "$role_report" ] && [ ! -f "$role_report" ]; then
  echo "FAIL: role report not found: $role_report" >&2
  exit 1
fi
[ -x "$HYGIENE" ] || {
  echo "FAIL: artifact hygiene checker is not executable: $HYGIENE" >&2
  exit 1
}

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbit-iam-sim-report.XXXXXX")"
rendered_report="$temp_dir/IAM_SIMULATION_REPORT.md"
rendered_provenance="$temp_dir/IAM_SIMULATION_PROVENANCE.md"
report_backup="$temp_dir/original-IAM_SIMULATION_REPORT.md"
provenance_backup="$temp_dir/original-IAM_SIMULATION_PROVENANCE.md"
publication_started=0
publication_complete=0
report_had_original=0
provenance_had_original=0

rollback_publication() {
  local rollback_rc=0
  if [ "$report_had_original" -eq 1 ]; then
    mv -- "$report_backup" "$out_dir/IAM_SIMULATION_REPORT.md" || rollback_rc=1
  elif [ -e "$out_dir/IAM_SIMULATION_REPORT.md" ]; then
    mv -- "$out_dir/IAM_SIMULATION_REPORT.md" "$temp_dir/failed-report.md" || rollback_rc=1
  fi
  if [ "$provenance_had_original" -eq 1 ]; then
    mv -- "$provenance_backup" "$out_dir/IAM_SIMULATION_PROVENANCE.md" || rollback_rc=1
  elif [ -e "$out_dir/IAM_SIMULATION_PROVENANCE.md" ]; then
    mv -- "$out_dir/IAM_SIMULATION_PROVENANCE.md" \
      "$temp_dir/failed-provenance.md" || rollback_rc=1
  fi
  return "$rollback_rc"
}

on_exit() {
  local rc=$?
  trap - EXIT
  if [ "$publication_started" -eq 1 ] && [ "$publication_complete" -eq 0 ]; then
    rollback_publication || rc=1
  fi
  rm -rf -- "$temp_dir" || rc=1
  exit "$rc"
}
trap on_exit EXIT
generator_commit="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

python3 - \
  "$custom_report" "$role_report" \
  "$rendered_report" "$rendered_provenance" \
  "$recorded_on_override" "$generator_commit" <<'PY'
from datetime import datetime
import hashlib
import json
from collections import Counter
from pathlib import Path
import re
import sys

(
    custom_path,
    role_path,
    report_path,
    provenance_path,
    recorded_on_override,
    generator_commit,
) = sys.argv[1:]

PLACEHOLDER_ACCOUNT = "000000000000"
SHA256 = re.compile(r"[0-9a-f]{64}")


def fail(message):
    raise SystemExit(f"FAIL: {message}")


def read_report(path, label):
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"{label} report cannot be read as JSON: {exc}")
    if not isinstance(value, dict):
        fail(f"{label} report must be a JSON object")
    records = value.get("records")
    if not isinstance(records, list):
        fail(f"{label} report records must be an array")
    return value


def require_string(value, label):
    if not isinstance(value, str) or not value:
        fail(f"{label} must be a non-empty string")
    return value


def require_sids(value, label):
    if not isinstance(value, list) or any(
        not isinstance(sid, str) or not sid for sid in value
    ):
        fail(f"{label} must be an array of non-empty strings")
    return value


def validate_hashes(record, label):
    groups = record.get("document_hashes_submitted")
    if not isinstance(groups, dict):
        fail(f"{label} document_hashes_submitted must be an object")
    for group, entries in groups.items():
        require_string(group, f"{label} document hash group")
        if not isinstance(entries, list):
            fail(f"{label} document hash group {group} must be an array")
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                fail(f"{label} document hash {group}[{index}] must be an object")
            digest = entry.get("sha256")
            if not isinstance(digest, str) or not SHA256.fullmatch(digest):
                fail(f"{label} document hash {group}[{index}] is not SHA-256")


def validate_custom(report):
    for index, record in enumerate(report["records"]):
        label = f"custom record {index}"
        if not isinstance(record, dict):
            fail(f"{label} must be an object")
        require_string(record.get("case_id"), f"{label} case_id")
        require_string(record.get("mode"), f"{label} mode")
        if not isinstance(record.get("expect"), dict):
            fail(f"{label} expect must be an object")
        if "decision_observed" not in record:
            fail(f"{label} decision_observed is required")
        require_sids(record.get("matched_sids"), f"{label} matched_sids")
        if not isinstance(record.get("pass"), bool):
            fail(f"{label} pass must be boolean")
        validate_hashes(record, label)


ROLE_EXPECTATION_FIELDS = (
    "decision",
    "resource_decisions",
    "matched_sid_required",
    "matched_sid_forbidden",
)


def resolve_role_expectation(record, custom_record):
    case_id = record["case_id"]
    if "expect" in record:
        expectation = record["expect"]
    elif custom_record is not None:
        expectation = custom_record["expect"]
    else:
        fail(f"role record {case_id} has no custom match and no expect")
    if not any(field in expectation for field in ROLE_EXPECTATION_FIELDS):
        fail(f"role record {case_id} expect must include a supported expectation field")
    return expectation


def validate_role(report, custom_by_id):
    if report.get("account_redacted") is not True:  # role-account-redacted-guard
        fail("role report must set account_redacted to true")
    for index, record in enumerate(report["records"]):
        label = f"role record {index}"
        if not isinstance(record, dict):
            fail(f"{label} must be an object")
        case_id = require_string(record.get("case_id"), f"{label} case_id")
        require_string(record.get("mode"), f"{label} mode")
        custom_record = custom_by_id.get(case_id)
        if "expect" in record and not isinstance(record["expect"], dict):
            fail(f"{label} expect must be an object")
        expectation = resolve_role_expectation(record, custom_record)
        if (
            custom_record is not None
            and "expect" in record
            and expectation != custom_record["expect"]
        ):
            fail(f"role record {case_id} expectation differs from custom vector expectation")
        if not isinstance(record.get("pass"), bool):
            fail(f"{label} pass must be boolean")
        for lane in ("custom_lane", "scp_excluded", "default"):
            detail = record.get(lane)
            if not isinstance(detail, dict) or "decision_observed" not in detail:
                fail(f"{label} {lane} decision_observed is required")
            require_sids(detail.get("matched_sids"), f"{label} {lane} matched_sids")
        validate_hashes(record, label)
    exclusions = report.get("exclusions", [])
    if not isinstance(exclusions, list) or any(
        not isinstance(item, dict) or not isinstance(item.get("reason"), str)
        for item in exclusions
    ):
        fail("role report exclusions must be objects with reasons")


def markdown(value):
    if value is None:
        rendered = "not observed"
    elif isinstance(value, bool):
        rendered = "true" if value else "false"
    elif isinstance(value, (dict, list)):
        rendered = json.dumps(value, sort_keys=True, separators=(",", ":"))
    else:
        rendered = str(value)
    return rendered.replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ")


def code(value):
    rendered = markdown(value).replace("`", "'")
    return f"`{rendered}`"


def custom_view(record):
    expected = record["expect"].get("decision", "attribution-only")
    return expected, record["decision_observed"], record["matched_sids"]


def role_expectation(record):
    return resolve_role_expectation(
        record, custom_by_id.get(record["case_id"])
    )


def role_view(record):
    expected = role_expectation(record).get("decision", "attribution-only")
    observed = record["scp_excluded"]["decision_observed"]
    return expected, observed, record["scp_excluded"]["matched_sids"]


def custom_matches(record):
    if "runner_failure" in record:
        return False
    expectation = record["expect"]
    expected_decision = expectation.get("decision")
    per_resource = expectation.get("resource_decisions")
    observed = record["decision_observed"]
    details = record.get("details")
    if isinstance(per_resource, dict):
        missing = object()
        observed_resources = set()
        if isinstance(details, list):  # resource-decision-details-guard
            if not details:
                return False
            for detail in details:
                if not isinstance(detail, dict):
                    return False
                resource = detail.get("resource_arn")
                observed_resources.add(resource)
                if per_resource.get(resource, missing) != detail.get(
                    "decision_observed"
                ):
                    return False
        elif isinstance(observed, dict) and observed:
            for pair_or_resource, decision in observed.items():
                resource = pair_or_resource.split("|", 1)[-1]
                observed_resources.add(resource)
                if per_resource.get(resource, missing) != decision:
                    return False
        elif per_resource and all(
            decision == observed for decision in per_resource.values()
        ):
            observed_resources = set(per_resource)
        else:
            return False
        if observed_resources != set(per_resource):
            return False
    elif expected_decision is not None:
        if isinstance(details, list) and details:
            decisions = [
                detail.get("decision_observed")
                for detail in details
                if isinstance(detail, dict)
            ]
            if len(decisions) != len(details):
                return False
        else:
            decisions = list(observed.values()) if isinstance(observed, dict) else [observed]
        if not decisions or any(decision != expected_decision for decision in decisions):
            return False
    required = set(expectation.get("matched_sid_required", []))
    forbidden = set(expectation.get("matched_sid_forbidden", []))
    if isinstance(details, list) and details:
        for detail in details:
            matched = set(detail.get("matched_sids", [])) if isinstance(detail, dict) else set()
            if not required <= matched or forbidden & matched:
                return False
        return True
    matched = set(record["matched_sids"])
    return required <= matched and not (forbidden & matched)


def detail_pairs(details, label):
    if not isinstance(details, list):
        fail(f"{label} details must be an array")
    if not details:
        fail(f"{label} details must not be empty")
    pairs = set()
    for index, detail in enumerate(details):
        if not isinstance(detail, dict):
            fail(f"{label} details[{index}] must be an object")
        action = require_string(
            detail.get("action_name"), f"{label} details[{index}] action_name"
        )
        resource = require_string(
            detail.get("resource_arn"), f"{label} details[{index}] resource_arn"
        )
        pair = (action, resource)
        if pair in pairs:
            fail(f"{label} details repeats action/resource pair: {action} {resource}")
        pairs.add(pair)
    return pairs


def role_matches(record):
    if "runner_failure" in record:
        return False
    case_id = record["case_id"]
    custom_pairs = detail_pairs(
        record["custom_lane"].get("details"), f"role record {case_id} custom_lane"
    )
    excluded_pairs = detail_pairs(
        record["scp_excluded"].get("details"),
        f"role record {case_id} scp_excluded",
    )
    if custom_pairs != excluded_pairs:
        return False
    observed = record["scp_excluded"]
    candidate = {
        "expect": role_expectation(record),
        "decision_observed": observed["decision_observed"],
        "details": observed["details"],
        "matched_sids": observed["matched_sids"],
    }
    return custom_matches(candidate)


def outcome(records, matches):
    passed = sum(matches(record) for record in records)
    return {
        "total": len(records),
        "passed": passed,
        "failed": len(records) - passed,
        "runner_failures": sum("runner_failure" in record for record in records),
    }


def append_case_rows(lines, records, view, matches):
    for record in sorted(records, key=lambda item: item["case_id"]):
        expected, observed, matched_sids = view(record)
        matched = ", ".join(markdown(sid) for sid in matched_sids) or "none"
        lines.append(
            f"| {markdown(record['case_id'])} | {markdown(record['mode'])} | "
            f"{markdown(expected)} | {markdown(observed)} | {matched} | "
            f"{'yes' if matches(record) else 'no'} |"
        )


def append_hash_rows(lines, lane, records):
    for record in sorted(records, key=lambda item: item["case_id"]):
        for group, entries in sorted(record["document_hashes_submitted"].items()):
            for entry in entries:
                lines.append(
                    f"| {lane} | {markdown(record['case_id'])} | "
                    f"{markdown(group)} | {entry['sha256']} |"
                )


custom = read_report(custom_path, "custom")
validate_custom(custom)
custom_records = custom["records"]
custom_by_id = {}
for record in custom_records:
    case_id = record["case_id"]
    if case_id in custom_by_id:
        fail(f"custom report repeats case_id: {case_id}")
    custom_by_id[case_id] = record
role = read_report(role_path, "role") if role_path else None
if role is not None:
    validate_role(role, custom_by_id)

supplied_reports = [("custom", custom)]
if role is not None:
    supplied_reports.append(("role", role))
recorded_values = [
    report["recorded_at"] if "recorded_at" in report else None
    for _, report in supplied_reports
]
modern = ["recorded_at" in report for _, report in supplied_reports]
if any(modern):
    if not all(modern):
        fail("all supplied reports must carry recorded_at or all must be legacy")
    parsed = []
    for (label, _), value in zip(supplied_reports, recorded_values):
        try:
            parsed.append(datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ"))
        except (TypeError, ValueError):
            fail(f"{label} report recorded_at must be UTC YYYY-MM-DDTHH:MM:SSZ")
    if recorded_on_override:
        fail("--recorded-on is only valid for legacy reports without recorded_at")
    if role is not None:
        if parsed[1] < parsed[0]:
            fail("role report recorded_at precedes custom report recorded_at")
        expected_custom_digest = hashlib.sha256(Path(custom_path).read_bytes()).hexdigest()
        if role.get("custom_report_sha256") != expected_custom_digest:
            fail(
                "role report custom_report_sha256 does not match the exact custom report bytes"
            )
    recorded_on = parsed[0].strftime("%Y-%m-%d")
else:
    if not recorded_on_override:
        fail("legacy reports require --recorded-on YYYY-MM-DD")
    try:
        parsed_override = datetime.strptime(recorded_on_override, "%Y-%m-%d")
    except ValueError:
        fail("--recorded-on must be YYYY-MM-DD")
    if parsed_override.strftime("%Y-%m-%d") != recorded_on_override:
        fail("--recorded-on must be YYYY-MM-DD")
    recorded_on = recorded_on_override

role_records = role["records"] if role is not None else []
report_lines = [
    "# IAM simulation report",
    "",
    "This publication renders account `000000000000` only.",
    "",
    "## Publication metadata",
    "",
    "| Field | Value |",
    "| --- | --- |",
    f"| recorded_on | {recorded_on} |",
    f"| generator commit | {generator_commit} |",
    "",
    "## Case results",
    "",
    "| Case ID | Mode | Expected | Observed | Matched Sids | Pass |",
    "| --- | --- | --- | --- | --- | --- |",
]
append_case_rows(report_lines, custom_records, custom_view, custom_matches)
append_case_rows(report_lines, role_records, role_view, role_matches)

report_lines.extend(["", "## Findings", ""])
findings = []
for lane, records, view, matches in (
    ("custom", custom_records, custom_view, custom_matches),
    ("role", role_records, role_view, role_matches),
):
    for record in sorted(records, key=lambda item: item["case_id"]):
        if matches(record):
            continue
        expected, observed, matched_sids = view(record)
        matched = ", ".join(code(sid) for sid in matched_sids) or "none"
        findings.append(
            f"- {code(record['case_id'])} ({lane}). Expected: {code(expected)}; "
            f"observed: {code(observed)}. Matched Sids: {matched}."
        )
report_lines.extend(findings or ["No non-passing cases."])

report_lines.extend(["", "## Divergences", ""])
if role is None:
    report_lines.append("No role report was provided.")
else:
    divergence_rows = []
    for record in sorted(role_records, key=lambda item: item["case_id"]):
        if record.get("comparison") == "divergence":
            divergence_rows.append(
                (
                    record["case_id"],
                    "principal/custom",
                    role_expectation(record).get("decision", "attribution-only"),
                    record["custom_lane"]["decision_observed"],
                    record["scp_excluded"]["decision_observed"],
                    record["default"]["decision_observed"],
                )
            )
        organizations = record.get("organizations_divergences", [])
        if not isinstance(organizations, list):
            fail(
                f"role record {record['case_id']} "
                "organizations_divergences must be an array"
            )
        for item in organizations:
            if not isinstance(item, dict):
                fail(
                    f"role record {record['case_id']} has an invalid "
                    "Organizations divergence"
                )
            divergence_rows.append(
                (
                    record["case_id"],
                    f"Organizations: {item.get('action_name')} {item.get('resource_arn')}",
                    role_expectation(record).get("decision", "attribution-only"),
                    record["custom_lane"]["decision_observed"],
                    item.get("scp_excluded", {}).get("decision_observed"),
                    item.get("default", {}).get("decision_observed"),
                )
            )
    if divergence_rows:
        report_lines.extend(
            [
                "| Case ID | Scope | Expected | Custom observed | SCP-excluded | Default |",
                "| --- | --- | --- | --- | --- | --- |",
            ]
        )
        for case_id, scope, expected, custom_decision, excluded, default in divergence_rows:
            report_lines.append(
                f"| {markdown(case_id)} | {markdown(scope)} | "
                f"{markdown(expected)} | {markdown(custom_decision)} | "
                f"{markdown(excluded)} | {markdown(default)} |"
            )
    else:
        report_lines.append("No divergences recorded.")

report_lines.extend(
    [
        "",
        "## Counts by outcome",
        "",
        "| Lane | Total | Passed | Failed | Runner failures |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
)
for lane, records, matches in (
    ("custom", custom_records, custom_matches),
    ("role", role_records, role_matches),
):
    if lane == "role" and role is None:
        continue
    counts = outcome(records, matches)
    report_lines.append(
        f"| {lane} | {counts['total']} | {counts['passed']} | "
        f"{counts['failed']} | {counts['runner_failures']} |"
    )

report_lines.extend(
    [
        "",
        "## Submitted document SHA-256s",
        "",
        "| Lane | Case ID | Input | SHA-256 |",
        "| --- | --- | --- | --- |",
    ]
)
append_hash_rows(report_lines, "custom", custom_records)
append_hash_rows(report_lines, "role", role_records)
Path(report_path).write_text("\n".join(report_lines) + "\n", encoding="utf-8")
report_digests = {
    "custom report sha256": hashlib.sha256(Path(custom_path).read_bytes()).hexdigest(),
    "Markdown report sha256": hashlib.sha256(Path(report_path).read_bytes()).hexdigest(),
}
if role is not None:
    report_digests["role report sha256"] = hashlib.sha256(Path(role_path).read_bytes()).hexdigest()

custom_counts = outcome(custom_records, custom_matches)
role_counts = outcome(role_records, role_matches)
recorded_from = "custom-policy report"
if role is not None:
    recorded_from += " and temporary-role principal-policy report"
commands = [
    "`TARGET=aws scripts/iam-simulate.sh --plan &lt;terraform-plan.json&gt; "
    "--vectors tests/fixtures/iam-simulate/vectors --report "
    "&lt;custom-report.json&gt;`",
]
if role is not None:
    commands.append(
        "`IAM_SIM_LANE_CONFIRM=create-real-iam-resources TARGET=aws "
        "scripts/iam-simulate-roles.sh --plan &lt;terraform-plan.json&gt; "
        "--vectors tests/fixtures/iam-simulate/vectors --custom-report "
        "&lt;custom-report.json&gt; --report &lt;role-report.json&gt; "
        "--expect-account &lt;account&gt;`"
    )
renderer_command = (
    "`scripts/iam-simulate-report.sh --custom-report &lt;custom-report.json&gt; "
    + ("--role-report &lt;role-report.json&gt; " if role is not None else "")
    + "--out-dir docs/assets`"
)
commands.append(renderer_command)
outcomes = (
    f"custom: {custom_counts['passed']} passed, {custom_counts['failed']} failed, "
    f"{custom_counts['runner_failures']} runner failures"
)
if role is not None:
    outcomes += (
        f"; role: {role_counts['passed']} passed, {role_counts['failed']} failed, "
        f"{role_counts['runner_failures']} runner failures"
    )

provenance_lines = [
    "# IAM simulation provenance",
    "",
    "The IAM simulation artifacts are generated from the JSON lane reports and are never hand-edited.",
    "",
    "| Field | Value |",
    "| --- | --- |",
    f"| recorded_from | {recorded_from} |",
    f"| recorded_on | {recorded_on} |",
    f"| generator commit | {generator_commit} |",
    *[
        f"| {name} | {report_digests[name]} |"
        for name in (
            "custom report sha256",
            "role report sha256",
            "Markdown report sha256",
        )
        if name in report_digests
    ],
    f"| commands | {'<br>'.join(commands)} |",
    (
        "| account and region | Free Plan account in `us-east-1`; the rendered "
        f"account identifier is always `{PLACEHOLDER_ACCOUNT}`. |"
    ),
    f"| case counts by outcome | {outcomes} |",
    "",
    "## Exclusions",
    "",
]
if role is None:
    provenance_lines.append(
        "- A role report was not provided, so role-lane exclusions are not represented."
    )
else:
    exclusion_counts = Counter(item["reason"] for item in role.get("exclusions", []))
    if exclusion_counts:
        for reason, count in sorted(exclusion_counts.items()):
            provenance_lines.append(f"- {count}: {markdown(reason)}")
    else:
        provenance_lines.append("- No role-lane exclusions recorded.")

provenance_lines.extend(
    [
        "",
        "## Hygiene review (what was actually checked)",
        "",
        "Before publication, `scripts/artifact-hygiene.sh` checks each supplied JSON lane report and both Markdown files for:",
        "",
        "- non-placeholder 12-digit account identifiers, including IAM ARN accounts;",
        "- AWS principal and session identifiers, including assumed-role paths;",
        "- request identifier keys and bare UUIDs; and",
        "- field-scoped complete 64/40-hex digest and commit exemptions: JSON digest keys and Markdown digest/commit table cells only.",
        "",
        "No forbidden-value file is supplied by this renderer, so forbid-list matching is not part of this publication check.",
    ]
)
Path(provenance_path).write_text(
    "\n".join(provenance_lines) + "\n", encoding="utf-8"
)
PY

hygiene_inputs=("$custom_report")
if [ -n "$role_report" ]; then
  hygiene_inputs+=("$role_report")
fi
hygiene_inputs+=("$rendered_report" "$rendered_provenance")
if ! "$HYGIENE" "${hygiene_inputs[@]}"; then  # artifact-hygiene-publication-guard
  exit 1
fi

mkdir -p "$out_dir"
if [ -e "$out_dir/IAM_SIMULATION_REPORT.md" ]; then
  cp -p -- "$out_dir/IAM_SIMULATION_REPORT.md" "$report_backup"
  report_had_original=1
fi
if [ -e "$out_dir/IAM_SIMULATION_PROVENANCE.md" ]; then
  cp -p -- "$out_dir/IAM_SIMULATION_PROVENANCE.md" "$provenance_backup"
  provenance_had_original=1
fi
publication_started=1
mv -- "$rendered_report" "$out_dir/IAM_SIMULATION_REPORT.md"
mv -- "$rendered_provenance" "$out_dir/IAM_SIMULATION_PROVENANCE.md"
publication_complete=1
echo "PASS: IAM simulation artifacts rendered in $out_dir"
