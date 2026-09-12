#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$REPO_ROOT/tests/docs-contracts.sh"

scan_docs() {
  local root=$1 manifest=$2 publication=${3:-current}
  python3 - "$root" "$manifest" "$publication" <<'PY_DOCS_SCAN'
from pathlib import Path
from urllib.parse import unquote
import posixpath
import re
import sys


root = Path(sys.argv[1]).resolve()
manifest_path = Path(sys.argv[2])
publication = sys.argv[3] == "publication"


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


tracked: set[str] = set()
for line_number, raw in enumerate(
    manifest_path.read_text(encoding="utf-8").splitlines(), 1
):
    path = raw.strip()
    if not path:
        continue
    normalized = posixpath.normpath(path)
    if path.startswith("/") or normalized == ".." or normalized.startswith("../"):
        fail(f"tracked manifest line {line_number} is outside the scan root: {path}")
    if normalized in tracked:
        fail(f"tracked manifest repeats path: {normalized}")
    if not (root / normalized).is_file():
        fail(f"tracked manifest path is not a file: {normalized}")
    tracked.add(normalized)

markdown = sorted(path for path in tracked if path.lower().endswith(".md"))
shell = sorted(path for path in tracked if path.lower().endswith(".sh"))
if not markdown:
    fail("tracked manifest contains no Markdown files")

link_pattern = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
reference_pattern = re.compile(r"^\s*\[[^\]]+\]:\s*(\S+)")
scheme_pattern = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
retired_paths = {
    "RUNBOOKS" + ".md",
    "docs/" + "EVIDENCE.md",
    "docs/" + "iam-matrix.md",
}


def destinations(text: str):
    fenced = False
    for line_number, line in enumerate(text.splitlines(), 1):
        if re.match(r"^\s*(?:```|~~~)", line):
            fenced = not fenced
            continue
        if fenced:
            continue
        for match in link_pattern.finditer(line):
            yield line_number, match.group(1)
        match = reference_pattern.match(line)
        if match:
            yield line_number, match.group(1)


for source in markdown:
    text = (root / source).read_text(encoding="utf-8")
    for line_number, raw_destination in destinations(text):
        destination = raw_destination.strip()
        parts = destination.split()
        if not destination or not parts:
            continue
        destination = parts[0]
        if destination.startswith("<") and destination.endswith(">"):
            destination = destination[1:-1]
        if (
            not destination
            or destination.startswith("#")
            or destination.startswith("//")
            or scheme_pattern.match(destination)
        ):
            continue
        path_part = unquote(destination.split("#", 1)[0].split("?", 1)[0])
        if not path_part:
            continue
        if path_part.startswith("/"):
            target = posixpath.normpath(path_part.lstrip("/"))
        else:
            target = posixpath.normpath(
                posixpath.join(posixpath.dirname(source), path_part)
            )
        if (
            target == "STATE" + ".md"
            or target in retired_paths
            or posixpath.normpath(path_part) == "iam-matrix.md"
        ):
            fail(f"retired documentation target in {source}:{line_number}: {path_part}")
        if target not in tracked:
            fail(f"unresolved documentation link in {source}:{line_number}: {path_part}")

for source in markdown + shell:
    text = (root / source).read_text(encoding="utf-8")
    for retired in sorted(retired_paths):
        found = (
            source in shell and re.search(r"(?<!docs/)RUNBOOKS\.md", text) is not None
            if retired == "RUNBOOKS" + ".md"
            else retired in text
        )
        if found:
            fail(f"retired documentation name in {source}: {retired}")

readme = (root / "README.md").read_text(encoding="utf-8")
for required_embed in (
    "docs/assets/storyboard.svg",
    "docs/assets/demo.gif",
    "docs/assets/demo-lease.gif",
    "docs/assets/demo-supplychain.gif",
):
    if not re.search(
        rf"!\[[^\]]*\]\({re.escape(required_embed)}(?:[?#][^)]*)?\)", readme
    ):
        fail(f"README missing required image embed: {required_embed}")

if publication:
    budgets = {
        "README.md": 80,
        "ARCHITECTURE.md": 160,
        "docs/VERIFY.md": 130,
        "docs/RUNBOOKS.md": 460,
        "docs/THREAT_MODEL.md": 110,
        "tests/README.md": 520,
    }
    for path, limit in budgets.items():
        if path not in tracked:
            fail(f"documentation budget file is not tracked: {path}")
        count = len((root / path).read_text(encoding="utf-8").splitlines())
        if count > limit:
            fail(f"documentation budget exceeded: {path} has {count} lines (limit {limit})")

    forbidden = (
        "Free" + " Plan",
        "Paid" + " Plan",
        "2027-" + "03-02",
        "$" + "100",
        "user" + " decision",
        "the owner" + " decided",
        "auto-" + "close",
    )
    for source in markdown + shell:
        text = (root / source).read_text(encoding="utf-8")
        for token in forbidden:
            if token in text:
                fail(f"forbidden public-scope token in {source}: {token}")

    for source in markdown:
        text = (root / source).read_text(encoding="utf-8")
        if "STATE" + ".md" in text:
            fail(f"retired documentation name in {source}: {'STATE' + '.md'}")
    if "STATE" + ".md" in tracked:
        fail("STATE" + ".md remains in the tracked manifest")

    index_path = "docs/evidence/README.md"
    if index_path not in tracked:
        fail(f"evidence index is not tracked: {index_path}")
    index_text = (root / index_path).read_text(encoding="utf-8")
    linked: set[str] = set()
    for _, raw_destination in destinations(index_text):
        destination = raw_destination.strip()
        parts = destination.split()
        if not destination or not parts:
            continue
        destination = parts[0]
        if destination.startswith("<") and destination.endswith(">"):
            destination = destination[1:-1]
        if (
            not destination
            or destination.startswith("#")
            or scheme_pattern.match(destination)
        ):
            continue
        path_part = unquote(destination.split("#", 1)[0].split("?", 1)[0])
        linked.add(
            posixpath.normpath(path_part.lstrip("/"))
            if path_part.startswith("/")
            else posixpath.normpath(
                posixpath.join(posixpath.dirname(index_path), path_part)
            )
        )
    indexed_files = sorted(
        path
        for path in tracked
        if (
            path.startswith("docs/assets/")
            or path.startswith("docs/evidence/")
        )
        and path != index_path
    )
    for path in indexed_files:
        if path not in linked:
            fail(f"evidence index missing link: {path}")

print(f"PASS: documentation scanner ({len(markdown)} Markdown files)")
PY_DOCS_SCAN
}

if [ "${1:-}" = "--scan" ]; then
  if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "usage: $0 --scan <root> <tracked-manifest> [current|publication]" >&2
    exit 2
  fi
  scan_docs "$2" "$3" "${4:-current}"
  exit 0
fi
if [ "$#" -ne 0 ]; then
  echo "usage: $0 [--scan <root> <tracked-manifest> [current|publication]]" >&2
  exit 2
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbit-docs.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
manifest="$tmp_dir/tracked-files.txt"
git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard | while IFS= read -r path; do
  if [ -f "$REPO_ROOT/$path" ]; then
    printf '%s\n' "$path"
  else
    echo "FAIL: tracked path missing on disk: $path" >&2
    exit 1
  fi
done | LC_ALL=C sort -u >"$manifest"

if [ -f "$REPO_ROOT/docs/VERIFY.md" ]; then
  scan_docs "$REPO_ROOT" "$manifest" publication
else
  scan_docs "$REPO_ROOT" "$manifest" current
  echo "SKIP: documentation budgets and publication wording (docs/VERIFY.md not present; packet B activates them)"
  echo "SKIP: evidence-index completeness (docs/VERIFY.md not present; packet B supplies the final index)"
fi

state_doc='STATE''.md'
if git -C "$REPO_ROOT" ls-files --error-unmatch "$state_doc" >/dev/null 2>&1; then
  if [ -e "$REPO_ROOT/$state_doc" ]; then
    echo "FAIL: $state_doc remains in the working tree" >&2
    exit 1
  fi
  echo "SKIP: $state_doc index removal awaits orchestrator staging"
else
  echo "PASS: $state_doc is untracked"
fi

fixture_manifest="$tmp_dir/fixture-manifest.txt"

write_fixture() {
  local destination=$1
  mkdir -p "$destination/docs/evidence" "$destination/docs/assets" \
    "$destination/tests" "$destination/scripts"
  cat >"$destination/README.md" <<'EOF_README'
# Fixture
![storyboard](docs/assets/storyboard.svg)
![demo](docs/assets/demo.gif)
![lease](docs/assets/demo-lease.gif)
![supply](docs/assets/demo-supplychain.gif)
[Architecture](ARCHITECTURE.md)
[Verification](docs/VERIFY.md)
[Runbooks](docs/RUNBOOKS.md)
[Evidence](docs/evidence/README.md)
[empty]( )
EOF_README
  printf '# Architecture\n' >"$destination/ARCHITECTURE.md"
  printf '# Verify\n' >"$destination/docs/VERIFY.md"
  printf '# Runbooks\n' >"$destination/docs/RUNBOOKS.md"
  printf '# Threat model\n' >"$destination/docs/THREAT_MODEL.md"
  printf '# Tests\n' >"$destination/tests/README.md"
  printf '# Matrix\n' >"$destination/docs/evidence/iam-matrix.md"
  printf '# Schema\n' >"$destination/docs/evidence/iam-simulate-vector-schema.md"
  printf '<svg/>\n' >"$destination/docs/assets/storyboard.svg"
  printf 'gif\n' >"$destination/docs/assets/demo.gif"
  printf 'gif\n' >"$destination/docs/assets/demo-lease.gif"
  printf 'gif\n' >"$destination/docs/assets/demo-supplychain.gif"
  cat >"$destination/docs/evidence/README.md" <<'EOF_INDEX'
# Evidence
[empty]( )
[storyboard](../assets/storyboard.svg)
[demo](<../assets/demo.gif> "demo")
[lease](../assets/demo-lease.gif)
[supply](../assets/demo-supplychain.gif)
[matrix](/docs/evidence/iam-matrix.md)
[schema](./iam-simulate-vector-schema.md)
EOF_INDEX
  printf '#!/usr/bin/env bash\ntrue\n' >"$destination/scripts/check.sh"
  rm -f "$destination/STATE.md"
  find "$destination" -type f -print | sed "s#^$destination/##" | LC_ALL=C sort >"$fixture_manifest"
}

run_mutation() {
  local label=$1 expected=$2 mutation=$3 token=${4:-}
  local root="$tmp_dir/mutation-$label" output rc fail_line
  write_fixture "$root"
  "$mutation" "$root" "$token"
  set +e
  output="$("$SELF" --scan "$root" "$fixture_manifest" publication 2>&1)"
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -eq 0 ] || [ -z "$fail_line" ] || ! grep -Fq "$expected" <<<"$fail_line"; then
    echo "FAIL: docs mutation $label did not fail as required: rc=$rc output=$output" >&2
    exit 1
  fi
  echo "PASS: docs mutation $label -> $fail_line"
  write_fixture "$root"
  "$SELF" --scan "$root" "$fixture_manifest" publication >/dev/null
  echo "PASS: docs mutation $label restored PASS"
}

mutate_budget() {
  local root=$1
  for _ in $(seq 1 80); do printf 'overflow\n'; done >>"$root/README.md"
}
mutate_link() { printf '[broken](missing.md)\n' >>"$1/README.md"; }
mutate_retired() { printf '[retired](RUNBOOKS%s\n' '.md)' >>"$1/README.md"; }
mutate_index() {
  sed '/\.\.\/assets\/demo\.gif/d' "$1/docs/evidence/README.md" \
    >"$1/docs/evidence/README.md.mutant"
  mv "$1/docs/evidence/README.md.mutant" "$1/docs/evidence/README.md"
}
mutate_state_tracked() {
  printf '# State\n' >"$1/STATE.md"
  printf 'STATE.md\n' >>"$fixture_manifest"
}
mutate_readme_embed() {
  sed '/docs\/assets\/demo-lease\.gif/d' "$1/README.md" \
    >"$1/README.md.mutant"
  mv "$1/README.md.mutant" "$1/README.md"
}
mutate_token() { printf '%s\n' "$2" >>"$1/docs/VERIFY.md"; }

run_mutation budget-overrun 'FAIL: documentation budget exceeded: README.md' mutate_budget
run_mutation broken-link 'FAIL: unresolved documentation link in README.md' mutate_link
run_mutation retired-name 'FAIL: retired documentation target in README.md' mutate_retired
run_mutation missing-index-entry 'FAIL: evidence index missing link: docs/assets/demo.gif' mutate_index
run_mutation state-tracked 'FAIL: STATE.md remains in the tracked manifest' mutate_state_tracked
run_mutation readme-embed 'FAIL: README missing required image embed: docs/assets/demo-lease.gif' mutate_readme_embed

token_specs=(
  'free-plan|Free'' Plan'
  'paid-plan|Paid'' Plan'
  'closure-date|2027-''03-02'
  'credit-amount|$''100'
  'decision-phrase|user'' decision'
  'owner-phrase|the owner'' decided'
  'closure-phrase|auto-''close'
)
for spec in "${token_specs[@]}"; do
  label=${spec%%|*}
  token=${spec#*|}
  run_mutation "$label" 'FAIL: forbidden public-scope token in docs/VERIFY.md' \
    mutate_token "$token"
done

echo "PASS: documentation contracts (13 mutations; restored suite passed)"
