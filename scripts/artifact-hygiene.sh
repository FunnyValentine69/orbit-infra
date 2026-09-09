#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 [--forbid-file <path>] <artifact.md> [artifact.md ...]" >&2
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
import re
import sys

artifact, forbid_file = sys.argv[1], sys.argv[2]

HEX64 = re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])")
ACCOUNT_ID = re.compile(r"[0-9]{12}")
IAM_ARN = re.compile(r"arn:aws:iam::([0-9]{12})")
PRINCIPAL_ID = re.compile(r"(?:AIDA|AROA|ASIA|AKIA|ANPA|AGPA|AIPA)[A-Z0-9]{12,}")
ASSUMED_ROLE = re.compile(r"assumed-role/")
REQUEST_ID_KEY = re.compile(r"(?:x-amzn-)?RequestId")
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

for line_no, line in enumerate(lines, 1):
    content = line.rstrip("\n")
    sanitized = HEX64.sub("", content)

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
