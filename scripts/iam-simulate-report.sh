#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${IAM_SIM_REPORT_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
HYGIENE="$REPO_ROOT/scripts/artifact-hygiene.sh"

usage() {
  echo "usage: $0 --custom-report <json> [--role-report <json>] --out-dir <dir>" >&2
  exit 2
}

custom_report=""
role_report=""
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
trap 'rm -rf -- "$temp_dir"' EXIT
rendered_report="$temp_dir/IAM_SIMULATION_REPORT.md"
rendered_provenance="$temp_dir/IAM_SIMULATION_PROVENANCE.md"
recorded_on="$(date +%F)"
generator_commit="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

python3 - \
  "$custom_report" "$role_report" \
  "$rendered_report" "$rendered_provenance" \
  "$recorded_on" "$generator_commit" <<'PY'
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
    recorded_on,
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


def validate_role(report):
    if report.get("account_redacted") is not True:  # role-account-redacted-guard
        fail("role report must set account_redacted to true")
    for index, record in enumerate(report["records"]):
        label = f"role record {index}"
        if not isinstance(record, dict):
            fail(f"{label} must be an object")
        require_string(record.get("case_id"), f"{label} case_id")
        require_string(record.get("mode"), f"{label} mode")
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


def role_view(record):
    expected = record["custom_lane"]["decision_observed"]
    observed = record["scp_excluded"]["decision_observed"]
    return expected, observed, record["scp_excluded"]["matched_sids"]


def outcome(records):
    return {
        "total": len(records),
        "passed": sum(record["pass"] is True for record in records),
        "failed": sum(record["pass"] is False for record in records),
        "runner_failures": sum("runner_failure" in record for record in records),
    }


def append_case_rows(lines, records, view):
    for record in sorted(records, key=lambda item: item["case_id"]):
        expected, observed, matched_sids = view(record)
        matched = ", ".join(markdown(sid) for sid in matched_sids) or "none"
        lines.append(
            f"| {markdown(record['case_id'])} | {markdown(record['mode'])} | "
            f"{markdown(expected)} | {markdown(observed)} | {matched} | "
            f"{'yes' if record['pass'] else 'no'} |"
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
role = read_report(role_path, "role") if role_path else None
if role is not None:
    validate_role(role)

custom_records = custom["records"]
role_records = role["records"] if role is not None else []
report_lines = [
    "# IAM simulation report",
    "",
    "This publication renders account `000000000000` only.",
    "",
    "## Case results",
    "",
    "| Case ID | Mode | Expected | Observed | Matched Sids | Pass |",
    "| --- | --- | --- | --- | --- | --- |",
]
append_case_rows(report_lines, custom_records, custom_view)
append_case_rows(report_lines, role_records, role_view)

report_lines.extend(["", "## Findings", ""])
findings = []
for lane, records, view in (
    ("custom", custom_records, custom_view),
    ("role", role_records, role_view),
):
    for record in sorted(records, key=lambda item: item["case_id"]):
        if record["pass"]:
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
                    "not applicable",
                    item.get("scp_excluded", {}).get("decision_observed"),
                    item.get("default", {}).get("decision_observed"),
                )
            )
    if divergence_rows:
        report_lines.extend(
            [
                "| Case ID | Scope | Custom | SCP-excluded | Default |",
                "| --- | --- | --- | --- | --- |",
            ]
        )
        for case_id, scope, custom_decision, excluded, default in divergence_rows:
            report_lines.append(
                f"| {markdown(case_id)} | {markdown(scope)} | "
                f"{markdown(custom_decision)} | {markdown(excluded)} | "
                f"{markdown(default)} |"
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
for lane, records in (("custom", custom_records), ("role", role_records)):
    if lane == "role" and role is None:
        continue
    counts = outcome(records)
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

custom_counts = outcome(custom_records)
role_counts = outcome(role_records)
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
        "Before publication, `scripts/artifact-hygiene.sh` checks both Markdown files for:",
        "",
        "- non-placeholder 12-digit account identifiers, including IAM ARN accounts;",
        "- AWS principal and session identifiers, including assumed-role paths;",
        "- request identifier keys and bare UUIDs; and",
        "- the SHA-256 exemption that removes complete 64-hex digests before the account and UUID checks.",
        "",
        "No forbidden-value file is supplied by this renderer, so forbid-list matching is not part of this publication check.",
    ]
)
Path(provenance_path).write_text(
    "\n".join(provenance_lines) + "\n", encoding="utf-8"
)
PY

if ! "$HYGIENE" "$rendered_report" "$rendered_provenance"; then  # artifact-hygiene-publication-guard
  exit 1
fi

mkdir -p "$out_dir"
mv -- "$rendered_report" "$out_dir/IAM_SIMULATION_REPORT.md"
mv -- "$rendered_provenance" "$out_dir/IAM_SIMULATION_PROVENANCE.md"
echo "PASS: IAM simulation artifacts rendered in $out_dir"
