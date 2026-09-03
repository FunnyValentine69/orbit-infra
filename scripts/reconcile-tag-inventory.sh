#!/usr/bin/env bash
# Compatibility entry point: normalize tag entries and delegate every exact
# predicate to cleanup-verifier.sh. It never aborts a batch for one resource.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFIER="$SCRIPT_DIR/cleanup-verifier.sh"
case "${TARGET:-}" in
  aws|localstack) ;;
  *) echo "reconcile-tag-inventory.sh: TARGET is required and must be aws or localstack" >&2; exit 2 ;;
esac
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

"$VERIFIER" normalize-tags > "$tmp_dir/candidates.json"
result="$("$VERIFIER" verify-live "$tmp_dir/candidates.json")"
jq -c '
  .typed_live = .live
  | .typed_gone = .gone
  | .live = [.live[] | (.tag_entry // {ResourceARN: .arn, Tags: []})]
  | .stale = [.gone[] | (.tag_entry // {ResourceARN: .arn, Tags: []})]
  | .stale_tag_entries = .stale
' <<< "$result"
