#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANON="$REPO_ROOT/scripts/sbom-canon.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/sbom"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if [ ! -x "$CANON" ]; then
  fail "scripts/sbom-canon.sh must exist and be executable"
fi

for fixture in "$FIXTURES"/*.spdx.json; do
  jq -e '.creationInfo.creators | index("Tool: syft-1.51.1") != null' \
    "$fixture" >/dev/null || fail "fixture lacks syft creator provenance: ${fixture##*/}"
done

jq -e '
  (.packages | length) == 2
  and ([.packages[] | select(has("checksums"))] | length) == 1
  and (.packages[0].name == .packages[1].name)
  and (.packages[0].versionInfo == .packages[1].versionInfo)
  and any(.relationships[];
    .relationshipType == "CONTAINS"
    and (.spdxElementId | startswith("SPDXRef-Package-"))
    and (.relatedSpdxElement | startswith("SPDXRef-File-")))
' "$FIXTURES/base.spdx.json" >/dev/null || fail "base fixture shape is not the trimmed real-syft graph"
echo "PASS: SBOM fixtures retain syft provenance and two-package graph"

for fixture in "$FIXTURES"/*.spdx.json; do
  "$CANON" < "$fixture" > "$tmp_dir/${fixture##*/}.canon"
done

base="$tmp_dir/base.spdx.json.canon"
for equal_fixture in \
  timestamp-only-difference \
  identifier-renumber \
  reversed-order-same-name; do
  cmp -s "$base" "$tmp_dir/${equal_fixture}.spdx.json.canon" || \
    fail "base canonical form must equal ${equal_fixture}"
  echo "PASS: SBOM canonical equality base == ${equal_fixture}"
done

for different_fixture in \
  same-inventory-different-checksum \
  same-inventory-different-license \
  same-inventory-different-relationship \
  identifier-swap \
  relationship-switch-same-name; do
  if cmp -s "$base" "$tmp_dir/${different_fixture}.spdx.json.canon"; then
    fail "base canonical form must differ from ${different_fixture}"
  fi
  echo "PASS: SBOM canonical difference base != ${different_fixture}"
done

jq 'del(.packages, .relationships)' "$FIXTURES/base.spdx.json" \
  | "$CANON" > "$tmp_dir/null-safe.canon"
if [ "$(cat "$tmp_dir/null-safe.canon")" != '{"packages":[],"relationships":[]}' ]; then
  fail "missing package and relationship arrays must canonicalise to empty arrays"
fi
echo "PASS: SBOM canonicalizer is null-safe"

echo "PASS: SBOM canonicalization contracts (12 assertions)"
