#!/usr/bin/env python3
"""Shared IAM simulator response mapping and submitted-document attribution."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from typing import Any, NamedTuple, NoReturn


class RunnerFailure(Exception):
    """A fail-closed IAM simulator response or attribution error."""


class SubmittedDocument(NamedTuple):
    source: str
    text: str
    spans: tuple[tuple[int, int, str], ...]


# Actions outside these explicit classes share the default request group.
ACTION_AUTHORIZATION_CLASSES: tuple[frozenset[str], ...] = (
    frozenset(
        {
            "s3:DeleteBucketOwnershipControls",
            "s3:DeleteBucketPublicAccessBlock",
        }
    ),
)


def _statement_sid(statement: Any, statement_index: int) -> str:
    if (
        not isinstance(statement, dict)
        or not isinstance(statement.get("Sid"), str)
        or not statement["Sid"].strip()
    ):
        raise RunnerFailure(
            f"submitted statement {statement_index} must carry a non-empty Sid"
        )
    return statement["Sid"]


def split_action_authorization_groups(action_names: list[str]) -> list[list[str]]:
    """Partition actions into groups accepted by one IAM simulator request."""
    groups = [[] for _ in range(len(ACTION_AUTHORIZATION_CLASSES) + 1)]
    classified: dict[str, int] = {}
    normalized_classes = tuple(
        frozenset(member.casefold() for member in action_class)
        for action_class in ACTION_AUTHORIZATION_CLASSES
    )
    for index, action_class in enumerate(normalized_classes, 1):
        for action in action_names:
            if action.casefold() not in action_class:
                continue
            if action in classified and classified[action] != index:
                raise RunnerFailure(
                    f"action belongs to multiple authorization classes: {action}"
                )
            classified[action] = index
    for action in action_names:
        groups[classified.get(action, 0)].append(action)
    return [group for group in groups if group]


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
                statement_index = 0
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
                    sid = _statement_sid(statement, statement_index)
                    raw_spans.append((start, end, sid))
                    statement_index += 1
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
                sid = _statement_sid(statement, 0)
                raw_spans.append((start, end, sid))
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
    return tuple(raw_spans)


def submitted_documents(
    policy_inputs: list[str], boundaries: list[str]
) -> list[SubmittedDocument]:
    submitted = []
    for index, text in enumerate(policy_inputs, 1):
        submitted.append(
            SubmittedDocument(f"PolicyInputList.{index}", text, statement_spans(text))
        )
    for index, text in enumerate(boundaries, 1):
        submitted.append(
            SubmittedDocument(
                f"PermissionsBoundaryPolicyInputList.{index}",
                text,
                statement_spans(text),
            )
        )
    return submitted


def position_offset(policy: str, position: Any) -> int:
    if not isinstance(position, dict):
        raise RunnerFailure("matched statement position is not an object")
    line = position.get("Line")
    column = position.get("Column")
    if type(line) is not int or type(column) is not int or line < 1 or column < 1:
        raise RunnerFailure("matched statement position has invalid line or column")
    lines = policy.splitlines(keepends=True)
    if line > len(lines):
        raise RunnerFailure(
            "matched statement position line is outside the submitted document"
        )
    offset = sum(len(item) for item in lines[: line - 1]) + column - 1
    line_body = lines[line - 1].rstrip("\r\n")
    if column - 1 > len(line_body):
        raise RunnerFailure(
            "matched statement position column is outside the submitted document"
        )
    return offset


def map_match(
    match: Any,
    documents: list[SubmittedDocument],
    bind_to_single_document: bool = False,
) -> str:
    if not isinstance(match, dict):
        raise RunnerFailure("MatchedStatements entry is not an object")
    source = match.get("SourcePolicyId")
    by_source: dict[str, list[SubmittedDocument]] = {}
    for document in documents:
        by_source.setdefault(document.source, []).append(document)
    submitted_labels = sorted(by_source)
    if bind_to_single_document and len(documents) == 1:
        candidates = documents
    elif source in by_source:
        candidates = by_source[source]
    else:
        raise RunnerFailure(
            f"unrecognised SourcePolicyId {source}; submitted labels: {', '.join(submitted_labels)}"
        )
    overlaps: list[str] = []
    diagnostics: list[tuple[SubmittedDocument, int, int]] = []
    for document in candidates:
        start = position_offset(document.text, match.get("StartPosition"))
        end = position_offset(document.text, match.get("EndPosition"))
        diagnostics.append((document, start, end))
        for span_start, span_end, sid in document.spans:
            if start < end and start < span_end and span_start < end:
                overlaps.append(sid)
    document, start, end = diagnostics[0]
    first_start, first_end, first_sid = document.spans[0]
    last_start, last_end, last_sid = document.spans[-1]
    detail = (
        f"document_length={len(document.text)} "
        f"statement_span_count={len(document.spans)} "
        f"returned_range=[{start},{end}) "
        f"first_span=[{first_start},{first_end}):{first_sid} "
        f"last_span=[{last_start},{last_end}):{last_sid}"
    )
    if len(overlaps) > 1:
        raise RunnerFailure(
            f"ambiguous matched statement position from {source}: "
            f"overlap_count={len(overlaps)} {detail}"
        )
    if not overlaps:
        raise RunnerFailure(
            f"unmapped matched statement position from {source}: "
            f"unmapped_offset={start} {detail}"
        )
    return overlaps[0]


def document_sha256(document: str) -> str:
    return hashlib.sha256(document.encode("utf-8")).hexdigest()


ROLE_KINDS = ("plan-reader", "deployer", "publisher")
ROLE_FOR_DOCUMENT = {
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
ROLE_POLICY_CHARACTER_LIMIT = 10240


def _combine_role_documents(
    role: str, addresses: list[str], documents: dict[str, str]
) -> str:
    versions = set()
    statements = []
    seen_sids = {}
    for address in addresses:
        document = documents.get(address)
        if not isinstance(document, str) or not document:
            raise RunnerFailure(f"projected policy document is missing: {address}")
        statement_spans(document)
        try:
            policy = json.loads(document)
        except json.JSONDecodeError as exc:
            raise RunnerFailure(
                f"projected policy document is invalid JSON: {address}: {exc}"
            ) from exc
        version = policy.get("Version") if isinstance(policy, dict) else None
        if not isinstance(version, str) or not version:
            raise RunnerFailure(f"projected policy document lacks Version: {address}")
        versions.add(version)
        raw_statements = policy.get("Statement")
        if isinstance(raw_statements, dict):
            raw_statements = [raw_statements]
        if not isinstance(raw_statements, list) or not raw_statements:
            raise RunnerFailure(f"projected policy document has no statements: {address}")
        for statement in raw_statements:
            sid = statement["Sid"]
            if sid in seen_sids and seen_sids[sid] != address:
                raise RunnerFailure(
                    f"duplicate Sid {sid} across {seen_sids[sid]} and {address}"
                )
            seen_sids[sid] = address
            statements.append(statement)
    if len(versions) != 1:
        raise RunnerFailure(
            f"role {role} policy documents disagree on Version: {sorted(versions)}"
        )
    return json.dumps(
        {"Version": next(iter(versions)), "Statement": statements},
        separators=(",", ":"),
    )


def build_role_projections(
    documents: dict[str, str], selected_roles: set[str] | None = None
) -> list[dict[str, Any]]:
    """Build deterministic combined or per-document temporary-role policies."""
    selected = set(ROLE_KINDS) if selected_roles is None else set(selected_roles)
    unknown = selected - set(ROLE_KINDS)
    if unknown:
        raise RunnerFailure(f"unknown role projection kind: {sorted(unknown)[0]}")
    projections = []
    for role in ROLE_KINDS:
        if role not in selected:
            continue
        addresses = sorted(
            address
            for address, mapped_role in ROLE_FOR_DOCUMENT.items()
            if mapped_role == role
        )
        combined_policy = _combine_role_documents(role, addresses, documents)
        combined_size = len(re.sub(r"\s", "", combined_policy))
        source_size = sum(
            len(re.sub(r"\s", "", documents[address])) for address in addresses
        )
        if combined_size <= ROLE_POLICY_CHARACTER_LIMIT:
            pass_specs = [("combined", addresses, combined_policy)]
        else:
            pass_specs = []
            for address in addresses:
                policy = documents[address]
                policy_size = len(re.sub(r"\s", "", policy))
                if policy_size > ROLE_POLICY_CHARACTER_LIMIT:
                    raise RunnerFailure(
                        "per-document projection exceeds 10240 characters for "
                        f"{address}: {policy_size}"
                    )
                pass_specs.append(("per-document", [address], policy))
        for projection_kind, source_addresses, policy in pass_specs:
            projection_id = (
                f"{role}:combined"
                if projection_kind == "combined"
                else f"{role}:{source_addresses[0]}"
            )
            redacted_policy = redact_report(policy, "policy_document")
            projections.append({
                "role_kind": role,
                "projection_id": projection_id,
                "projection_kind": projection_kind,
                "policy_document": policy,
                "policy_sha256": document_sha256(policy),
                "redacted_policy_sha256": document_sha256(redacted_policy),
                "policy_character_count": len(re.sub(r"\s", "", policy)),
                "source_character_count": (
                    source_size
                    if projection_kind == "combined"
                    else len(re.sub(r"\s", "", documents[source_addresses[0]]))
                ),
                "source_documents": [
                    {
                        "address": address,
                        "sha256": document_sha256(documents[address]),
                    }
                    for address in source_addresses
                ],
            })
    return projections


def _plan_role_documents(plan: Any) -> dict[str, str]:
    try:
        resources = plan["planned_values"]["root_module"]["resources"]
    except (KeyError, TypeError) as exc:
        raise RunnerFailure("role projection plan lacks root resources") from exc
    if not isinstance(resources, list):
        raise RunnerFailure("role projection plan resources must be an array")
    documents = {}
    for address in ROLE_FOR_DOCUMENT:
        matches = [
            resource
            for resource in resources
            if isinstance(resource, dict) and resource.get("address") == address
        ]
        if len(matches) != 1:
            raise RunnerFailure(
                f"role projection plan must contain exactly one {address}, "
                f"found {len(matches)}"
            )
        values = matches[0].get("values")
        policy = values.get("policy") if isinstance(values, dict) else None
        if not isinstance(policy, str) or not policy:
            raise RunnerFailure(
                f"role projection plan policy is null, unknown, or empty: {address}"
            )
        documents[address] = policy
    return documents


def validate_role_report_projections(plan: Any, role_report: Any) -> int:
    """Bind reported projection policy bytes to policies in a saved plan."""
    rebuilt = build_role_projections(_plan_role_documents(plan))
    reported = (
        role_report.get("projection", {}).get("roles")
        if isinstance(role_report, dict)
        else None
    )
    if not isinstance(reported, list):
        raise RunnerFailure("role report projection roles must be an array")
    reported_by_id = {}
    for projection in reported:
        projection_id = (
            projection.get("projection_id") if isinstance(projection, dict) else None
        )
        if not isinstance(projection_id, str) or projection_id in reported_by_id:
            raise RunnerFailure("role report contains an invalid or duplicate projection id")
        reported_by_id[projection_id] = projection
    rebuilt_ids = [projection["projection_id"] for projection in rebuilt]
    if set(reported_by_id) != set(rebuilt_ids):
        raise RunnerFailure("role report projection ids differ from the plan rebuild")
    for expected in rebuilt:
        projection_id = expected["projection_id"]
        observed = reported_by_id[projection_id]
        expected_policy_document = redact_report(
            expected["policy_document"], "policy_document"
        )
        if observed.get("policy_document") != expected_policy_document:
            raise RunnerFailure(
                f"role projection source policy differs for {projection_id}"
            )
        if observed.get("source_documents") != expected["source_documents"]:
            raise RunnerFailure(
                f"role projection source documents differ for {projection_id}"
            )
        if observed.get("policy_sha256") != expected["policy_sha256"]:
            raise RunnerFailure(
                f"role projection source sha256 differs for {projection_id}"
            )
        expected_redacted_sha256 = document_sha256(expected_policy_document)
        if observed.get("redacted_policy_sha256") != expected_redacted_sha256:
            raise RunnerFailure(
                f"role projection redacted sha256 differs for {projection_id}"
            )
    return len(rebuilt)


REPORT_PLACEHOLDER_ACCOUNT = "000000000000"
REPORT_REDACTED = "<redacted>"
REPORT_REDACTED_PRINCIPAL = "arn:aws:iam::000000000000:<redacted-principal>"
REPORT_RESOURCE_FIELDS = frozenset(
    {
        "NotResource",
        "Resource",
        "policy_document",
        "resource_arn",
        "resource_arns",
        "resource_decisions",
    }
)
REPORT_PRINCIPAL_ARN = re.compile(
    r"arn:aws:(?:"
    r"iam::[0-9]{12}:(?:user|role|assumed-role|group|federated-user)"
    r"|sts::[0-9]{12}:assumed-role"
    r")/[A-Za-z0-9+=,.@_/-]+"
)
REPORT_DIGEST = re.compile(
    r"(?<![0-9A-Fa-f])(?:[0-9A-Fa-f]{64}|[0-9A-Fa-f]{40})(?![0-9A-Fa-f])"
)
REPORT_IAM_ARN_ACCOUNT = re.compile(r"(arn:[^:\s]+:iam::)([0-9]{12})")
REPORT_ACCOUNT_ID = re.compile(r"[0-9]{12}")
REPORT_PRINCIPAL_ID = re.compile(
    r"(?<![A-Z0-9])(?:AIDA|AROA|ASIA|AKIA)[A-Z0-9]{12,}(?![A-Z0-9])"
)
REPORT_REQUEST_ID = re.compile(
    r"(?:x-amzn-)?request[-_]?id"
    r"(?:(?:\s*[:=]\s*|\s+)[A-Za-z0-9-]+)?",
    re.IGNORECASE,
)
REPORT_UUID = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)


def _redact_report_fragment(value: str) -> str:
    value = REPORT_PRINCIPAL_ID.sub(REPORT_REDACTED, value)
    value = REPORT_REQUEST_ID.sub(REPORT_REDACTED, value)
    value = REPORT_UUID.sub(REPORT_REDACTED, value)
    value = REPORT_IAM_ARN_ACCOUNT.sub(
        lambda match: match.group(1)
        + (
            match.group(2)
            if match.group(2) == REPORT_PLACEHOLDER_ACCOUNT
            else REPORT_PLACEHOLDER_ACCOUNT
        ),
        value,
    )
    return REPORT_ACCOUNT_ID.sub(
        lambda match: (
            match.group(0)
            if match.group(0) == REPORT_PLACEHOLDER_ACCOUNT
            else REPORT_PLACEHOLDER_ACCOUNT
        ),
        value,
    )


def _redact_report_text(value: str, *, redact_principal: bool = True) -> str:
    if redact_principal:
        value = REPORT_PRINCIPAL_ARN.sub(REPORT_REDACTED_PRINCIPAL, value)
    redacted: list[str] = []
    start = 0
    for digest in REPORT_DIGEST.finditer(value):
        redacted.append(_redact_report_fragment(value[start : digest.start()]))
        redacted.append(digest.group(0))
        start = digest.end()
    redacted.append(_redact_report_fragment(value[start:]))
    return "".join(redacted)


def redact_report(value: Any, field: str | None = None) -> Any:
    """Redact report identifiers recursively while preserving digest tokens."""
    if isinstance(value, str):
        return _redact_report_text(
            value, redact_principal=field not in REPORT_RESOURCE_FIELDS
        )
    if isinstance(value, list):
        return [redact_report(item, field) for item in value]
    if isinstance(value, tuple):
        return tuple(redact_report(item, field) for item in value)
    if isinstance(value, dict):
        redacted = {}
        for key, item in value.items():
            request_id_key = isinstance(key, str) and REPORT_REQUEST_ID.search(key)
            redacted_key = redact_report(key, field)
            if redacted_key in redacted:
                raise RunnerFailure("report redaction creates a duplicate key")
            redacted[redacted_key] = (
                REPORT_REDACTED if request_id_key else redact_report(item, key)
            )
        return redacted
    return value


def recorded_at_utc() -> str:
    """Return the current UTC second in the report timestamp format."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_report(path: Path, payload: dict[str, Any]) -> None:
    """Write a redacted stable report with one compact record or exclusion per line."""
    recorded_at = payload.get("recorded_at")
    if (
        not isinstance(recorded_at, str)
        or re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", recorded_at) is None
    ):
        raise RunnerFailure("report recorded_at must be UTC YYYY-MM-DDTHH:MM:SSZ")
    try:
        datetime.strptime(recorded_at, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as exc:
        raise RunnerFailure("report recorded_at must be UTC YYYY-MM-DDTHH:MM:SSZ") from exc
    payload = redact_report(payload)
    payload["redaction_applied"] = True
    keys = sorted(payload)
    lines = ["{"]
    for key_index, key in enumerate(keys):
        suffix = "," if key_index < len(keys) - 1 else ""
        value = payload[key]
        if key not in {"records", "exclusions"}:
            rendered = json.dumps(value, sort_keys=True, separators=(",", ":"))
            lines.append(f"  {json.dumps(key)}:{rendered}{suffix}")
            continue
        if not isinstance(value, list) or any(
            not isinstance(item, dict) for item in value
        ):
            raise RunnerFailure(f"report {key} must be an array of objects")
        rows = sorted(
            value,
            key=lambda item: (
                item.get("case_id", ""),
                json.dumps(item, sort_keys=True, separators=(",", ":")),
            ),
        )
        lines.append(f"  {json.dumps(key)}:[")
        for row_index, row in enumerate(rows):
            rendered = json.dumps(row, sort_keys=True, separators=(",", ":"))
            row_suffix = "," if row_index < len(rows) - 1 else ""
            lines.append(f"    {rendered}{row_suffix}")
        lines.append(f"  ]{suffix}")
    lines.append("}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            handle.write("\n".join(lines) + "\n")
        os.replace(temporary_path, path)
    except BaseException:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
        raise


def document_hashes(
    policy_inputs: list[str], boundaries: list[str]
) -> dict[str, list[dict[str, str]]]:
    def entries(documents: list[str]) -> list[dict[str, str]]:
        return [{"sha256": document_sha256(document)} for document in documents]

    return {
        "policy_input_list": entries(policy_inputs),
        "permissions_boundary_policy_input_list": entries(boundaries),
    }


def _source(match: dict[str, Any]) -> dict[str, Any]:
    return {
        "source_policy_id": match.get("SourcePolicyId"),
        "source_policy_type": match.get("SourcePolicyType"),
        "start_position": match.get("StartPosition"),
        "end_position": match.get("EndPosition"),
    }


def _ignore_match(match: dict[str, Any], ignore_organizations: bool) -> bool:
    source_type = match.get("SourcePolicyType")
    return (
        ignore_organizations
        and isinstance(source_type, str)
        and "organization" in source_type.lower()
    )


def map_evaluation_results(
    response: dict[str, Any],
    action_names: list[str],
    resource_arns: list[str],
    documents: list[SubmittedDocument],
    *,
    bind_to_single_document: bool = False,
    ignore_organizations: bool = False,
) -> dict[str, Any]:
    results = response.get("EvaluationResults")
    if not isinstance(results, list):
        raise RunnerFailure("AWS simulator response lacks EvaluationResults array")
    observed: dict[tuple[str, str], str] = {}
    matched_sources: list[dict[str, Any]] = []
    matched_sids: set[str] = set()
    details: list[dict[str, Any]] = []
    for action in action_names:
        action_results = [
            result
            for result in results
            if isinstance(result, dict) and result.get("EvalActionName") == action
        ]
        if len(action_results) != 1:
            raise RunnerFailure(
                f"expected one action-level EvaluationResult for {action}, found {len(action_results)}"
            )
        action_result = action_results[0]
        resource_results = (
            action_result["ResourceSpecificResults"]
            if "ResourceSpecificResults" in action_result
            else None
        )
        if "ResourceSpecificResults" in action_result and not isinstance(
            resource_results, list
        ):
            raise RunnerFailure(f"ResourceSpecificResults is not an array for {action}")
        resolved: list[tuple[str, dict[str, Any], str]] = []
        for resource in resource_arns:
            matches = []
            if isinstance(resource_results, list):
                matches = [
                    result
                    for result in resource_results
                    if isinstance(result, dict)
                    and result.get("EvalResourceName") == resource
                ]
            if len(matches) > 1:
                raise RunnerFailure(
                    f"response repeats submitted resource ARN: {action} {resource}"
                )
            if matches:
                resolved.append((resource, matches[0], "EvalResourceDecision"))
            elif len(resource_arns) == 1 and resource == "*":
                resolved.append((resource, action_result, "EvalDecision"))
            elif not isinstance(resource_results, list):
                raise RunnerFailure(
                    f"action-level result lacks ResourceSpecificResults for {action}"
                )
            else:
                raise RunnerFailure(
                    f"submitted resource ARN is absent from response: {action} {resource}"
                )
        if not resource_arns:
            resolved.append(("*", action_result, "EvalDecision"))
        for resource, result, decision_field in resolved:
            decision = result.get(decision_field)
            if decision not in {"allowed", "implicitDeny", "explicitDeny"}:
                scope = (
                    "action-level" if decision_field == "EvalDecision" else "resource"
                )
                raise RunnerFailure(
                    f"{scope} result has unknown decision for {action} {resource}"
                )
            observed[(action, resource)] = decision
            raw_matches = result.get("MatchedStatements", [])
            if not isinstance(raw_matches, list):
                raise RunnerFailure(
                    f"MatchedStatements is not an array for {action} {resource}"
                )
            item_sources: list[dict[str, Any]] = []
            item_sids: set[str] = set()
            for raw_match in raw_matches:
                if not isinstance(raw_match, dict):
                    raise RunnerFailure("MatchedStatements entry is not an object")
                source = _source(raw_match)
                matched_sources.append(source)
                item_sources.append(source)
                if _ignore_match(raw_match, ignore_organizations):
                    continue
                sid = map_match(
                    raw_match,
                    documents,
                    bind_to_single_document=bind_to_single_document,
                )
                matched_sids.add(sid)
                item_sids.add(sid)
            details.append(
                {
                    "action_name": action,
                    "resource_arn": resource,
                    "decision_observed": decision,
                    "matched_statement_sources": item_sources,
                    "matched_sids": sorted(item_sids),
                }
            )

    if len(resource_arns) > 1 and len(action_names) == 1:
        decision_observed: Any = {
            resource: observed[(action_names[0], resource)]
            for resource in sorted(resource_arns)
        }
    elif len(set(observed.values())) == 1:
        decision_observed = next(iter(observed.values()))
    else:
        decision_observed = {
            f"{action}|{resource}": decision
            for (action, resource), decision in sorted(observed.items())
        }
    return {
        "decision_observed": decision_observed,
        "matched_statement_sources": matched_sources,
        "matched_sids": sorted(matched_sids),
        "details": details,
    }


def _string_list(value: Any, label: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise RunnerFailure(f"{label} must be an array of strings")
    return value


def map_request(response: Any, request: Any) -> dict[str, Any]:
    if not isinstance(response, dict):
        raise RunnerFailure("AWS simulator response top level is not an object")
    if not isinstance(request, dict):
        raise RunnerFailure("mapping request is not an object")
    actions = _string_list(request.get("action_names"), "action_names")
    resources = _string_list(request.get("resource_arns"), "resource_arns")
    policies = _string_list(request.get("policy_input_list"), "policy_input_list")
    boundaries = _string_list(
        request.get("permissions_boundary_policy_input_list", []),
        "permissions_boundary_policy_input_list",
    )
    documents = submitted_documents(policies, boundaries)
    mapped = map_evaluation_results(
        response,
        actions,
        resources,
        documents,
        bind_to_single_document=request.get("bind_to_single_document") is True,
        ignore_organizations=request.get("ignore_organizations") is True,
    )
    mapped["document_hashes_submitted"] = document_hashes(policies, boundaries)
    return mapped


def _read_payload(path: str) -> Any:
    try:
        raw = (
            sys.stdin.read() if path == "-" else Path(path).read_text(encoding="utf-8")
        )
    except OSError as exc:
        raise RunnerFailure(f"cannot read input {path}: {exc}") from exc
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RunnerFailure(f"input is not valid JSON: {exc}") from exc


def _write_payload(value: Any) -> None:
    print(json.dumps(value, sort_keys=True, separators=(",", ":")))


def _command_scan(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict) or not isinstance(payload.get("document"), str):
        raise RunnerFailure("scan input must contain a string document")
    document = payload["document"]
    return {
        "sha256": document_sha256(document),
        "spans": [
            {"start": start, "end": end, "sid": sid}
            for start, end, sid in statement_spans(document)
        ],
    }


def _command_hash(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise RunnerFailure("hash input is not an object")
    documents = _string_list(payload.get("documents"), "documents")
    return {"documents": [{"sha256": document_sha256(item)} for item in documents]}


def _command_map_batch(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise RunnerFailure("map-batch input is not an object")
    requests = payload.get("requests")
    if not isinstance(requests, list):
        raise RunnerFailure("map-batch requests must be an array")
    response = payload.get("response")
    results = []
    for request in requests:
        try:
            results.append(map_request(response, request))
        except RunnerFailure as exc:
            results.append({"error": str(exc)})
    return {"results": results}


def _command_map_many(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict) or not isinstance(payload.get("items"), list):
        raise RunnerFailure("map-many input must contain an items array")
    results = []
    for index, item in enumerate(payload["items"]):
        if not isinstance(item, dict) or "response" not in item or "request" not in item:
            raise RunnerFailure(f"map-many item {index} must contain response and request")
        try:
            results.append(map_request(item["response"], item["request"]))
        except RunnerFailure as exc:
            results.append({"error": str(exc)})
    return {"results": results}


def _command_map_role_pass(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise RunnerFailure("map-role-pass input is not an object")
    role_plan_path = payload.get("role_plan_path")
    response_directory = payload.get("response_directory")
    response_prefix = payload.get("response_prefix")
    if not all(isinstance(value, str) and value for value in (
        role_plan_path, response_directory, response_prefix
    )):
        raise RunnerFailure(
            "map-role-pass requires role_plan_path, response_directory, and response_prefix"
        )
    try:
        role_plan = json.loads(Path(role_plan_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RunnerFailure(f"cannot read role plan for mapping: {exc}") from exc
    cases = role_plan.get("cases") if isinstance(role_plan, dict) else None
    roles = role_plan.get("roles") if isinstance(role_plan, dict) else None
    if not isinstance(cases, list) or not isinstance(roles, list):
        raise RunnerFailure("role plan mapping input lacks cases or roles")
    by_projection = {
        role.get("projection_id"): role
        for role in roles
        if isinstance(role, dict) and isinstance(role.get("projection_id"), str)
    }
    response_paths = [
        Path(response_directory) / f"{response_prefix}-{index}.json"
        for index in range(len(cases))
    ]
    missing_responses = [path for path in response_paths if not path.is_file()]
    if missing_responses:
        raise RunnerFailure(
            f"map-role-pass response is missing: {missing_responses[0]}"
        )
    items = []
    for index, (case, response_path) in enumerate(zip(cases, response_paths)):
        if not isinstance(case, dict):
            raise RunnerFailure(f"role plan case {index} is not an object")
        projection = by_projection.get(case.get("temporary_projection_id"))
        if not isinstance(projection, dict):
            raise RunnerFailure(f"role plan case {index} has no projection")
        try:
            response = json.loads(response_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise RunnerFailure(f"cannot read role response {response_path}: {exc}") from exc
        items.append({
            "response": response,
            "request": {
                "action_names": case.get("action_names"),
                "resource_arns": case.get("resource_arns"),
                "policy_input_list": [projection.get("policy_document")],
                "permissions_boundary_policy_input_list": [],
                "bind_to_single_document": True,
                "ignore_organizations": payload.get("ignore_organizations") is True,
            },
        })
    return _command_map_many({"items": items})


def _fail(message: str) -> NoReturn:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in (
        "scan", "hash", "map-response", "map-batch", "map-many", "map-role-pass"
    ):
        child = subparsers.add_parser(command)
        child.add_argument("input", nargs="?", default="-")
    args = parser.parse_args()
    payload = _read_payload(args.input)
    if args.command == "scan":
        result = _command_scan(payload)
    elif args.command == "hash":
        result = _command_hash(payload)
    elif args.command == "map-response":
        if not isinstance(payload, dict):
            raise RunnerFailure("map-response input is not an object")
        result = map_request(payload.get("response"), payload)
    elif args.command == "map-batch":
        result = _command_map_batch(payload)
    elif args.command == "map-many":
        result = _command_map_many(payload)
    else:
        result = _command_map_role_pass(payload)
    _write_payload(result)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RunnerFailure as exc:
        _fail(str(exc))
