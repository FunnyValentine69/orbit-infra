#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 [--forbid-file <path>] <artifact> [artifact ...]" >&2
  exit 2
}

forbid_file=""
files=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --forbid-file)
      [ "$#" -ge 2 ] || usage
      forbid_file="$2"
      shift 2
      ;;
    *)
      files+=("$1")
      shift
      ;;
  esac
done

[ "${#files[@]}" -ge 1 ] || usage

for artifact in "${files[@]}"; do
  [ -f "$artifact" ] || { echo "FAIL: $artifact: file not found" >&2; exit 1; }
done

if [ -n "$forbid_file" ]; then
  [ -f "$forbid_file" ] || { echo "FAIL: --forbid-file $forbid_file: file not found" >&2; exit 1; }
fi

for artifact in "${files[@]}"; do
  if ! python3 - "$artifact" "$forbid_file" <<'PY'
import json
import re
import sys

artifact, forbid_file = sys.argv[1], sys.argv[2]

HEX64 = re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])")
HEX40 = re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{40}(?![0-9a-fA-F])")
ACCOUNT_ID = re.compile(r"[0-9]{12}")
IAM_ARN = re.compile(r"arn:aws:iam::([0-9]{12})")
PRINCIPAL_ID = re.compile(r"(?:AIDA|AROA|ASIA|AKIA|ANPA|AGPA|AIPA)[A-Z0-9]{12,}")
PRINCIPAL_ARN = re.compile(
    r"arn:aws:(?:iam|sts)::[0-9]{12}:"
    r"(?P<identity_path>"
    r"<redacted-principal>|"
    r"(?:user|role|assumed-role|group|federated-user)/[A-Za-z0-9+=,.@_/-]+"
    r")"
)
REDACTED_PRINCIPAL = "<redacted-principal>"
RESOURCE_FIELDS = {"resource_arn", "Resource", "NotResource"}
ASSUMED_ROLE = re.compile(r"assumed-role/")
REQUEST_ID_KEY = re.compile(r"(?:x-amzn-)?RequestId", re.IGNORECASE)
BARE_UUID = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)
PLACEHOLDER_ACCOUNT = "000000000000"

forbid_terms = []
if forbid_file:
    with open(forbid_file, encoding="utf-8") as handle:
        for raw in handle:
            term = raw.rstrip("\n")
            if not term.strip() or term.strip().startswith("#"):
                continue
            forbid_terms.append(term)

with open(artifact, encoding="utf-8") as handle:
    lines = handle.readlines()


def unredacted_principal(value):
    for match in PRINCIPAL_ARN.finditer(value):
        identity_path = match.group("identity_path")
        if identity_path != REDACTED_PRINCIPAL:  # principal-arn-guard
            return match.group(0)
    return None


def find_unredacted_principal(value, field=None):
    if field in RESOURCE_FIELDS:
        return None
    if isinstance(value, dict):
        for key, item in value.items():
            found = find_unredacted_principal(item, key)
            if found is not None:
                return found
        return None
    if isinstance(value, list):
        for item in value:
            found = find_unredacted_principal(item, field)
            if found is not None:
                return found
        return None
    if not isinstance(value, str):
        return None
    if value.lstrip().startswith("{"):
        try:
            nested = json.loads(value)
        except json.JSONDecodeError:
            pass
        else:
            return find_unredacted_principal(nested)
    return unredacted_principal(value)


serialized = "".join(lines)
try:
    json_payload = json.loads(serialized)
except json.JSONDecodeError:
    json_payload = None


def digest_field(field):
    if not isinstance(field, str):
        return False
    normalized = field.casefold()
    return (
        normalized.endswith("sha256")
        or normalized.endswith("hash")
        or normalized.endswith("hashes_submitted")
        or normalized == "generator_commit"
    )


def collect_scoped_hex(value, field=None, inherited=False):
    scoped = inherited or digest_field(field)
    found = set()
    if isinstance(value, dict):
        for key, item in value.items():
            found.update(collect_scoped_hex(item, key, scoped))
    elif isinstance(value, list):
        for item in value:
            found.update(collect_scoped_hex(item, field, scoped))
    elif isinstance(value, str) and scoped:
        found.update(HEX64.findall(value))
        found.update(HEX40.findall(value))
    return found


json_scoped_hex = collect_scoped_hex(json_payload) if json_payload is not None else set()
markdown_sha_column = None
markdown_sha_columns = {}
for index, raw_line in enumerate(lines, 1):
    table_line = raw_line.rstrip("\n")
    if not (table_line.startswith("|") and table_line.endswith("|")):
        markdown_sha_column = None
        continue
    cells = [cell.strip() for cell in table_line[1:-1].split("|")]
    normalized = [re.sub(r"[^a-z0-9]", "", cell.casefold()) for cell in cells]
    if "sha256" in normalized:
        markdown_sha_column = normalized.index("sha256")
        continue
    if markdown_sha_column is not None and markdown_sha_column < len(cells):
        markdown_sha_columns[index] = markdown_sha_column


def strip_complete_hex(value):
    sanitized = HEX64.sub("", value)  # sha256-guard
    sanitized = HEX40.sub("", sanitized)  # git-sha-guard
    return sanitized


def sanitize_scoped_hex(content, json_payload, line_no):
    if json_payload is not None:
        direct_digest = re.compile(
            r'("(?:[^"\\]|\\.)*(?:sha256|hash|generator_commit)"\s*:\s*")'
            r'([0-9a-fA-F]{40}|[0-9a-fA-F]{64})(")',
            re.IGNORECASE,
        )
        sanitized = direct_digest.sub(r"\1\3", content)
        if '"hashes_submitted"' in content or re.match(
            r'^\s*"[0-9a-fA-F]+"[,]?\s*$', content
        ):
            for token in json_scoped_hex:
                sanitized = sanitized.replace(token, "")
        return sanitized
    if not (content.startswith("|") and content.endswith("|")):
        return content
    cells = content[1:-1].split("|")
    first = re.sub(r"[^a-z0-9]", "", cells[0].casefold()) if cells else ""
    scoped_cells = set()
    if "sha256" in first or "commit" in first:
        scoped_cells.update(range(len(cells)))
    if line_no in markdown_sha_columns:
        scoped_cells.add(markdown_sha_columns[line_no])
    for index in scoped_cells:
        cells[index] = strip_complete_hex(cells[index])
    return "|" + "|".join(cells) + "|"


if json_payload is not None:
    leaked_principal = find_unredacted_principal(json_payload)
    if leaked_principal is not None:
        line_no = next(
            (index for index, line in enumerate(lines, 1) if leaked_principal in line),
            1,
        )
        print(
            f"FAIL: {artifact}:{line_no}: principal-arn - "
            "IAM/STS principal identity path is not <redacted-principal>",
            file=sys.stderr,
        )
        sys.exit(1)


for line_no, line in enumerate(lines, 1):
    content = line.rstrip("\n")
    sanitized = sanitize_scoped_hex(content, json_payload, line_no)

    for account_id in IAM_ARN.findall(sanitized):
        if account_id != PLACEHOLDER_ACCOUNT:  # iam-arn-guard
            print(
                f"FAIL: {artifact}:{line_no}: iam-arn - "
                f"arn:aws:iam:: account {account_id} is not the placeholder",
                file=sys.stderr,
            )
            sys.exit(1)

    for account_id in ACCOUNT_ID.findall(sanitized):
        if account_id != PLACEHOLDER_ACCOUNT:  # account-id-guard
            print(
                f"FAIL: {artifact}:{line_no}: account-id - "
                f"non-placeholder 12-digit account id {account_id}",
                file=sys.stderr,
            )
            sys.exit(1)

    leaked_principal = unredacted_principal(content) if json_payload is None else None
    if leaked_principal is not None:
        print(
            f"FAIL: {artifact}:{line_no}: principal-arn - "
            "IAM/STS principal identity path is not <redacted-principal>",
            file=sys.stderr,
        )
        sys.exit(1)

    if PRINCIPAL_ID.search(content):
        print(
            f"FAIL: {artifact}:{line_no}: principal-id - "
            "AWS principal/session identifier present",
            file=sys.stderr,
        )
        sys.exit(1)

    if ASSUMED_ROLE.search(content):
        print(
            f"FAIL: {artifact}:{line_no}: principal-id - assumed-role/ present",
            file=sys.stderr,
        )
        sys.exit(1)

    if REQUEST_ID_KEY.search(content):
        print(
            f"FAIL: {artifact}:{line_no}: request-id - "
            "RequestId / x-amzn-RequestId key present",
            file=sys.stderr,
        )
        sys.exit(1)

    if BARE_UUID.search(sanitized):
        print(
            f"FAIL: {artifact}:{line_no}: request-id - bare UUID present",
            file=sys.stderr,
        )
        sys.exit(1)

    for term in forbid_terms:
        if term in content:
            print(
                f"FAIL: {artifact}:{line_no}: forbid-list - "
                f"forbidden literal '{term}' present",
                file=sys.stderr,
            )
            sys.exit(1)

print(f"PASS: {artifact}")
PY
  then
    exit 1
  fi
done
