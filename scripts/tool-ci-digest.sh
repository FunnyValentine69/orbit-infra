#!/usr/bin/env bash
# Print exactly one Linux x86_64 release-archive digest from tools.lock.
set -euo pipefail

tool="${1:?usage: tool-ci-digest.sh <tool>}"
lock="${TOOLS_LOCK:-$(cd "$(dirname "$0")/.." && pwd)/tools.lock}"
header="# CI release-archive checksums (linux x86_64); verified once against the release's checksums.txt on 2026-09-04"

digest="$(awk -v tool="$tool" -v header="$header" '
  $0 == header { in_ci_block = 1; next }
  in_ci_block && /^#/ { exit }
  in_ci_block && $1 == tool && $2 ~ /^[0-9a-f]{64}$/ {
    print $2
    matches += 1
  }
  END { if (matches != 1) exit 1 }
' "$lock")" || {
  echo "tool-ci-digest.sh: expected one CI release-archive digest for '$tool' in $lock" >&2
  exit 1
}

printf '%s\n' "$digest"
