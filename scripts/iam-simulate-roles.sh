#!/usr/bin/env bash
# shellcheck disable=SC2329 # Trap handlers are invoked indirectly.
# Project IAM matrix policies onto temporary roles and simulate each principal.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AWS_CLI_SH="${AWS_CLI_SH:-$REPO_ROOT/scripts/aws-cli.sh}"
VALIDATOR="$REPO_ROOT/scripts/iam-simulate-validate.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbit-iam-simulate-roles.XXXXXX")"
manifest_dir="$tmp_dir/manifest"
mkdir -p "$manifest_dir"

plan=""
vectors=""
report=""
expect_account=""
only=""
custom_report=""
dry_run=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan) plan=${2:-}; shift 2 ;;
    --vectors) vectors=${2:-}; shift 2 ;;
    --report) report=${2:-}; shift 2 ;;
    --expect-account) expect_account=${2:-}; shift 2 ;;
    --custom-report) custom_report=${2:-}; shift 2 ;;
    --only) only=${2:-}; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "FAIL: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$plan" ] || [ -z "$vectors" ] || [ -z "$report" ] || [ -z "$expect_account" ]; then
  echo "FAIL: --plan, --vectors, --report, and --expect-account are required" >&2
  exit 2
fi
if ! [[ "$expect_account" =~ ^[0-9]{12}$ ]]; then
  echo "FAIL: --expect-account must be exactly 12 digits" >&2
  exit 2
fi
if [ "${TARGET:-}" != aws ]; then
  echo "FAIL: TARGET must be exactly aws" >&2
  exit 2
fi
if [ "$dry_run" -eq 0 ] && [ "${IAM_SIM_LANE_CONFIRM:-}" != create-real-iam-resources ]; then
  echo "FAIL: IAM_SIM_LANE_CONFIRM must equal create-real-iam-resources" >&2
  exit 2
fi
if [ "$dry_run" -eq 0 ] && [ -z "$custom_report" ]; then
  echo "FAIL: --custom-report is required outside --dry-run" >&2
  exit 2
fi

# shellcheck source=scripts/iam-matrix-documents.sh
source "$REPO_ROOT/scripts/iam-matrix-documents.sh"

run_id="${IAM_SIM_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM}"
if ! [[ "$run_id" =~ ^[A-Za-z0-9+=,.@_-]{1,32}$ ]]; then
  echo "FAIL: IAM_SIM_RUN_ID must be 1-32 IAM-name characters" >&2
  exit 2
fi
tag_key=OrbitIamSimulationRun
tag_value="$run_id"
role_plan="$tmp_dir/role-plan.json"
records="$tmp_dir/records.jsonl"
manual_notes="$tmp_dir/manual-cleanup.txt"
: >"$records"
: >"$manual_notes"

prepare_args=(
  "$REPO_ROOT" "$VALIDATOR" "$plan" "$vectors" "$expect_account" "$run_id"
  "$role_plan" "$custom_report" "$dry_run"
)
if [ -n "$only" ]; then
  prepare_args+=("$only")
fi
python3 - "${core_documents[@]}" -- "${prepare_args[@]}" <<'PY'
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

separator = sys.argv.index("--")
core_documents = sys.argv[1:separator]
repo_root = Path(sys.argv[separator + 1])
validator = Path(sys.argv[separator + 2])
plan_path = Path(sys.argv[separator + 3])
vectors_path = Path(sys.argv[separator + 4])
account_id = sys.argv[separator + 5]
run_id = sys.argv[separator + 6]
output_path = Path(sys.argv[separator + 7])
custom_report_path = Path(sys.argv[separator + 8]) if sys.argv[separator + 8] else None
dry_run = sys.argv[separator + 9] == "1"
only = sys.argv[separator + 10] if len(sys.argv) > separator + 10 else None


def fail(message):
    raise SystemExit(f"FAIL: {message}")


try:
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    resources = plan["planned_values"]["root_module"]["resources"]
except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
    fail(f"cannot read Terraform plan: {exc}")
if not isinstance(resources, list):
    fail("plan resources must be an array")
by_address = {}
for resource in resources:
    if isinstance(resource, dict) and isinstance(resource.get("address"), str):
        by_address.setdefault(resource["address"], []).append(resource)

documents = {}
for address in core_documents:
    matches = by_address.get(address, [])
    if len(matches) != 1:
        fail(f"plan must contain exactly one {address}, found {len(matches)}")
    values = matches[0].get("values")
    policy = values.get("policy") if isinstance(values, dict) else None
    if not isinstance(policy, str) or not policy:
        fail(f"plan policy document is null, unknown, or empty: {address}")
    try:
        parsed = json.loads(policy)
    except json.JSONDecodeError as exc:
        fail(f"plan policy document is invalid JSON for {address}: {exc}")
    if not isinstance(parsed, dict) or "Statement" not in parsed:
        fail(f"plan policy document is incomplete: {address}")
    documents[address] = policy

reader_matches = by_address.get("aws_iam_role.plan_reader", [])
if len(reader_matches) != 1:
    fail("plan must contain exactly one aws_iam_role.plan_reader")
reader_values = reader_matches[0].get("values")
reader_name = reader_values.get("name") if isinstance(reader_values, dict) else None
suffix_match = re.fullmatch(r"orbit-infra-(.+)-plan-reader", reader_name or "")
if suffix_match is None:
    fail(f"cannot derive SUFFIX from plan reader role name: {reader_name}")
suffix = suffix_match.group(1)
plan_account_ids = sorted(set(re.findall(
    r"(?<![0-9])[0-9]{12}(?![0-9])", "\n".join(documents.values())
)))
if len(plan_account_ids) > 1:
    fail(f"plan policy documents contain multiple account ids: {plan_account_ids}")
vector_account_id = plan_account_ids[0] if plan_account_ids else "000000000000"


def render(value):
    if isinstance(value, str):
        rendered = value.replace("${ACCOUNT_ID}", vector_account_id).replace("${SUFFIX}", suffix)
        if re.search(r"\$\{[^}]+\}", rendered):
            fail(f"unknown template remains after rendering: {rendered}")
        return rendered
    if isinstance(value, list):
        return [render(item) for item in value]
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            rendered_key = render(key)
            if rendered_key in result:
                fail(f"rendering creates duplicate key: {rendered_key}")
            result[rendered_key] = render(item)
        return result
    return value


if not vectors_path.is_dir():
    fail(f"vector directory not found: {vectors_path}")
vectors = []
for path in sorted(vectors_path.rglob("*.json")):
    checked = subprocess.run(
        [sys.executable, str(validator), str(path)],
        text=True,
        capture_output=True,
        check=False,
    )
    if checked.returncode != 0:
        fail(f"vector validation failed for {path}: {checked.stderr.strip() or checked.stdout.strip()}")
    vector = json.loads(path.read_text(encoding="utf-8"))
    prefix = f"case:{vector['document']}:{vector['sid']}:"
    if not vector["case_id"].startswith(prefix) or vector["case_id"] == prefix:
        fail(f"case id exact prefix mismatch: expected {prefix}")
    if only is None or vector["case_id"] == only:
        vectors.append(render(vector))
if not vectors:
    fail(f"no vectors selected{f' for --only {only}' if only else ''}")
if only is not None and len(vectors) != 1:
    fail(f"--only selected {len(vectors)} vectors")

role_for_document = {
    "aws_iam_role_policy.plan_reader_deny": "plan-reader",
    "aws_iam_role_policy.plan_reader_state": "plan-reader",
    "aws_iam_policy.deployer_state": "deployer",
    "aws_iam_policy.deployer_ec2": "deployer",
    "aws_iam_policy.deployer_elb_ecs": "deployer",
    "aws_iam_policy.deployer_data": "deployer",
    "aws_iam_policy.deployer_iam": "deployer",
    "aws_iam_policy.deployer_guard": "deployer",
    "aws_iam_role_policy.publisher": "publisher",
}
exclusions = [{
    "binding": "aws_iam_role_policy_attachment.plan_reader_readonly",
    "reason": "AWS-managed ReadOnlyAccess cannot be represented by the inline role-lane projection",
}]
candidate_cases = {role: [] for role in ("plan-reader", "deployer", "publisher")}
for vector in vectors:
    if vector["simulation_mode"] == "custom-isolated":
        exclusions.append({
            "case_id": vector["case_id"],
            "reason": "isolated single-statement simulation has no principal equivalent",
        })
        continue
    if vector["simulation_mode"] != "custom":
        exclusions.append({
            "case_id": vector["case_id"],
            "reason": "role lane reuses custom-lane vectors only",
        })
        continue
    role = role_for_document.get(vector["document"])
    if role is None:
        exclusions.append({"case_id": vector["case_id"], "reason": "document is not an identity-role binding"})
        continue
    candidate_cases[role].append(vector)

def combine_documents(role, addresses):
    versions = set()
    statements = []
    seen_sids = {}
    for address in addresses:
        policy = json.loads(documents[address])
        version = policy.get("Version")
        if not isinstance(version, str) or not version:
            fail(f"projected policy document lacks Version: {address}")
        versions.add(version)
        raw_statements = policy.get("Statement")
        if isinstance(raw_statements, dict):
            raw_statements = [raw_statements]
        if not isinstance(raw_statements, list) or not raw_statements:
            fail(f"projected policy document has no statements: {address}")
        for statement in raw_statements:
            if not isinstance(statement, dict) or not isinstance(statement.get("Sid"), str):
                fail(f"every projected statement must carry a Sid: {address}")
            sid = statement["Sid"]
            if sid in seen_sids and seen_sids[sid] != address:
                fail(
                    f"duplicate Sid {sid} across {seen_sids[sid]} and {address}"
                )
            seen_sids[sid] = address
            statements.append(statement)
    if len(versions) != 1:
        fail(f"role {role} policy documents disagree on Version: {sorted(versions)}")
    return json.dumps(
        {"Version": next(iter(versions)), "Statement": statements},
        separators=(",", ":"),
    )


def source_entries(addresses):
    return [
        {
            "address": address,
            "sha256": hashlib.sha256(documents[address].encode("utf-8")).hexdigest(),
        }
        for address in addresses
    ]


roles = []
supported = []
for role in ("plan-reader", "deployer", "publisher"):
    cases = candidate_cases[role]
    if not cases:
        continue
    role_documents = sorted(
        address for address, mapped_role in role_for_document.items()
        if mapped_role == role
    )
    combined_policy = combine_documents(role, role_documents)
    combined_size = len(re.sub(r"\s", "", combined_policy))
    source_size = sum(len(re.sub(r"\s", "", documents[address])) for address in role_documents)
    if combined_size <= 10240:
        pass_specs = [("combined", role_documents, combined_policy)]
    else:
        pass_specs = []
        for address in role_documents:
            policy = documents[address]
            policy_size = len(re.sub(r"\s", "", policy))
            if policy_size > 10240:
                fail(
                    f"per-document projection exceeds 10240 characters for {address}: {policy_size}"
                )
            pass_specs.append(("per-document", [address], policy))

    projection_for_document = {}
    for pass_index, (projection_kind, source_addresses, policy) in enumerate(pass_specs, 1):
        projection_id = (
            f"{role}:combined"
            if projection_kind == "combined"
            else f"{role}:{source_addresses[0]}"
        )
        role_name = f"orbit-iam-sim-{run_id}-{role}"
        policy_name = f"orbit-iam-sim-{role}"
        if len(pass_specs) > 1:
            role_name += f"-p{pass_index}"
            policy_name += f"-p{pass_index}"
        entries = source_entries(source_addresses)
        roles.append({
            "kind": role,
            "role_kind": role,
            "projection_id": projection_id,
            "projection_kind": projection_kind,
            "name": role_name,
            "policy_name": policy_name,
            "policy_document": policy,
            "policy_sha256": hashlib.sha256(policy.encode("utf-8")).hexdigest(),
            "policy_character_count": len(re.sub(r"\s", "", policy)),
            "source_character_count": (
                source_size if projection_kind == "combined"
                else len(re.sub(r"\s", "", documents[source_addresses[0]]))
            ),
            "source_documents": entries,
        })
        for address in source_addresses:
            projection_for_document[address] = projection_id
    for vector in cases:
        vector["temporary_projection_id"] = projection_for_document[vector["document"]]
    supported.extend(cases)

if not supported:
    fail("role lane selected no supported custom cases")

if not dry_run:
    try:
        custom_payload = json.loads(custom_report_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, AttributeError) as exc:
        fail(f"cannot read custom report: {exc}")
    custom_records = custom_payload.get("records") if isinstance(custom_payload, dict) else None
    if not isinstance(custom_records, list):
        fail("custom report records must be an array")
    for vector in vectors:
        matches = [
            record for record in custom_records
            if isinstance(record, dict) and record.get("case_id") == vector["case_id"]
        ]
        if len(matches) != 1:
            fail(f"custom report lacks exactly one record for {vector['case_id']}")
        custom_record = matches[0]
        if "decision_observed" not in custom_record or custom_record["decision_observed"] is None:
            fail(f"custom report lacks an observed decision for {vector['case_id']}")
        matched_sids = custom_record.get("matched_sids")
        if not isinstance(matched_sids, list) or any(
            not isinstance(sid, str) for sid in matched_sids
        ):
            fail(f"custom report matched_sids is invalid for {vector['case_id']}")

assume_policy = json.dumps({
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"AWS": f"arn:aws:iam::{account_id}:root"},
        "Action": "sts:AssumeRole",
    }],
}, separators=(",", ":"))
payload = {
    "account_id": account_id,
    "vector_account_id": vector_account_id,
    "suffix": suffix,
    "run_id": run_id,
    "assume_role_policy": assume_policy,
    "assume_role_policy_sha256": hashlib.sha256(assume_policy.encode("utf-8")).hexdigest(),
    "roles": roles,
    "cases": supported,
    "exclusions": exclusions,
}
output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

role_count="$(jq '.roles | length' "$role_plan")"
cleanup_complete=0
cleanup_failed=0
terminated=0
main_succeeded=0
IAM_SIM_LANE_PID=$$
export IAM_SIM_LANE_PID

AWS_COMMAND=()
build_call() {
  AWS_COMMAND=("$AWS_CLI_SH" "$@")
}

print_call() {
  printf 'DRY-RUN:'
  printf ' %q' "${AWS_COMMAND[@]}"
  printf '\n'
}

CALL_OUTPUT=""
CALL_ERROR=""
CALL_RC=0
call_capture() {
  local stdout_file="$tmp_dir/call.stdout"
  local stderr_file="$tmp_dir/call.stderr"
  build_call "$@"
  if [ "$dry_run" -eq 1 ]; then
    print_call
    CALL_OUTPUT=""
    CALL_ERROR=""
    CALL_RC=0
    return 0
  fi
  set +e
  "${AWS_COMMAND[@]}" >"$stdout_file" 2>"$stderr_file"
  CALL_RC=$?
  set -e
  CALL_OUTPUT="$(<"$stdout_file")"
  CALL_ERROR="$(<"$stderr_file")"
  return 0
}

append_manual_note() {
  printf '%s\n' "$1" >>"$manual_notes"
  printf 'FAIL: %s\n' "$1" >&2
  cleanup_failed=1
}

role_status_file() {
  printf '%s/%s.status\n' "$manifest_dir" "$1"
}

role_policy_file() {
  printf '%s/%s.policy\n' "$manifest_dir" "$1"
}

verify_owned_tag() {
  local role_name=$1
  local allow_missing=${2:-0}
  call_capture iam list-role-tags --role-name "$role_name" --output json
  if [ "$CALL_RC" -ne 0 ]; then
    if [ "$allow_missing" -eq 1 ] && grep -Fq '(NoSuchEntity)' <<<"$CALL_ERROR"; then
      return 2
    fi
    append_manual_note "manual cleanup: could not re-read ownership tags for $role_name"
    return 1
  fi
  if ! jq -e --arg key "$tag_key" --arg value "$tag_value" \
    'any(.Tags[]?; .Key == $key and .Value == $value)' <<<"$CALL_OUTPUT" >/dev/null; then
    append_manual_note "ownership tag mismatch for $role_name"
    return 1
  fi
  return 0
}

cleanup_roles() {
  local index role_name policy_name status tag_rc
  if [ "$cleanup_complete" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
    return 0
  fi
  for ((index = role_count - 1; index >= 0; index--)); do
    role_name="$(jq -r ".roles[$index].name" "$role_plan")"
    policy_name="$(jq -r ".roles[$index].policy_name" "$role_plan")"
    status=none
    [ ! -f "$(role_status_file "$index")" ] || status="$(<"$(role_status_file "$index")")"
    if [ "$status" = none ] || [ "$status" = collision ]; then
      continue
    fi
    set +e
    verify_owned_tag "$role_name" 1
    tag_rc=$?
    set -e
    if [ "$tag_rc" -eq 2 ]; then
      continue
    fi
    if [ "$tag_rc" -ne 0 ]; then
      continue
    fi
    if [ -f "$(role_policy_file "$index")" ]; then
      call_capture iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name"
      if [ "$CALL_RC" -ne 0 ]; then
        append_manual_note "manual cleanup: delete-role-policy failed for $role_name"
        continue
      fi
    fi
    if ! verify_owned_tag "$role_name" 0; then
      continue
    fi
    call_capture iam delete-role --role-name "$role_name"
    if [ "$CALL_RC" -ne 0 ]; then
      append_manual_note "manual cleanup: delete-role failed for $role_name"
    fi
  done

  for ((index = 0; index < role_count; index++)); do
    status=none
    [ ! -f "$(role_status_file "$index")" ] || status="$(<"$(role_status_file "$index")")"
    if [ "$status" = none ] || [ "$status" = collision ]; then
      continue
    fi
    role_name="$(jq -r ".roles[$index].name" "$role_plan")"
    call_capture iam get-role --role-name "$role_name" --output json
    if [ "$CALL_RC" -eq 0 ]; then
      append_manual_note "manual cleanup: role still exists after cleanup: $role_name"
    elif ! grep -Fq '(NoSuchEntity)' <<<"$CALL_ERROR"; then
      append_manual_note "manual cleanup: role absence could not be verified: $role_name"
    fi
  done
  cleanup_complete=1
  [ "$cleanup_failed" -eq 0 ]
}

write_report() {
  python3 - "$role_plan" "$records" "$manual_notes" "$report" <<'PY'
import json
from pathlib import Path
import sys

role_plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
records_path = Path(sys.argv[2])
notes_path = Path(sys.argv[3])
report_path = Path(sys.argv[4])
records = [json.loads(line) for line in records_path.read_text(encoding="utf-8").splitlines() if line]
notes = notes_path.read_text(encoding="utf-8").splitlines()
case_exclusions = {}
for exclusion in role_plan["exclusions"]:
    if "case_id" in exclusion:
        reason = exclusion["reason"]
        case_exclusions[reason] = case_exclusions.get(reason, 0) + 1
payload = {
    "run_id": role_plan["run_id"],
    "projection": {
        "assume_role_policy": role_plan["assume_role_policy"],
        "assume_role_policy_sha256": role_plan["assume_role_policy_sha256"],
        "roles": role_plan["roles"],
    },
    "exclusions": role_plan["exclusions"],
    "records": records,
    "manual_cleanup": notes,
    "summary": {
        "total": len(records),
        "passed": sum(record.get("pass") is True for record in records),
        "failed": sum(record.get("pass") is False for record in records),
        "cases_selected": len(role_plan["cases"]),
        "cases_excluded": sum(case_exclusions.values()),
        "cases_excluded_by_reason": dict(sorted(case_exclusions.items())),
        "agreements": sum(record.get("comparison") == "agreement" for record in records),
        "divergences": sum(record.get("comparison") == "divergence" for record in records),
        "organizations_divergences": sum(
            len(record.get("organizations_divergences", [])) for record in records
        ),
        "manual_cleanup_notes": len(notes),
    },
}
report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

on_exit() {
  local rc=$?
  trap - EXIT TERM INT
  if [ "$dry_run" -eq 0 ]; then
    cleanup_roles || rc=1
    write_report || rc=1
  fi
  rm -rf "$tmp_dir"
  if [ "$terminated" -eq 1 ]; then
    echo "FAIL: terminated by TERM" >&2
    rc=143
  elif [ "$rc" -eq 0 ] && [ "$main_succeeded" -eq 1 ]; then
    echo "PASS: IAM simulator role lane"
  fi
  exit "$rc"
}

on_term() {
  terminated=1
  exit 143
}

# The EXIT trap is armed before the first create-role call. Intent files are
# written before each create so cleanup also covers the signal-in-create gap.
trap on_exit EXIT
trap on_term TERM INT

role_call_args() {
  local index=$1
  ROLE_NAME="$(jq -r ".roles[$index].name" "$role_plan")"
  POLICY_NAME="$(jq -r ".roles[$index].policy_name" "$role_plan")"
  POLICY_DOCUMENT="$(jq -r ".roles[$index].policy_document" "$role_plan")"
}

print_dry_run_inventory() {
  local index case_json projection_id role_name context
  local -a actions resources context_args
  call_capture sts get-caller-identity --output json
  for ((index = 0; index < role_count; index++)); do
    role_call_args "$index"
    call_capture iam create-role --role-name "$ROLE_NAME" \
      --assume-role-policy-document "$(jq -r '.assume_role_policy' "$role_plan")" \
      --tags "Key=$tag_key,Value=$tag_value"
  done
  for ((index = 0; index < role_count; index++)); do
    role_call_args "$index"
    call_capture iam list-role-tags --role-name "$ROLE_NAME" --output json
    call_capture iam put-role-policy --role-name "$ROLE_NAME" \
      --policy-name "$POLICY_NAME" --policy-document "$POLICY_DOCUMENT"
  done
  while IFS= read -r case_json; do
    projection_id="$(jq -r '.temporary_projection_id' <<<"$case_json")"
    role_name="$(jq -r --arg projection_id "$projection_id" \
      '.roles[] | select(.projection_id == $projection_id) | .name' "$role_plan")"
    actions=()
    jq -r '.action_names[]' <<<"$case_json" >"$tmp_dir/action-names"
    while IFS= read -r value; do actions+=("$value"); done <"$tmp_dir/action-names"
    resources=()
    jq -r '.resource_arns[]' <<<"$case_json" >"$tmp_dir/resource-arns"
    while IFS= read -r value; do resources+=("$value"); done <"$tmp_dir/resource-arns"
    context="$(jq -c '.context_entries // [] | sort_by(.ContextKeyName,.ContextKeyType,(.ContextKeyValues|join("\u0000")))' <<<"$case_json")"
    context_args=(--output json)
    [ "$context" = '[]' ] || context_args=(--context-entries "$context" --output json)
    call_capture iam simulate-principal-policy \
      --policy-source-arn "arn:aws:iam::$expect_account:role/$role_name" \
      --action-names "${actions[@]}" --resource-arns "${resources[@]}" \
      "${context_args[@]}" --policy-exclusion-list '{"PolicyType":"scp"}'
    call_capture iam simulate-principal-policy \
      --policy-source-arn "arn:aws:iam::$expect_account:role/$role_name" \
      --action-names "${actions[@]}" --resource-arns "${resources[@]}" \
      "${context_args[@]}"
  done < <(jq -c '.cases[]' "$role_plan")
  for ((index = role_count - 1; index >= 0; index--)); do
    role_call_args "$index"
    call_capture iam list-role-tags --role-name "$ROLE_NAME" --output json
    call_capture iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME"
    call_capture iam list-role-tags --role-name "$ROLE_NAME" --output json
    call_capture iam delete-role --role-name "$ROLE_NAME"
  done
  for ((index = 0; index < role_count; index++)); do
    role_call_args "$index"
    call_capture iam get-role --role-name "$ROLE_NAME" --output json
  done
}

if [ "$dry_run" -eq 1 ]; then
  print_dry_run_inventory
  main_succeeded=1
  exit 0
fi

call_capture sts get-caller-identity --output json
if [ "$CALL_RC" -ne 0 ]; then
  echo "FAIL: caller identity preflight failed: $CALL_ERROR" >&2
  exit 1
fi
actual_account="$(jq -er '.Account | select(type == "string")' <<<"$CALL_OUTPUT")" || {
  echo "FAIL: caller identity response lacks Account" >&2
  exit 1
}
if [ "$actual_account" != "$expect_account" ]; then
  echo "FAIL: caller account mismatch: expected $expect_account, observed $actual_account" >&2
  exit 1
fi

for ((index = 0; index < role_count; index++)); do
  role_call_args "$index"
  printf 'intended\n' >"$(role_status_file "$index")"
  call_capture iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$(jq -r '.assume_role_policy' "$role_plan")" \
    --tags "Key=$tag_key,Value=$tag_value"
  if [ "$CALL_RC" -ne 0 ]; then
    if grep -Fq '(EntityAlreadyExists)' <<<"$CALL_ERROR"; then
      printf 'collision\n' >"$(role_status_file "$index")"
      append_manual_note "manual cleanup: role already existed at create time: $ROLE_NAME"
      exit 1
    fi
    echo "FAIL: create-role failed for $ROLE_NAME: $CALL_ERROR" >&2
    exit 1
  fi
  printf 'created\n' >"$(role_status_file "$index")"
done

for ((index = 0; index < role_count; index++)); do
  role_call_args "$index"
  if ! verify_owned_tag "$ROLE_NAME" 0; then
    exit 1
  fi
  call_capture iam put-role-policy --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" --policy-document "$POLICY_DOCUMENT"
  if [ "$CALL_RC" -ne 0 ]; then
    echo "FAIL: put-role-policy failed for $ROLE_NAME: $CALL_ERROR" >&2
    exit 1
  fi
  printf 'loaded\n' >"$(role_policy_file "$index")"
done

evaluate_case() {
  local case_file=$1
  local excluded_response=$2
  local organizations_response=$3
  local projection=$4
  python3 - "$case_file" "$excluded_response" "$organizations_response" \
    "$projection" "$custom_report" <<'PY'
import json
from pathlib import Path
import sys

case = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
excluded = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
organizations = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
projection = json.loads(sys.argv[4])
custom = json.loads(Path(sys.argv[5]).read_text(encoding="utf-8"))


def fail(message):
    raise SystemExit(f"FAIL: {message}")


def statement_spans(policy):
    decoder = json.JSONDecoder()

    def whitespace(index):
        while index < len(policy) and policy[index].isspace():
            index += 1
        return index

    index = whitespace(0)
    if index >= len(policy) or policy[index] != "{":
        fail("role projection is not a JSON object")
    index += 1
    spans = []
    while True:
        index = whitespace(index)
        if index < len(policy) and policy[index] == "}":
            break
        key, end = decoder.raw_decode(policy, index)
        index = whitespace(end)
        if index >= len(policy) or policy[index] != ":":
            fail("role projection object key lacks a colon")
        index = whitespace(index + 1)
        if key != "Statement":
            _, index = decoder.raw_decode(policy, index)
        elif policy[index] == "[":
            index += 1
            while True:
                index = whitespace(index)
                if policy[index] == "]":
                    index += 1
                    break
                statement_start = index
                statement, statement_end = decoder.raw_decode(policy, index)
                if not isinstance(statement, dict) or not isinstance(statement.get("Sid"), str):
                    fail("every projected statement must carry a Sid")
                spans.append((
                    len(policy[:statement_start].encode("utf-8")),
                    len(policy[:statement_end].encode("utf-8")),
                    statement["Sid"],
                ))
                index = whitespace(statement_end)
                if policy[index] == ",":
                    index += 1
                    continue
                if policy[index] == "]":
                    index += 1
                    break
                fail("role projection Statement array has invalid separators")
        else:
            statement_start = index
            statement, statement_end = decoder.raw_decode(policy, index)
            if not isinstance(statement, dict) or not isinstance(statement.get("Sid"), str):
                fail("every projected statement must carry a Sid")
            spans.append((
                len(policy[:statement_start].encode("utf-8")),
                len(policy[:statement_end].encode("utf-8")),
                statement["Sid"],
            ))
            index = statement_end
        index = whitespace(index)
        if policy[index] == ",":
            index += 1
            continue
        if policy[index] == "}":
            break
        fail("role projection object has invalid separators")
    if not spans:
        fail("role projection has no statements")
    return spans


projection_policy = projection["policy_document"]
projection_spans = statement_spans(projection_policy)


def position_offset(position):
    if not isinstance(position, dict):
        fail("role matched statement position is not an object")
    line = position.get("Line")
    column = position.get("Column")
    if type(line) is not int or type(column) is not int or line < 1 or column < 1:
        fail("role matched statement position is invalid")
    lines = projection_policy.encode("utf-8").splitlines(keepends=True)
    if line > len(lines):
        fail("role matched statement line is outside the projection")
    body = lines[line - 1].rstrip(b"\r\n")
    if column - 1 > len(body):
        fail("role matched statement column is outside the projection")
    return sum(len(item) for item in lines[: line - 1]) + column - 1


def map_sid(match, allow_organizations):
    source_type = match.get("SourcePolicyType")
    if allow_organizations and isinstance(source_type, str) and "organization" in source_type.lower():
        return None
    start = position_offset(match.get("StartPosition"))
    end = position_offset(match.get("EndPosition"))
    matches = [
        sid for span_start, span_end, sid in projection_spans
        if span_start <= start < span_end and span_start <= end < span_end
    ]
    if len(matches) == 0:
        fail(f"unmapped role matched statement position from {match.get('SourcePolicyId')}")
    if len(matches) != 1:
        fail(f"ambiguous role matched statement position from {match.get('SourcePolicyId')}")
    return matches[0]


def observe(response, allow_organizations):
    results = response.get("EvaluationResults")
    if not isinstance(results, list):
        fail("role simulation response lacks EvaluationResults")
    decisions = {}
    matched_sources = []
    matched_sids = set()
    details = []
    for action in case["action_names"]:
        action_results = [item for item in results if isinstance(item, dict) and item.get("EvalActionName") == action]
        if len(action_results) != 1:
            fail(f"role response does not have one result for {action}")
        resources = action_results[0].get("ResourceSpecificResults")
        if not isinstance(resources, list):
            fail(f"role response lacks ResourceSpecificResults for {action}")
        for resource in case["resource_arns"]:
            resource_results = [item for item in resources if isinstance(item, dict) and item.get("EvalResourceName") == resource]
            if len(resource_results) != 1:
                fail(f"role response does not have one exact resource result for {action} {resource}")
            item = resource_results[0]
            decision = item.get("EvalResourceDecision")
            if decision not in {"allowed", "implicitDeny", "explicitDeny"}:
                fail(f"role response has an unknown decision for {action} {resource}")
            decisions[(action, resource)] = decision
            raw_matches = item.get("MatchedStatements", [])
            if not isinstance(raw_matches, list):
                fail(f"role MatchedStatements is not an array for {action} {resource}")
            item_sources = []
            item_sids = set()
            for match in raw_matches:
                if not isinstance(match, dict):
                    fail("role MatchedStatements entry is not an object")
                source = {
                    "source_policy_id": match.get("SourcePolicyId"),
                    "source_policy_type": match.get("SourcePolicyType"),
                    "start_position": match.get("StartPosition"),
                    "end_position": match.get("EndPosition"),
                }
                matched_sources.append(source)
                item_sources.append(source)
                sid = map_sid(match, allow_organizations)
                if sid is not None:
                    matched_sids.add(sid)
                    item_sids.add(sid)
            details.append({
                "action_name": action,
                "resource_arn": resource,
                "decision_observed": decision,
                "matched_statement_sources": item_sources,
                "matched_sids": sorted(item_sids),
            })
    if len(case["resource_arns"]) > 1 and len(case["action_names"]) == 1:
        observed = {resource: decisions[(case["action_names"][0], resource)] for resource in sorted(case["resource_arns"])}
    elif len(set(decisions.values())) == 1:
        observed = next(iter(decisions.values()))
    else:
        observed = {f"{action}|{resource}": value for (action, resource), value in sorted(decisions.items())}
    return observed, matched_sources, sorted(matched_sids), details


excluded_decision, excluded_sources, excluded_sids, excluded_details = observe(excluded, False)
organizations_decision, organizations_sources, organizations_sids, organizations_details = observe(organizations, True)
custom_records = [record for record in custom.get("records", []) if record.get("case_id") == case["case_id"]]
if len(custom_records) != 1:
    fail(f"custom report lacks exactly one record for {case['case_id']}")
custom_record = custom_records[0]
custom_decision = custom_record.get("decision_observed")
if custom_decision is None:
    fail(f"custom report lacks an observed decision for {case['case_id']}")
custom_sids = custom_record.get("matched_sids")
if not isinstance(custom_sids, list) or any(not isinstance(sid, str) for sid in custom_sids):
    fail(f"custom report matched_sids is invalid for {case['case_id']}")
custom_hashes = [
    entry.get("sha256")
    for entry in custom_record.get("document_hashes_submitted", {}).get("policy_input_list", [])
]
source_document = next(
    entry for entry in projection["source_documents"]
    if entry["address"] == case["document"]
)
same_decision = excluded_decision == custom_decision
observed_in = []
if excluded_decision != custom_decision:
    observed_in.append("scp-excluded")
if organizations_decision != custom_decision:
    observed_in.append("default")
projection_record = {
    "projection_id": projection["projection_id"],
    "projection_kind": projection["projection_kind"],
    "role_kind": projection["role_kind"],
    "policy_sha256": projection["policy_sha256"],
    "source_documents": projection["source_documents"],
}
organizations_divergences = []
excluded_by_pair = {
    (detail["action_name"], detail["resource_arn"]): detail
    for detail in excluded_details
}
organizations_by_pair = {
    (detail["action_name"], detail["resource_arn"]): detail
    for detail in organizations_details
}
if set(excluded_by_pair) != set(organizations_by_pair):
    fail(f"principal runs returned different action/resource pairs for {case['case_id']}")
for pair in sorted(excluded_by_pair):
    excluded_detail = excluded_by_pair[pair]
    organizations_detail = organizations_by_pair[pair]
    if excluded_detail["decision_observed"] == organizations_detail["decision_observed"]:
        continue
    organizations_divergences.append({
        "action_name": pair[0],
        "resource_arn": pair[1],
        "scp_excluded": excluded_detail,
        "default": organizations_detail,
    })
record = {
    "case_id": case["case_id"],
    "mode": "principal",
    "projection": projection_record,
    "document_hashes_submitted": {
        "put_role_policy": [{"sha256": projection["policy_sha256"]}],
        "custom_lane": [{"sha256": value} for value in custom_hashes],
    },
    "source_document_hash_agrees_with_custom_lane": custom_hashes == [source_document["sha256"]],
    "custom_lane": {
        "decision_observed": custom_decision,
        "matched_sids": custom_sids,
    },
    "scp_excluded": {
        "decision_observed": excluded_decision,
        "matched_statement_sources": excluded_sources,
        "matched_sids": excluded_sids,
        "agrees_with_custom_lane": same_decision,
    },
    "default": {
        "decision_observed": organizations_decision,
        "matched_statement_sources": organizations_sources,
        "matched_sids": organizations_sids,
        "changed_from_scp_excluded": organizations_decision != excluded_decision,
    },
    "comparison": "agreement" if same_decision else "divergence",
    "organizations_divergences": organizations_divergences,
    "pass": True,
}
if not same_decision:
    record["divergence"] = {
        "observed_in": observed_in,
        "custom_lane": {
            "decision_observed": custom_decision,
            "matched_sids": custom_sids,
        },
        "scp_excluded": {
            "decision_observed": excluded_decision,
            "matched_sids": excluded_sids,
        },
        "default": {
            "decision_observed": organizations_decision,
            "matched_sids": organizations_sids,
        },
    }

print(json.dumps(record, sort_keys=True))
PY
}

simulation_failed=0
case_index=0
while IFS= read -r case_json; do
  case_file="$tmp_dir/case-$case_index.json"
  excluded_file="$tmp_dir/excluded-$case_index.json"
  organizations_file="$tmp_dir/organizations-$case_index.json"
  printf '%s\n' "$case_json" >"$case_file"
  projection_id="$(jq -r '.temporary_projection_id' <<<"$case_json")"
  role_name="$(jq -r --arg projection_id "$projection_id" \
    '.roles[] | select(.projection_id == $projection_id) | .name' "$role_plan")"
  projection="$(jq -c --arg projection_id "$projection_id" \
    '.roles[] | select(.projection_id == $projection_id)' "$role_plan")"
  actions=()
  jq -r '.action_names[]' <<<"$case_json" >"$tmp_dir/action-names"
  while IFS= read -r value; do actions+=("$value"); done <"$tmp_dir/action-names"
  resources=()
  jq -r '.resource_arns[]' <<<"$case_json" >"$tmp_dir/resource-arns"
  while IFS= read -r value; do resources+=("$value"); done <"$tmp_dir/resource-arns"
  context="$(jq -c '.context_entries // [] | sort_by(.ContextKeyName,.ContextKeyType,(.ContextKeyValues|join("\u0000")))' <<<"$case_json")"
  context_args=(--output json)
  [ "$context" = '[]' ] || context_args=(--context-entries "$context" --output json)

  call_capture iam simulate-principal-policy \
    --policy-source-arn "arn:aws:iam::$expect_account:role/$role_name" \
    --action-names "${actions[@]}" --resource-arns "${resources[@]}" \
    "${context_args[@]}" --policy-exclusion-list '{"PolicyType":"scp"}'
  if [ "$CALL_RC" -ne 0 ]; then
    echo "FAIL: SCP-excluded principal simulation failed for $(jq -r '.case_id' <<<"$case_json"): $CALL_ERROR" >&2
    simulation_failed=1
    break
  fi
  printf '%s\n' "$CALL_OUTPUT" >"$excluded_file"

  call_capture iam simulate-principal-policy \
    --policy-source-arn "arn:aws:iam::$expect_account:role/$role_name" \
    --action-names "${actions[@]}" --resource-arns "${resources[@]}" \
    "${context_args[@]}"
  if [ "$CALL_RC" -ne 0 ]; then
    echo "FAIL: Organizations-applied principal simulation failed for $(jq -r '.case_id' <<<"$case_json"): $CALL_ERROR" >&2
    simulation_failed=1
    break
  fi
  printf '%s\n' "$CALL_OUTPUT" >"$organizations_file"
  set +e
  evaluated="$(evaluate_case "$case_file" "$excluded_file" "$organizations_file" "$projection" 2>&1)"
  evaluate_rc=$?
  set -e
  if [ "$evaluate_rc" -ne 0 ]; then
    echo "$evaluated" >&2
    simulation_failed=1
    break
  fi
  printf '%s\n' "$evaluated" >>"$records"
  case_index=$((case_index + 1))
done < <(jq -c '.cases[]' "$role_plan")

if [ "$simulation_failed" -ne 0 ]; then
  exit 1
fi
if [ "$(wc -l <"$records" | tr -d ' ')" -ne "$(jq '.cases | length' "$role_plan")" ]; then
  echo "FAIL: role lane did not record every supported case" >&2
  exit 1
fi
main_succeeded=1
exit 0
