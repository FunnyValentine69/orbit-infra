#!/usr/bin/env bash
# shellcheck disable=SC2329 # Trap handlers are invoked indirectly.
# Project IAM matrix policies onto temporary roles and simulate each principal.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AWS_CLI_SH="${AWS_CLI_SH:-$REPO_ROOT/scripts/aws-cli.sh}"
VALIDATOR="$REPO_ROOT/scripts/iam-simulate-validate.py"
IAM_SIM_CORE="${IAM_SIM_CORE:-$REPO_ROOT/scripts/iam_simulate_core.py}"
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

recorded_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
run_id="${IAM_SIM_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM}"
if ! [[ "$run_id" =~ ^[A-Za-z0-9+=,.@_-]{1,32}$ ]]; then
  echo "FAIL: IAM_SIM_RUN_ID must be 1-32 IAM-name characters" >&2
  exit 2
fi
retry_base_seconds="${IAM_SIM_RETRY_BASE_SECONDS:-1}"
if ! [[ "$retry_base_seconds" =~ ^[0-9]+$ ]]; then
  echo "FAIL: IAM_SIM_RETRY_BASE_SECONDS must be a non-negative integer" >&2
  exit 2
fi
tag_key=OrbitIamSimulationRun
tag_value="$run_id"
nonce_tag_key=OrbitIamSimulationNonce
nonce_value=""
if ! nonce_value="$(LC_ALL=C od -An -N16 -tx1 /dev/urandom | tr -d '[:space:]')" || \
   ! [[ "$nonce_value" =~ ^[0-9a-f]{32}$ ]]; then
  echo "FAIL: could not generate a 32-character ownership nonce" >&2
  exit 1
fi
expected_tags_json="$(jq -cn \
  --arg run_key "$tag_key" --arg run_value "$tag_value" \
  --arg nonce_key "$nonce_tag_key" --arg nonce_value "$nonce_value" \
  '[{Key:$run_key,Value:$run_value},{Key:$nonce_key,Value:$nonce_value}]')"
role_plan="$tmp_dir/role-plan.json"
case_stream="$tmp_dir/cases.bin"
records="$tmp_dir/records.jsonl"
manual_notes="$tmp_dir/manual-cleanup.txt"
custom_report_sha256=""
if [ "$dry_run" -eq 0 ]; then
  custom_report_snapshot="$tmp_dir/custom-report.json"
  if ! cp -- "$custom_report" "$custom_report_snapshot"; then
    echo "FAIL: could not snapshot custom report: $custom_report" >&2
    rm -rf "$tmp_dir"
    exit 1
  fi
  custom_report="$custom_report_snapshot"
  custom_report_sha256="$(python3 - "$custom_report" <<'PY_DIGEST'
import hashlib
from pathlib import Path
import sys

print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY_DIGEST
)"
fi
: >"$records"
: >"$manual_notes"

prepare_args=(
  "$REPO_ROOT" "$VALIDATOR" "$IAM_SIM_CORE" "$plan" "$vectors" "$expect_account" "$run_id"
  "$role_plan" "$case_stream" "$custom_report" "$dry_run" "$recorded_at"
  "$custom_report_sha256"
)
if [ -n "$only" ]; then
  prepare_args+=("$only")
fi
python3 - "${core_documents[@]}" -- "${prepare_args[@]}" <<'PY'
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

separator = sys.argv.index("--")
core_documents = sys.argv[1:separator]
repo_root = Path(sys.argv[separator + 1])
validator = Path(sys.argv[separator + 2])
core_path = Path(sys.argv[separator + 3])
plan_path = Path(sys.argv[separator + 4])
vectors_path = Path(sys.argv[separator + 5])
account_id = sys.argv[separator + 6]
run_id = sys.argv[separator + 7]
output_path = Path(sys.argv[separator + 8])
case_stream_path = Path(sys.argv[separator + 9])
custom_report_path = Path(sys.argv[separator + 10]) if sys.argv[separator + 10] else None
dry_run = sys.argv[separator + 11] == "1"
recorded_at = sys.argv[separator + 12]
custom_report_sha256 = sys.argv[separator + 13] or None
only = sys.argv[separator + 14] if len(sys.argv) > separator + 14 else None


sys.dont_write_bytecode = True


def load_core(path):
    spec = importlib.util.spec_from_file_location("iam_simulate_core", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"FAIL: cannot load IAM simulator core: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


core = load_core(core_path)


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
if not isinstance(reader_name, str):
    fail("plan reader role name is null or unknown")
suffix_match = re.fullmatch(r"orbit-infra-(.+)-plan-reader", reader_name)
if suffix_match is None:
    fail(f"cannot derive SUFFIX from plan reader role name: {reader_name}")
suffix = suffix_match.group(1)
plan_account_ids = sorted(set(re.findall(
    r"(?<![0-9])[0-9]{12}(?![0-9])", "\n".join(documents.values())
)))
if len(plan_account_ids) > 1:
    fail(f"plan policy documents contain multiple account ids: {plan_account_ids}")
placeholder_account = "000000000000"
vector_account_id = plan_account_ids[0] if plan_account_ids else placeholder_account
if vector_account_id not in (placeholder_account, account_id):
    fail(f"plan account mismatch: plan {vector_account_id}, expected {account_id}")


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
checked = subprocess.run(
    [sys.executable, str(validator), str(vectors_path), "--jsonl"],
    text=True,
    capture_output=True,
    check=False,
)
if checked.returncode != 0:
    fail(
        f"vector validation failed for {vectors_path}: "
        f"{checked.stderr.strip() or checked.stdout.strip()}"
    )
try:
    flattened = [json.loads(line) for line in checked.stdout.splitlines()]
except json.JSONDecodeError as exc:
    fail(f"vector validator emitted invalid JSONL for {vectors_path}: {exc}")
if not flattened:
    fail(f"vector validator emitted no cases for {vectors_path}")
all_vectors = []
for vector in flattened:
    prefix = f"case:{vector['document']}:{vector['sid']}:"
    if not vector["case_id"].startswith(prefix) or vector["case_id"] == prefix:
        fail(f"case id exact prefix mismatch: expected {prefix}")
    all_vectors.append(render(vector))
vectors = all_vectors
if only is not None:
    selected = [vector for vector in vectors if vector["case_id"] == only]
    if not selected:
        fail(f"--only {only} excluded: case id was not found")
    if len(selected) != 1:
        fail(
            f"--only {only} excluded: duplicate exact case id "
            f"({len(selected)} matches)"
        )
    vectors = selected
case_ids = [vector["case_id"] for vector in vectors]
if len(case_ids) != len(set(case_ids)):
    fail("vector directory repeats a case_id")

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
        try:
            core.statement_spans(documents[address])
        except core.RunnerFailure as exc:
            fail(str(exc))
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
            "sha256": core.document_sha256(documents[address]),
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
            "role_kind": role,
            "projection_id": projection_id,
            "projection_kind": projection_kind,
            "name": role_name,
            "policy_name": policy_name,
            "policy_document": policy,
            "policy_sha256": core.document_sha256(policy),
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

if not dry_run:
    for projection in roles:
        readiness_case = None
        source_addresses = {
            entry["address"] for entry in projection["source_documents"]
        }
        for vector in all_vectors:
            expect = vector.get("expect", {})
            required_sids = expect.get("matched_sid_required", [])
            decision = expect.get("decision")
            if (
                vector.get("document") not in source_addresses
                or vector.get("assertion_kind") != "decision"
                or not required_sids
            ):
                continue
            qualifies = decision == "allowed"
            if decision == "explicitDeny":
                policy = json.loads(documents[vector["document"]])
                statements = policy["Statement"]
                if isinstance(statements, dict):
                    statements = [statements]
                deny_sids = {
                    statement.get("Sid")
                    for statement in statements
                    if statement.get("Effect") == "Deny"
                }
                qualifies = any(sid in deny_sids for sid in required_sids)
            if not qualifies:
                continue
            readiness_case = vector
            break
        if readiness_case is None:
            fail(
                "role projection lacks a Sid-matching readiness case: "
                f"{projection['projection_id']}"
            )
        action_groups = core.split_action_authorization_groups(
            readiness_case["action_names"]
        )
        if len(action_groups) != 1:
            fail(
                "role projection readiness case needs more than one request: "
                f"{projection['projection_id']} {readiness_case['case_id']}"
            )
        projection["readiness_case"] = readiness_case
        projection["propagation_attempts"] = {"readback": 0, "probe": 0}
if not supported:
    if only is not None:
        reason = next(
            exclusion["reason"]
            for exclusion in exclusions
            if exclusion.get("case_id") == only
        )
        fail(f"--only {only} excluded: {reason}")
    fail("role lane selected no supported custom cases")

if not dry_run:
    try:
        custom_payload = json.loads(custom_report_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, AttributeError) as exc:
        fail(f"cannot read custom report: {exc}")
    custom_records = custom_payload.get("records") if isinstance(custom_payload, dict) else None
    if not isinstance(custom_records, list):
        fail("custom report records must be an array")
    for vector in supported:
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
        expected_mode = vector["simulation_mode"]
        observed_mode = custom_record.get("mode")
        if observed_mode != expected_mode:
            fail(
                f"custom report mode mismatch for {vector['case_id']}: "
                f"report={observed_mode!r} vector={expected_mode!r}"
            )
        if expected_mode == "custom":
            submitted_hashes = custom_record.get("document_hashes_submitted")
            hash_entries = (
                submitted_hashes.get("policy_input_list", [])
                if isinstance(submitted_hashes, dict)
                else []
            )
            custom_hashes = [
                entry.get("sha256") if isinstance(entry, dict) else None
                for entry in hash_entries
            ] if isinstance(hash_entries, list) else []
            if len(custom_hashes) > 1:
                fail(
                    f"role lane cannot represent synthetic identity documents for {vector['case_id']}: "
                    f"custom report submitted {len(custom_hashes)} policy_input_list documents"
                )
            plan_hash = core.document_sha256(documents[vector["document"]])
            if custom_hashes != [plan_hash]:
                observed_hash = (
                    custom_hashes[0]
                    if len(custom_hashes) == 1
                    else json.dumps(custom_hashes, separators=(",", ":"))
                )
                fail(
                    f"custom report policy hash mismatch for {vector['case_id']}: "
                    f"report={observed_hash} plan={plan_hash}"
                )

initial_principal = f"arn:aws:iam::{account_id}:<redacted-principal>"
assume_policy = json.dumps({
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"AWS": initial_principal},
        "Action": "sts:AssumeRole",
    }],
}, separators=(",", ":"))
payload = {
    "account_id": account_id,
    "vector_account_id": vector_account_id,
    "suffix": suffix,
    "run_id": run_id,
    "recorded_at": recorded_at,
    "custom_report_sha256": custom_report_sha256,
    "caller_arn": initial_principal,
    "assume_role_policy": assume_policy,
    "assume_role_policy_sha256": core.document_sha256(assume_policy),
    "roles": roles,
    "cases": supported,
    "exclusions": exclusions,
}
output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
roles_by_projection = {role["projection_id"]: role for role in roles}
with case_stream_path.open("wb") as stream:
    for case in supported:
        projection = roles_by_projection[case["temporary_projection_id"]]
        context = sorted(
            case.get("context_entries", []),
            key=lambda entry: (
                entry["ContextKeyName"],
                entry["ContextKeyType"],
                "\0".join(entry["ContextKeyValues"]),
            ),
        )
        action_groups = core.split_action_authorization_groups(case["action_names"])
        fields = [case["case_id"], projection["name"], str(len(action_groups))]
        for action_group in action_groups:
            fields.append(str(len(action_group)))
            fields.extend(action_group)
        fields.extend([
            str(len(case["resource_arns"])),
            *case["resource_arns"],
            json.dumps(context, separators=(",", ":")),
        ])
        for field in fields:
            stream.write(field.encode("utf-8") + b"\0")
PY

role_count="$(jq '.roles | length' "$role_plan")"
cleanup_complete=0
cleanup_failed=0
cleanup_in_progress=0
ownership_mismatch=0
signal_status=0
signal_name=""
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
  local expected_tags=$2
  local allow_missing=${3:-0}
  call_capture iam list-role-tags --role-name "$role_name" --output json
  if [ "$CALL_RC" -ne 0 ]; then
    if [ "$allow_missing" -eq 1 ] && grep -Fq '(NoSuchEntity)' <<<"$CALL_ERROR"; then
      return 2
    fi
    append_manual_note "manual cleanup: could not re-read ownership tags for $role_name"
    return 1
  fi
  if ! jq -e --argjson expected "$expected_tags" '
    (.Tags // []) as $actual
    | ($expected | type == "array" and length > 0)
      and all(
        $expected[];
        . as $expected_tag
        | any($actual[]?; .Key == $expected_tag.Key and .Value == $expected_tag.Value)
      )
  ' <<<"$CALL_OUTPUT" >/dev/null; then
    ownership_mismatch=1
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
  if [ "$ownership_mismatch" -eq 1 ]; then
    return 1
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
    verify_owned_tag "$role_name" "$expected_tags_json" 1
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
      if [ "$CALL_RC" -ne 0 ] && ! grep -Fq '(NoSuchEntity)' <<<"$CALL_ERROR"; then
        append_manual_note "manual cleanup: delete-role-policy failed for $role_name"
        continue
      fi
    fi
    if ! verify_owned_tag "$role_name" "$expected_tags_json" 0; then
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
  python3 - "$IAM_SIM_CORE" "$role_plan" "$records" "$manual_notes" "$report" "$nonce_value" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True

core_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("iam_simulate_core", core_path)
if spec is None or spec.loader is None:
    raise SystemExit(f"FAIL: cannot load IAM simulator core: {core_path}")
core = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = core
spec.loader.exec_module(core)

role_plan = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
records_path = Path(sys.argv[3])
notes_path = Path(sys.argv[4])
report_path = Path(sys.argv[5])
records = [json.loads(line) for line in records_path.read_text(encoding="utf-8").splitlines() if line]
notes = notes_path.read_text(encoding="utf-8").splitlines()
nonce = sys.argv[6]


def redact_sensitive(value, replacements):
    if isinstance(value, str):
        for original, replacement in replacements:
            value = value.replace(original, replacement)
        return value
    if isinstance(value, list):
        return [redact_sensitive(item, replacements) for item in value]
    if isinstance(value, dict):
        redacted = {}
        for key, item in value.items():
            redacted_key = redact_sensitive(key, replacements)
            if redacted_key in redacted:
                raise SystemExit("FAIL: sensitive-value redaction creates a duplicate report key")
            redacted[redacted_key] = redact_sensitive(item, replacements)
        return redacted
    return value


case_exclusions = {}
for exclusion in role_plan["exclusions"]:
    if "case_id" in exclusion:
        reason = exclusion["reason"]
        case_exclusions[reason] = case_exclusions.get(reason, 0) + 1
placeholder_account = "000000000000"
payload = {
    "account": role_plan["account_id"],
    "account_redacted": True,
    "plan_account": role_plan["vector_account_id"],
    "plan_account_redacted": role_plan["vector_account_id"] != placeholder_account,
    "run_id": role_plan["run_id"],
    "recorded_at": role_plan["recorded_at"],
    "custom_report_sha256": role_plan["custom_report_sha256"],
    "ownership_nonce": nonce,
    "ownership_nonce_redacted": True,
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
redacted_principal = "arn:aws:iam::000000000000:<redacted-principal>"
redactions = [(role_plan["caller_arn"], redacted_principal)]
redactions.append((role_plan["account_id"], placeholder_account))
if role_plan["vector_account_id"] != placeholder_account:
    redactions.append((role_plan["vector_account_id"], placeholder_account))
redactions.append((nonce, "<redacted>"))
payload = redact_sensitive(payload, redactions)
serialized = json.dumps(payload, sort_keys=True, separators=(",", ":"))
principal_identity = role_plan["caller_arn"].split(":", 5)[-1]
if principal_identity != "<redacted-principal>" and (
    role_plan["caller_arn"] in serialized or principal_identity in serialized
):
    raise SystemExit("FAIL: role report contains caller principal identity")
report_trust = json.loads(payload["projection"]["assume_role_policy"])
if report_trust["Statement"][0]["Principal"] != {"AWS": redacted_principal}:
    raise SystemExit("FAIL: role report does not fully redact the caller principal ARN")
core.write_report(report_path, payload)
PY
}

on_exit() {
  local rc=$?
  trap - EXIT
  cleanup_in_progress=1
  if [ "$dry_run" -eq 0 ]; then
    cleanup_roles || rc=1
    write_report || rc=1
  fi
  trap - TERM INT
  cleanup_in_progress=0
  rm -rf "$tmp_dir"
  if [ "$signal_status" -ne 0 ]; then
    echo "FAIL: terminated by $signal_name" >&2
    rc=$signal_status
  elif [ "$rc" -eq 0 ] && [ "$main_succeeded" -eq 1 ]; then
    echo "PASS: IAM simulator role lane"
  fi
  exit "$rc"
}

record_signal() {
  local status=$1
  local name=$2
  if [ "$signal_status" -eq 0 ]; then
    signal_status=$status
    signal_name=$name
  fi
  if [ "$cleanup_in_progress" -eq 0 ]; then
    exit "$status"
  fi
}

on_term() {
  record_signal 143 TERM
}

on_int() {
  record_signal 130 INT
}

# The EXIT trap is armed before the first create-role call. Intent files are
# written before each create so cleanup also covers the signal-in-create gap.
trap on_exit EXIT
trap on_term TERM
trap on_int INT

role_call_args() {
  local index=$1
  ROLE_NAME="$(jq -r ".roles[$index].name" "$role_plan")"
  POLICY_NAME="$(jq -r ".roles[$index].policy_name" "$role_plan")"
  POLICY_DOCUMENT="$(jq -r ".roles[$index].policy_document" "$role_plan")"
}

read_case_record() {
  local group_count group_index action_count action_index count value context
  IFS= read -r -d '' CASE_ID <&3 || return 1
  IFS= read -r -d '' CASE_ROLE_NAME <&3
  IFS= read -r -d '' group_count <&3
  CASE_ACTION_GROUP_SIZES=()
  CASE_GROUPED_ACTIONS=()
  for ((group_index = 0; group_index < group_count; group_index++)); do
    IFS= read -r -d '' action_count <&3
    CASE_ACTION_GROUP_SIZES+=("$action_count")
    for ((action_index = 0; action_index < action_count; action_index++)); do
      IFS= read -r -d '' value <&3
      CASE_GROUPED_ACTIONS+=("$value")
    done
  done
  IFS= read -r -d '' count <&3
  CASE_RESOURCES=()
  for ((action_index = 0; action_index < count; action_index++)); do
    IFS= read -r -d '' value <&3
    CASE_RESOURCES+=("$value")
  done
  IFS= read -r -d '' context <&3
  CASE_CONTEXT_ARGS=(--output json)
  [ "$context" = '[]' ] || CASE_CONTEXT_ARGS=(--context-entries "$context" --output json)
}


principal_simulation_pass() {
  local response_prefix=$1
  local case_index=$2
  local include_exclusion=$3
  local group_index group_size action_offset=0 group_file output_file
  local -a action_group call_args response_files
  response_files=()
  for ((group_index = 0; group_index < ${#CASE_ACTION_GROUP_SIZES[@]}; group_index++)); do
    group_size=${CASE_ACTION_GROUP_SIZES[$group_index]}
    action_group=("${CASE_GROUPED_ACTIONS[@]:action_offset:group_size}")
    action_offset=$((action_offset + group_size))
    call_args=(
      iam simulate-principal-policy
      --policy-source-arn "arn:aws:iam::$expect_account:role/$CASE_ROLE_NAME"
      --action-names "${action_group[@]}"
    )
    if [ "${#CASE_RESOURCES[@]}" -gt 0 ]; then
      call_args+=(--resource-arns "${CASE_RESOURCES[@]}")
    fi
    call_args+=("${CASE_CONTEXT_ARGS[@]}")
    if [ "$include_exclusion" -eq 1 ]; then
      call_args+=(--policy-exclusion-list '{"PolicyType":"scp"}')
    fi
    call_capture "${call_args[@]}"
    if [ "$CALL_RC" -ne 0 ]; then
      return 1
    fi
    if [ "$dry_run" -eq 0 ]; then
      group_file="$tmp_dir/$response_prefix-$case_index-group-$group_index.json"
      printf '%s\n' "$CALL_OUTPUT" >"$group_file"
      response_files+=("$group_file")
    fi
  done
  if [ "$dry_run" -eq 0 ]; then
    output_file="$tmp_dir/$response_prefix-$case_index.json"
    if ! jq -s '{EvaluationResults: [.[].EvaluationResults[]]}' \
      "${response_files[@]}" >"$output_file"; then
      CALL_RC=1
      CALL_ERROR="principal simulation responses could not be combined"
      return 1
    fi
  fi
}


load_readiness_call() {
  local index=$1 value context
  PROBE_ACTIONS=()
  while IFS= read -r value; do
    PROBE_ACTIONS+=("$value")
  done < <(jq -r ".roles[$index].readiness_case.action_names[]" "$role_plan")
  PROBE_RESOURCES=()
  while IFS= read -r value; do
    PROBE_RESOURCES+=("$value")
  done < <(jq -r ".roles[$index].readiness_case.resource_arns[]" "$role_plan")
  context="$(jq -c ".roles[$index].readiness_case.context_entries" "$role_plan")"
  PROBE_CONTEXT_ARGS=(--output json)
  [ "$context" = '[]' ] || PROBE_CONTEXT_ARGS=(--context-entries "$context" --output json)
}


validate_readiness_probe() {
  local index=$1 response_path=$2
  python3 - "$REPO_ROOT/scripts/iam_simulate_core.py" "$role_plan" "$index" "$response_path" <<'PY_READINESS'
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
core_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("iam_simulate_core_readiness", core_path)
if spec is None or spec.loader is None:
    raise SystemExit(f"FAIL: cannot load IAM simulator core: {core_path}")
core = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = core
spec.loader.exec_module(core)
role_plan = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
role = role_plan["roles"][int(sys.argv[3])]
case = role["readiness_case"]
response = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
try:
    mapped = core.map_request(response, {
        "action_names": case["action_names"],
        "resource_arns": case["resource_arns"],
        "policy_input_list": [role["policy_document"]],
        "permissions_boundary_policy_input_list": [],
        "bind_to_single_document": True,
        "ignore_organizations": True,
    })
except core.RunnerFailure as exc:
    raise SystemExit(f"FAIL: readiness response could not be mapped: {exc}") from exc
expect = case["expect"]
per_resource = expect.get("resource_decisions")
required = set(expect["matched_sid_required"])
for detail in mapped["details"]:
    expected_decision = (
        per_resource[detail["resource_arn"]]
        if isinstance(per_resource, dict)
        else expect["decision"]
    )
    if detail["decision_observed"] != expected_decision:
        raise SystemExit("FAIL: readiness decision does not match the selected case")
    if not required.issubset(detail["matched_sids"]):
        raise SystemExit("FAIL: readiness response lacks a required Sid")
PY_READINESS
}


wait_for_policy_readback() {
  local attempt delay
  READBACK_ATTEMPTS=0
  for ((attempt = 1; attempt <= 5; attempt++)); do
    READBACK_ATTEMPTS=$attempt
    call_capture iam get-role-policy --role-name "$ROLE_NAME" \
      --policy-name "$POLICY_NAME" --query PolicyDocument --output text
    if [ "$CALL_RC" -eq 0 ] && [ "$CALL_OUTPUT" = "$POLICY_DOCUMENT" ]; then
      return 0
    fi
    if [ "$attempt" -lt 5 ]; then
      delay=$((retry_base_seconds * (1 << (attempt - 1))))
      sleep "$delay"
    fi
  done
  return 1
}


wait_for_readiness_probe() {
  local index=$1 attempt delay response_path
  local -a call_args
  PROBE_ATTEMPTS=0
  load_readiness_call "$index"
  for ((attempt = 1; attempt <= 5; attempt++)); do
    PROBE_ATTEMPTS=$attempt
    call_args=(
      iam simulate-principal-policy
      --policy-source-arn "arn:aws:iam::$expect_account:role/$ROLE_NAME"
      --action-names "${PROBE_ACTIONS[@]}"
    )
    if [ "${#PROBE_RESOURCES[@]}" -gt 0 ]; then
      call_args+=(--resource-arns "${PROBE_RESOURCES[@]}")
    fi
    call_args+=("${PROBE_CONTEXT_ARGS[@]}")
    call_args+=(--policy-exclusion-list '{"PolicyType":"scp"}')
    call_capture "${call_args[@]}"
    if [ "$CALL_RC" -eq 0 ]; then
      response_path="$tmp_dir/readiness-$index-$attempt.json"
      printf '%s\n' "$CALL_OUTPUT" >"$response_path"
      if validate_readiness_probe "$index" "$response_path" >/dev/null 2>&1; then
        return 0
      fi
    fi
    if [ "$attempt" -lt 5 ]; then
      delay=$((retry_base_seconds * (1 << (attempt - 1))))
      sleep "$delay"
    fi
  done
  return 1
}


record_propagation_attempts() {
  local index=$1 readback=$2 probe=$3 next_plan
  next_plan="$tmp_dir/role-plan-next.json"
  if ! jq --argjson readback "$readback" --argjson probe "$probe" \
    ".roles[$index].propagation_attempts = {readback:\$readback, probe:\$probe}" \
    "$role_plan" >"$next_plan"; then
    echo "FAIL: could not record propagation attempts for $ROLE_NAME" >&2
    return 1
  fi
  mv "$next_plan" "$role_plan"
}


bind_assume_role_policy() {
  python3 - "$IAM_SIM_CORE" "$role_plan" "$1" <<'PY_TRUST'
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
core_path = Path(sys.argv[1])
role_plan_path = Path(sys.argv[2])
caller_arn = sys.argv[3]
spec = importlib.util.spec_from_file_location("iam_simulate_core_trust", core_path)
if spec is None or spec.loader is None:
    raise SystemExit(f"FAIL: cannot load IAM simulator core: {core_path}")
core = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = core
spec.loader.exec_module(core)
if not caller_arn.startswith("arn:aws:") or caller_arn.endswith(":root"):
    raise SystemExit("FAIL: temporary role trust must name exactly the invoking identity")
principal = caller_arn
assume_policy_object = {
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"AWS": principal},
        "Action": "sts:AssumeRole",
    }],
}
observed_principal = assume_policy_object["Statement"][0]["Principal"]
if observed_principal != {"AWS": caller_arn}:
    raise SystemExit("FAIL: temporary role trust must name exactly the invoking identity")
assume_policy = json.dumps(assume_policy_object, separators=(",", ":"))
role_plan = json.loads(role_plan_path.read_text(encoding="utf-8"))
role_plan["caller_arn"] = caller_arn
role_plan["assume_role_policy"] = assume_policy
role_plan["assume_role_policy_sha256"] = core.document_sha256(assume_policy)
role_plan_path.write_text(json.dumps(role_plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY_TRUST
}


print_dry_run_inventory() {
  local index case_index=0
  call_capture sts get-caller-identity --output json
  for ((index = 0; index < role_count; index++)); do
    role_call_args "$index"
    call_capture iam create-role --role-name "$ROLE_NAME" \
      --assume-role-policy-document "$(jq -r '.assume_role_policy' "$role_plan")" \
      --tags "Key=$tag_key,Value=$tag_value" \
        "Key=$nonce_tag_key,Value=$nonce_value"
  done
  for ((index = 0; index < role_count; index++)); do
    role_call_args "$index"
    call_capture iam list-role-tags --role-name "$ROLE_NAME" --output json
  done
  for ((index = 0; index < role_count; index++)); do
    role_call_args "$index"
    call_capture iam put-role-policy --role-name "$ROLE_NAME" \
      --policy-name "$POLICY_NAME" --policy-document "$POLICY_DOCUMENT"
  done
  exec 3<"$case_stream"
  while read_case_record; do
    principal_simulation_pass excluded "$case_index" 1
    principal_simulation_pass organizations "$case_index" 0
    case_index=$((case_index + 1))
  done
  exec 3<&-
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
  bind_assume_role_policy "arn:aws:iam::$expect_account:<redacted-principal>"
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
caller_arn="$(jq -er '.Arn | select(type == "string" and length > 0)' <<<"$CALL_OUTPUT")" || {
  echo "FAIL: caller identity response lacks Arn" >&2
  exit 1
}
if [ "$actual_account" != "$expect_account" ]; then
  echo "FAIL: caller account mismatch: expected $expect_account, observed $actual_account" >&2
  exit 1
fi
bind_assume_role_policy "$caller_arn"

for ((index = 0; index < role_count; index++)); do
  role_call_args "$index"
  printf 'intended\n' >"$(role_status_file "$index")"
  call_capture iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$(jq -r '.assume_role_policy' "$role_plan")" \
    --tags "Key=$tag_key,Value=$tag_value" \
      "Key=$nonce_tag_key,Value=$nonce_value"
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
  if ! verify_owned_tag "$ROLE_NAME" "$expected_tags_json" 0; then
    exit 1
  fi
done

for ((index = 0; index < role_count; index++)); do
  role_call_args "$index"
  printf 'intended\n' >"$(role_policy_file "$index")"
  call_capture iam put-role-policy --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" --policy-document "$POLICY_DOCUMENT"
  if [ "$CALL_RC" -ne 0 ]; then
    echo "FAIL: put-role-policy failed for $ROLE_NAME: $CALL_ERROR" >&2
    exit 1
  fi
  printf 'loaded\n' >"$(role_policy_file "$index")"
  if ! wait_for_policy_readback; then
    record_propagation_attempts "$index" "$READBACK_ATTEMPTS" 0
    echo "FAIL: inline policy readback propagation exhausted for $ROLE_NAME after 5 attempts" >&2
    exit 1
  fi
  if ! wait_for_readiness_probe "$index"; then
    record_propagation_attempts "$index" "$READBACK_ATTEMPTS" "$PROBE_ATTEMPTS"
    echo "FAIL: inline policy readiness probe propagation exhausted for $ROLE_NAME after 5 attempts" >&2
    exit 1
  fi
  record_propagation_attempts "$index" "$READBACK_ATTEMPTS" "$PROBE_ATTEMPTS"
done

map_role_pass() {
  local response_prefix=$1
  local ignore_organizations=$2
  local output_path=$3
  jq -cn \
    --arg role_plan_path "$role_plan" \
    --arg response_directory "$tmp_dir" \
    --arg response_prefix "$response_prefix" \
    --argjson ignore_organizations "$ignore_organizations" '
      {
        role_plan_path: $role_plan_path,
        response_directory: $response_directory,
        response_prefix: $response_prefix,
        ignore_organizations: $ignore_organizations
      }
    ' | python3 "$IAM_SIM_CORE" map-role-pass >"$output_path"
}


evaluate_all_cases() {
  local excluded_mapping=$1
  local organizations_mapping=$2
  python3 - "$role_plan" "$excluded_mapping" "$organizations_mapping" \
    "$custom_report" <<'PY'
import json
from pathlib import Path
import sys

role_plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
excluded_payload = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
organizations_payload = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
custom = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))


def fail(message):
    raise SystemExit(f"FAIL: {message}")


def observation_matches(case, details):
    if not isinstance(details, list):
        return False, ["per-pair details are missing"]
    resources = case["resource_arns"] or ["*"]
    expected_pairs = {
        (action, resource)
        for action in case["action_names"]
        for resource in resources
    }
    observed_pairs = {
        (detail.get("action_name"), detail.get("resource_arn"))
        for detail in details
        if isinstance(detail, dict)
    }
    errors = []
    if len(details) != len(expected_pairs) or observed_pairs != expected_pairs:
        errors.append("action/resource pairs differ from the vector")
    expect = case["expect"]
    per_resource = expect.get("resource_decisions")
    for detail in details:
        if not isinstance(detail, dict):
            errors.append("per-pair detail is invalid")
            continue
        action = detail.get("action_name")
        resource = detail.get("resource_arn")
        if case["assertion_kind"] == "decision":
            expected_decision = (
                per_resource.get(resource)
                if isinstance(per_resource, dict)
                else expect.get("decision")
            )
            observed_decision = detail.get("decision_observed")
            if observed_decision != expected_decision:
                errors.append(
                    f"decision differs from expectation for {action} {resource}: "
                    f"expected {expected_decision}, observed {observed_decision}"
                )
        matched = detail.get("matched_sids")
        if not isinstance(matched, list):
            errors.append(f"matched Sids are invalid for {action} {resource}")
            continue
        for sid in expect["matched_sid_required"]:
            if sid not in matched:
                errors.append(f"required matched Sid is absent for {action} {resource}: {sid}")
        for sid in expect["matched_sid_forbidden"]:
            if sid in matched:
                errors.append(f"forbidden matched Sid is present for {action} {resource}: {sid}")
    return not errors, errors


cases = role_plan["cases"]
roles = {role["projection_id"]: role for role in role_plan["roles"]}
excluded_results = excluded_payload.get("results")
organizations_results = organizations_payload.get("results")
if not isinstance(excluded_results, list) or len(excluded_results) != len(cases):
    fail("SCP-excluded bulk mapper returned the wrong result count")
if not isinstance(organizations_results, list) or len(organizations_results) != len(cases):
    fail("Organizations-applied bulk mapper returned the wrong result count")
for case, excluded, organizations in zip(
    cases, excluded_results, organizations_results
):
    for mapping in (excluded, organizations):
        if isinstance(mapping, dict) and isinstance(mapping.get("error"), str):
            fail(mapping["error"])
    projection = roles[case["temporary_projection_id"]]
    excluded_decision = excluded["decision_observed"]
    excluded_sources = excluded["matched_statement_sources"]
    excluded_sids = excluded["matched_sids"]
    excluded_details = excluded["details"]
    organizations_decision = organizations["decision_observed"]
    organizations_sources = organizations["matched_statement_sources"]
    organizations_sids = organizations["matched_sids"]
    organizations_details = organizations["details"]
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
    custom_details = custom_record.get("details")
    if not isinstance(custom_details, list):
        fail(f"custom report per-pair details are invalid for {case['case_id']}")
    custom_hashes = [
        entry.get("sha256")
        for entry in custom_record.get("document_hashes_submitted", {}).get("policy_input_list", [])
    ]
    source_document = next(
        entry for entry in projection["source_documents"]
        if entry["address"] == case["document"]
    )
    same_decision = excluded_decision == custom_decision
    role_matches_expectation, role_errors = observation_matches(case, excluded_details)
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
        "expect": case["expect"],
        "projection": projection_record,
        "document_hashes_submitted": {
            "put_role_policy": [{"sha256": projection["policy_sha256"]}],
            "custom_lane": [{"sha256": value} for value in custom_hashes],
        },
        "source_document_hash_agrees_with_custom_lane": (
            custom_hashes == [source_document["sha256"]]
        ),
        "custom_lane": {
            "decision_observed": custom_decision,
            "matched_sids": custom_sids,
            "details": custom_details,
        },
        "scp_excluded": {
            "decision_observed": excluded_decision,
            "matched_statement_sources": excluded_sources,
            "matched_sids": excluded_sids,
            "details": excluded_details,
            "agrees_with_custom_lane": same_decision,
            "matches_expectation": role_matches_expectation,
        },
        "default": {
            "decision_observed": organizations_decision,
            "matched_statement_sources": organizations_sources,
            "matched_sids": organizations_sids,
            "details": organizations_details,
            "changed_from_scp_excluded": organizations_decision != excluded_decision,
        },
        "comparison": "agreement" if same_decision else "divergence",
        "organizations_divergences": organizations_divergences,
        "pass": (
            custom_hashes == [source_document["sha256"]]
            and role_matches_expectation
        ),
    }
    if role_errors:
        record["errors"] = role_errors
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
exec 3<"$case_stream"
while read_case_record; do
  if ! principal_simulation_pass excluded "$case_index" 1; then
    echo "FAIL: SCP-excluded principal simulation failed for $CASE_ID: $CALL_ERROR" >&2
    simulation_failed=1
    break
  fi
  if ! principal_simulation_pass organizations "$case_index" 0; then
    echo "FAIL: Organizations-applied principal simulation failed for $CASE_ID: $CALL_ERROR" >&2
    simulation_failed=1
    break
  fi
  case_index=$((case_index + 1))
done
exec 3<&-

if [ "$simulation_failed" -eq 0 ]; then
  excluded_mapping="$tmp_dir/excluded-mapping.json"
  organizations_mapping="$tmp_dir/organizations-mapping.json"
  if ! map_role_pass excluded false "$excluded_mapping" || \
     ! map_role_pass organizations true "$organizations_mapping"; then
    simulation_failed=1
  elif ! evaluate_all_cases "$excluded_mapping" "$organizations_mapping" >"$records"; then
    simulation_failed=1
  else
    if ! failed_record_count="$(jq -s '[.[] | select(.pass != true)] | length' "$records")"; then
      echo "FAIL: role lane could not count expectation-mismatching records" >&2
      simulation_failed=1
    elif [ "$failed_record_count" -ne 0 ]; then
      echo "FAIL: role lane recorded $failed_record_count case(s) that do not match vector expectations" >&2
      simulation_failed=1
    fi
  fi
fi

if [ "$simulation_failed" -ne 0 ]; then
  exit 1
fi
if [ "$(wc -l <"$records" | tr -d ' ')" -ne "$(jq '.cases | length' "$role_plan")" ]; then
  echo "FAIL: role lane did not record every supported case" >&2
  exit 1
fi
main_succeeded=1
exit 0
