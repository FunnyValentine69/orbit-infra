#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="${IAM_MATRIX_REPO_ROOT:-$DEFAULT_REPO_ROOT}"
DOC="${IAM_MATRIX_DOC:-$DEFAULT_REPO_ROOT/docs/iam-matrix.md}"
GENERATOR="$DEFAULT_REPO_ROOT/scripts/iam-matrix-inventory.sh"
FIXTURES="$DEFAULT_REPO_ROOT/tests/fixtures/iam-matrix"

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

if [ "${IAM_MATRIX_HYGIENE_ONLY:-0}" = 1 ]; then
  scan_hygiene "$DOC"
  echo "PASS: IAM matrix hygiene"
  exit 0
fi

[ -f "$DOC" ] || fail "IAM matrix document not found: $DOC"
[ -x "$GENERATOR" ] || fail "IAM matrix generator is missing or not executable"

python3 - "$DOC" "$REPO_ROOT" <<'PY_SOURCE'
import json
from pathlib import Path
import re
import sys


def fail(message):
    raise SystemExit(f"FAIL: {message}")


doc_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
text = doc_path.read_text()

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


roles_source = (repo_root / "bootstrap/roles.tf").read_text()
kms_source = (repo_root / "bootstrap/kms.tf").read_text()
policy_blocks = hcl_blocks(roles_source, "data", "aws_iam_policy_document")
kms_blocks = hcl_blocks(kms_source, "data", "aws_iam_policy_document")
rows_by_document = {}
for _, cells in statement_rows:
    rows_by_document.setdefault(cells[0], []).append(cells[1])

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
    ("Allow", "StringEquals"): ("matching", "non-matching", "absent"),
    ("Allow", "StringLike"): ("matching", "non-matching", "absent"),
    ("Allow", "ForAnyValue:StringEquals"): ("one-matching", "none-matching", "absent"),
    ("Allow", "ArnLike"): ("matching", "non-matching", "absent"),
    ("Deny", "StringNotLike"): ("outside-set", "inside-set", "absent"),
    ("Deny", "Null"): ("absent", "present"),
    ("Deny", "StringNotEquals"): ("different", "equal", "absent"),
}
case_pattern = re.compile(r"case:[^ ;=)]+")
for line_no, cells in statement_rows:
    document, key, effect, _, _, _, condition_text, cases, _, evidence = cells
    if not cases:
        fail(f"empty Cases cell at line {line_no}")
    if not evidence:
        fail(f"empty Evidence cell at line {line_no}")
    if "N/A()" in cases or "N/A()" in evidence:
        fail(f"N/A requires a non-empty reason at line {line_no}")
    case_ids = case_pattern.findall(cases)
    evidence_ids = case_pattern.findall(evidence)
    if not case_ids:
        fail(f"Cases cell has no structured case id at line {line_no}")
    if len(case_ids) != len(set(case_ids)):
        fail(f"duplicate case id in Cases cell at line {line_no}")
    if evidence_ids != case_ids:
        fail(f"Evidence does not list every case id in order at line {line_no}")
    evidence_entries = evidence.split("; ")
    if len(evidence_entries) != len(case_ids):
        fail(f"Evidence entry count differs from Cases at line {line_no}")
    for entry, case_id in zip(evidence_entries, case_ids):
        if not entry.startswith(case_id + "="):
            fail(f"Evidence case id mismatch at line {line_no}: {case_id}")
        label = entry[len(case_id) + 1:]
        if label == "CODE-ONLY":
            continue
        if re.fullmatch(r"(AWS-SIMULATED|AWS-VERIFIED|CONFIG-COMPARED) \d{4}-\d{2}-\d{2} \S+", label):
            continue
        if re.fullmatch(r"N/A\(.+\)", label):
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
                for variant in variants:
                    required = f"case:{document}:{key}:ALL:{condition_key}:{variant}"
                    if required not in case_ids:
                        fail(f"missing required condition variant at line {line_no}: {required}")
    if effect == "Deny":
        protected = f"case:{document}:{key}:ALL:none:protected-resource"
        if protected not in case_ids:
            fail(f"Deny row lacks protected-resource case at line {line_no}: {protected}")

print("PASS: IAM matrix source rows, truth-table cases, and evidence labels")
PY_SOURCE

python3 - "$REPO_ROOT" <<'PY_WIRING'
from pathlib import Path
import sys


def fail(message):
    raise SystemExit(f"FAIL: {message}")


root = Path(sys.argv[1])
checks = (
    (root / "modules/ecs-service/main.tf", "permissions_boundary = var.permissions_boundary_arn", 2, "ecs-service role boundary links"),
    (root / "envs/preview/main.tf", "permissions_boundary_arn = local.task_boundary_arn", 4, "preview boundary call sites"),
    (root / "modules/redis/main.tf", "permissions_boundary_arn = var.permissions_boundary_arn", 1, "Redis boundary forwarding links"),
    (root / "modules/clickhouse/main.tf", "permissions_boundary_arn = var.permissions_boundary_arn", 1, "ClickHouse boundary forwarding links"),
)
for path, needle, expected, label in checks:
    if not path.is_file():
        fail(f"boundary source file missing: {path.relative_to(root)}")
    actual = path.read_text().count(needle)
    if actual != expected:
        fail(f"expected {expected} {label}, found {actual}")

print("PASS: IAM task-boundary source chain")
PY_WIRING

scan_hygiene "$DOC"

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

  source_root="$fixture_tmp/clickhouse-forwarding"
  make_source_root "$source_root"
  mutate_source_once "$source_root/modules/clickhouse/main.tf" "permissions_boundary_arn = var.permissions_boundary_arn"
  expect_fail clickhouse-forwarding "expected 1 ClickHouse boundary forwarding links, found 0" "${child_env[@]}" IAM_MATRIX_REPO_ROOT="$source_root" "$0"

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
}

if [ "${IAM_MATRIX_SKIP_NEGATIVES:-0}" != 1 ]; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  run_negative_fixtures "$tmp_dir"
fi

echo "PASS: IAM matrix contracts (85 statements, 13 bindings)"
