#!/usr/bin/env bash
# Execute IAM matrix vectors through SimulateCustomPolicy.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AWS_CLI_SH="${AWS_CLI_SH:-$REPO_ROOT/scripts/aws-cli.sh}"
VALIDATOR="$REPO_ROOT/scripts/iam-simulate-validate.py"
IAM_SIM_CORE="${IAM_SIM_CORE:-$REPO_ROOT/scripts/iam_simulate_core.py}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbit-iam-simulate-runner.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

if [ "${TARGET:-}" != aws ]; then
  echo "FAIL: TARGET must be exactly aws" >&2
  exit 2
fi

# shellcheck source=scripts/iam-matrix-documents.sh
source "$REPO_ROOT/scripts/iam-matrix-documents.sh"

python3 - "$REPO_ROOT" "$tmp_dir" "$AWS_CLI_SH" "$VALIDATOR" "$IAM_SIM_CORE" \
  "${core_documents[@]}" -- "$@" <<'PY'
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any, NoReturn


def fail(message: str, code: int = 1) -> NoReturn:
    raise SystemExitWithMessage(message, code)


class SystemExitWithMessage(Exception):
    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.message = message
        self.code = code


separator = sys.argv.index("--")
repo_root = Path(sys.argv[1])
scratch = Path(sys.argv[2])
aws_cli = Path(sys.argv[3])
validator = Path(sys.argv[4])
core_path = Path(sys.argv[5])
core_documents = sys.argv[6:separator]
cli_args = sys.argv[separator + 1 :]


sys.dont_write_bytecode = True


def load_core(path: Path) -> Any:
    spec = importlib.util.spec_from_file_location("iam_simulate_core", path)
    if spec is None or spec.loader is None:
        raise SystemExitWithMessage(f"cannot load IAM simulator core: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


core = load_core(core_path)
RunnerFailure = core.RunnerFailure

S3_DIFFERENT_AUTHORIZATION_ACTIONS = frozenset(
    {
        "s3:DeleteBucketOwnershipControls",
        "s3:DeleteBucketPublicAccessBlock",
    }
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Execute custom IAM simulator vectors")
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--vectors", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--only")
    return parser.parse_args(cli_args)


def read_json(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        fail(f"cannot read {label} {path}: {exc}")
    except json.JSONDecodeError as exc:
        fail(f"{label} is not valid JSON: {exc}")


def extract_plan(plan_path: Path) -> tuple[dict[str, str], str, str]:
    plan = read_json(plan_path, "plan")
    try:
        resources = plan["planned_values"]["root_module"]["resources"]
    except (KeyError, TypeError):
        fail("plan lacks planned_values.root_module.resources")
    if not isinstance(resources, list):
        fail("plan planned_values.root_module.resources must be an array")
    by_address: dict[str, list[dict[str, Any]]] = {}
    for resource in resources:
        if isinstance(resource, dict) and isinstance(resource.get("address"), str):
            by_address.setdefault(resource["address"], []).append(resource)

    documents: dict[str, str] = {}
    for address in core_documents:
        matches = by_address.get(address, [])
        if not matches:
            continue
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

    role_matches = by_address.get("aws_iam_role.plan_reader", [])
    if len(role_matches) != 1:
        fail("plan must contain exactly one aws_iam_role.plan_reader")
    role_values = role_matches[0].get("values")
    role_name = role_values.get("name") if isinstance(role_values, dict) else None
    if not isinstance(role_name, str):
        fail("plan reader role name is null or unknown")
    suffix_match = re.fullmatch(r"orbit-infra-(.+)-plan-reader", role_name)
    if suffix_match is None or not suffix_match.group(1):
        fail(f"cannot derive SUFFIX from plan reader role name: {role_name}")
    suffix = suffix_match.group(1)

    account_ids = sorted(set(re.findall(r"(?<![0-9])[0-9]{12}(?![0-9])", "\n".join(documents.values()))))
    if len(account_ids) > 1:
        fail(f"plan policy documents contain multiple account ids: {account_ids}")
    account_id = account_ids[0] if account_ids else "000000000000"
    return documents, account_id, suffix


def resolve_plan_document(plan_documents: dict[str, str], address: str) -> str:
    try:
        return plan_documents[address]
    except KeyError:
        fail(f"named policy document is absent from plan: {address}")


def isolated_policy(document_text: str, address: str, sid: str) -> str:
    document = json.loads(document_text)
    raw_statements = document["Statement"]
    statements = raw_statements if isinstance(raw_statements, list) else [raw_statements]
    matches = [
        statement
        for statement in statements
        if isinstance(statement, dict) and statement.get("Sid") == sid
    ]
    if not matches:
        fail(f"named Sid is absent from plan policy {address}: {sid}")
    if len(matches) != 1:
        fail(
            f"named Sid matches more than one statement in plan policy {address}: {sid}"
        )
    return json.dumps(
        {
            "Version": document.get("Version", "2012-10-17"),
            "Statement": matches,
        },
        separators=(",", ":"),
        ensure_ascii=False,
    )


def render(value: Any, account_id: str, suffix: str) -> Any:
    replacements = {"${ACCOUNT_ID}": account_id, "${SUFFIX}": suffix}
    if isinstance(value, str):
        for token, replacement in replacements.items():
            value = value.replace(token, replacement)
        unknown = re.search(r"\$\{[^}]+\}", value)
        if unknown:
            fail(f"rendered vector retains unknown template: {unknown.group(0)}")
        return value
    if isinstance(value, list):
        return [render(item, account_id, suffix) for item in value]
    if isinstance(value, dict):
        rendered: dict[str, Any] = {}
        for raw_key, raw_value in value.items():
            key = render(raw_key, account_id, suffix)
            if key in rendered:
                fail(f"template rendering creates duplicate object key: {key}")
            rendered[key] = render(raw_value, account_id, suffix)
        return rendered
    return value


def normalize_context(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    normalized = []
    for entry in entries:
        normalized.append({
            "ContextKeyName": entry["ContextKeyName"],
            "ContextKeyValues": sorted(entry["ContextKeyValues"]),
            "ContextKeyType": entry["ContextKeyType"],
        })
    return sorted(normalized, key=lambda item: json.dumps(item, sort_keys=True, separators=(",", ":")))


def load_vectors(
    vector_dir: Path, only: str | None, account_id: str, suffix: str
) -> list[dict[str, Any]]:
    if not vector_dir.is_dir():
        fail(f"vector directory not found: {vector_dir}")
    loaded = []
    for path in sorted(vector_dir.rglob("*.json")):
        checked = subprocess.run(
            [sys.executable, str(validator), str(path), "--jsonl"],
            text=True,
            capture_output=True,
            check=False,
        )
        if checked.returncode != 0:
            detail = checked.stderr.strip() or checked.stdout.strip()
            fail(f"vector validation failed for {path}: {detail}")
        try:
            flattened = [json.loads(line) for line in checked.stdout.splitlines()]
        except json.JSONDecodeError as exc:
            fail(f"vector validator emitted invalid JSONL for {path}: {exc}")
        if not flattened:
            fail(f"vector validator emitted no cases for {path}")
        for vector in flattened:
            prefix = f"case:{vector['document']}:{vector['sid']}:"
            if not vector["case_id"].startswith(prefix) or vector["case_id"] == prefix:
                fail(f"case id exact prefix mismatch: expected {prefix}")
            if only is None or vector["case_id"] == only:
                loaded.append(render(vector, account_id, suffix))
    if not loaded:
        fail(f"no vectors selected{f' for --only {only}' if only else ''}")
    if only is not None and len(loaded) != 1:
        fail(f"--only selected {len(loaded)} vectors for {only}")
    case_ids = [vector["case_id"] for vector in loaded]
    if len(case_ids) != len(set(case_ids)):
        fail("vector directory repeats a case_id")
    return loaded


def prepare_vector(vector: dict[str, Any], plan_documents: dict[str, str]) -> dict[str, Any]:
    mode = vector["simulation_mode"]
    address = vector["document"]
    document_text = resolve_plan_document(plan_documents, address)
    if mode == "custom-isolated":
        policies = [isolated_policy(document_text, address, vector["sid"])]
        boundaries: list[str] = []
    else:
        policies = [document_text]
        policies.extend(vector.get("synthetic_policy_input_list", []))
        boundaries = [
            resolve_plan_document(plan_documents, boundary_address)
            for boundary_address in vector.get(
                "permissions_boundary_policy_input_list", []
            )
        ]
    context = normalize_context(vector.get("context_entries", []))
    return {
        "vector": vector,
        "policies": policies,
        "boundaries": boundaries,
        "context": context,
        "documents": core.submitted_documents(policies, boundaries),
    }


def group_vectors(prepared: list[dict[str, Any]]) -> list[list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for item in prepared:
        vector = item["vector"]
        key = json.dumps(
            {
                "policies": item["policies"],
                "boundaries": item["boundaries"],
                "context": item["context"],
                "assertion_kind": vector["assertion_kind"],
                "required": sorted(vector["expect"]["matched_sid_required"]),
                "forbidden": sorted(vector["expect"]["matched_sid_forbidden"]),
                "resource_arns_omitted": not vector["resource_arns"],
            },
            sort_keys=True,
            separators=(",", ":"),
        )
        groups.setdefault(key, []).append(item)
    batches = [groups[key] for key in sorted(groups)]
    for batch in batches:
        pairs: dict[tuple[str, str], tuple[str, tuple[Any, ...]]] = {}
        for item in batch:
            vector = item["vector"]
            expectation = (
                vector["assertion_kind"],
                vector["expect"].get("decision"),
                tuple(sorted(vector["expect"]["matched_sid_required"])),
                tuple(sorted(vector["expect"]["matched_sid_forbidden"])),
            )
            for action in vector["action_names"]:
                for resource in vector["resource_arns"]:
                    pair = (action, resource)
                    if pair in pairs and pairs[pair][1] != expectation:
                        raise SystemExitWithMessage(
                            "expectation-disagreeing duplicate action/resource pair in batch: "
                            f"{action} {resource} ({pairs[pair][0]} and {vector['case_id']})"
                        )
                    pairs.setdefault(pair, (vector["case_id"], expectation))
    return batches


def shared_call_case_ids(
    batch: list[dict[str, Any]], case_id: str
) -> list[str]:
    return sorted(
        item["vector"]["case_id"]
        for item in batch
        if item["vector"]["case_id"] != case_id
    )


def aws_call(argv: list[str]) -> dict[str, Any]:
    try:
        base = float(os.environ.get("IAM_SIM_RETRY_BASE_SECONDS", "1"))
    except ValueError:
        raise RunnerFailure("IAM_SIM_RETRY_BASE_SECONDS must be numeric")
    if base < 0:
        raise RunnerFailure("IAM_SIM_RETRY_BASE_SECONDS must not be negative")
    last_detail = ""
    for attempt in range(1, 6):
        result = subprocess.run(
            [str(aws_cli), *argv],
            text=True,
            capture_output=True,
            check=False,
            env=os.environ.copy(),
        )
        detail = result.stderr.strip() or result.stdout.strip()
        if result.returncode == 0:
            try:
                response = json.loads(result.stdout)
            except json.JSONDecodeError as exc:
                raise RunnerFailure(f"AWS simulator returned invalid JSON: {exc}") from exc
            if not isinstance(response, dict):
                raise RunnerFailure("AWS simulator response top level is not an object")
            return response
        if result.returncode == 124:
            raise RunnerFailure("AWS simulator timed out with exit 124")
        throttled = "(Throttling)" in detail or "(RequestLimitExceeded)" in detail
        if not throttled:
            raise RunnerFailure(f"AWS simulator call failed with exit {result.returncode}: {detail}")
        last_detail = detail
        if attempt < 5:
            time.sleep(base * (2 ** (attempt - 1)))
    raise RunnerFailure(f"AWS simulator throttling failed after 5 attempts: {last_detail}")


def batch_call(batch: list[dict[str, Any]]) -> dict[str, Any]:
    first = batch[0]
    actions = sorted(
        {action for item in batch for action in item["vector"]["action_names"]}
    )
    resources = sorted({resource for item in batch for resource in item["vector"]["resource_arns"]})
    direct_actions = [
        action for action in actions if action not in S3_DIFFERENT_AUTHORIZATION_ACTIONS
    ]
    different_authorization_actions = [
        action for action in actions if action in S3_DIFFERENT_AUTHORIZATION_ACTIONS
    ]
    combined_results: list[Any] = []
    for action_group in (direct_actions, different_authorization_actions):
        if not action_group:
            continue
        argv = [
            "iam",
            "simulate-custom-policy",
            "--policy-input-list",
            *first["policies"],
        ]
        if first["boundaries"]:
            argv.extend(
                ["--permissions-boundary-policy-input-list", *first["boundaries"]]
            )
        argv.extend(["--action-names", *action_group])
        if resources:
            argv.extend(["--resource-arns", *resources])
        if first["context"]:
            argv.extend([
                "--context-entries",
                json.dumps(first["context"], separators=(",", ":")),
            ])
        argv.extend(["--no-paginate", "--output", "json"])
        response = aws_call(argv)
        if "EvaluationResults" not in response:
            return response
        results = response["EvaluationResults"]
        if not isinstance(results, list):
            return response
        combined_results.extend(results)
    return {"EvaluationResults": combined_results}


def map_batch(
    batch: list[dict[str, Any]], response: dict[str, Any]
) -> list[dict[str, Any]]:
    payload = {
        "response": response,
        "requests": [
            {
                "action_names": item["vector"]["action_names"],
                "resource_arns": item["vector"]["resource_arns"],
                "policy_input_list": item["policies"],
                "permissions_boundary_policy_input_list": item["boundaries"],
            }
            for item in batch
        ],
    }
    completed = subprocess.run(
        [sys.executable, str(core_path), "map-batch"],
        input=json.dumps(payload, separators=(",", ":")),
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        if detail.startswith("FAIL: "):
            detail = detail[6:]
        raise RunnerFailure(detail or "shared IAM simulator core failed")
    try:
        mapped = json.loads(completed.stdout)
        results = mapped["results"]
    except (json.JSONDecodeError, KeyError, TypeError) as exc:
        raise RunnerFailure(f"shared IAM simulator core returned invalid JSON: {exc}") from exc
    if not isinstance(results, list) or len(results) != len(batch):
        raise RunnerFailure("shared IAM simulator core returned the wrong result count")
    return results


def evaluate(
    item: dict[str, Any], mapping: dict[str, Any]
) -> tuple[Any, list[str], list[str]]:
    if isinstance(mapping.get("error"), str):
        raise RunnerFailure(mapping["error"])
    vector = item["vector"]
    details = mapping.get("details")
    matched = mapping.get("matched_sids")
    if not isinstance(details, list) or not isinstance(matched, list):
        raise RunnerFailure("shared IAM simulator core returned an invalid mapping")
    observed = {
        (detail["action_name"], detail["resource_arn"]): detail["decision_observed"]
        for detail in details
    }

    errors: list[str] = []
    expect = vector["expect"]
    if vector["assertion_kind"] == "decision":
        per_resource = expect.get("resource_decisions")
        for (action, resource), decision in observed.items():
            expected = per_resource[resource] if per_resource is not None else expect["decision"]
            if decision != expected:
                errors.append(f"decision mismatch for {action} {resource}: expected {expected}, observed {decision}")
    for sid in expect["matched_sid_required"]:
        if sid not in matched:
            errors.append(f"required matched Sid is absent: {sid}")
    for sid in expect["matched_sid_forbidden"]:
        if sid in matched:
            errors.append(f"forbidden matched Sid is present: {sid}")
    return mapping["decision_observed"], matched, errors


def hashes(item: dict[str, Any]) -> dict[str, list[dict[str, str]]]:
    return core.document_hashes(item["policies"], item["boundaries"])


def write_report(
    path: Path, records: list[dict[str, Any]], expected_case_ids: list[str]
) -> None:
    record_case_ids = [record["case_id"] for record in records]
    repeated = sorted(
        case_id for case_id in set(record_case_ids) if record_case_ids.count(case_id) > 1
    )
    if repeated:
        fail(f"report repeats selected case_id: {repeated[0]}")
    missing = sorted(set(expected_case_ids) - set(record_case_ids))
    if missing:
        fail(f"report omits selected case_id: {missing[0]}")
    unexpected = sorted(set(record_case_ids) - set(expected_case_ids))
    if unexpected:
        fail(f"report contains unselected case_id: {unexpected[0]}")
    summary = {
        "total": len(records),
        "passed": sum(record["pass"] is True for record in records),
        "failed": sum(record["pass"] is False for record in records),
        "runner_failures": sum("runner_failure" in record for record in records),
    }
    payload = {"records": sorted(records, key=lambda record: record["case_id"]), "summary": summary}
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = scratch / "report.json"
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def main() -> int:
    args = parse_args()
    plan_documents, account_id, suffix = extract_plan(args.plan)
    vectors = load_vectors(args.vectors, args.only, account_id, suffix)
    expected_case_ids = [vector["case_id"] for vector in vectors]
    prepared = [prepare_vector(vector, plan_documents) for vector in vectors]
    try:
        batches = group_vectors(prepared)
    except SystemExitWithMessage as exc:
        records = []
        for item in prepared:
            vector = item["vector"]
            records.append({
                "case_id": vector["case_id"],
                "decision_observed": None,
                "matched_sids": [],
                "shared_call_case_ids": [],
                "expect": vector["expect"],
                "pass": False,
                "mode": vector["simulation_mode"],
                "document_hashes_submitted": hashes(item),
                "runner_failure": exc.message,
            })
        write_report(args.report, records, expected_case_ids)
        print(f"FAIL: {exc.message}", file=sys.stderr)
        return exc.code
    records: list[dict[str, Any]] = []
    failure_messages: list[str] = []
    for batch in batches:
        try:
            response = batch_call(batch)
            mappings = map_batch(batch, response)
        except RunnerFailure as exc:
            for item in batch:
                vector = item["vector"]
                records.append({
                    "case_id": vector["case_id"],
                    "decision_observed": None,
                    "matched_sids": [],
                    "shared_call_case_ids": shared_call_case_ids(
                        batch, vector["case_id"]
                    ),
                    "expect": vector["expect"],
                    "pass": False,
                    "mode": vector["simulation_mode"],
                    "document_hashes_submitted": hashes(item),
                    "runner_failure": str(exc),
                })
            failure_messages.append(str(exc))
            continue
        for item, mapping in zip(batch, mappings):
            vector = item["vector"]
            try:
                decision, matched, errors = evaluate(item, mapping)
                record = {
                    "case_id": vector["case_id"],
                    "decision_observed": decision,
                    "matched_sids": matched,
                    "shared_call_case_ids": shared_call_case_ids(
                        batch, vector["case_id"]
                    ),
                    "expect": vector["expect"],
                    "pass": not errors,
                    "mode": vector["simulation_mode"],
                    "document_hashes_submitted": hashes(item),
                }
                if errors:
                    record["errors"] = errors
                    failure_messages.extend(errors)
            except RunnerFailure as exc:
                record = {
                    "case_id": vector["case_id"],
                    "decision_observed": None,
                    "matched_sids": [],
                    "shared_call_case_ids": shared_call_case_ids(
                        batch, vector["case_id"]
                    ),
                    "expect": vector["expect"],
                    "pass": False,
                    "mode": vector["simulation_mode"],
                    "document_hashes_submitted": hashes(item),
                    "runner_failure": str(exc),
                }
                failure_messages.append(str(exc))
            records.append(record)
    write_report(args.report, records, expected_case_ids)
    if failure_messages:
        print(f"FAIL: {failure_messages[0]}", file=sys.stderr)
        return 1
    print(f"PASS: IAM simulator custom lane ({len(records)} case(s))")
    return 0


try:
    raise SystemExit(main())
except SystemExitWithMessage as exc:
    print(f"FAIL: {exc.message}", file=sys.stderr)
    raise SystemExit(exc.code)
except RunnerFailure as exc:
    print(f"FAIL: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
