#!/usr/bin/env python3
"""Generate the IAM simulator case taxonomy from docs/iam-matrix.md."""

from __future__ import annotations

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import tempfile
from typing import NoReturn


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MATRIX = REPO_ROOT / "docs" / "iam-matrix.md"
DEFAULT_OUTPUT = REPO_ROOT / "tests" / "fixtures" / "iam-simulate" / "categories.json"
CATEGORIES = (
    "simulator-decision",
    "simulator-attribution-only",
    "live-call-only",
    "not-simulatable",
)
CASE_ENTRY = re.compile(r"(case:[^ ;=)]+) => (.*?)(?=; case:|$)")
EVIDENCE_ENTRY = re.compile(r"(case:[^ ;=)]+)=(.*?)(?=; case:|$)")
NA_LABEL = re.compile(r"N/A\((.+)\)")


def fail(message: str) -> NoReturn:
    raise SystemExit(f"FAIL: {message}")


def statement_rows(matrix_text: str) -> list[tuple[int, list[str]]]:
    rows = []
    for line_no, line in enumerate(matrix_text.splitlines(), 1):
        if not line.startswith("| `"):
            continue
        table_line = line.replace(r"; \| case:", "; case:")
        cells = re.findall(r"`([^`]*)`", table_line)
        if len(cells) == 10 and cells[0].startswith(("aws_", "trust:")):
            rows.append((line_no, cells))
    if len(rows) != 86:
        fail(f"expected 86 matrix statement rows, found {len(rows)}")
    return rows


def category_and_reason(document: str, body: str, evidence: str) -> tuple[str, str]:
    na_match = NA_LABEL.fullmatch(evidence)
    if na_match:
        return "not-simulatable", na_match.group(1)
    if document.startswith("trust:"):
        return (
            "not-simulatable",
            "The IAM policy simulator does not evaluate role trust.",
        )
    if document == "aws_kms_key.signing":
        return (
            "live-call-only",
            "The IAM simulator cannot evaluate this key policy because it contains "
            "an IAM-role resource principal and kms:*.",
        )
    if "expect not denied by this statement" in body:
        return (
            "simulator-attribution-only",
            "The matrix expects not denied by this statement, so the Sid must be "
            "absent from matched-statement attribution.",
        )
    return (
        "simulator-decision",
        "The matrix supplies an IAM simulator decision expectation.",
    )


def generate(matrix_path: Path) -> list[dict[str, str]]:
    try:
        matrix_text = matrix_path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"cannot read matrix {matrix_path}: {exc}")

    taxonomy = []
    seen = set()
    for line_no, cells in statement_rows(matrix_text):
        document, sid = cells[0], cells[1]
        case_entries = CASE_ENTRY.findall(cells[7])
        evidence_entries = dict(EVIDENCE_ENTRY.findall(cells[9]))
        if not case_entries:
            fail(f"matrix statement row has no cases at line {line_no}")
        if len(case_entries) != len(evidence_entries):
            fail(f"Cases and Evidence counts differ at line {line_no}")
        for case_id, body in case_entries:
            prefix = f"case:{document}:{sid}:"
            if not case_id.startswith(prefix):
                fail(
                    "case id does not start with its exact document and Sid "
                    f"at line {line_no}: {case_id}"
                )
            suffix = case_id[len(prefix) :]
            if not suffix:
                fail(f"case id has an empty suffix at line {line_no}: {case_id}")
            if case_id in seen:
                fail(f"matrix repeats case id: {case_id}")
            seen.add(case_id)
            try:
                evidence = evidence_entries[case_id]
            except KeyError:
                fail(f"Evidence omits case id at line {line_no}: {case_id}")
            category, reason = category_and_reason(document, body, evidence)
            taxonomy.append(
                {
                    "case_id": case_id,
                    "document": document,
                    "sid": sid,
                    "suffix": suffix,
                    "category": category,
                    "reason": reason,
                }
            )

    if len(taxonomy) != 290:
        fail(f"expected 290 unique matrix cases, found {len(taxonomy)}")
    return taxonomy


def render(taxonomy: list[dict[str, str]]) -> bytes:
    entries = [
        json.dumps(entry, ensure_ascii=False, separators=(",", ":"))
        for entry in taxonomy
    ]
    return ("[\n" + ",\n".join(entries) + "\n]\n").encode("utf-8")


def report_counts(taxonomy: list[dict[str, str]]) -> None:
    counts = Counter(entry["category"] for entry in taxonomy)
    for category in CATEGORIES:
        print(f"{category}: {counts[category]}")
    print(f"total: {sum(counts.values())}")


def check_output(output_path: Path, expected: bytes) -> None:
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix="orbit-iam-simulate-categories.",
            suffix=".json",
            dir=os.environ.get("TMPDIR"),
            delete=False,
        ) as temporary:
            temporary.write(expected)
            temporary_path = Path(temporary.name)
        try:
            actual = output_path.read_bytes()
        except OSError as exc:
            fail(f"cannot read generated taxonomy {output_path}: {exc}")
        if actual != temporary_path.read_bytes():
            fail(
                f"generated taxonomy differs: run python3 {Path(__file__).relative_to(REPO_ROOT)}"
            )
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    taxonomy = generate(args.matrix)
    generated = render(taxonomy)
    if args.check:
        check_output(args.output, generated)
        print("PASS: IAM simulate taxonomy is byte-current")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(generated)
        print(f"WROTE: {args.output}")
    report_counts(taxonomy)


if __name__ == "__main__":
    main()
