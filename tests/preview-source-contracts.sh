#!/usr/bin/env bash
set -u

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ROOT="$REPO_ROOT/envs/preview"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

run_contract() {
  python3 - "$1" <<'PY'
from collections import Counter
from pathlib import Path
import re
import sys


source_root = Path(sys.argv[1])
paths = sorted(source_root.glob("*.tf"))
tf_json_paths = sorted(source_root.glob("*.tf.json"))
if not paths or tf_json_paths:
    raise SystemExit("FAIL: preview-source-input")


def strip_comments(text):
    result = list(text)
    index = 0
    state = "normal"
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""
        if state == "normal":
            if text.startswith("<<", index):
                raise ValueError("heredocs are not supported")
            if char == '"':
                state = "string"
            elif char == "#":
                state = "line"
                result[index] = " "
            elif char == "/" and next_char == "/":
                state = "line"
                result[index] = result[index + 1] = " "
                index += 1
            elif char == "/" and next_char == "*":
                state = "block"
                result[index] = result[index + 1] = " "
                index += 1
        elif state == "string":
            if char == "\\":
                index += 1
            elif char == '"':
                state = "normal"
        elif state == "line":
            if char == "\n":
                state = "normal"
            else:
                result[index] = " "
        elif state == "block":
            if char == "*" and next_char == "/":
                result[index] = result[index + 1] = " "
                index += 1
                state = "normal"
            elif char != "\n":
                result[index] = " "
        index += 1
    return "".join(result)


def structural_depths(text):
    depths = [0] * (len(text) + 1)
    depth = 0
    in_string = False
    escaped = False
    for index, char in enumerate(text):
        depths[index] = depth
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
    depths[len(text)] = depth
    return depths


def matching_brace(text, opening):
    depth = 0
    in_string = False
    escaped = False
    for index in range(opening, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    raise ValueError("unmatched block brace")


block_pattern = re.compile(
    r"(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_-]*)\b([^\n={]*)\{"
)


def top_blocks(text):
    depths = structural_depths(text)
    for match in block_pattern.finditer(text):
        if depths[match.start()] != 0:
            continue
        opening = text.find("{", match.start(), match.end())
        closing = matching_brace(text, opening)
        yield {
            "kind": match.group(1),
            "labels": re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', match.group(2)),
            "body": text[opening + 1 : closing],
        }


assignment_pattern = re.compile(r"(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*([^\n]*)")


def top_assignments(text):
    depths = structural_depths(text)
    return [
        (match.group(1), match.group(2).strip())
        for match in assignment_pattern.finditer(text)
        if depths[match.start()] == 0
    ]


def normalized(value):
    return re.sub(r"\s+", "", value)


def nested_assignments(body, path=()):
    values = [(path, name, value) for name, value in top_assignments(body)]
    for block in top_blocks(body):
        values.extend(nested_assignments(block["body"], path + (block["kind"],)))
    return values


try:
    texts = {path: strip_comments(path.read_text()) for path in paths}
    if any(structural_depths(text)[-1] != 0 for text in texts.values()):
        raise ValueError("unbalanced source braces")
    root_blocks = [block for text in texts.values() for block in top_blocks(text)]
except ValueError as error:
    print(f"FAIL: preview-source-parse ({error})", file=sys.stderr)
    raise SystemExit(1)
combined = "\n".join(texts.values())
resources = {
    f'{block["labels"][0]}.{block["labels"][1]}': block
    for block in root_blocks
    if block["kind"] == "resource" and len(block["labels"]) == 2
}
modules = {
    block["labels"][0]: block
    for block in root_blocks
    if block["kind"] == "module" and len(block["labels"]) == 1
}

alb_reference_count = len(re.findall(r"\baws_security_group\.alb\b", combined))
lb_block = resources.get("aws_lb.this", {"body": ""})
service_block = resources.get("aws_security_group.service", {"body": ""})
lb_security_groups = [
    value for name, value in top_assignments(lb_block["body"]) if name == "security_groups"
]
service_ingress_security_groups = [
    value
    for block in top_blocks(service_block["body"])
    if block["kind"] == "ingress"
    for name, value in top_assignments(block["body"])
    if name == "security_groups"
]
alb_reference_set = (
    alb_reference_count == 2
    and [normalized(value) for value in lb_security_groups]
    == ["[aws_security_group.alb.id]"]
    and [normalized(value) for value in service_ingress_security_groups]
    == ["[aws_security_group.alb.id]"]
)

sg_argument_names = {
    "security_groups",
    "security_group_id",
    "security_group_ids",
    "vpc_security_group_ids",
    "source_security_group_id",
    "referenced_security_group_id",
}
expected_workload_modules = {"redis", "clickhouse", "api", "worker"}
workload_records = []
unexpected_module_arguments = []
for module_name, block in modules.items():
    for name, value in top_assignments(block["body"]):
        if "security_group" not in name:
            continue
        if name == "security_group_ids":
            workload_records.append((module_name, normalized(value)))
        else:
            unexpected_module_arguments.append((module_name, name, normalized(value)))
workload_security_groups = (
    {record[0] for record in workload_records} == expected_workload_modules
    and all(record[1] == "[aws_security_group.service.id]" for record in workload_records)
    and not unexpected_module_arguments
)

forbidden_patterns = (
    r"\baws_lb\.this\.security_groups\b",
    r"\baws_security_group\.(?:service|alb)\.(?:ingress|egress)\b",
    r'\bdata\s+"aws_security_groups?"\s+"',
    r"\baws_security_group\.alb\b(?!\.id\b)",
)
no_indirection = not any(re.search(pattern, combined) for pattern in forbidden_patterns)

root_sg_records = []
for resource_name, block in resources.items():
    for path, name, value in nested_assignments(block["body"]):
        if name in sg_argument_names:
            root_sg_records.append(
                (resource_name, "/".join(path) if path else "root", name, normalized(value))
            )
expected_root_sg_records = [
    ("aws_lb.this", "root", "security_groups", "[aws_security_group.alb.id]"),
    (
        "aws_security_group.service",
        "ingress",
        "security_groups",
        "[aws_security_group.alb.id]",
    ),
    (
        "aws_security_group.service",
        "egress",
        "security_groups",
        "[module.network.endpoint_sg_id]",
    ),
]
root_resource_allowlist = Counter(root_sg_records) == Counter(expected_root_sg_records)

bucket_policy = resources.get("aws_s3_bucket_policy.data", {"body": ""})["body"]
partition_source = "arn:${data.aws_partition.current.partition}:s3:::"
policy_partition_source = (
    bucket_policy.count(partition_source) == 2
    and "arn:aws:" not in combined
)

checks = (
    ("alb-reference-set", alb_reference_set),
    ("workload-security-groups", workload_security_groups),
    ("no-indirection", no_indirection),
    ("root-resource-allowlist", root_resource_allowlist),
    ("policy-partition-source", policy_partition_source),
)
failures = 0
for name, passed in checks:
    if passed:
        print(f"PASS: {name}")
    else:
        print(f"FAIL: {name}", file=sys.stderr)
        failures += 1
if failures:
    print(
        f"FAIL: preview source contracts ({failures} of {len(checks)} assertions failed)",
        file=sys.stderr,
    )
    raise SystemExit(1)
print(f"PASS: preview source contracts ({len(checks)} assertions)")
PY
}

baseline_output="$(run_contract "$SOURCE_ROOT" 2>&1)"
baseline_rc=$?
if [ "$baseline_rc" -ne 0 ]; then
  echo "FAIL: unmodified preview source" >&2
  printf '%s\n' "$baseline_output" >&2
  exit 1
fi
printf '%s\n' "$baseline_output"

mutant_count=0
killed_count=0
runner_failures=0

run_mutant() {
  local name="$1"
  local predicate="$2"
  local mutant_root="$tmp_dir/$name"
  local output
  local rc

  mutant_count=$((mutant_count + 1))
  mkdir -p "$mutant_root"
  cp "$SOURCE_ROOT"/*.tf "$mutant_root/"

  case "$name" in
    local-alb-alias)
      printf '\nlocals {\n  mutant_alb_id = aws_security_group.alb.id\n}\n' >> "$mutant_root/main.tf"
      ;;
    local-lb-security-groups)
      printf '\nlocals {\n  mutant_lb_groups = tolist(aws_lb.this.security_groups)\n}\nmodule "mutant" {\n  source = "../../modules/ecs-service"\n  security_group_ids = local.mutant_lb_groups\n}\n' >> "$mutant_root/main.tf"
      ;;
    local-service-ingress-readback)
      printf '\nlocals {\n  mutant_service_groups = aws_security_group.service.ingress[*].security_groups\n}\nresource "aws_instance" "mutant" {\n  vpc_security_group_ids = flatten(local.mutant_service_groups)\n}\n' >> "$mutant_root/main.tf"
      ;;
    module-alb-group)
      perl -0pi -e 's/security_group_ids = \[aws_security_group\.service\.id\]/security_group_ids = [aws_security_group.alb.id]/' "$mutant_root/main.tf"
      ;;
    module-second-group)
      perl -0pi -e 's/security_group_ids = \[aws_security_group\.service\.id\]/security_group_ids = [aws_security_group.service.id, module.network.endpoint_sg_id]/' "$mutant_root/main.tf"
      ;;
    data-security-group-lookup)
      printf '\ndata "aws_security_group" "mutant" {\n  id = aws_security_group.alb.id\n}\n' >> "$mutant_root/main.tf"
      ;;
    third-alb-reference)
      printf '\nresource "aws_instance" "mutant" {\n  vpc_security_group_ids = [aws_security_group.alb.id]\n}\n' >> "$mutant_root/main.tf"
      ;;
    unallowlisted-service-reference)
      printf '\nresource "aws_instance" "mutant" {\n  vpc_security_group_ids = [aws_security_group.service.id]\n}\n' >> "$mutant_root/main.tf"
      ;;
    lb-reference-removed)
      perl -0pi -e 's/security_groups            = \[aws_security_group\.alb\.id\]/security_groups            = []/' "$mutant_root/main.tf"
      ;;
    hardcoded-policy-partition)
      perl -0pi -e 's/arn:\$\{data\.aws_partition\.current\.partition\}:s3:::/arn:aws:s3:::/g' "$mutant_root/main.tf"
      ;;
    heredoc-depth-decoy)
      printf '
locals {
  mutant_heredoc = <<END-MARK
}
END-MARK
}
resource "aws_instance" "mutant" {
  vpc_security_group_ids = [aws_security_group.service.id]
}
' >> "$mutant_root/main.tf"
      ;;
    duplicate-service-egress)
      perl -0pi -e 's/(  egress \{
    description     = "Interface VPC endpoints[^"\n]*".*?security_groups = \[module\.network\.endpoint_sg_id\]
  \}
)/$1$1/s' "$mutant_root/main.tf"
      ;;
    heredoc-alb-reference)
      printf '\nlocals {\n  mutant_heredoc_reference = <<EOT\n$%s\nEOT\n}\n' \
        '{aws_security_group.alb.id}' >> "$mutant_root/main.tf"
      ;;
    unsupported-tf-json)
      printf '%s\n' '{"resource":{"aws_instance":{"mutant":{"vpc_security_group_ids":["unexpected"]}}}}' > "$mutant_root/mutant.tf.json"
      ;;
    unsupported-unicode-heredoc)
      printf '\nlocals {\n  mutant_heredoc = <<ÉND\nharmless\nÉND\n}\n' >> "$mutant_root/main.tf"
      ;;
    *)
      echo "FAIL: unknown source mutant $name" >&2
      runner_failures=$((runner_failures + 1))
      return
      ;;
  esac

  output="$(run_contract "$mutant_root" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] && grep -Fq "FAIL: $predicate" <<< "$output"; then
    printf 'PASS: mutant %s killed by %s\n' "$name" "$predicate"
    killed_count=$((killed_count + 1))
  else
    printf 'FAIL: mutant %s survived %s\n' "$name" "$predicate" >&2
    runner_failures=$((runner_failures + 1))
  fi
}

run_mutant local-alb-alias alb-reference-set
run_mutant local-lb-security-groups no-indirection
run_mutant local-service-ingress-readback no-indirection
run_mutant module-alb-group workload-security-groups
run_mutant module-second-group workload-security-groups
run_mutant data-security-group-lookup no-indirection
run_mutant third-alb-reference alb-reference-set
run_mutant unallowlisted-service-reference root-resource-allowlist
run_mutant lb-reference-removed alb-reference-set
run_mutant hardcoded-policy-partition policy-partition-source
run_mutant heredoc-depth-decoy preview-source-parse
run_mutant duplicate-service-egress root-resource-allowlist
run_mutant heredoc-alb-reference preview-source-parse
run_mutant unsupported-tf-json preview-source-input
run_mutant unsupported-unicode-heredoc preview-source-parse

if [ "$runner_failures" -ne 0 ]; then
  printf 'FAIL: preview source mutations (%d of %d mutants not killed)\n' \
    "$runner_failures" "$mutant_count" >&2
  exit 1
fi

printf 'PASS: preview source mutations (%d mutants, all killed)\n' "$killed_count"
