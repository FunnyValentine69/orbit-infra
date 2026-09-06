#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="${IAM_MATRIX_REPO_ROOT:-$DEFAULT_REPO_ROOT}"
DOC="${IAM_MATRIX_DOC:-$DEFAULT_REPO_ROOT/docs/iam-matrix.md}"
GENERATOR="$DEFAULT_REPO_ROOT/scripts/iam-matrix-inventory.sh"
FIXTURES="${IAM_MATRIX_FIXTURES:-$DEFAULT_REPO_ROOT/tests/fixtures/iam-matrix}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

scan_hygiene() {
  local input="$1"
  local matches
  matches="$(
    sed 's/000000000000//g' "$input" \
      | grep -nE '[0-9]{12}|/Users/|203\.0\.113|([0-9]{1,3}\.){3}[0-9]{1,3}|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
      || true
  )"
  if [ -n "$matches" ]; then
    echo "FAIL: IAM matrix hygiene rejected public-repository data" >&2
    return 1
  fi
}

scan_hygiene_text() {
  local input="$1"
  local matches
  matches="$(
    printf '%s\n' "$input" \
      | sed 's/000000000000//g' \
      | grep -nE '[0-9]{12}|/Users/|203\.0\.113|([0-9]{1,3}\.){3}[0-9]{1,3}|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
      || true
  )"
  if [ -n "$matches" ]; then
    echo "FAIL: IAM matrix hygiene rejected public-repository data" >&2
    return 1
  fi
}

scan_fixture_hygiene() {
  [ -d "$FIXTURES" ] || fail "IAM matrix fixture directory not found: $FIXTURES"
  while IFS= read -r fixture; do
    if [ -L "$fixture" ]; then
      local link_target
      link_target="$(readlink "$fixture")"
      scan_hygiene_text "$link_target"
      if ! python3 - "$FIXTURES" "$fixture" <<'PY_SYMLINK'
from pathlib import Path
import sys

fixture_root = Path(sys.argv[1]).resolve()
resolved_target = Path(sys.argv[2]).resolve(strict=False)
if resolved_target != fixture_root and fixture_root not in resolved_target.parents:
    raise SystemExit(1)
PY_SYMLINK
      then
        fail "IAM matrix fixture symlink points outside fixture directory: ${fixture#"$FIXTURES"/}"
      fi
    else
      scan_hygiene "$fixture"
    fi
  done < <(find "$FIXTURES" \( -type f -o -type l \) -print | sort)
}

if [ "${IAM_MATRIX_HYGIENE_ONLY:-0}" = 1 ]; then
  scan_hygiene "$DOC"
  scan_fixture_hygiene
  echo "PASS: IAM matrix hygiene"
  exit 0
fi

[ -f "$DOC" ] || fail "IAM matrix document not found: $DOC"
[ -x "$GENERATOR" ] || fail "IAM matrix generator is missing or not executable"

python3 - "$DOC" "$REPO_ROOT" <<'PY_SOURCE'
import fnmatch
import json
from pathlib import Path
import re
import sys


def fail(message):
    raise SystemExit(f"FAIL: {message}")


doc_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
text = doc_path.read_text()

account_bearing_arn_pattern = re.compile(
    r"arn:[^:`\s]+:[^:`\s]*:[^:`\s]*:([0-9]{12}):"
)
for account_match in account_bearing_arn_pattern.finditer(text):
    if account_match.group(1) != "000000000000":
        fail("account-bearing ARN must use placeholder account 000000000000")

required_legend = (
    "`CODE-ONLY`",
    "`AWS-SIMULATED <date> <pointer>`",
    "`AWS-VERIFIED <date> <pointer>`",
    "`CONFIG-COMPARED <date> <pointer>`",
    "`N/A(<reason>)`",
)
for entry in required_legend:
    if entry not in text:
        fail(f"evidence legend is missing {entry}")

truth_rows = (
    ("Allow", "StringEquals", "matching=allowed; non-matching=implicitDeny; absent=implicitDeny"),
    ("Allow", "StringLike", "matching=allowed; non-matching=implicitDeny; absent=implicitDeny"),
    ("Allow", "ForAnyValue:StringEquals", "one-matching=allowed; none-matching=implicitDeny; absent=implicitDeny"),
    ("Allow", "ArnLike", "matching=allowed; non-matching=implicitDeny; absent=implicitDeny"),
    ("Deny", "StringNotLike", "outside-set=explicitDeny; inside-set=not-denied-by-this-statement; absent=explicitDeny"),
    ("Deny", "Null", "absent=explicitDeny; present=not-denied-by-this-statement"),
    ("Deny", "StringNotEquals", "different=explicitDeny; equal=not-denied-by-this-statement; absent=explicitDeny"),
)
for effect, operator, variants in truth_rows:
    literal = f"| `{effect}` | `{operator}` | `{variants}` |"
    if literal not in text:
        fail(f"condition truth table is missing {effect} {operator}")
resource_truth_rows = (
    "| `Allow` | `Resource cell is not * and has no full-type wildcard` | `resource:nonmatching=implicitDeny` |",
    "| `Allow` | `Resource pattern is a full-type wildcard` | `resource:nonmatching=N/A(non-empty reason)` |",
    "| `Allow` | `Resource cell is * and Condition is none (negative case)` | `none:non-resource=N/A(non-empty reason)` |",
    "| `Deny` | `Resource cell is * (positive case)` | `none:non-protected-resource=N/A(non-empty reason)` |",
)
for resource_truth in resource_truth_rows:
    if resource_truth not in text:
        fail(f"resource-scope truth table is missing: {resource_truth}")
if "For `ForAnyValue` operators, present condition keys are supplied as `ContextKeyType=stringList`" not in text:
    fail("truth table does not require stringList context for ForAnyValue")

statement_rows = []
binding_rows = []
for line_no, line in enumerate(text.splitlines(), 1):
    if not line.startswith("| `"):
        continue
    cells = re.findall(r"`([^`]*)`", line)
    if len(cells) == 10 and cells[0].startswith(("aws_", "trust:")):
        if line.count("|") != 11:
            fail(f"bare pipe inside statement table cell at line {line_no}")
        statement_rows.append((line_no, cells))
    elif len(cells) == 5 and cells[0] in {"inline", "attachment", "role"}:
        if line.count("|") != 6:
            fail(f"bare pipe inside binding table cell at line {line_no}")
        binding_rows.append((line_no, cells))

if len(statement_rows) != 85:
    fail(f"expected 85 statement rows, found {len(statement_rows)}")
if len(binding_rows) != 13:
    fail(f"expected 13 binding rows, found {len(binding_rows)}")

section_documents = []
for match in re.finditer(r"^### ([^ ]+) \(", text, re.MULTILINE):
    section_documents.append(match.group(1))

core_documents = []
resource_pattern = re.compile(r'^\s*resource\s+"(aws_iam_policy|aws_iam_role_policy)"\s+"([^"]+)"', re.MULTILINE)
for tf_path in sorted((repo_root / "bootstrap").glob("*.tf")):
    for resource_type, name in resource_pattern.findall(tf_path.read_text()):
        core_documents.append(f"{resource_type}.{name}")
expected_documents = core_documents + [
    "aws_kms_key.signing",
    "trust:plan_reader",
    "trust:deployer",
    "trust:publisher",
]
if section_documents != expected_documents:
    fail(f"document sections do not match bootstrap resource order: expected {expected_documents}, found {section_documents}")

row_document_order = []
for _, cells in statement_rows:
    if not row_document_order or row_document_order[-1] != cells[0]:
        row_document_order.append(cells[0])
if row_document_order != expected_documents:
    fail("statement row document order does not match section order")


def strip_hcl_comments(source):
    output = []
    index = 0
    in_string = False
    escaped = False
    line_comment = False
    block_comment = False
    while index < len(source):
        char = source[index]
        following = source[index + 1] if index + 1 < len(source) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
                output.append(char)
            index += 1
            continue
        if block_comment:
            if char == "*" and following == "/":
                block_comment = False
                index += 2
            else:
                if char == "\n":
                    output.append(char)
                index += 1
            continue
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            output.append(char)
            index += 1
        elif char == "#":
            line_comment = True
            index += 1
        elif char == "/" and following == "/":
            line_comment = True
            index += 2
        elif char == "/" and following == "*":
            block_comment = True
            index += 2
        else:
            output.append(char)
            index += 1
    return "".join(output)


def hcl_blocks(source, kind, name_pattern):
    start_pattern = re.compile(
        rf'^\s*{re.escape(kind)}\s+"{re.escape(name_pattern)}"\s+"([^"]+)"\s*{{',
        re.MULTILINE,
    )
    blocks = {}
    for match in start_pattern.finditer(source):
        depth = 0
        end = None
        for index in range(match.start(), len(source)):
            char = source[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end is None:
            fail(f"unterminated HCL block {name_pattern}.{match.group(1)}")
        blocks[match.group(1)] = source[match.start():end]
    return blocks


def hcl_statement_blocks(source):
    start_pattern = re.compile(r"^\s*statement\s*{", re.MULTILINE)
    blocks = []
    for match in start_pattern.finditer(source):
        depth = 0
        end = None
        for index in range(match.start(), len(source)):
            char = source[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end is None:
            fail("unterminated HCL statement block")
        blocks.append(source[match.start():end])
    return blocks


roles_source = strip_hcl_comments((repo_root / "bootstrap/roles.tf").read_text())
kms_source = strip_hcl_comments((repo_root / "bootstrap/kms.tf").read_text())
policy_blocks = hcl_blocks(roles_source, "data", "aws_iam_policy_document")
kms_blocks = hcl_blocks(kms_source, "data", "aws_iam_policy_document")
inline_policy_resources = hcl_blocks(roles_source, "resource", "aws_iam_role_policy")
attachment_resources = hcl_blocks(roles_source, "resource", "aws_iam_role_policy_attachment")
source_bound_roles = {}
for name, block in inline_policy_resources.items():
    role_match = re.search(r"^\s*role\s*=\s*aws_iam_role\.([A-Za-z0-9_]+)\.name", block, re.MULTILINE)
    policy_match = re.search(
        r"^\s*policy\s*=\s*data\.aws_iam_policy_document\.([A-Za-z0-9_]+)\.json",
        block,
        re.MULTILINE,
    )
    if role_match is None or policy_match is None or policy_match.group(1) != name:
        fail(f"unsupported inline policy binding in source: aws_iam_role_policy.{name}")
    source_bound_roles[f"aws_iam_role_policy.{name}"] = role_match.group(1)
for name, block in attachment_resources.items():
    role_match = re.search(r"^\s*role\s*=\s*aws_iam_role\.([A-Za-z0-9_]+)\.name", block, re.MULTILINE)
    policy_match = re.search(
        r"^\s*policy_arn\s*=\s*aws_iam_policy\.([A-Za-z0-9_]+)\.arn",
        block,
        re.MULTILINE,
    )
    if policy_match is None:
        continue
    if role_match is None or policy_match.group(1) != name:
        fail(f"unsupported managed policy binding in source: aws_iam_role_policy_attachment.{name}")
    source_bound_roles[f"aws_iam_policy.{name}"] = role_match.group(1)

rows_by_document = {}
for _, cells in statement_rows:
    rows_by_document.setdefault(cells[0], []).append(cells[1])

source_actions_by_statement = {}
source_effects_by_statement = {}
matrix_resources_by_statement = {}
for _, cells in statement_rows:
    if cells[0] not in core_documents:
        continue
    try:
        matrix_resources_by_statement[(cells[0], cells[1])] = json.loads(cells[5])
    except json.JSONDecodeError as exc:
        fail(f"invalid canonical Resource JSON for {cells[0]}:{cells[1]}: {exc}")
for address in core_documents:
    name = address.split(".", 1)[1]
    block = policy_blocks.get(name)
    if block is None:
        fail(f"source policy document missing for {address}")
    source_sids = re.findall(r'^\s*sid\s*=\s*"([^"]+)"', block, re.MULTILINE)
    doc_keys = rows_by_document.get(address, [])
    extra = [key for key in doc_keys if key not in source_sids]
    if extra:
        fail(f"document key not in source for {address}: {extra[0]}")
    missing = [sid for sid in source_sids if sid not in doc_keys]
    if missing:
        fail(f"source Sid missing from matrix for {address}: {missing[0]}")
    if doc_keys != source_sids:
        fail(f"Sid order or multiplicity differs for {address}")
    for statement in hcl_statement_blocks(block):
        sid_match = re.search(r'^\s*sid\s*=\s*"([^"]+)"', statement, re.MULTILINE)
        effect_match = re.search(r'^\s*effect\s*=\s*"([^"]+)"', statement, re.MULTILINE)
        if sid_match is None or effect_match is None:
            continue
        actions_match = re.search(
            r"^\s*actions\s*=\s*\[(.*?)\]",
            statement,
            re.MULTILINE | re.DOTALL,
        )
        if actions_match is None:
            fail(f"source statement has no literal Action array for {address}: {sid_match.group(1)}")
        actions = frozenset(re.findall(r'"([^"]+)"', actions_match.group(1)))
        if not actions:
            fail(f"source statement has an empty Action array for {address}: {sid_match.group(1)}")
        source_actions_by_statement[(address, sid_match.group(1))] = actions
        source_effects_by_statement[(address, sid_match.group(1))] = effect_match.group(1)

kms_block = kms_blocks.get("signing_key")
if kms_block is None:
    fail("source policy document missing for aws_kms_key.signing")
kms_sids = re.findall(r'^\s*sid\s*=\s*"([^"]+)"', kms_block, re.MULTILINE)
kms_keys = rows_by_document.get("aws_kms_key.signing", [])
extra = [key for key in kms_keys if key not in kms_sids]
if extra:
    fail(f"document key not in source for aws_kms_key.signing: {extra[0]}")
missing = [sid for sid in kms_sids if sid not in kms_keys]
if missing:
    fail(f"source Sid missing from matrix for aws_kms_key.signing: {missing[0]}")
if kms_keys != kms_sids:
    fail("Sid order or multiplicity differs for aws_kms_key.signing")

for role in ("plan_reader", "deployer", "publisher"):
    expected = [f"trust:{role}#0"]
    actual = rows_by_document.get(f"trust:{role}", [])
    if actual != expected:
        fail(f"trust key mismatch for {role}: expected {expected}, found {actual}")

variant_table = {
    ("Allow", "StringEquals"): (("matching", "allowed"), ("non-matching", "implicitDeny"), ("absent", "implicitDeny")),
    ("Allow", "StringLike"): (("matching", "allowed"), ("non-matching", "implicitDeny"), ("absent", "implicitDeny")),
    ("Allow", "ForAnyValue:StringEquals"): (("one-matching", "allowed"), ("none-matching", "implicitDeny"), ("absent", "implicitDeny")),
    ("Allow", "ArnLike"): (("matching", "allowed"), ("non-matching", "implicitDeny"), ("absent", "implicitDeny")),
    ("Deny", "StringNotLike"): (("outside-set", "explicitDeny"), ("inside-set", "not denied by this statement"), ("absent", "explicitDeny")),
    ("Deny", "Null"): (("absent", "explicitDeny"), ("present", "not denied by this statement")),
    ("Deny", "StringNotEquals"): (("different", "explicitDeny"), ("equal", "not denied by this statement"), ("absent", "explicitDeny")),
}
case_pattern = re.compile(r"case:[^ ;=)]+")
case_entry_pattern = re.compile(r"(case:[^ ;=)]+) => ")
evidence_entry_pattern = re.compile(r"(case:[^ ;=)]+)=")
decision_clause_pattern = re.compile(
    r"(?<![A-Za-z0-9_])expect (allowed|implicitDeny|explicitDeny|not denied by this statement)(?![A-Za-z0-9_])"
)
expect_marker_pattern = re.compile(r"(?<![A-Za-z0-9_])expect\s+")
decision_keyword_pattern = re.compile(
    r"(?<![A-Za-z0-9_])(allowed|implicitDeny|explicitDeny|not denied by this statement)(?![A-Za-z0-9_])"
)
na_body_pattern = re.compile(r"N/A\([^()\s](?:[^()]*[^()\s])?\)")
masked_attribution = r"(ReadOnlyAccess|[A-Za-z0-9]+ in [A-Za-z0-9_.:]+)"
masked_attribution_note_pattern = re.compile(
    rf" \(isolated; principal simulation is masked by {masked_attribution}\)$"
)
masked_form_pattern = re.compile(
    r"^aws iam simulate-custom-policy --policy-input-list <this document only> "
    r"--action-names [^;]+ --resource-arns [^;]+"
    r"(?: --context-entries [^;]+|; no --context-entries); "
    r"expect implicitDeny \(isolated; principal simulation is masked by "
    rf"{masked_attribution}\)$"
)


def masked_form_match(body):
    match = masked_form_pattern.fullmatch(body)
    required_tokens = (
        "aws iam simulate-custom-policy",
        "--policy-input-list ",
        "--action-names ",
        "--resource-arns ",
        "expect implicitDeny",
        "principal simulation is masked by ",
    )
    context_forms = body.count("--context-entries ") + body.count("no --context-entries")
    if (
        match is None
        or any(body.count(token) != 1 for token in required_tokens)
        or context_forms != 1
    ):
        return None
    return match


def trust_na_required(document, case_id):
    return document.startswith("trust:") and (
        case_id.endswith(":absent")
        or case_id.endswith(":token.actions.githubusercontent.com:aud:non-matching")
    )


def negative_variant(case_id):
    return case_id.endswith(
        (":non-matching", ":none-matching", ":absent", ":resource:nonmatching")
    )


def case_entries(cases):
    matches = list(case_entry_pattern.finditer(cases))
    entries = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(cases)
        entries[match.group(1)] = cases[match.end():end].removesuffix("; ")
    return entries


def evidence_entries(evidence):
    matches = list(evidence_entry_pattern.finditer(evidence))
    entries = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(evidence)
        entries.append(evidence[match.start():end].removesuffix("; "))
    return entries


def parse_case_decision(body, line_no, case_id):
    attribution_note = masked_attribution_note_pattern.search(body)
    decision_text = body[:attribution_note.start()] if attribution_note else body
    clauses = list(decision_clause_pattern.finditer(decision_text))
    expect_markers = list(expect_marker_pattern.finditer(decision_text))
    if (
        len(clauses) != 1
        or len(expect_markers) != 1
        or clauses[0].start() != expect_markers[0].start()
    ):
        fail(
            f"case body must contain exactly one expect <decision> clause at line {line_no}: "
            f"{case_id}"
        )
    decision = clauses[0].group(1)
    contradictory = [
        keyword
        for keyword in decision_keyword_pattern.findall(decision_text)
        if keyword != decision
    ]
    if contradictory:
        fail(
            f"contradictory decision keyword at line {line_no}: {case_id} "
            f"expects {decision} but also contains {contradictory[0]}"
        )
    return decision


def has_full_type_wildcard(resource):
    if not isinstance(resource, dict):
        return False
    patterns = resource.get("Resource", [])
    if not isinstance(patterns, list):
        patterns = [patterns]
    for pattern in patterns:
        if not isinstance(pattern, str):
            continue
        arn_parts = pattern.split(":", 5)
        if len(arn_parts) != 6 or arn_parts[0] != "arn" or arn_parts[2] == "s3":
            continue
        if re.fullmatch(r"[^/*:]+/\*", arn_parts[5]):
            return True
    return False


bound_roles = {}
for _, cells in binding_rows:
    kind, address, role, _, _ = cells
    if kind == "inline":
        bound_roles[address] = role
    elif kind == "attachment" and address != "aws_iam_role_policy_attachment.plan_reader_readonly":
        name = address.rsplit(".", 1)[1]
        bound_roles[f"aws_iam_policy.{name}"] = role


def wildcard_patterns_overlap(first, second):
    if first == "*" or second == "*":
        return True
    if fnmatch.fnmatchcase(first, second) or fnmatch.fnmatchcase(second, first):
        return True
    if not any(char in first for char in "*?") or not any(char in second for char in "*?"):
        return False
    first_arn = first.split(":", 5)
    second_arn = second.split(":", 5)
    if len(first_arn) == 6 and len(second_arn) == 6 and first_arn[:3] != second_arn[:3]:
        return False
    first_prefix = re.split(r"[*?]", first, maxsplit=1)[0]
    second_prefix = re.split(r"[*?]", second, maxsplit=1)[0]
    if not (first_prefix.startswith(second_prefix) or second_prefix.startswith(first_prefix)):
        return False
    first_suffix = re.split(r"[*?]", first)[-1]
    second_suffix = re.split(r"[*?]", second)[-1]
    if (
        first_suffix
        and second_suffix
        and not (first_suffix.endswith(second_suffix) or second_suffix.endswith(first_suffix))
    ):
        return False
    return True


def action_sets_overlap(first, second):
    return any(
        wildcard_patterns_overlap(first_action.lower(), second_action.lower())
        for first_action in first
        for second_action in second
    )


def resource_sets_overlap(current, other):
    current_patterns = current.get("Resource", ["*"])
    if not isinstance(current_patterns, list):
        current_patterns = [current_patterns]
    if "Resource" in other:
        other_patterns = other["Resource"]
        if not isinstance(other_patterns, list):
            other_patterns = [other_patterns]
        return any(
            wildcard_patterns_overlap(current_pattern, other_pattern)
            for current_pattern in current_patterns
            for other_pattern in other_patterns
        )

    excluded_patterns = other.get("NotResource", [])
    if not isinstance(excluded_patterns, list):
        excluded_patterns = [excluded_patterns]

    def wholly_excluded(pattern):
        return any(
            excluded == "*"
            or pattern == excluded
            or (
                not any(char in pattern for char in "*?")
                and fnmatch.fnmatchcase(pattern, excluded)
            )
            for excluded in excluded_patterns
        )

    return not all(wholly_excluded(pattern) for pattern in current_patterns)


readonly_roles = {
    cells[2]
    for _, cells in binding_rows
    if cells[0] == "attachment"
    and cells[1] == "aws_iam_role_policy_attachment.plan_reader_readonly"
    and cells[3] == "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
if readonly_roles != {"orbit-infra-79s5rw-plan-reader"}:
    fail("ReadOnlyAccess binding must attach exactly to the plan-reader role")


def covering_statements(document, key):
    role = source_bound_roles.get(document)
    row_actions = source_actions_by_statement.get((document, key))
    row_resources = matrix_resources_by_statement.get((document, key))
    if role is None or row_actions is None or row_resources is None:
        return []
    covering = []
    for (other_document, other_sid), other_actions in source_actions_by_statement.items():
        if (other_document, other_sid) == (document, key):
            continue
        if source_bound_roles.get(other_document) != role:
            continue
        if source_effects_by_statement.get((other_document, other_sid)) not in {"Allow", "Deny"}:
            continue
        other_resources = matrix_resources_by_statement[(other_document, other_sid)]
        if action_sets_overlap(row_actions, other_actions) and resource_sets_overlap(
            row_resources, other_resources
        ):
            covering.append(f"{other_sid} in {other_document}")
    if bound_roles.get(document) in readonly_roles and any(
        action.split(":", 1)[-1].lower().startswith(("describe", "get", "list"))
        for action in row_actions
    ):
        covering.append("ReadOnlyAccess")
    return covering


required_masked_case_ids = []
masked_row_sids = set()
for line_no, cells in statement_rows:
    document, key, effect, _, _, _, condition_text, cases, _, evidence = cells
    if not cases:
        fail(f"empty Cases cell at line {line_no}")
    if not evidence:
        fail(f"empty Evidence cell at line {line_no}")
    if "N/A()" in cases or "N/A()" in evidence:
        fail(f"N/A requires a non-empty reason at line {line_no}")
    case_ids = case_pattern.findall(cases)
    entries_by_id = case_entries(cases)
    evidence_ids = case_pattern.findall(evidence)
    if not case_ids:
        fail(f"Cases cell has no structured case id at line {line_no}")
    if len(case_ids) != len(set(case_ids)):
        fail(f"duplicate case id in Cases cell at line {line_no}")
    if evidence_ids != case_ids:
        fail(f"Evidence does not list every case id in order at line {line_no}")
    parsed_evidence_entries = evidence_entries(evidence)
    if len(parsed_evidence_entries) != len(case_ids):
        fail(f"Evidence entry count differs from Cases at line {line_no}")
    try:
        resource = json.loads(cells[5])
    except json.JSONDecodeError:
        resource = None
    is_star_resource = resource == {"Resource": ["*"]}
    full_type_wildcard = has_full_type_wildcard(resource)
    case_decisions = {}
    for case_id in case_ids:
        body = entries_by_id[case_id]
        case_is_na = bool(na_body_pattern.fullmatch(body))
        if "N/A(" in body and not case_is_na:
            fail(f"N/A case body must be exactly N/A(<reason>) at line {line_no}: {case_id}")
        if not case_is_na:
            case_decisions[case_id] = parse_case_decision(body, line_no, case_id)

    covering = covering_statements(document, key) if effect == "Allow" else []
    covering_set = set(covering)
    masked_validations = []
    masked_simulator_case_ids = set()
    for case_id in case_ids:
        body = entries_by_id[case_id]
        form_match = masked_form_match(body)
        requires_mask = (
            bool(covering)
            and negative_variant(case_id)
            and case_decisions.get(case_id) == "implicitDeny"
        )
        if form_match is not None or "masked by" in body:
            masked_simulator_case_ids.add(case_id)
        masked_validations.append((case_id, form_match, requires_mask))

    for entry, case_id in zip(parsed_evidence_entries, case_ids):
        if not entry.startswith(case_id + "="):
            fail(f"Evidence case id mismatch at line {line_no}: {case_id}")
        label = entry[len(case_id) + 1:]
        trust_na = trust_na_required(document, case_id)
        case_is_na = bool(na_body_pattern.fullmatch(entries_by_id[case_id]))
        label_is_na = bool(na_body_pattern.fullmatch(label))
        if trust_na and (not case_is_na or not label_is_na):
            fail(f"trust case must be N/A at line {line_no}: {case_id}")
        na_allowed = trust_na or (
            effect == "Allow"
            and is_star_resource
            and condition_text == "none"
            and case_id.endswith(":ALL:none:non-resource")
        ) or (
            effect == "Deny"
            and is_star_resource
            and case_id.endswith(":ALL:none:non-protected-resource")
        ) or (
            effect == "Allow"
            and full_type_wildcard
            and case_id.endswith(":ALL:resource:nonmatching")
        )
        if case_is_na or label_is_na:
            if not na_allowed:
                fail(f"N/A is not allowed for executable case at line {line_no}: {case_id}")
            if not case_is_na or not label_is_na:
                fail(f"Cases and Evidence must agree on N/A at line {line_no}: {case_id}")
            continue
        if label == "CODE-ONLY":
            continue
        if re.fullmatch(r"(AWS-SIMULATED|AWS-VERIFIED|CONFIG-COMPARED) \d{4}-\d{2}-\d{2} \S+", label):
            continue
        fail(f"invalid Evidence label at line {line_no}: {label}")

    if condition_text != "none":
        try:
            condition = json.loads(condition_text)
        except json.JSONDecodeError as exc:
            fail(f"invalid canonical Condition JSON at line {line_no}: {exc}")
        for operator, keyed_values in condition.items():
            variants = variant_table.get((effect, operator))
            if variants is None:
                fail(f"condition operator outside truth table at line {line_no}: {effect} {operator}")
            if not isinstance(keyed_values, dict):
                fail(f"condition operator value is not an object at line {line_no}: {operator}")
            for condition_key in keyed_values:
                for variant, expected_decision in variants:
                    required = f"case:{document}:{key}:ALL:{condition_key}:{variant}"
                    if required not in case_ids:
                        fail(f"missing required condition variant at line {line_no}: {required}")
                    if trust_na_required(document, required):
                        continue
                    observed_decision = case_decisions.get(required)
                    if observed_decision != expected_decision:
                        fail(
                            f"truth-table decision mismatch at line {line_no}: "
                            f"{required} must expect {expected_decision}"
                        )
                    if condition_key == "kms:ResourceAliases":
                        expected_context = {
                            "one-matching": "--context-entries ContextKeyName=kms:ResourceAliases,ContextKeyValues=alias/nonmatching-one,alias/orbit-infra-79s5rw-signing,alias/nonmatching-two,ContextKeyType=stringList",
                            "none-matching": "--context-entries ContextKeyName=kms:ResourceAliases,ContextKeyValues=alias/nonmatching-one,alias/nonmatching-two,ContextKeyType=stringList",
                            "absent": "no --context-entries for kms:ResourceAliases",
                        }[variant]
                        if expected_context not in entries_by_id[required]:
                            fail(f"kms:ResourceAliases context is not a stringList fixture at line {line_no}: {required}")

    if document == "aws_iam_policy.task_boundary":
        if "simulate-principal-policy" in cases or "--policy-source-arn" in cases:
            fail(f"task boundary must not use a principal policy source at line {line_no}")
        for case_id, body in entries_by_id.items():
            if not na_body_pattern.fullmatch(body) and "aws iam simulate-custom-policy" not in body:
                fail(f"task boundary case must use simulate-custom-policy at line {line_no}: {case_id}")
        outside_boundary = f"case:{document}:{key}:ALL:none:outside-boundary"
        if outside_boundary not in entries_by_id:
            fail(f"task boundary row lacks the boundary-cap case at line {line_no}: {outside_boundary}")
        if "--action-names s3:ListAllMyBuckets" not in entries_by_id[outside_boundary]:
            fail(f"task boundary cap case must retain s3:ListAllMyBuckets at line {line_no}: {outside_boundary}")
        if case_decisions.get(outside_boundary) != "implicitDeny":
            fail(f"boundary-cap decision mismatch at line {line_no}: {outside_boundary} must expect implicitDeny")
        in_boundary = f"case:{document}:{key}:ALL:none:in-boundary"
        if in_boundary not in entries_by_id:
            fail(f"task boundary row lacks the in-scope positive case at line {line_no}: {in_boundary}")
        if case_decisions.get(in_boundary) != "allowed":
            fail(f"boundary in-scope decision mismatch at line {line_no}: {in_boundary} must expect allowed")
    elif document in bound_roles:
        expected_arn = f"arn:aws:iam::000000000000:role/{bound_roles[document]}"
        for case_id, body in entries_by_id.items():
            if na_body_pattern.fullmatch(body) or case_id in masked_simulator_case_ids:
                continue
            source_arns = re.findall(r"--policy-source-arn ([^ ;]+)", body)
            principal_call = f"aws iam simulate-principal-policy --policy-source-arn {expected_arn}"
            if (
                body.count("aws iam simulate-principal-policy") != 1
                or source_arns != [expected_arn]
                or principal_call not in body
            ):
                fail(f"policy source ARN does not match binding at line {line_no}: {case_id}")
            fallback = "or an isolated simulate-custom-policy with only this document"
            if "simulate-custom-policy" in body:
                if body.count("simulate-custom-policy") != 1 or fallback not in body:
                    fail(f"principal policy case has invalid custom-policy fallback at line {line_no}: {case_id}")
                if body.index(fallback) < body.index(principal_call):
                    fail(f"principal policy custom-policy fallback precedes principal call at line {line_no}: {case_id}")

    if document == "aws_kms_key.signing":
        kms_roles = {
            "plan-reader-describe": "orbit-infra-79s5rw-plan-reader",
            "plan-reader-public-key": "orbit-infra-79s5rw-plan-reader",
            "deployer-sign": "orbit-infra-79s5rw-deployer",
            "plan-reader-sign": "orbit-infra-79s5rw-plan-reader",
            "publisher-sign-verify": "orbit-infra-79s5rw-publisher",
            "canonical-policy": "orbit-infra-79s5rw-plan-reader",
        }
        for case_id, body in entries_by_id.items():
            variant = case_id.rsplit(":", 1)[1]
            expected_role = kms_roles.get(variant)
            if expected_role is None:
                fail(f"KMS case has no exact execution role mapping at line {line_no}: {case_id}")
            expected_arn = f"arn:aws:iam::000000000000:role/{expected_role}"
            role_arns = re.findall(r"arn:aws:iam::000000000000:role/[^ ;,]+", body)
            if "aws kms " not in body or role_arns != [expected_arn]:
                fail(f"KMS case must name its exact execution role ARN at line {line_no}: {case_id}")

    if effect == "Allow" and document in core_documents and condition_text == "none":
        positive_variant = "in-boundary" if document == "aws_iam_policy.task_boundary" else "matching"
        positive = f"case:{document}:{key}:ALL:none:{positive_variant}"
        if positive not in entries_by_id:
            fail(f"unconditional Allow row lacks its positive case at line {line_no}: {positive}")
        if case_decisions.get(positive) != "allowed":
            fail(f"unconditional Allow decision mismatch at line {line_no}: {positive} must expect allowed")

    if effect == "Allow" and document in core_documents and resource is not None and not is_star_resource:
        required = f"case:{document}:{key}:ALL:resource:nonmatching"
        if required not in case_ids:
            fail(f"missing required resource-scope variant at line {line_no}: {required}")
        resource_case = entries_by_id[required]
        resource_case_is_na = bool(na_body_pattern.fullmatch(resource_case))
        if resource_case_is_na:
            if not full_type_wildcard:
                fail(f"N/A is not allowed for executable case at line {line_no}: {required}")
            continue
        if case_decisions.get(required) != "implicitDeny":
            fail(f"resource-scope decision mismatch at line {line_no}: {required} must expect implicitDeny")
        for required_text in (
            "--action-names <each row Action value>",
            "--resource-arns same-type resource outside every row Resource pattern",
        ):
            if required_text not in resource_case:
                fail(f"resource-scope case is not same-action/same-type at line {line_no}: {required}")
        if document == "aws_iam_policy.task_boundary" and "<identity Allow for each row action>" not in resource_case:
            fail(f"task boundary resource case lacks its matching identity grant at line {line_no}: {required}")

    if effect == "Deny":
        protected = f"case:{document}:{key}:ALL:none:protected-resource"
        if protected not in case_ids:
            fail(f"Deny row lacks protected-resource case at line {line_no}: {protected}")
        if case_decisions.get(protected) != "explicitDeny":
            fail(f"Deny protected-resource decision mismatch at line {line_no}: {protected} must expect explicitDeny")

    for case_id, form_match, requires_mask in masked_validations:
        if requires_mask:
            required_masked_case_ids.append(case_id)
            masked_row_sids.add(key)
            if form_match is None:
                fail(f"masked negative must use isolated custom policy at line {line_no}: {case_id}")
            attribution = form_match.group(1)
            if attribution not in covering_set:
                fail(
                    f"masked negative attribution is not a covering same-role statement or managed policy "
                    f"at line {line_no}: {case_id} names {attribution}"
                )
        elif form_match is not None or "masked by" in entries_by_id[case_id]:
            fail(f"masked negative form is not allowed at line {line_no}: {case_id}")

print("PASS: IAM matrix source rows, truth-table cases, bindings, and evidence label syntax")
print(
    f"PASS: IAM matrix masked negatives ({len(required_masked_case_ids)} cases; Sids: "
    + ", ".join(sorted(masked_row_sids))
    + ")"
)

checks = (
    (
        repo_root / "modules/ecs-service/main.tf",
        r"^\s*permissions_boundary\s*=\s*var\.permissions_boundary_arn\s*$",
        2,
        "ecs-service role boundary links",
    ),
    (
        repo_root / "envs/preview/main.tf",
        r"^\s*permissions_boundary_arn\s*=\s*local\.task_boundary_arn\s*$",
        4,
        "preview boundary call sites",
    ),
    (
        repo_root / "modules/redis/main.tf",
        r"^\s*permissions_boundary_arn\s*=\s*var\.permissions_boundary_arn\s*$",
        1,
        "Redis boundary forwarding links",
    ),
    (
        repo_root / "modules/clickhouse/main.tf",
        r"^\s*permissions_boundary_arn\s*=\s*var\.permissions_boundary_arn\s*$",
        1,
        "ClickHouse boundary forwarding links",
    ),
)
for source_path, assignment_pattern, expected, label in checks:
    if not source_path.is_file():
        fail(f"boundary source file missing: {source_path.relative_to(repo_root)}")
    source = strip_hcl_comments(source_path.read_text())
    actual = sum(
        1 for line in source.splitlines()
        if re.fullmatch(assignment_pattern, line)
    )
    if actual != expected:
        fail(f"expected {expected} {label}, found {actual}")

print("PASS: IAM task-boundary source chain")
PY_SOURCE


scan_hygiene "$DOC"
scan_fixture_hygiene

if [ "$REPO_ROOT" = "$DEFAULT_REPO_ROOT" ]; then
  make_recipe="$(make -n -C "$DEFAULT_REPO_ROOT" iam-matrix-plan)"
  # shellcheck disable=SC2016
  for required in \
    'mktemp "${TMPDIR:-/tmp}/orbit-iam-matrix.XXXXXX"' \
    'POLICY_SIZE_PLAN_JSON_OUT="$plan_json" bootstrap/policy-size-check.sh' \
    'bash tests/iam-matrix-contracts.sh "$plan_json"'; do
    if ! grep -Fq "$required" <<<"$make_recipe"; then
      fail "iam-matrix-plan recipe is missing: $required"
    fi
  done
  grep -Eq '^\.PHONY:.*(^| )iam-matrix-plan( |$)' "$DEFAULT_REPO_ROOT/Makefile" \
    || fail "Makefile .PHONY is missing iam-matrix-plan"
fi

if [ "$#" -gt 1 ]; then
  fail "usage: $0 [plan.json]"
fi

if [ "$#" -eq 1 ]; then
  plan_json="$1"
  generated_file="$(mktemp)"
  trap 'rm -f "$generated_file"' EXIT
  "$GENERATOR" "$plan_json" >"$generated_file"
  python3 - "$DOC" "$generated_file" <<'PY_PLAN'
import re
from pathlib import Path
import sys


def fail(message):
    raise SystemExit(f"FAIL: {message}")


doc_text = Path(sys.argv[1]).read_text()
generated = Path(sys.argv[2]).read_text().splitlines()
generated_statements = []
generated_bindings = []
mode = None
for line in generated:
    if line == "# statements":
        mode = "statements"
        continue
    if line == "# bindings":
        mode = "bindings"
        continue
    cells = re.findall(r"`([^`]*)`", line)
    if mode == "statements":
        generated_statements.append(cells)
    elif mode == "bindings":
        generated_bindings.append(cells)

doc_statements = []
doc_bindings = []
for line in doc_text.splitlines():
    if not line.startswith("| `"):
        continue
    cells = re.findall(r"`([^`]*)`", line)
    if len(cells) == 10 and cells[0].startswith(("aws_", "trust:")):
        doc_statements.append(cells[:7])
    elif len(cells) == 5 and cells[0] in {"inline", "attachment", "role"}:
        doc_bindings.append(cells)

if len(generated_statements) != len(doc_statements):
    fail(f"generated statement count {len(generated_statements)} differs from document count {len(doc_statements)}")
for index, (expected, actual) in enumerate(zip(doc_statements, generated_statements), 1):
    if actual != expected:
        fail(f"statement inventory drift at row {index}")
if generated_bindings != doc_bindings:
    for index, pair in enumerate(zip(doc_bindings, generated_bindings), 1):
        if pair[0] != pair[1]:
            fail(f"binding inventory drift at row {index}")
    fail(f"binding inventory count differs: expected {len(doc_bindings)}, generated {len(generated_bindings)}")

print(f"PASS: IAM matrix plan inventory ({len(doc_statements)} statements, {len(doc_bindings)} bindings)")
PY_PLAN
  exit 0
fi

run_negative_fixtures() {
  local fixture_tmp="$1"
  local child_env=(env IAM_MATRIX_SKIP_NEGATIVES=1)

  expect_fail() {
    local label="$1"
    local expected="$2"
    shift 2
    local output rc fail_line
    set +e
    output="$("$@" 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -eq 0 ] || [ -z "$fail_line" ] || ! grep -Fq "$expected" <<<"$output"; then
      fail "negative fixture $label did not fail as required: rc=$rc output=$output"
    fi
    echo "PASS: negative fixture $label -> $fail_line"
  }

  mutate_doc() {
    local label="$1"
    local mutation="$2"
    local destination="$fixture_tmp/$label.md"
    python3 - "$DOC" "$destination" "$mutation" <<'PY_MUTATE_DOC'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text()
destination = Path(sys.argv[2])
mutation = sys.argv[3]

if mutation == "sid-removed":
    source = source.replace("| `ReadStateObjects` |", "| `ListStatePrefixes` |", 1)
elif mutation == "extra-sid":
    source = source.replace("| `ReadStateObjects` |", "| `ExtraSid` |", 1)
elif mutation == "empty-cases":
    source = re.sub(r'(`none` \|) `case:[^`]*` (\| `n/a` \|)', r'\1 `` \2', source, count=1)
elif mutation == "missing-variant":
    target = "case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:absent"
    source = source.replace(target, target.rsplit(":", 1)[0] + ":omitted")
elif mutation == "unknown-operator":
    source = source.replace('{"StringLike":{"s3:prefix"', '{"NumericEquals":{"s3:prefix"', 1)
elif mutation == "empty-na-reason":
    reason = "N/A(Resource * leaves no non-protected resource of the same action type)"
    source = source.replace(reason, "N/A()", 2)
elif mutation == "evidence-omits-case":
    line = next(line for line in source.splitlines() if "DenyReadStateObjectsOutsideScope" in line and line.startswith("| `"))
    cells = re.findall(r"`([^`]*)`", line)
    first_case = re.findall(r"case:[^ ;=)]+", cells[9])[0]
    cells[9] = cells[9].replace(first_case, "case:omitted", 1)
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "decision-reversed":
    line = next(line for line in source.splitlines() if "| `ListStatePrefixes` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    cells[7] = cells[7].replace("expect allowed", "expect implicitDeny", 1)
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "decision-contradictory":
    line = next(line for line in source.splitlines() if "| `ListStatePrefixes` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    cells[7] = cells[7].replace(
        "expect allowed",
        "expect allowed; contradictory outcome keyword explicitDeny",
        1,
    )
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "decision-resource-reversed":
    line = next(line for line in source.splitlines() if "| `ReadStateObjects` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    case_id = "case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:resource:nonmatching"
    cells[7], count = re.subn(
        rf"({re.escape(case_id)} => .*?)expect implicitDeny",
        r"\1expect allowed",
        cells[7],
        count=1,
    )
    if count != 1:
        raise SystemExit(f"decision-resource-reversed mutation count was {count}")
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "custom-policy-on-principal-row":
    line = next(line for line in source.splitlines() if "| `ListStatePrefixes` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    principal = "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::000000000000:role/orbit-infra-79s5rw-plan-reader"
    cells[7] = cells[7].replace(principal, "aws iam simulate-custom-policy <wrong-policy>", 1)
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "wrong-role-arn":
    line = next(line for line in source.splitlines() if "| `ListStatePrefixes` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    cells[7] = cells[7].replace(
        "arn:aws:iam::000000000000:role/orbit-infra-79s5rw-plan-reader",
        "arn:aws:iam::000000000000:role/orbit-infra-79s5rw-deployer",
        1,
    )
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "arn-real-account":
    account_id = "".join(("123456", "789012"))
    placeholder = "arn:aws:iam::000000000000:"
    replacement = f"arn:aws:iam::{account_id}:"
    if source.count(placeholder) < 1:
        raise SystemExit("arn-real-account mutation anchor mismatch")
    source = source.replace(placeholder, replacement, 1)
elif mutation == "na-executable-case":
    line = next(line for line in source.splitlines() if "| `ListStatePrefixes` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    case_id = "case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:matching"
    cells[7] = re.sub(
        rf"{re.escape(case_id)} => .*?(?=; case:)",
        f"{case_id} => N/A(executable case mislabeled)",
        cells[7],
        count=1,
    )
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "na-resource-not-wildcard":
    line = next(line for line in source.splitlines() if "| `ReadStateObjects` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    case_id = "case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:resource:nonmatching"
    cells[7], case_count = re.subn(
        rf"{re.escape(case_id)} => .*$",
        f"{case_id} => N/A(non-wildcard resource mislabeled)",
        cells[7],
        count=1,
    )
    old_evidence = f"{case_id}=CODE-ONLY"
    new_evidence = f"{case_id}=N/A(non-wildcard resource mislabeled)"
    if case_count != 1 or cells[9].count(old_evidence) != 1:
        raise SystemExit("na-resource-not-wildcard mutation anchor mismatch")
    cells[9] = cells[9].replace(old_evidence, new_evidence, 1)
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "na-with-trailing-instructions":
    line = next(line for line in source.splitlines() if "| `DenySecretsAndParams` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    reason = "N/A(Resource * leaves no non-protected resource of the same action type)"
    if cells[7].count(reason) != 1:
        raise SystemExit("na-with-trailing-instructions mutation anchor mismatch")
    cells[7] = cells[7].replace(reason, reason + "; execute an extra probe", 1)
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "na-embedded-in-executable":
    line = next(line for line in source.splitlines() if "| `ListStatePrefixes` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    cells[7] = cells[7].replace(
        "expect allowed",
        "expect allowed; N/A(embedded executable marker)",
        1,
    )
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "missing-resource-variant":
    target = "case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:resource:nonmatching"
    if source.count(target) != 2:
        raise SystemExit(f"expected two resource variant occurrences, found {source.count(target)}")
    source = source.replace(target, target.rsplit(":", 1)[0] + ":omitted")
elif mutation == "masked-negative-missing":
    line = next(line for line in source.splitlines() if "| `ListStatePrefixes` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    case_id = "case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:non-matching"
    body = (
        "aws iam simulate-principal-policy --policy-source-arn "
        "arn:aws:iam::000000000000:role/orbit-infra-79s5rw-plan-reader "
        "--action-names <each row Action value> --resource-arns matching row resources; "
        "--context-entries s3:prefix:non-matching with every other condition key satisfying; "
        "expect implicitDeny"
    )
    cells[7], count = re.subn(
        rf"{re.escape(case_id)} => .*?(?=; case:)",
        f"{case_id} => {body}",
        cells[7],
        count=1,
    )
    if count != 1:
        raise SystemExit("masked-negative-missing mutation anchor mismatch")
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "allow-masked-negative-missing":
    line = next(line for line in source.splitlines() if "| `ListStateBucket` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    case_id = "case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:non-matching"
    body = (
        "aws iam simulate-principal-policy --policy-source-arn "
        "arn:aws:iam::000000000000:role/orbit-infra-79s5rw-deployer "
        "--action-names <each row Action value> --resource-arns matching row resources; "
        "--context-entries s3:prefix:non-matching with every other condition key satisfying; "
        "expect implicitDeny"
    )
    cells[7], count = re.subn(
        rf"{re.escape(case_id)} => .*?(?=; case:)",
        f"{case_id} => {body}",
        cells[7],
        count=1,
    )
    if count != 1 or "simulate-custom-policy" not in source[source.index(line):source.index(line) + len(line)]:
        raise SystemExit("allow-masked-negative-missing mutation anchor mismatch")
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "masked-negative-wrong-sid":
    line = next(line for line in source.splitlines() if "| `ListStatePrefixes` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    case_id = "case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:non-matching"
    body = (
        "aws iam simulate-custom-policy --policy-input-list <this document only> "
        "--action-names <each row Action value> --resource-arns matching row resources "
        "--context-entries <s3:prefix non-matching with every other condition key satisfying>; "
        "expect implicitDeny (isolated; principal simulation is masked by DenySecretsAndParams "
        "in aws_iam_role_policy.plan_reader_deny)"
    )
    cells[7], count = re.subn(
        rf"{re.escape(case_id)} => .*?(?=; case:)",
        f"{case_id} => {body}",
        cells[7],
        count=1,
    )
    if count != 1:
        raise SystemExit("masked-negative-wrong-sid mutation anchor mismatch")
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "masked-form-on-unmasked-row":
    line = next(line for line in source.splitlines() if "| `EcrVerificationPull` |" in line)
    cells = re.findall(r"`([^`]*)`", line)
    case_id = "case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:resource:nonmatching"
    body = (
        "aws iam simulate-custom-policy --policy-input-list <this document only> "
        "--action-names <each row Action value> --resource-arns same-type resource outside every row Resource pattern "
        "--context-entries <every condition key satisfying>; "
        "expect implicitDeny (isolated; principal simulation is masked by DenyMutatingOwnControlRoles "
        "in aws_iam_policy.deployer_guard)"
    )
    cells[7], count = re.subn(
        rf"{re.escape(case_id)} => .*$",
        f"{case_id} => {body}",
        cells[7],
        count=1,
    )
    if count != 1:
        raise SystemExit("masked-form-on-unmasked-row mutation anchor mismatch")
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "trust-absent-executable":
    line = next(line for line in source.splitlines() if line.startswith("| `trust:plan_reader`"))
    cells = re.findall(r"`([^`]*)`", line)
    case_id = "case:trust:plan_reader:trust:plan_reader#0:ALL:token.actions.githubusercontent.com:aud:absent"
    body = "deliberate plan-reader STS attempt with a token that omits aud; expect implicitDeny"
    cells[7], case_count = re.subn(
        rf"{re.escape(case_id)} => .*?(?=; case:)",
        f"{case_id} => {body}",
        cells[7],
        count=1,
    )
    cells[9], evidence_count = re.subn(
        rf"{re.escape(case_id)}=[^;]+",
        f"{case_id}=CODE-ONLY",
        cells[9],
        count=1,
    )
    if case_count != 1 or evidence_count != 1:
        raise SystemExit("trust-absent-executable mutation anchor mismatch")
    replacement = "| " + " | ".join(f"`{cell}`" for cell in cells) + " |"
    source = source.replace(line, replacement, 1)
elif mutation == "kms-string-context":
    target = "ContextKeyValues=alias/nonmatching-one,alias/orbit-infra-79s5rw-signing,alias/nonmatching-two,ContextKeyType=stringList"
    if source.count(target) != 2:
        raise SystemExit(f"expected two KMS one-matching contexts, found {source.count(target)}")
    source = source.replace(target, target.replace("stringList", "string"), 1)
else:
    raise SystemExit(f"unknown mutation: {mutation}")

destination.write_text(source)
PY_MUTATE_DOC
    printf '%s\n' "$destination"
  }

  local mutated
  mutated="$(mutate_doc sid-removed sid-removed)"
  expect_fail sid-removed "source Sid missing from matrix" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc extra-sid extra-sid)"
  expect_fail extra-sid "document key not in source" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc empty-cases empty-cases)"
  expect_fail empty-cases "empty Cases cell" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc missing-condition-variant missing-variant)"
  expect_fail missing-condition-variant "missing required condition variant" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc operator-outside-table unknown-operator)"
  expect_fail operator-outside-table "condition operator outside truth table" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc empty-na-reason empty-na-reason)"
  expect_fail empty-na-reason "N/A requires a non-empty reason" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc evidence-omits-case evidence-omits-case)"
  expect_fail evidence-omits-case "Evidence does not list every case id" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc decision-reversed decision-reversed)"
  expect_fail decision-reversed "truth-table decision mismatch" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc decision-contradictory decision-contradictory)"
  expect_fail decision-contradictory "contradictory decision keyword" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc decision-resource-reversed decision-resource-reversed)"
  expect_fail decision-resource-reversed "resource-scope decision mismatch" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc custom-policy-on-principal-row custom-policy-on-principal-row)"
  expect_fail custom-policy-on-principal-row "policy source ARN does not match binding" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc wrong-role-arn wrong-role-arn)"
  expect_fail wrong-role-arn "policy source ARN does not match binding" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc arn-real-account arn-real-account)"
  expect_fail arn-real-account "account-bearing ARN must use placeholder account 000000000000" \
    "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc na-executable-case na-executable-case)"
  expect_fail na-executable-case "N/A is not allowed" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc na-resource-not-wildcard na-resource-not-wildcard)"
  expect_fail na-resource-not-wildcard "N/A is not allowed" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc na-with-trailing-instructions na-with-trailing-instructions)"
  expect_fail na-with-trailing-instructions "N/A case body must be exactly" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc na-embedded-in-executable na-embedded-in-executable)"
  expect_fail na-embedded-in-executable "N/A case body must be exactly" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc missing-resource-variant missing-resource-variant)"
  expect_fail missing-resource-variant "missing required resource-scope variant" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc masked-negative-missing masked-negative-missing)"
  expect_fail masked-negative-missing "masked negative must use isolated custom policy" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc allow-masked-negative-missing allow-masked-negative-missing)"
  expect_fail allow-masked-negative-missing "masked negative must use isolated custom policy" \
    "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc masked-negative-wrong-sid masked-negative-wrong-sid)"
  expect_fail masked-negative-wrong-sid "masked negative attribution is not a covering same-role statement or managed policy" \
    "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc masked-form-on-unmasked-row masked-form-on-unmasked-row)"
  expect_fail masked-form-on-unmasked-row "masked negative form is not allowed" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc trust-absent-executable trust-absent-executable)"
  expect_fail trust-absent-executable "trust case must be N/A" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"
  mutated="$(mutate_doc kms-string-context kms-string-context)"
  expect_fail kms-string-context "kms:ResourceAliases context is not a stringList fixture" "${child_env[@]}" IAM_MATRIX_DOC="$mutated" "$0"

  local base_plan="$FIXTURES/base-plan.json"
  local plan_case
  make_plan() {
    local name="$1"
    local filter="$2"
    plan_case="$fixture_tmp/$name.json"
    jq "$filter" "$base_plan" >"$plan_case"
  }

  make_plan empty-plan '.planned_values.root_module.resources = []'
  expect_fail empty-plan "expected 7 aws_iam_policy resources, found 0" "${child_env[@]}" "$0" "$plan_case"
  make_plan null-policy '(.planned_values.root_module.resources[] | select(.address == "aws_iam_policy.deployer_state").values.policy) = null'
  expect_fail null-policy "policy document is null or unknown" "${child_env[@]}" "$0" "$plan_case"
  make_plan pre-apply-trust 'del(.planned_values.root_module.resources[] | select(.address == "aws_iam_role.plan_reader").values.assume_role_policy)'
  expect_fail pre-apply-trust "trust policies unknown at plan time: apply bootstrap to LocalStack first" "${child_env[@]}" "$0" "$plan_case"

  make_plan action-string-array '(.planned_values.root_module.resources[] | select(.address == "aws_iam_role_policy.plan_reader_deny").values.policy) |= (fromjson | .Statement[1].Action = [.Statement[1].Action] | tojson)'
  "${child_env[@]}" "$0" "$plan_case" >/dev/null
  echo "PASS: positive fixture action-string-array canonicalises identically"

  make_plan condition-keys-reordered '(.planned_values.root_module.resources[] | select(.address == "aws_iam_policy.deployer_ec2").values.policy) |= (fromjson | .Statement[2].Condition.StringEquals |= (to_entries | reverse | from_entries) | tojson)'
  base_inventory="$fixture_tmp/base-inventory.txt"
  reordered_inventory="$fixture_tmp/reordered-inventory.txt"
  "$GENERATOR" "$base_plan" >"$base_inventory"
  "$GENERATOR" "$plan_case" >"$reordered_inventory"
  if ! cmp -s "$base_inventory" "$reordered_inventory"; then
    fail "positive fixture condition-keys-reordered did not canonicalise identically"
  fi
  echo "PASS: positive fixture condition-keys-reordered canonicalises identically"

  make_plan effect-flip '(.planned_values.root_module.resources[] | select(.address == "aws_iam_policy.deployer_state").values.policy) |= (fromjson | .Statement[0].Effect = "Deny" | tojson)'
  expect_fail effect-flip "statement inventory drift" "${child_env[@]}" "$0" "$plan_case"
  make_plan condition-value-change '(.planned_values.root_module.resources[] | select(.address == "aws_iam_policy.deployer_state").values.policy) |= (fromjson | .Statement[1].Condition.StringLike["s3:prefix"] = ["changed/*"] | tojson)'
  expect_fail condition-value-change "statement inventory drift" "${child_env[@]}" "$0" "$plan_case"
  make_plan resource-change '(.planned_values.root_module.resources[] | select(.address == "aws_iam_role_policy.plan_reader_state").values.policy) |= (fromjson | .Statement[1].Resource = "arn:aws:s3:::changed/*" | tojson)'
  expect_fail resource-change "statement inventory drift" "${child_env[@]}" "$0" "$plan_case"
  make_plan not-resource-change '(.planned_values.root_module.resources[] | select(.address == "aws_iam_role_policy.plan_reader_deny").values.policy) |= (fromjson | .Statement[0].NotResource = ["arn:aws:s3:::changed/*"] | tojson)'
  expect_fail not-resource-change "statement inventory drift" "${child_env[@]}" "$0" "$plan_case"
  make_plan kms-policy-missing '.planned_values.root_module.resources |= map(select(.address != "aws_kms_key.signing"))'
  expect_fail kms-policy-missing "aws_kms_key.signing policy is missing or unknown" "${child_env[@]}" "$0" "$plan_case"
  make_plan kms-principal-swap '(.planned_values.root_module.resources[] | select(.address == "aws_kms_key.signing").values.policy) |= (fromjson | .Statement[1].Principal.AWS = "arn:aws:iam::000000000000:role/orbit-infra-79s5rw-deployer" | tojson)'
  expect_fail kms-principal-swap "statement inventory drift" "${child_env[@]}" "$0" "$plan_case"
  make_plan wildcard-principal '(.planned_values.root_module.resources[] | select(.address == "aws_kms_key.signing").values.policy) |= (fromjson | .Statement[1].Principal.AWS = "*" | tojson)'
  expect_fail wildcard-principal "statement inventory drift" "${child_env[@]}" "$0" "$plan_case"
  make_plan trust-aud-change '(.planned_values.root_module.resources[] | select(.address == "aws_iam_role.plan_reader").values.assume_role_policy) |= (fromjson | .Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] = "changed-audience" | tojson)'
  expect_fail trust-aud-change "statement inventory drift" "${child_env[@]}" "$0" "$plan_case"
  make_plan trust-sub-widening '(.planned_values.root_module.resources[] | select(.address == "aws_iam_role.plan_reader").values.assume_role_policy) |= (fromjson | .Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] = "repo:*" | tojson)'
  expect_fail trust-sub-widening "statement inventory drift" "${child_env[@]}" "$0" "$plan_case"
  make_plan deployer-guard-detached '.planned_values.root_module.resources |= map(select(.address != "aws_iam_role_policy_attachment.deployer_guard"))'
  expect_fail deployer-guard-detached "expected 7 aws_iam_role_policy_attachment resources, found 6" "${child_env[@]}" "$0" "$plan_case"
  make_plan inline-role-reassigned '(.planned_values.root_module.resources[] | select(.address == "aws_iam_role_policy.publisher").values.role) = "orbit-infra-79s5rw-deployer"'
  expect_fail inline-role-reassigned "binding inventory drift" "${child_env[@]}" "$0" "$plan_case"
  make_plan readonly-widened '(.planned_values.root_module.resources[] | select(.address == "aws_iam_role_policy_attachment.plan_reader_readonly").values.policy_arn) = "arn:aws:iam::aws:policy/AdministratorAccess"'
  expect_fail readonly-widened "binding inventory drift" "${child_env[@]}" "$0" "$plan_case"
  make_plan ci-role-boundary '(.planned_values.root_module.resources[] | select(.address == "aws_iam_role.deployer").values.permissions_boundary) = "arn:aws:iam::000000000000:policy/unexpected"'
  expect_fail ci-role-boundary "binding inventory drift" "${child_env[@]}" "$0" "$plan_case"

  make_source_root() {
    local destination="$1"
    mkdir -p "$destination/bootstrap" "$destination/modules/ecs-service" \
      "$destination/modules/redis" "$destination/modules/clickhouse" "$destination/envs/preview"
    cp "$DEFAULT_REPO_ROOT/bootstrap/roles.tf" "$destination/bootstrap/roles.tf"
    cp "$DEFAULT_REPO_ROOT/bootstrap/kms.tf" "$destination/bootstrap/kms.tf"
    cp "$DEFAULT_REPO_ROOT/modules/ecs-service/main.tf" "$destination/modules/ecs-service/main.tf"
    cp "$DEFAULT_REPO_ROOT/modules/redis/main.tf" "$destination/modules/redis/main.tf"
    cp "$DEFAULT_REPO_ROOT/modules/clickhouse/main.tf" "$destination/modules/clickhouse/main.tf"
    cp "$DEFAULT_REPO_ROOT/envs/preview/main.tf" "$destination/envs/preview/main.tf"
  }
  mutate_source_once() {
    local path="$1"
    local needle="$2"
    python3 - "$path" "$needle" <<'PY_MUTATE_SOURCE'
from pathlib import Path
import sys

path = Path(sys.argv[1])
needle = sys.argv[2]
text = path.read_text()
if text.count(needle) < 1:
    raise SystemExit(f"mutation needle not found: {needle}")
path.write_text(text.replace(needle, "# fixture removed", 1))
PY_MUTATE_SOURCE
  }
  comment_source_once() {
    local path="$1"
    local needle="$2"
    python3 - "$path" "$needle" <<'PY_COMMENT_SOURCE'
from pathlib import Path
import sys

path = Path(sys.argv[1])
needle = sys.argv[2]
text = path.read_text()
if text.count(needle) < 1:
    raise SystemExit(f"comment mutation needle not found: {needle}")
path.write_text(text.replace(needle, f"# {needle}", 1))
PY_COMMENT_SOURCE
  }

  local source_root
  source_root="$fixture_tmp/module-role-boundary"
  make_source_root "$source_root"
  mutate_source_once "$source_root/modules/ecs-service/main.tf" "permissions_boundary = var.permissions_boundary_arn"
  expect_fail module-role-boundary "expected 2 ecs-service role boundary links, found 1" "${child_env[@]}" IAM_MATRIX_REPO_ROOT="$source_root" "$0"

  source_root="$fixture_tmp/preview-call-site"
  make_source_root "$source_root"
  mutate_source_once "$source_root/envs/preview/main.tf" "permissions_boundary_arn = local.task_boundary_arn"
  expect_fail preview-call-site "expected 4 preview boundary call sites, found 3" "${child_env[@]}" IAM_MATRIX_REPO_ROOT="$source_root" "$0"

  source_root="$fixture_tmp/redis-forwarding"
  make_source_root "$source_root"
  mutate_source_once "$source_root/modules/redis/main.tf" "permissions_boundary_arn = var.permissions_boundary_arn"
  expect_fail redis-forwarding "expected 1 Redis boundary forwarding links, found 0" "${child_env[@]}" IAM_MATRIX_REPO_ROOT="$source_root" "$0"

  source_root="$fixture_tmp/redis-forwarding-commented"
  make_source_root "$source_root"
  comment_source_once "$source_root/modules/redis/main.tf" "permissions_boundary_arn = var.permissions_boundary_arn"
  expect_fail redis-forwarding-commented "expected 1 Redis boundary forwarding links, found 0" "${child_env[@]}" IAM_MATRIX_REPO_ROOT="$source_root" "$0"

  source_root="$fixture_tmp/clickhouse-forwarding"
  make_source_root "$source_root"
  mutate_source_once "$source_root/modules/clickhouse/main.tf" "permissions_boundary_arn = var.permissions_boundary_arn"
  expect_fail clickhouse-forwarding "expected 1 ClickHouse boundary forwarding links, found 0" "${child_env[@]}" IAM_MATRIX_REPO_ROOT="$source_root" "$0"

  source_root="$fixture_tmp/wiring-quoted-decoy"
  make_source_root "$source_root"
  mutate_source_once "$source_root/modules/redis/main.tf" "permissions_boundary_arn = var.permissions_boundary_arn"
  printf '%s\n' 'decoy = "permissions_boundary_arn = var.permissions_boundary_arn"' \
    >>"$source_root/modules/redis/main.tf"
  expect_fail wiring-quoted-decoy "expected 1 Redis boundary forwarding links, found 0" \
    "${child_env[@]}" IAM_MATRIX_REPO_ROOT="$source_root" "$0"

  source_root="$fixture_tmp/commented-sid-ignored"
  make_source_root "$source_root"
  python3 - "$source_root/bootstrap/roles.tf" <<'PY_COMMENTED_SID'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
anchor = 'data "aws_iam_policy_document" "plan_reader_state" {\n'
if text.count(anchor) != 1:
    raise SystemExit("commented-sid-ignored mutation anchor mismatch")
path.write_text(text.replace(anchor, anchor + '  # sid = "RetiredCase"\n', 1))
PY_COMMENTED_SID
  commented_sid_output="$("${child_env[@]}" IAM_MATRIX_REPO_ROOT="$source_root" "$0")"
  commented_sid_pass="$(grep -m1 '^PASS: IAM matrix source rows' <<<"$commented_sid_output" || true)"
  if [ -z "$commented_sid_pass" ]; then
    fail "positive fixture commented-sid-ignored did not report its source-row pass"
  fi
  echo "PASS: positive fixture commented-sid-ignored -> $commented_sid_pass"

  source_root="$fixture_tmp/uncommented-extra-sid"
  make_source_root "$source_root"
  python3 - "$source_root/bootstrap/roles.tf" <<'PY_UNCOMMENTED_SID'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
anchor = 'data "aws_iam_policy_document" "plan_reader_state" {\n'
if text.count(anchor) != 1:
    raise SystemExit("uncommented-extra-sid mutation anchor mismatch")
path.write_text(text.replace(anchor, anchor + '  sid = "RetiredCase"\n', 1))
PY_UNCOMMENTED_SID
  expect_fail uncommented-extra-sid "source Sid missing from matrix" \
    "${child_env[@]}" IAM_MATRIX_REPO_ROOT="$source_root" "$0"

  IAM_MATRIX_DOC="$FIXTURES/hygiene-immutable-subject.md" IAM_MATRIX_HYGIENE_ONLY=1 "$0" >/dev/null
  echo "PASS: positive fixture immutable-ID-subject hygiene"

  local email_left email_domain email_suffix account_left account_right
  email_left="$(sed -n '1p' "$FIXTURES/hygiene-email.fragments")"
  email_domain="$(sed -n '2p' "$FIXTURES/hygiene-email.fragments")"
  email_suffix="$(sed -n '3p' "$FIXTURES/hygiene-email.fragments")"
  # shellcheck disable=SC2016
  printf '| `%s@%s.%s` |\n' "$email_left" "$email_domain" "$email_suffix" >"$fixture_tmp/hygiene-email.md"
  expect_fail hygiene-email "IAM matrix hygiene rejected" env IAM_MATRIX_DOC="$fixture_tmp/hygiene-email.md" IAM_MATRIX_HYGIENE_ONLY=1 "$0"

  account_left="$(sed -n '1p' "$FIXTURES/hygiene-second-account.fragments")"
  account_right="$(sed -n '2p' "$FIXTURES/hygiene-second-account.fragments")"
  # shellcheck disable=SC2016
  printf '| `000000000000` | `%s%s` |\n' "$account_left" "$account_right" >"$fixture_tmp/hygiene-second-account.md"
  expect_fail hygiene-second-account "IAM matrix hygiene rejected" env IAM_MATRIX_DOC="$fixture_tmp/hygiene-second-account.md" IAM_MATRIX_HYGIENE_ONLY=1 "$0"

  hygiene_symlink_dir="$fixture_tmp/hygiene-symlink-account"
  mkdir -p "$hygiene_symlink_dir"
  ln -s "../$account_left$account_right.json" "$hygiene_symlink_dir/account-link.json"
  expect_fail hygiene-symlink-account "IAM matrix hygiene rejected" \
    env IAM_MATRIX_FIXTURES="$hygiene_symlink_dir" IAM_MATRIX_HYGIENE_ONLY=1 "$0"

  outside_symlink_dir="$fixture_tmp/symlink-outside-fixture-directory"
  mkdir -p "$outside_symlink_dir"
  printf '%s\n' safe >"$fixture_tmp/outside-fixture.txt"
  ln -s ../outside-fixture.txt "$outside_symlink_dir/outside-link.txt"
  expect_fail symlink-outside-fixture-directory "fixture symlink points outside fixture directory" \
    env IAM_MATRIX_FIXTURES="$outside_symlink_dir" IAM_MATRIX_HYGIENE_ONLY=1 "$0"

  hygiene_fixture_dir="$fixture_tmp/hygiene-fixture-directory"
  mkdir -p "$hygiene_fixture_dir"
  cp "$base_plan" "$hygiene_fixture_dir/copied-base-plan.json"
  python3 - "$hygiene_fixture_dir/copied-base-plan.json" "$account_left$account_right" <<'PY_MUTATE_HYGIENE_PLAN'
from pathlib import Path
import sys

path = Path(sys.argv[1])
account_id = sys.argv[2]
source = path.read_text()
if source.count("000000000000") < 1:
    raise SystemExit("placeholder account id not found in copied plan")
path.write_text(source.replace("000000000000", account_id, 1))
PY_MUTATE_HYGIENE_PLAN
  expect_fail hygiene-second-account-base-plan "IAM matrix hygiene rejected" \
    "${child_env[@]}" IAM_MATRIX_FIXTURES="$hygiene_fixture_dir" "$0"
}

if [ "${IAM_MATRIX_SKIP_NEGATIVES:-0}" != 1 ]; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  run_negative_fixtures "$tmp_dir"
fi

echo "PASS: IAM matrix contracts (85 statements, 13 bindings)"
