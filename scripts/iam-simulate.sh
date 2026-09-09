#!/usr/bin/env bash
# Execute IAM matrix vectors through SimulateCustomPolicy.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AWS_CLI_SH="${AWS_CLI_SH:-$REPO_ROOT/scripts/aws-cli.sh}"
VALIDATOR="$REPO_ROOT/scripts/iam-simulate-validate.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbit-iam-simulate-runner.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

if [ "${TARGET:-}" != aws ]; then
  echo "FAIL: TARGET must be exactly aws" >&2
  exit 2
fi

# shellcheck source=scripts/iam-matrix-documents.sh
source "$REPO_ROOT/scripts/iam-matrix-documents.sh"

python3 - "$REPO_ROOT" "$tmp_dir" "$AWS_CLI_SH" "$VALIDATOR" \
  "${core_documents[@]}" -- "$@" <<'PY'
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
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


class RunnerFailure(Exception):
    pass


@dataclass(frozen=True)
class SubmittedDocument:
    source: str
    text: str
    spans: tuple[tuple[int, int, str], ...]


separator = sys.argv.index("--")
repo_root = Path(sys.argv[1])
scratch = Path(sys.argv[2])
aws_cli = Path(sys.argv[3])
validator = Path(sys.argv[4])
core_documents = sys.argv[5:separator]
cli_args = sys.argv[separator + 1 :]


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


def statement_spans(policy: str) -> tuple[tuple[int, int, str], ...]:
    decoder = json.JSONDecoder()

    def whitespace(index: int) -> int:
        while index < len(policy) and policy[index].isspace():
            index += 1
        return index

    index = whitespace(0)
    if index >= len(policy) or policy[index] != "{":
        raise RunnerFailure("submitted policy is not a JSON object")
    index += 1
    raw_spans: list[tuple[int, int, str]] = []
    found = False
    while True:
        index = whitespace(index)
        if index < len(policy) and policy[index] == "}":
            break
        try:
            key, key_end = decoder.raw_decode(policy, index)
        except json.JSONDecodeError as exc:
            raise RunnerFailure(f"cannot locate policy Statement spans: {exc}") from exc
        if not isinstance(key, str):
            raise RunnerFailure("submitted policy has a non-string object key")
        index = whitespace(key_end)
        if index >= len(policy) or policy[index] != ":":
            raise RunnerFailure("submitted policy object key lacks a colon")
        index = whitespace(index + 1)
        if key != "Statement":
            try:
                _, index = decoder.raw_decode(policy, index)
            except json.JSONDecodeError as exc:
                raise RunnerFailure(f"cannot scan submitted policy: {exc}") from exc
        else:
            found = True
            if index < len(policy) and policy[index] == "[":
                index += 1
                while True:
                    index = whitespace(index)
                    if index < len(policy) and policy[index] == "]":
                        index += 1
                        break
                    start = index
                    try:
                        statement, end = decoder.raw_decode(policy, start)
                    except json.JSONDecodeError as exc:
                        raise RunnerFailure(f"cannot scan submitted statement: {exc}") from exc
                    if not isinstance(statement, dict) or not isinstance(statement.get("Sid"), str):
                        raise RunnerFailure("every submitted statement must carry a non-empty Sid")
                    raw_spans.append((start, end, statement["Sid"]))
                    index = whitespace(end)
                    if index < len(policy) and policy[index] == ",":
                        index += 1
                        continue
                    if index < len(policy) and policy[index] == "]":
                        index += 1
                        break
                    raise RunnerFailure("submitted Statement array has invalid separators")
            else:
                start = index
                try:
                    statement, end = decoder.raw_decode(policy, start)
                except json.JSONDecodeError as exc:
                    raise RunnerFailure(f"cannot scan submitted statement: {exc}") from exc
                if not isinstance(statement, dict) or not isinstance(statement.get("Sid"), str):
                    raise RunnerFailure("every submitted statement must carry a non-empty Sid")
                raw_spans.append((start, end, statement["Sid"]))
                index = end
        index = whitespace(index)
        if index < len(policy) and policy[index] == ",":
            index += 1
            continue
        if index < len(policy) and policy[index] == "}":
            break
        raise RunnerFailure("submitted policy object has invalid separators")
    if not found or not raw_spans:
        raise RunnerFailure("submitted policy has no statements to attribute")
    return tuple(
        (len(policy[:start].encode("utf-8")), len(policy[:end].encode("utf-8")), sid)
        for start, end, sid in raw_spans
    )


def submitted_documents(policy_inputs: list[str], boundaries: list[str]) -> list[SubmittedDocument]:
    submitted = []
    for index, text in enumerate(policy_inputs, 1):
        submitted.append(SubmittedDocument(f"PolicyInputList.{index}", text, statement_spans(text)))
    for index, text in enumerate(boundaries, 1):
        submitted.append(SubmittedDocument(f"PermissionsBoundaryPolicyInputList.{index}", text, statement_spans(text)))
    return submitted


def position_offset(policy: str, position: Any) -> int:
    if not isinstance(position, dict):
        raise RunnerFailure("matched statement position is not an object")
    line = position.get("Line")
    column = position.get("Column")
    if type(line) is not int or type(column) is not int or line < 1 or column < 1:
        raise RunnerFailure("matched statement position has invalid line or column")
    lines = policy.encode("utf-8").splitlines(keepends=True)
    if line > len(lines):
        raise RunnerFailure("matched statement position line is outside the submitted document")
    offset = sum(len(item) for item in lines[: line - 1]) + column - 1
    line_body = lines[line - 1].rstrip(b"\r\n")
    if column - 1 > len(line_body):
        raise RunnerFailure("matched statement position column is outside the submitted document")
    return offset


def map_match(match: Any, documents: list[SubmittedDocument]) -> str:
    if not isinstance(match, dict):
        raise RunnerFailure("MatchedStatements entry is not an object")
    source = match.get("SourcePolicyId")
    by_source: dict[str, list[SubmittedDocument]] = {}
    for document in documents:
        by_source.setdefault(document.source, []).append(document)
    submitted_labels = sorted(by_source)
    if source not in by_source:
        raise RunnerFailure(
            f"unrecognised SourcePolicyId {source}; submitted labels: {', '.join(submitted_labels)}"
        )
    mapped: list[str] = []
    touched: list[str] = []
    for document in by_source[source]:
        start = position_offset(document.text, match.get("StartPosition"))
        end = position_offset(document.text, match.get("EndPosition"))
        for span_start, span_end, sid in document.spans:
            contains_start = span_start <= start < span_end
            contains_end = span_start <= end < span_end
            if contains_start or contains_end:
                touched.append(sid)
            if contains_start and contains_end:
                mapped.append(sid)
    if len(touched) > 1 or len(mapped) > 1:
        raise RunnerFailure(f"ambiguous matched statement position from {source}")
    if not mapped:
        raise RunnerFailure(f"unmapped matched statement position from {source}")
    return mapped[0]


def normalize_context(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    normalized = []
    for entry in entries:
        normalized.append({
            "ContextKeyName": entry["ContextKeyName"],
            "ContextKeyValues": sorted(entry["ContextKeyValues"]),
            "ContextKeyType": entry["ContextKeyType"],
        })
    return sorted(normalized, key=lambda item: json.dumps(item, sort_keys=True, separators=(",", ":")))


def load_vectors(vector_dir: Path, only: str | None, account_id: str, suffix: str) -> list[dict[str, Any]]:
    if not vector_dir.is_dir():
        fail(f"vector directory not found: {vector_dir}")
    loaded = []
    for path in sorted(vector_dir.rglob("*.json")):
        checked = subprocess.run(
            [sys.executable, str(validator), str(path)],
            text=True,
            capture_output=True,
            check=False,
        )
        if checked.returncode != 0:
            detail = checked.stderr.strip() or checked.stdout.strip()
            fail(f"vector validation failed for {path}: {detail}")
        vector = read_json(path, "vector")
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
        "documents": submitted_documents(policies, boundaries),
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
    actions = sorted({action for item in batch for action in item["vector"]["action_names"]})
    resources = sorted({resource for item in batch for resource in item["vector"]["resource_arns"]})
    argv = ["iam", "simulate-custom-policy", "--policy-input-list", *first["policies"]]
    if first["boundaries"]:
        argv.extend(["--permissions-boundary-policy-input-list", *first["boundaries"]])
    argv.extend(["--action-names", *actions, "--resource-arns", *resources])
    if first["context"]:
        argv.extend(["--context-entries", json.dumps(first["context"], separators=(",", ":"))])
    argv.extend(["--no-paginate", "--output", "json"])
    return aws_call(argv)


def evaluate(item: dict[str, Any], response: dict[str, Any]) -> tuple[Any, list[str], list[str]]:
    vector = item["vector"]
    results = response.get("EvaluationResults")
    if not isinstance(results, list):
        raise RunnerFailure("AWS simulator response lacks EvaluationResults array")
    observed: dict[tuple[str, str], str] = {}
    matched_sids: set[str] = set()
    for action in vector["action_names"]:
        action_results = [result for result in results if isinstance(result, dict) and result.get("EvalActionName") == action]
        if len(action_results) != 1:
            raise RunnerFailure(f"expected one action-level EvaluationResult for {action}, found {len(action_results)}")
        resource_results = action_results[0].get("ResourceSpecificResults")
        if not isinstance(resource_results, list):
            raise RunnerFailure(f"action-level result lacks ResourceSpecificResults for {action}")
        for resource in vector["resource_arns"]:
            matches = [result for result in resource_results if isinstance(result, dict) and result.get("EvalResourceName") == resource]
            if len(matches) == 0:
                raise RunnerFailure(f"submitted resource ARN is absent from response: {action} {resource}")
            if len(matches) != 1:
                raise RunnerFailure(f"response repeats submitted resource ARN: {action} {resource}")
            result = matches[0]
            decision = result.get("EvalResourceDecision")
            if decision not in {"allowed", "implicitDeny", "explicitDeny"}:
                raise RunnerFailure(f"resource result has unknown decision for {action} {resource}")
            observed[(action, resource)] = decision
            raw_matches = result.get("MatchedStatements", [])
            if not isinstance(raw_matches, list):
                raise RunnerFailure(f"MatchedStatements is not an array for {action} {resource}")
            for raw_match in raw_matches:
                matched_sids.add(map_match(raw_match, item["documents"]))

    errors: list[str] = []
    expect = vector["expect"]
    if vector["assertion_kind"] == "decision":
        per_resource = expect.get("resource_decisions")
        for (action, resource), decision in observed.items():
            expected = per_resource[resource] if per_resource is not None else expect["decision"]
            if decision != expected:
                errors.append(f"decision mismatch for {action} {resource}: expected {expected}, observed {decision}")
    for sid in expect["matched_sid_required"]:
        if sid not in matched_sids:
            errors.append(f"required matched Sid is absent: {sid}")
    for sid in expect["matched_sid_forbidden"]:
        if sid in matched_sids:
            errors.append(f"forbidden matched Sid is present: {sid}")

    if len(vector["resource_arns"]) > 1 and len(vector["action_names"]) == 1:
        decision_observed: Any = {resource: observed[(vector["action_names"][0], resource)] for resource in sorted(vector["resource_arns"])}
    elif len(set(observed.values())) == 1:
        decision_observed = next(iter(observed.values()))
    else:
        decision_observed = {f"{action}|{resource}": decision for (action, resource), decision in sorted(observed.items())}
    return decision_observed, sorted(matched_sids), errors


def hashes(item: dict[str, Any]) -> dict[str, list[dict[str, str]]]:
    def entries(documents: list[str]) -> list[dict[str, str]]:
        return [{"sha256": hashlib.sha256(document.encode("utf-8")).hexdigest()} for document in documents]
    return {
        "policy_input_list": entries(item["policies"]),
        "permissions_boundary_policy_input_list": entries(item["boundaries"]),
    }


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
        for item in batch:
            vector = item["vector"]
            try:
                decision, matched, errors = evaluate(item, response)
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
