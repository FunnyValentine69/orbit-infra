#!/usr/bin/env python3
"""Validate one offline IAM simulator vector envelope."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
from typing import Any, NoReturn


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATEGORIES = (
    REPO_ROOT / "tests" / "fixtures" / "iam-simulate" / "categories.json"
)
ENVELOPE_FIELDS = {"schema_version", "document", "sid", "cases"}
COMMON_FIELDS = {
    "case_id",
    "simulation_mode",
    "assertion_kind",
    "action_names",
    "resource_arns",
    "context_entries",
    "expect",
}
MODE_FIELDS = {
    "custom": {
        "permissions_boundary_policy_input_list",
        "synthetic_policy_input_list",
    },
    "custom-isolated": set(),
}
ASSERTION_KINDS = {"decision", "attribution-only"}
DECISIONS = {"allowed", "implicitDeny", "explicitDeny"}
CONTEXT_KEY_TYPES = {
    "string",
    "stringList",
    "numeric",
    "numericList",
    "boolean",
    "booleanList",
    "ip",
    "ipList",
    "binary",
    "binaryList",
    "date",
    "dateList",
}
ACCOUNT_ID = re.compile(r"(?<![0-9])[0-9]{12}(?![0-9])")
TEMPLATE = re.compile(r"\$\{([^}]+)\}")
ACTION_NAME = re.compile(r"[a-z0-9-]+:[A-Za-z0-9]+")


def fail(message: str) -> NoReturn:
    raise SystemExit(f"FAIL: {message}")


def read_json(path: Path, label: str) -> tuple[Any, str]:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"cannot read {label} {path}: {exc}")
    try:
        return json.loads(raw), raw
    except json.JSONDecodeError as exc:
        fail(f"{label} is not valid JSON: {exc}")


def require_object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    return value


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        fail(f"{label} must be a non-empty string")
    return value


def require_string_list(value: Any, label: str, *, nonempty: bool = True) -> list[str]:
    if not isinstance(value, list) or (nonempty and not value):
        qualifier = "non-empty " if nonempty else ""
        fail(f"{label} must be a {qualifier}array of strings")
    if any(not isinstance(item, str) or not item for item in value):
        fail(f"{label} must contain only non-empty strings")
    if len(value) != len(set(value)):
        fail(f"{label} must not contain duplicates")
    return value


def load_categories(path: Path) -> dict[str, dict[str, Any]]:
    data, _ = read_json(path, "categories")
    if not isinstance(data, list):
        fail("categories.json top level must be an array")
    categories = {}
    for index, raw_entry in enumerate(data):
        entry = require_object(raw_entry, f"categories entry {index}")
        case_id = require_string(
            entry.get("case_id"), f"categories entry {index}.case_id"
        )
        if case_id in categories:
            fail(f"categories.json repeats case_id: {case_id}")
        categories[case_id] = entry
    return categories


def validate_templates(raw: str) -> None:
    if ACCOUNT_ID.search(raw):
        fail("vector contains a literal 12-digit account id; use ${ACCOUNT_ID}")
    unknown = sorted(set(TEMPLATE.findall(raw)) - {"ACCOUNT_ID", "SUFFIX"})
    if unknown:
        fail(f"vector contains unknown template ${{{unknown[0]}}}")


def validate_policy_documents(
    value: Any, label: str, *, maximum: int | None = None
) -> None:
    documents = require_string_list(value, label)
    if maximum is not None and len(documents) > maximum:
        fail(f"{label} accepts at most {maximum} policy document")
    for index, document_text in enumerate(documents):
        try:
            document = json.loads(document_text)
        except json.JSONDecodeError as exc:
            fail(f"{label}[{index}] is not a JSON policy string: {exc}")
        if not isinstance(document, dict) or "Statement" not in document:
            fail(f"{label}[{index}] must be a complete JSON policy string")
        statements = document["Statement"]
        if not isinstance(statements, (dict, list)) or not statements:
            fail(f"{label}[{index}].Statement must be a non-empty object or array")


def validate_context_entries(value: Any) -> None:
    if not isinstance(value, list):
        fail("context_entries must be an array")
    for index, raw_entry in enumerate(value):
        entry = require_object(raw_entry, f"context_entries[{index}]")
        required = {"ContextKeyName", "ContextKeyValues", "ContextKeyType"}
        if set(entry) != required:
            fail(f"context_entries[{index}] must contain exactly {sorted(required)}")
        require_string(
            entry["ContextKeyName"], f"context_entries[{index}].ContextKeyName"
        )
        require_string_list(
            entry["ContextKeyValues"],
            f"context_entries[{index}].ContextKeyValues",
        )
        context_type = entry["ContextKeyType"]
        if not isinstance(context_type, str) or context_type not in CONTEXT_KEY_TYPES:
            fail(f"unknown ContextKeyType: {context_type}")


def validate_expect(
    raw_expect: Any,
    assertion_kind: str,
    simulation_mode: str,
    resource_arns: list[str],
) -> None:
    expect = require_object(raw_expect, "expect")
    allowed = {
        "decision",
        "matched_sid_required",
        "matched_sid_forbidden",
        "resource_decisions",
    }
    unknown = sorted(set(expect) - allowed)
    if unknown:
        fail(f"expect contains unknown field: {unknown[0]}")
    for field in ("matched_sid_required", "matched_sid_forbidden"):
        if field not in expect:
            fail(f"expect.{field} is required")
    required_sids = require_string_list(
        expect["matched_sid_required"],
        "expect.matched_sid_required",
        nonempty=False,
    )
    forbidden_sids = require_string_list(
        expect["matched_sid_forbidden"],
        "expect.matched_sid_forbidden",
        nonempty=False,
    )
    overlap = sorted(set(required_sids) & set(forbidden_sids))
    if overlap:
        fail(f"expect requires and forbids the same Sid: {overlap[0]}")

    if assertion_kind == "decision":
        if "decision" not in expect:
            fail("expect.decision is required for a decision vector")
        if not isinstance(expect["decision"], str) or expect["decision"] not in DECISIONS:
            fail(f"expect.decision is unknown: {expect['decision']}")
        if simulation_mode == "custom-isolated" and expect["decision"] == "allowed":
            fail("custom-isolated vectors cannot expect allowed")
    else:
        if "decision" in expect:
            fail("expect.decision is forbidden for attribution-only vectors")
        if not required_sids and not forbidden_sids:
            fail("attribution-only vectors require a matched Sid assertion")
        if "resource_decisions" in expect:
            fail("expect.resource_decisions is forbidden for attribution-only vectors")

    if "resource_decisions" in expect:
        resource_decisions = require_object(
            expect["resource_decisions"], "expect.resource_decisions"
        )
        if set(resource_decisions) != set(resource_arns):
            fail(
                "expect.resource_decisions keys must equal the submitted resource_arns"
            )
        invalid = sorted(
            resource
            for resource, decision in resource_decisions.items()
            if not isinstance(decision, str) or decision not in DECISIONS
        )
        if invalid:
            fail(f"expect.resource_decisions has an unknown decision for {invalid[0]}")
    elif len(resource_arns) > 1 and assertion_kind == "decision":
        fail("multi-resource decision vectors require expect.resource_decisions")


def validate_case(
    raw_case: Any,
    document: str,
    sid: str,
    categories: dict[str, dict[str, Any]],
    index: int,
) -> dict[str, Any]:
    vector = require_object(raw_case, f"cases[{index}]")
    common_required = COMMON_FIELDS - {"context_entries"}
    missing_common = sorted(common_required - set(vector))
    if missing_common:
        fail(f"case is missing required field: {missing_common[0]}")
    simulation_mode = vector.get("simulation_mode")
    if not isinstance(simulation_mode, str) or simulation_mode not in MODE_FIELDS:
        fail(f"unknown simulation_mode: {simulation_mode}")
    for embedded_field in ("policy_input_list", "isolated_statement"):
        if embedded_field in vector:
            fail(
                f"{embedded_field} is forbidden for {simulation_mode} vectors; "
                "resolve repository policies from the plan"
            )
    allowed_fields = COMMON_FIELDS | MODE_FIELDS[simulation_mode]
    unknown_fields = sorted(set(vector) - allowed_fields)
    if unknown_fields:
        fail(f"{unknown_fields[0]} is forbidden for {simulation_mode} vectors")
    case_id = require_string(vector["case_id"], "case_id")
    prefix = f"case:{document}:{sid}:"
    if not case_id.startswith(prefix) or case_id == prefix:
        fail(
            "case_id prefix does not match envelope header: "
            f"{case_id} expected {prefix}"
        )
    category = categories.get(case_id)
    if category is None:
        fail(f"case_id is absent from categories.json: {case_id}")
    if category.get("document") != document or category.get("sid") != sid:
        fail("vector document and sid must match categories.json")

    assertion_kind = vector["assertion_kind"]
    if not isinstance(assertion_kind, str) or assertion_kind not in ASSERTION_KINDS:
        fail(f"unknown assertion_kind: {assertion_kind}")
    expected_category = {
        "decision": "simulator-decision",
        "attribution-only": "simulator-attribution-only",
    }[assertion_kind]
    if category.get("category") != expected_category:
        fail(f"assertion_kind does not match taxonomy category for {case_id}")

    action_names = require_string_list(vector["action_names"], "action_names")
    for action in action_names:
        if ACTION_NAME.fullmatch(action) is None:
            fail(f"action_names contains an invalid IAM action: {action}")
    resource_arns = require_string_list(
        vector["resource_arns"], "resource_arns", nonempty=False
    )
    invalid_resource = next(
        (
            resource
            for resource in resource_arns
            if resource != "*" and not resource.startswith("arn:")
        ),
        None,
    )
    if invalid_resource is not None:
        fail(
            "resource_arns contains a value that is neither an ARN nor *: "
            f"{invalid_resource}"
        )
    if "context_entries" in vector:
        validate_context_entries(vector["context_entries"])

    if simulation_mode == "custom":
        if "permissions_boundary_policy_input_list" in vector:
            boundaries = require_string_list(
                vector["permissions_boundary_policy_input_list"],
                "permissions_boundary_policy_input_list",
            )
            if len(boundaries) > 1:
                fail(
                    "permissions_boundary_policy_input_list accepts at most 1 "
                    "plan document address"
                )
        if "synthetic_policy_input_list" in vector:
            if category.get("suffix") != "ALL:none:outside-boundary":
                fail(
                    "synthetic_policy_input_list is reserved for outside-boundary "
                    "vectors"
                )
            validate_policy_documents(
                vector["synthetic_policy_input_list"],
                "synthetic_policy_input_list",
                maximum=1,
            )

    validate_expect(vector["expect"], assertion_kind, simulation_mode, resource_arns)
    flattened = {
        "schema_version": 1,
        "case_id": case_id,
        "document": document,
        "sid": sid,
    }
    flattened.update({key: value for key, value in vector.items() if key != "case_id"})
    return flattened


def validate_envelope(
    vector_path: Path, categories_path: Path
) -> list[dict[str, Any]]:
    raw_envelope, raw_text = read_json(vector_path, "vector envelope")
    validate_templates(raw_text)
    envelope = require_object(raw_envelope, "vector envelope top level")
    missing = sorted(ENVELOPE_FIELDS - set(envelope))
    if missing:
        fail(f"envelope is missing required field: {missing[0]}")
    unknown = sorted(set(envelope) - ENVELOPE_FIELDS)
    if unknown:
        fail(f"envelope contains unknown field: {unknown[0]}")
    if type(envelope["schema_version"]) is not int or envelope["schema_version"] != 1:
        fail("schema_version must be integer 1")
    document = require_string(envelope["document"], "document")
    sid = require_string(envelope["sid"], "sid")
    raw_cases = envelope["cases"]
    if not isinstance(raw_cases, list) or not raw_cases:
        fail("cases must be a non-empty array")
    categories = load_categories(categories_path)
    flattened = []
    seen_case_ids = set()
    for index, raw_case in enumerate(raw_cases):
        vector = validate_case(raw_case, document, sid, categories, index)
        case_id = vector["case_id"]
        if case_id in seen_case_ids:
            fail(f"envelope repeats case_id: {case_id}")
        seen_case_ids.add(case_id)
        flattened.append(vector)
    return flattened


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vector", type=Path)
    parser.add_argument("--categories", type=Path, default=DEFAULT_CATEGORIES)
    parser.add_argument("--jsonl", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    vectors = validate_envelope(args.vector, args.categories)
    if args.jsonl:
        for vector in vectors:
            print(json.dumps(vector, ensure_ascii=False, separators=(",", ":")))
    else:
        print(f"PASS: IAM simulate vector envelope schema: {args.vector}")


if __name__ == "__main__":
    main()
