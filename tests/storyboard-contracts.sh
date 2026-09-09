#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GENERATOR="$REPO_ROOT/scripts/storyboard.py"
STORYBOARD_REPO_ROOT="${STORYBOARD_REPO_ROOT:-$REPO_ROOT}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

check_asset() {
  local asset_root=$1
  local asset="$asset_root/docs/assets/storyboard.svg"
  local provenance="$asset_root/docs/assets/STORYBOARD_PROVENANCE.md"
  local recorded_sha actual_sha recorded_commit
  if [ ! -e "$asset" ] && [ ! -e "$provenance" ]; then
    echo "SKIP: storyboard asset not committed yet"
  elif [ ! -f "$asset" ] || [ ! -f "$provenance" ]; then
    fail "storyboard asset and provenance must either both exist or both be absent"
  else
    python3 "$GENERATOR" --check
    recorded_sha="$(sed -n 's/^| artifact sha256 | \([0-9a-f]\{64\}\) |$/\1/p' "$provenance")"
    [ -n "$recorded_sha" ] || fail "storyboard provenance lacks one artifact sha256 row"
    actual_sha="$(shasum -a 256 "$asset" | awk '{print $1}')"
    [ "$recorded_sha" = "$actual_sha" ] || fail "storyboard provenance sha256 differs"
    recorded_commit="$(sed -n 's/^| generator commit | \([0-9a-f]\{7,40\}\) |$/\1/p' "$provenance")"
    [ -n "$recorded_commit" ] || fail "storyboard provenance lacks one generator commit row"
    grep -Fxq '| command | make storyboard |' "$provenance" || \
      fail "storyboard provenance lacks the reproduction command"
    git -C "$asset_root" cat-file -e "$recorded_commit^{commit}" 2>/dev/null || \
      fail "storyboard generator commit is unreachable"
    git -C "$asset_root" diff --quiet "$recorded_commit" HEAD -- \
      scripts/storyboard.py Makefile || fail "regenerate the storyboard"
    echo "PASS: storyboard asset contracts"
  fi
}

init_asset_scratch() {
  local destination=$1
  mkdir -p "$destination/docs/assets"
  cp "$REPO_ROOT/docs/assets/storyboard.svg" "$destination/docs/assets/storyboard.svg"
  cp "$REPO_ROOT/docs/assets/STORYBOARD_PROVENANCE.md" \
    "$destination/docs/assets/STORYBOARD_PROVENANCE.md"
  git -C "$destination" init -q
  git -C "$destination" add docs/assets/storyboard.svg \
    docs/assets/STORYBOARD_PROVENANCE.md
  git -C "$destination" -c user.name=t -c user.email=t@localhost \
    commit -q -m fixtures
}

inspect_svg() {
  local svg=$1
  local expected="$tmp_dir/expected-captions.txt"
  local actual="$tmp_dir/actual-captions.txt"
  cat > "$expected" <<'CAPTIONS'
Pull request opens
Static gates: fmt, validate, lint, policy-size, conftest
LocalStack plan posts a comment on the PR
Preview lease opens: new generation, owner token
Terraform applies; acceptance checks pass
Close begins: Stage 1 destroy and verify
Stage 2 sweep reclaims state and lock versions
Supply chain: signed images verified at apply
CAPTIONS
  python3 - "$svg" "$actual" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

svg_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
root = ET.fromstring(svg_path.read_text(encoding="utf-8"))
captions = [
    "".join(node.itertext())
    for node in root.iter()
    if node.attrib.get("class") == "caption"
]
output_path.write_text("\n".join(captions) + "\n", encoding="utf-8")
if any(len(caption) >= 60 for caption in captions):
    raise SystemExit("caption length must be less than 60 characters")
PY
  cmp -s "$expected" "$actual" || fail "storyboard captions differ from the contract"
  grep -Fq 'role="img"' "$svg" || fail 'storyboard lacks role="img"'
  grep -Fq '<title>' "$svg" || fail "storyboard lacks a title"
  grep -Fq '<desc>' "$svg" || fail "storyboard lacks a description"
  grep -Fq 'prefers-reduced-motion' "$svg" || fail "storyboard lacks reduced-motion styling"
  ! grep -Fqi '<script' "$svg" || fail "storyboard contains a script"
  ! grep -Eqi 'url[[:space:]]*\(' "$svg" || fail "storyboard contains an external URL reference"
  ! grep -qE '[0-9]{12}' "$svg" || fail "storyboard contains a 12-digit identifier"
  ! grep -qE '/Users/|/home/' "$svg" || fail "storyboard contains a home path"
  if grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$svg" | \
      grep -vqE '^203\.0\.113\.'; then
    fail "storyboard contains a non-TEST-NET-3 IP address"
  fi
  local local_user local_host
  local_user="$(id -un)"
  local_host="$(hostname -s 2>/dev/null || hostname)"
  ! grep -qiF "$local_user" "$svg" || fail "storyboard contains the local username"
  ! grep -qiF "$local_host" "$svg" || fail "storyboard contains the local hostname"
}

echo "== storyboard contracts: generator =="
[ -f "$GENERATOR" ] || fail "scripts/storyboard.py is required"
python3 "$GENERATOR" --output "$tmp_dir/first.svg"
python3 "$GENERATOR" --output "$tmp_dir/second.svg"
cmp -s "$tmp_dir/first.svg" "$tmp_dir/second.svg" || \
  fail "two storyboard generations differ"
inspect_svg "$tmp_dir/first.svg"

python3 "$GENERATOR" --snapshot 0 --output "$tmp_dir/snapshot-0.svg"
python3 "$GENERATOR" --snapshot 12 --output "$tmp_dir/snapshot-12.svg"
inspect_svg "$tmp_dir/snapshot-0.svg"
inspect_svg "$tmp_dir/snapshot-12.svg"
cmp -s "$tmp_dir/snapshot-0.svg" "$tmp_dir/snapshot-12.svg" && \
  fail "snapshot 0 and snapshot 12 are byte-identical"
grep -Fq 'data-snapshot="0"' "$tmp_dir/snapshot-0.svg" || \
  fail "snapshot 0 does not identify its simulated time"
grep -Fq 'data-snapshot="12"' "$tmp_dir/snapshot-12.svg" || \
  fail "snapshot 12 does not identify its simulated time"
grep -Fq 'id="step-1" class="panel panel-1 lit"' "$tmp_dir/snapshot-0.svg" || \
  fail "snapshot 0 does not light the first scheduled panel"
[ "$(grep -Ec 'id="step-[0-9]+" class="[^"]* lit"' \
  "$tmp_dir/snapshot-0.svg")" -eq 1 ] || \
  fail "snapshot 0 lights an unexpected panel set"
grep -Fq 'id="step-5" class="panel panel-5 lit"' "$tmp_dir/snapshot-12.svg" || \
  fail "snapshot 12 does not light the apply panel"
grep -Fq 'id="step-8" class="panel panel-8 supply lit"' \
  "$tmp_dir/snapshot-12.svg" || \
  fail "snapshot 12 does not light the attached supply-chain panel"
[ "$(grep -Ec 'id="step-[0-9]+" class="[^"]* lit"' \
  "$tmp_dir/snapshot-12.svg")" -eq 2 ] || \
  fail "snapshot 12 lights an unexpected panel set"

mutation_ok=1
sed 's/Pull request opens/Pull request closes/' "$tmp_dir/first.svg" >   "$tmp_dir/caption.svg"
if (inspect_svg "$tmp_dir/caption.svg") >/dev/null 2>&1; then mutation_ok=0; fi
cp "$tmp_dir/first.svg" "$tmp_dir/script.svg"
sed -i.bak 's#</svg>#<script>unsafe</script></svg>#' "$tmp_dir/script.svg"
rm -f "$tmp_dir/script.svg.bak"
if (inspect_svg "$tmp_dir/script.svg") >/dev/null 2>&1; then mutation_ok=0; fi
cp "$tmp_dir/first.svg" "$tmp_dir/motion.svg"
sed -i.bak 's/prefers-reduced-motion/reduced-motion-removed/' "$tmp_dir/motion.svg"
rm -f "$tmp_dir/motion.svg.bak"
if (inspect_svg "$tmp_dir/motion.svg") >/dev/null 2>&1; then mutation_ok=0; fi
cp "$tmp_dir/first.svg" "$tmp_dir/account.svg"
account_number="$(printf '1%.0s' {1..12})"
sed -i.bak "s#</desc># $account_number</desc>#" "$tmp_dir/account.svg"
rm -f "$tmp_dir/account.svg.bak"
if (inspect_svg "$tmp_dir/account.svg") >/dev/null 2>&1; then mutation_ok=0; fi
[ "$mutation_ok" -eq 1 ] || fail "storyboard scratch mutation table survived"

pairing_root="$tmp_dir/pairing-root"
init_asset_scratch "$pairing_root"
mv "$pairing_root/docs/assets/STORYBOARD_PROVENANCE.md" \
  "$tmp_dir/pairing-provenance.removed"
if pairing_output="$(
  check_asset "$pairing_root" 2>&1
)"; then
  fail "storyboard asset/provenance pairing mutation passed"
fi
grep -Fxq \
  'FAIL: storyboard asset and provenance must either both exist or both be absent' \
  <<< "$pairing_output" || \
  fail "storyboard pairing failure branch was not exercised"

absent_root="$tmp_dir/absent-root"
init_asset_scratch "$absent_root"
mv "$absent_root/docs/assets/storyboard.svg" "$tmp_dir/absent-storyboard.removed"
mv "$absent_root/docs/assets/STORYBOARD_PROVENANCE.md" \
  "$tmp_dir/absent-provenance.removed"
if ! absent_output="$(
  check_asset "$absent_root" 2>&1
)"; then
  fail "storyboard both-absent branch failed: $absent_output"
fi
grep -Fxq 'SKIP: storyboard asset not committed yet' <<< "$absent_output" || \
  fail "storyboard both-absent branch did not emit its explicit skip: $absent_output"
echo "PASS: storyboard generator contracts"

echo "== storyboard contracts: asset =="
check_asset "$STORYBOARD_REPO_ROOT"
