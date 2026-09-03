#!/usr/bin/env bash
# Print exactly one version for a tool named in tools.lock.
#
# tools.lock lists every tool twice: a "<name> <version>" line in the
# versions section and a "<name> <sha256|<checksum unavailable ...>>" line
# in the checksums section. A bare `grep '^<name> '` therefore returns two
# lines, and a multi-line value is an invalid GITHUB_OUTPUT record ("Invalid
# format '<checksum'"), which is how every CI version read failed before
# this helper existed. Only the first line whose second field looks like a
# semantic version is accepted; anything else is a hard error.
set -euo pipefail
tool="${1:?usage: tool-version.sh <tool>}"
lock="${TOOLS_LOCK:-$(cd "$(dirname "$0")/.." && pwd)/tools.lock}"
version="$(awk -v tool="$tool" '$1 == tool && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ { print $2; exit }' "$lock")"
if [ -z "$version" ]; then
  echo "tool-version.sh: no semantic version for '$tool' in $lock" >&2
  exit 1
fi
printf '%s\n' "$version"
