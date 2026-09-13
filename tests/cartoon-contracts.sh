#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CARTOON="$REPO_ROOT/scripts/cartoon.py"
EMBLEM="$REPO_ROOT/scripts/emblem.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbit-cartoon.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

replace_once() {
  local path=$1 old=$2 new=$3
  python3 - "$path" "$old" "$new" <<'PY_REPLACE'
from pathlib import Path
import sys

path = Path(sys.argv[1])
old = sys.argv[2]
new = sys.argv[3]
text = path.read_text(encoding="utf-8")
if text.count(old) != 1:
    raise SystemExit(f"replacement anchor count is {text.count(old)}, expected 1: {old}")
path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")
PY_REPLACE
}

inspect_cartoon() {
  python3 - "$1" <<'PY_INSPECT_CARTOON'
from pathlib import Path
import ipaddress
import re
import sys
import xml.etree.ElementTree as ET

path = Path(sys.argv[1])
if path.stat().st_size > 153600:
    raise SystemExit("cartoon exceeds 153600 bytes")

source = path.read_text(encoding="utf-8")
if re.search(r"<!DOCTYPE\b", source, re.IGNORECASE):
    raise SystemExit("cartoon contains a DOCTYPE declaration")
if "transform-box" in source.casefold() or "transform-origin" in source.casefold():
    raise SystemExit("cartoon contains forbidden transform pivot shortcuts")
root = ET.fromstring(source)
ns = "{http://www.w3.org/2000/svg}"


def nodes(name: str):
    return list(root.iter(ns + name))


def fail(message: str) -> None:
    raise SystemExit(message)


if root.tag != ns + "svg":
    fail("cartoon root namespace differs")
for node in root.iter():
    if not isinstance(node.tag, str) or not node.tag.startswith(ns):
        fail("cartoon element is outside the SVG namespace")
    names = (node.tag, *node.attrib)
    for name in names:
        if name.startswith("{") and name.split("}", 1)[0] + "}" != ns:
            fail("cartoon contains an absolute URI outside the root namespace")
if root.attrib.get("role") != "img":
    fail('cartoon root lacks role="img"')
if root.attrib.get("aria-labelledby") != "cartoon-title cartoon-desc":
    fail("cartoon aria-labelledby differs")
if len(nodes("title")) != 1 or nodes("title")[0].attrib.get("id") != "cartoon-title":
    fail("cartoon title contract differs")
if len(nodes("desc")) != 1 or nodes("desc")[0].attrib.get("id") != "cartoon-desc":
    fail("cartoon lacks desc")

ids = [node.attrib["id"] for node in root.iter() if "id" in node.attrib]
if len(ids) != len(set(ids)):
    fail("cartoon contains duplicate ids")
id_set = set(ids)
required_ids = {
    "actor-pip", "actor-orbit", "actor-orbit-ring-pivot", "actor-orbit-ring",
    "actor-scout", "actor-scout-lens", "actor-bill", "actor-bill-needle-pivot",
    "actor-bill-needle", "actor-broombot", "prop-cloud", "prop-leak",
    "prop-server-glow", "prop-wallet", "prop-coins", "prop-gate",
    "prop-gate-lights", "prop-lease-timer", "prop-seal", "prop-rec-reel",
    "prop-permission-row-1", "prop-permission-row-2", "prop-permission-row-3",
    "prop-permission-row-4", "prop-code-card", "prop-doc-card",
    "prop-contract-lamp", "prop-runway", "prop-coin-slot", "prop-velvet-rope",
    "prop-endcard", "wipe-ring", "movie", "reduced-motion-summary",
}
missing_ids = sorted(required_ids - id_set)
if missing_ids:
    fail(f"cartoon lacks required ids: {', '.join(missing_ids)}")
scene_ids = [
    node.attrib["id"]
    for node in nodes("g")
    if node.attrib.get("id", "").startswith("scene-")
]
if scene_ids != ["scene-problem", "scene-guardrails", "scene-proof", "scene-stop"]:
    fail("cartoon scene wrappers differ")

styles = nodes("style")
if len(styles) != 1:
    fail("cartoon must contain exactly one style block")
style = "".join(styles[0].itertext())
if "28s" not in style:
    fail("cartoon style lacks 28s")
reduced_motion = """    @media (prefers-reduced-motion: reduce) {
      #movie { display: none; }
      #reduced-motion-summary { display: inline; }
    }"""
if reduced_motion not in style:
    fail("cartoon reduced-motion block differs")
stop_keyframes = style.split("@keyframes track-scene-stop-opacity {", 1)
if len(stop_keyframes) != 2 or stop_keyframes[1].split("\n    }", 1)[0].count("100.000%") != 1:
    fail("cartoon last scene has duplicate 100% keyframes")
if re.search(r"@import", style, re.IGNORECASE):
    fail("cartoon style contains @import")
if re.search(r"url\s*\(", style, re.IGNORECASE):
    fail("cartoon style contains url(")
if re.search(r"data\s*:", style, re.IGNORECASE):
    fail("cartoon style contains data:")
if re.search(
    r"(?:^|[('\\\"=\s])(?:[A-Za-z][A-Za-z0-9+.-]*):[^\s;)}'\\\"<]",
    style,
):
    fail("cartoon style contains a scheme-prefixed reference")
for referenced in re.findall(r"(?m)(?:^|,)\s*#([A-Za-z_][\w.-]*)\s*\{", style):
    if referenced not in id_set:
        fail(f"cartoon style references missing id: {referenced}")
for animated in re.findall(r"(?m)^\s*#([A-Za-z_][\w.-]*)\s*\{\s*animation:", style):
    node = next(node for node in root.iter() if node.attrib.get("id") == animated)
    if node.tag != ns + "g":
        fail(f"cartoon animation target is not a group: {animated}")

for forbidden in ("script", "foreignObject", "image"):
    if nodes(forbidden):
        fail(f"cartoon contains forbidden element: {forbidden}")
for node in root.iter():
    for raw_name, value in node.attrib.items():
        name = raw_name.rsplit("}", 1)[-1]
        if name.lower().startswith("on"):
            fail(f"cartoon contains event attribute: {name}")
        if name == "href":
            if not value.startswith("#"):
                fail("cartoon href must start with #")
            if value[1:] not in id_set:
                fail(f"cartoon href target is missing: {value[1:]}")
text_items = ["".join(node.itertext()) for node in nodes("text")]
if text_items != ["REC", "PROVED. STOPPED ON PURPOSE."]:
    fail("cartoon visible text items differ")

values = []
for node in root.iter():
    values.extend(node.attrib.values())
    if node.text:
        values.append(node.text)
    if node.tail:
        values.append(node.tail)
payload = "\n".join(values)
for match in re.findall(r"(?<!\d)\d{12}(?!\d)", payload):
    if match != "000000000000":
        fail("cartoon contains a forbidden 12-digit number")
if "/Users/" in payload or "/home/" in payload:
    fail("cartoon contains a personal path")
for match in re.findall(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])", payload):
    try:
        address = ipaddress.ip_address(match)
    except ValueError:
        fail(f"cartoon contains malformed IPv4 address: {match}")
    if address not in ipaddress.ip_network("203.0.113.0/24"):
        fail(f"cartoon contains non-TEST-NET-3 IPv4 address: {match}")
absolute = re.compile(r"\b[A-Za-z][A-Za-z0-9+.-]*://[^\s<>'\\\"]+")
for value in values:
    if absolute.search(value):
        fail("cartoon contains an absolute URI outside the root namespace")
PY_INSPECT_CARTOON
}

inspect_transcript() {
  python3 - "$1" <<'PY_TRANSCRIPT'
from pathlib import Path
import sys

expected = """# Orbit-infra cartoon transcript

- **0-6 s, The problem.** Putting an app on the cloud is easy; doing it so nothing leaks, nothing is left running and billing you, and every step can be checked by a stranger is hard.
- **6-14 s, Guardrails.** The project takes a friend's app, builds the cloud plumbing around it, and wraps every action in rules: changes must pass gates before they merge, every environment has a lease that expires and cleans itself up, and only signed images can run.
- **14-21 s, Proof.** Instead of trusting a demo, the repo records evidence: terminal recordings, a permission-by-permission test against AWS's own policy simulator, and checks that fail if the docs drift from the code.
- **21-28 s, Stop.** The whole system is shown working on a local emulator and the permissions are proven on the real account; the live deployment tail was deliberately not paid for, because the cost is real and the audience is small.

End card: `PROVED. STOPPED ON PURPOSE.`

Generated by `scripts/cartoon.py`.
"""
actual = Path(sys.argv[1]).read_text(encoding="utf-8")
if actual != expected:
    raise SystemExit("cartoon transcript differs")
PY_TRANSCRIPT
}

inspect_emblem() {
  python3 - "$1" <<'PY_INSPECT_EMBLEM'
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

path = Path(sys.argv[1])
if path.stat().st_size > 20480:
    raise SystemExit("emblem exceeds 20480 bytes")
source = path.read_text(encoding="utf-8")
if re.search(r"<!DOCTYPE\b", source, re.IGNORECASE):
    raise SystemExit("emblem contains a DOCTYPE declaration")
if "transform-box" in source.casefold() or "transform-origin" in source.casefold():
    raise SystemExit("emblem contains forbidden transform pivot shortcuts")
root = ET.fromstring(source)
ns = "{http://www.w3.org/2000/svg}"
nodes = list(root.iter())
if root.tag != ns + "svg":
    raise SystemExit("emblem root namespace differs")
for node in nodes:
    if not isinstance(node.tag, str) or not node.tag.startswith(ns):
        raise SystemExit("emblem element is outside the SVG namespace")
    names = (node.tag, *node.attrib)
    for name in names:
        if name.startswith("{") and name.split("}", 1)[0] + "}" != ns:
            raise SystemExit("emblem contains an absolute URI outside the root namespace")
if root.attrib.get("role") != "img":
    raise SystemExit('emblem root lacks role="img"')
if root.attrib.get("aria-labelledby") != "emblem-title emblem-desc":
    raise SystemExit("emblem aria-labelledby differs")
if len(list(root.iter(ns + "title"))) != 1:
    raise SystemExit("emblem lacks title")
if len(list(root.iter(ns + "desc"))) != 1:
    raise SystemExit("emblem lacks desc")
styles = list(root.iter(ns + "style"))
if len(styles) != 1:
    raise SystemExit("emblem style block differs")
style = "".join(styles[0].itertext())
reduced_motion = """    @media (prefers-reduced-motion: reduce) {
      #emblem-orbit-ring, #emblem-shield { animation: none; }
    }"""
if reduced_motion not in style:
    raise SystemExit("emblem reduced-motion block differs")
if re.search(r"@import|url\s*\(|data\s*:", style, re.IGNORECASE):
    raise SystemExit("emblem style contains an external reference")
for forbidden in ("script", "foreignObject", "image"):
    if list(root.iter(ns + forbidden)):
        raise SystemExit(f"emblem contains forbidden element: {forbidden}")
ids = [node.attrib["id"] for node in nodes if "id" in node.attrib]
id_set = set(ids)
keyframes = set(re.findall(r"@keyframes\s+([A-Za-z_][\w.-]*)", style))
animation_targets = set()
active_targets = set()
for rule in re.finditer(r"([^{}]+)\{([^{}]*)\}", style):
    declarations = {}
    for declaration in rule.group(2).split(";"):
        if ":" in declaration:
            name, value = declaration.split(":", 1)
            declarations[name.strip().casefold()] = value.strip()
    if "animation" not in declarations:
        continue
    targets = re.findall(r"#([A-Za-z_][\w.-]*)", rule.group(1))
    if not targets:
        raise SystemExit("emblem animation selector lacks an id target")
    for target in targets:
        if ids.count(target) != 1:
            raise SystemExit(f"emblem animation target count differs: {target}")
        animation_targets.add(target)
    animation = declarations["animation"]
    if animation.casefold() == "none":
        continue
    names = keyframes.intersection(re.findall(r"[A-Za-z_][\w.-]*", animation))
    if len(names) != 1:
        raise SystemExit("emblem animation keyframes differ")
    if not re.search(r"(?<![\w.])6s(?![\w.])", animation):
        raise SystemExit("emblem style lacks 6s")
    active_targets.update(targets)
if animation_targets != active_targets:
    missing = sorted(animation_targets - active_targets)[0]
    raise SystemExit(f"emblem animation target lacks keyframes: {missing}")
parents = {child: parent for parent in nodes for child in parent}
ring = next(node for node in nodes if node.attrib.get("id") == "emblem-orbit-ring")
pivot = parents[ring]
if pivot.tag != ns + "g" or pivot.attrib.get("id") != "emblem-orbit-pivot":
    raise SystemExit("emblem orbit ring parent is not its pivot group")
if pivot.attrib.get("transform") != "translate(80 80)":
    raise SystemExit("emblem orbit pivot transform differs")
values = []
for node in nodes:
    values.extend(node.attrib.values())
    if node.text:
        values.append(node.text)
    if node.tail:
        values.append(node.tail)
    for raw_name, value in node.attrib.items():
        name = raw_name.rsplit("}", 1)[-1]
        if name.lower().startswith("on"):
            raise SystemExit(f"emblem contains event attribute: {name}")
        if name == "href":
            if not value.startswith("#"):
                raise SystemExit("emblem href must start with #")
            if value[1:] not in id_set:
                raise SystemExit(f"emblem href target is missing: {value[1:]}")
payload = "\n".join(values)
if re.search(r"(?<!\d)(?!000000000000)\d{12}(?!\d)", payload):
    raise SystemExit("emblem contains a forbidden 12-digit number")
if "/Users/" in payload or "/home/" in payload:
    raise SystemExit("emblem contains a personal path")
if re.search(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])", payload):
    raise SystemExit("emblem contains an IPv4 address")
if any(re.search(r"\b[A-Za-z][A-Za-z0-9+.-]*://", value) for value in values):
    raise SystemExit("emblem contains an absolute URI outside the root namespace")
PY_INSPECT_EMBLEM
}

style_value() {
  python3 - "$1" "$2" "$3" <<'PY_STYLE_VALUE'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
target_id = sys.argv[2]
property_name = sys.argv[3]
for node in root.iter():
    if node.attrib.get("id") != target_id:
        continue
    declarations = {}
    for declaration in node.attrib.get("style", "").split(";"):
        if ":" in declaration:
            name, value = declaration.split(":", 1)
            declarations[name.strip()] = value.strip()
    if property_name not in declarations:
        raise SystemExit(f"{target_id} lacks inline {property_name}")
    print(declarations[property_name])
    break
else:
    raise SystemExit(f"missing snapshot id: {target_id}")
PY_STYLE_VALUE
}

assert_snapshot_scene() {
  local svg=$1 visible=$2 marker=$3
  python3 - "$svg" "$visible" "$marker" <<'PY_SNAPSHOT'
import re
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
visible = "scene-" + sys.argv[2]
marker = sys.argv[3]
scenes = ("scene-problem", "scene-guardrails", "scene-proof", "scene-stop")


def declarations(source):
    values = {}
    for declaration in source.split(";"):
        if ":" in declaration:
            name, value = declaration.split(":", 1)
            values[name.strip().casefold()] = value.strip()
    return values


def style(node):
    return declarations(node.attrib.get("style", ""))


def reject_hidden(node, label):
    inline = style(node)
    for prop, hidden in (("display", "none"), ("visibility", "hidden")):
        attribute = node.attrib.get(prop, "").strip().casefold()
        inline_value = inline.get(prop, "").casefold()
        if attribute == hidden or inline_value == hidden:
            raise SystemExit(f"{label} has {prop}={hidden}")


by_id = {node.attrib["id"]: node for node in root.iter() if "id" in node.attrib}
for scene in scenes:
    want = "1.000" if scene == visible else "0.000"
    actual = style(by_id[scene]).get("opacity")
    if actual != want:
        raise SystemExit(f"{scene} opacity is {actual}, expected {want}")
    reject_hidden(by_id[scene], scene)
for node in list(by_id[visible].iter())[1:]:
    label = node.attrib.get("id", node.tag.rsplit("}", 1)[-1])
    reject_hidden(node, label)
if marker not in {node.attrib.get("id") for node in by_id[visible].iter()}:
    raise SystemExit(f"{marker} is not a descendant of {visible}")
smil = {"animate", "animateTransform", "animateMotion", "set"}
if any(node.tag.rsplit("}", 1)[-1] in smil for node in root.iter()):
    raise SystemExit("snapshot contains SMIL animation")
styles = list(root.iter("{http://www.w3.org/2000/svg}style"))
for style_node in styles:
    css = "".join(style_node.itertext())
    if "animation:" in css:
        raise SystemExit("snapshot retains style animation")
    for selectors, body in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
        properties = declarations(body)
        if not ({"display", "visibility"} & properties.keys()):
            continue
        scene_targets = re.findall(r"#(scene-[A-Za-z_][\w.-]*)", selectors)
        if scene_targets:
            raise SystemExit(
                f"snapshot CSS hides scene target: {scene_targets[0]}"
            )
PY_SNAPSHOT
}

assert_boundary_files() {
  local before_svg=$1 after_svg=$2 before=$3 after=$4 old_scene=$5 new_scene=$6
  [ "$(style_value "$before_svg" "scene-$old_scene" opacity)" = "1.000" ] || \
    fail "scene-$old_scene is not visible at $before"
  [ "$(style_value "$before_svg" "scene-$new_scene" opacity)" = "0.000" ] || \
    fail "scene-$new_scene is visible too early at $before"
  [ "$(style_value "$after_svg" "scene-$old_scene" opacity)" = "0.000" ] || \
    fail "scene-$old_scene remains visible at $after"
  [ "$(style_value "$after_svg" "scene-$new_scene" opacity)" = "1.000" ] || \
    fail "scene-$new_scene is not visible at $after"
}

assert_boundary() {
  local before=$1 after=$2 old_scene=$3 new_scene=$4
  local before_svg="$tmp_dir/boundary-${before}.svg"
  local after_svg="$tmp_dir/boundary-${after}.svg"
  run_cartoon --snapshot "$before" --output "$before_svg"
  run_cartoon --snapshot "$after" --output "$after_svg"
  assert_boundary_files \
    "$before_svg" "$after_svg" "$before" "$after" "$old_scene" "$new_scene"
}

inspect_provenance_metadata() {
  python3 - "$1" "$2" "$3" <<'PY_PROVENANCE_METADATA'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
expected_scene_count = sys.argv[2]
expected_cycle_seconds = sys.argv[3]
expected_fields = {
    "generator commit",
    "cartoon sha256",
    "transcript sha256",
    "emblem sha256",
    "scene count",
    "cycle seconds",
    "command",
}
lines = path.read_text(encoding="utf-8").splitlines()
try:
    divider = lines.index("| --- | --- |")
except ValueError:
    raise SystemExit("cartoon provenance table header differs")
table = lines[divider + 1:]
if len(table) != 7:
    raise SystemExit(f"cartoon provenance row count differs: {len(table)} != 7")
rows = []
for line in table:
    match = re.fullmatch(r"\| ([^|]+) \| ([^|]+) \|", line)
    if match is None:
        raise SystemExit("cartoon provenance row format differs")
    rows.append(match.groups())
fields = [field for field, _value in rows]
if len(fields) != len(set(fields)):
    raise SystemExit("cartoon provenance fields are not unique")
if set(fields) != expected_fields:
    raise SystemExit("cartoon provenance fields differ")
values = dict(rows)
if values["scene count"] != expected_scene_count:
    raise SystemExit("cartoon provenance scene count differs")
if values["cycle seconds"] != expected_cycle_seconds:
    raise SystemExit("cartoon provenance cycle seconds differs")
if values["command"] != "python3 scripts/cartoon.py --provenance":
    raise SystemExit("cartoon provenance command differs")
PY_PROVENANCE_METADATA
}

check_asset_group() {
  local root=$1
  local files=(
    docs/assets/orbit-cartoon.svg
    docs/assets/emblem.svg
    docs/assets/CARTOON_TRANSCRIPT.md
    docs/assets/CARTOON_PROVENANCE.md
  )
  local present=0 path provenance recorded actual commit scenes scene_count cycle_seconds
  for path in "${files[@]}"; do
    [ -f "$root/$path" ] && present=$((present + 1))
  done
  if [ "$present" -eq 0 ]; then
    echo "SKIP: cartoon assets absent (source-only; not a publication pass)"
    asset_group_ran=0
    return 0
  fi
  asset_group_ran=1
  [ "$present" -eq "${#files[@]}" ] || \
    fail "cartoon assets must all exist or all be absent"

  provenance="$root/docs/assets/CARTOON_PROVENANCE.md"
  scenes="$(cd "$root" && python3 scripts/cartoon.py --scenes)" || return 1
  scene_count="$(awk 'NF { count++ } END { print count + 0 }' <<<"$scenes")"
  cycle_seconds="$(awk 'NF { last = $3 } END { print last }' <<<"$scenes")"
  [ "$cycle_seconds" = 28 ] || fail "cartoon --scenes cycle seconds differs"
  inspect_provenance_metadata \
    "$provenance" "$scene_count" "$cycle_seconds" || return 1
  commit="$(sed -n 's/^| generator commit | \([0-9a-f]\{7,40\}\) |$/\1/p' "$provenance")"
  [ -n "$commit" ] || fail "cartoon provenance lacks generator commit row"
  git -C "$root" cat-file -e "$commit^{commit}" 2>/dev/null || \
    fail "cartoon generator commit is unreachable"
  git -C "$root" merge-base --is-ancestor "$commit" HEAD || \
    fail "cartoon generator commit is not an ancestor of HEAD"
  for path in scripts/cartoon.py scripts/emblem.py; do
    git -C "$root" ls-tree -r --name-only "$commit" -- "$path" | \
      grep -Fxq "$path" || fail "cartoon generator commit lacks $path"
  done
  git -C "$root" diff --quiet "$commit" -- \
    scripts/cartoon.py scripts/emblem.py || \
    fail "cartoon generator closure drift; regenerate the cartoon assets"
  (cd "$root" && python3 scripts/cartoon.py --check) || return 1
  (cd "$root" && python3 scripts/emblem.py --check) || return 1
  for spec in \
    "cartoon sha256|docs/assets/orbit-cartoon.svg" \
    "transcript sha256|docs/assets/CARTOON_TRANSCRIPT.md" \
    "emblem sha256|docs/assets/emblem.svg"; do
    recorded="$(sed -n "s/^| ${spec%%|*} | \\([0-9a-f]\\{64\\}\\) |$/\\1/p" "$provenance")"
    [ -n "$recorded" ] || fail "cartoon provenance lacks ${spec%%|*} row"
    actual="$(shasum -a 256 "$root/${spec#*|}" | awk '{print $1}')"
    [ "$recorded" = "$actual" ] || fail "cartoon provenance ${spec%%|*} differs"
  done
  grep -Fq '](docs/assets/orbit-cartoon.svg)' "$root/README.md" || \
    fail "README lacks the cartoon link"
  grep -Fq 'src="docs/assets/emblem.svg"' "$root/README.md" || \
    fail "README lacks the emblem image"
  for path in "${files[@]}"; do
    grep -Fq "../${path#docs/}" "$root/docs/evidence/README.md" || \
      fail "evidence index lacks $path"
  done
}

new_mutant_root() {
  local label=$1 root
  root="$tmp_dir/mutant-$label"
  mkdir -p "$root/scripts"
  cp "$CARTOON" "$root/scripts/cartoon.py"
  cp "$EMBLEM" "$root/scripts/emblem.py"
  printf '%s\n' "$root"
}

run_source_failure() {
  local label=$1 expected=$2 old=$3 new=$4
  local root output rc=0
  root="$(new_mutant_root "$label")"
  replace_once "$root/scripts/cartoon.py" "$old" "$new"
  output="$(cd "$root" && python3 scripts/cartoon.py \
    --output "$root/cartoon.svg" --transcript-output "$root/transcript.md" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "cartoon mutation $label survived"
  grep -Fq "$expected" <<<"$output" || \
    fail "cartoon mutation $label missed expected failure: $output"
  cp "$CARTOON" "$root/scripts/cartoon.py"
  (cd "$root" && python3 scripts/cartoon.py \
    --output "$root/cartoon.svg" --transcript-output "$root/transcript.md")
  mutation_count=$((mutation_count + 1))
}

run_file_failure() {
  local label=$1 expected=$2 mutation=$3
  local path="$tmp_dir/file-$label.svg" output rc=0
  cp "$tmp_dir/cartoon-first.svg" "$path"
  "$mutation" "$path"
  output="$(inspect_cartoon "$path" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "cartoon mutation $label survived"
  grep -Fq "$expected" <<<"$output" || \
    fail "cartoon mutation $label missed expected failure: $output"
  cp "$tmp_dir/cartoon-first.svg" "$path"
  inspect_cartoon "$path"
  mutation_count=$((mutation_count + 1))
}

run_emblem_file_failure() {
  local label=$1 expected=$2 mutation=$3
  local path="$tmp_dir/emblem-file-$label.svg" output rc=0
  cp "$tmp_dir/emblem-first.svg" "$path"
  "$mutation" "$path"
  output="$(inspect_emblem "$path" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "emblem mutation $label survived"
  grep -Fq "$expected" <<<"$output" || \
    fail "emblem mutation $label missed expected failure: $output"
  cp "$tmp_dir/emblem-first.svg" "$path"
  inspect_emblem "$path"
  mutation_count=$((mutation_count + 1))
}

mutate_drop_motion() {
  replace_once "$1" \
    $'    @media (prefers-reduced-motion: reduce) {\n      #movie { display: none; }\n      #reduced-motion-summary { display: inline; }\n    }\n' ""
}
mutate_inverted_motion() {
  replace_once "$1" \
    $'      #movie { display: none; }\n      #reduced-motion-summary { display: inline; }' \
    $'      #movie { display: inline; }\n      #reduced-motion-summary { display: none; }'
}

mutate_drop_desc() {
  python3 - "$1" <<'PY_DROP_DESC'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text, count = re.subn(r"  <desc id=\"cartoon-desc\">.*?</desc>\n", "", path.read_text(encoding="utf-8"), count=1)
if count != 1:
    raise SystemExit("desc mutation anchor differs")
path.write_text(text, encoding="utf-8", newline="\n")
PY_DROP_DESC
}

mutate_script() { replace_once "$1" "</svg>" "  <script>x</script>\n</svg>"; }
mutate_external_href() {
  replace_once "$1" "</svg>" '  <use href="http://203.0.113.9/x"/>\n</svg>'
}
mutate_relative_href() {
  replace_once "$1" "</svg>" '  <use href="evil.svg#x"/>\n</svg>'
}
mutate_dangling_href() {
  replace_once "$1" 'href="#actor-bill"' 'href="#no-such-id"'
}
mutate_doctype() {
  replace_once "$1" '<?xml version="1.0" encoding="UTF-8"?>' \
    $'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE svg>'
}
mutate_foreign_namespace_element() {
  replace_once "$1" "</svg>" $'  <g xmlns="urn:foreign"/>\n</svg>'
}
mutate_drop_aria_labelledby() {
  replace_once "$1" \
    ' role="img" aria-labelledby="cartoon-title cartoon-desc"' ' role="img"'
}
mutate_missing_style_id() {
  replace_once "$1" "  </style>" $'    #no-such-id { fill: #fff; }\n  </style>'
}
mutate_style_url() {
  replace_once "$1" "  </style>" $'    #movie { fill: url(#x); }\n  </style>'
}
mutate_emblem_drop_motion() {
  replace_once "$1" \
    $'    @media (prefers-reduced-motion: reduce) {\n      #emblem-orbit-ring, #emblem-shield { animation: none; }\n    }\n' ""
}
mutate_inline_transform_origin() {
  replace_once "$1" '<g id="emblem-shield">' \
    '<g id="emblem-shield" style="TrAnSfOrM-OrIgIn: center">'
}
mutate_emblem_renamed_target() {
  replace_once "$1" '<g id="emblem-orbit-ring">' \
    '<g id="emblem-orbit-ring-renamed">'
}
mutate_emblem_wrong_pivot() {
  replace_once "$1" \
    '<g id="emblem-orbit-pivot" transform="translate(80 80)">' \
    '<g id="emblem-orbit-pivot" transform="translate(0 0)">'
}
mutate_emblem_duration() {
  python3 - "$1" <<'PY_EMBLEM_DURATION'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if text.count(" 6s linear infinite;") != 2:
    raise SystemExit("emblem duration mutation anchor differs")
path.write_text(
    text.replace(" 6s linear infinite;", " 5s linear infinite;"),
    encoding="utf-8",
    newline="\n",
)
PY_EMBLEM_DURATION
}
mutate_oversize() {
  python3 - "$1" <<'PY_OVERSIZE'
from pathlib import Path
import sys

path = Path(sys.argv[1])
with path.open("a", encoding="utf-8", newline="\n") as handle:
    handle.write(" " * 153601)
PY_OVERSIZE
}

[ -f "$CARTOON" ] || fail "scripts/cartoon.py is required"
[ -f "$EMBLEM" ] || fail "scripts/emblem.py is required"

source_root="$tmp_dir/source-root"
mkdir -p "$source_root/scripts"
cp "$CARTOON" "$source_root/scripts/cartoon.py"
cp "$EMBLEM" "$source_root/scripts/emblem.py"
run_cartoon() { (cd "$source_root" && python3 scripts/cartoon.py "$@"); }
run_emblem() { (cd "$source_root" && python3 scripts/emblem.py "$@"); }

expect_arg_failure() {
  local label=$1 expected=$2 output rc=0
  shift 2
  output="$(run_cartoon "$@" 2>&1)" || rc=$?
  [ "$rc" -eq 2 ] || fail "$label returned $rc instead of parser status 2: $output"
  grep -Fq -- "$expected" <<<"$output" || \
    fail "$label missed parser failure '$expected': $output"
}

run_cartoon --output "$tmp_dir/cartoon-first.svg" \
  --transcript-output "$tmp_dir/transcript-first.md"
run_cartoon --output "$tmp_dir/cartoon-second.svg" \
  --transcript-output "$tmp_dir/transcript-second.md"
run_emblem --output "$tmp_dir/emblem-first.svg"
run_emblem --output "$tmp_dir/emblem-second.svg"
cmp -s "$tmp_dir/cartoon-first.svg" "$tmp_dir/cartoon-second.svg" || \
  fail "two cartoon renders differ"
cmp -s "$tmp_dir/transcript-first.md" "$tmp_dir/transcript-second.md" || \
  fail "two transcript renders differ"
cmp -s "$tmp_dir/emblem-first.svg" "$tmp_dir/emblem-second.svg" || \
  fail "two emblem renders differ"
inspect_cartoon "$tmp_dir/cartoon-first.svg"
inspect_transcript "$tmp_dir/transcript-first.md"
inspect_emblem "$tmp_dir/emblem-first.svg"

expected_scenes=$'problem 0 6\nguardrails 6 14\nproof 14 21\nstop 21 28'
actual_scenes="$(run_cartoon --scenes)"
[ "$actual_scenes" = "$expected_scenes" ] || \
  fail "cartoon --scenes output differs: $actual_scenes"
expect_arg_failure check-output '--check cannot be combined with output options' \
  --check --output "$tmp_dir/check.svg"
expect_arg_failure check-transcript '--check cannot be combined with output options' \
  --check --transcript-output "$tmp_dir/check.md"
expect_arg_failure check-provenance-output '--check cannot be combined with output options' \
  --check --provenance-output "$tmp_dir/check-provenance.md"
expect_arg_failure scenes-output '--scenes cannot be combined with output options' \
  --scenes --output "$tmp_dir/scenes.svg"
expect_arg_failure scenes-transcript '--scenes cannot be combined with output options' \
  --scenes --transcript-output "$tmp_dir/scenes.md"
expect_arg_failure scenes-provenance-output '--scenes cannot be combined with output options' \
  --scenes --provenance-output "$tmp_dir/scenes-provenance.md"
expect_arg_failure provenance-output '--provenance cannot be combined with cartoon outputs' \
  --provenance --output "$tmp_dir/provenance.svg"
expect_arg_failure provenance-transcript '--provenance cannot be combined with cartoon outputs' \
  --provenance --transcript-output "$tmp_dir/provenance.md"
expect_arg_failure snapshot-transcript '--snapshot cannot be combined with --transcript-output' \
  --snapshot 2 --output "$tmp_dir/snapshot-output.svg" \
  --transcript-output "$tmp_dir/snapshot-transcript.md"
expect_arg_failure provenance-output-without-provenance \
  '--provenance-output requires --provenance' \
  --provenance-output "$tmp_dir/orphan-provenance.md"
expect_arg_failure snapshot-provenance-output \
  '--provenance-output requires --provenance' \
  --snapshot 2 --output "$tmp_dir/snapshot-provenance.svg" \
  --provenance-output "$tmp_dir/snapshot-provenance.md"

snapshot_specs=(
  '2|problem|prop-leak'
  '10|guardrails|prop-seal'
  '17|proof|prop-contract-lamp'
  '24|stop|prop-velvet-rope'
)
for spec in "${snapshot_specs[@]}"; do
  IFS='|' read -r second scene marker <<<"$spec"
  snapshot="$tmp_dir/snapshot-$second.svg"
  run_cartoon --snapshot "$second" --output "$snapshot"
  assert_snapshot_scene "$snapshot" "$scene" "$marker"
done
exact_snapshot_specs=(
  '0|problem|prop-leak'
  '6|guardrails|prop-seal'
  '14|proof|prop-contract-lamp'
  '21|stop|prop-velvet-rope'
)
for spec in "${exact_snapshot_specs[@]}"; do
  IFS='|' read -r second scene marker <<<"$spec"
  snapshot="$tmp_dir/snapshot-exact-$second.svg"
  run_cartoon --snapshot "$second" --output "$snapshot"
  assert_snapshot_scene "$snapshot" "$scene" "$marker"
done
assert_boundary 5.9 6.1 problem guardrails
assert_boundary 13.9 14.1 guardrails proof
assert_boundary 20.9 21.1 proof stop
assert_boundary 27.9 0.1 stop problem

partial_root="$tmp_dir/partial-root"
mkdir -p "$partial_root/docs/assets"
cp "$tmp_dir/cartoon-first.svg" "$partial_root/docs/assets/orbit-cartoon.svg"
partial_rc=0
partial_output="$(check_asset_group "$partial_root" 2>&1)" || partial_rc=$?
[ "$partial_rc" -ne 0 ] || fail "partial cartoon asset set passed"
grep -Fq 'cartoon assets must all exist or all be absent' <<<"$partial_output" || \
  fail "partial cartoon asset set missed the pairing failure: $partial_output"

mutation_count=0
expected_mutations=30
run_source_failure delete-scene 'scene ids must be problem, guardrails, proof, stop' \
  '    ("problem", 0, 6, "The problem", PROBLEM_SUMMARY),' ''
run_source_failure shift-boundary 'scene guardrails must begin at 6' \
  '("guardrails", 6, 14,' '("guardrails", 7, 14,'

track_root="$(new_mutant_root proof-track)"
replace_once "$track_root/scripts/cartoon.py" \
  'visible_start = float(start)' \
  'visible_start = 10.0 if scene_id == "proof" else float(start)'
(cd "$track_root" && python3 scripts/cartoon.py --snapshot 13.9 \
  --output "$track_root/proof-track.svg")
track_rc=0
track_output="$(assert_snapshot_scene "$track_root/proof-track.svg" \
  guardrails prop-seal 2>&1)" || track_rc=$?
[ "$track_rc" -ne 0 ] || fail "cartoon mutation proof-track survived"
grep -Fq 'scene-proof opacity' <<<"$track_output" || \
  fail "cartoon mutation proof-track missed expected failure: $track_output"
cp "$CARTOON" "$track_root/scripts/cartoon.py"
(cd "$track_root" && python3 scripts/cartoon.py --snapshot 13.9 \
  --output "$track_root/proof-track.svg")
assert_snapshot_scene "$track_root/proof-track.svg" guardrails prop-seal
mutation_count=$((mutation_count + 1))

blank_root="$(new_mutant_root blank-boundary)"
replace_once "$blank_root/scripts/cartoon.py" \
  '(visible_start, 1.0),' '(visible_start + .001, 1.0),'
(cd "$blank_root" && python3 scripts/cartoon.py --snapshot 6 \
  --output "$blank_root/blank-boundary.svg")
blank_rc=0
blank_output="$(assert_snapshot_scene "$blank_root/blank-boundary.svg" \
  guardrails prop-seal 2>&1)" || blank_rc=$?
[ "$blank_rc" -ne 0 ] || fail "cartoon mutation blank-boundary survived"
grep -Fq 'scene-guardrails opacity is 0.000, expected 1.000' \
  <<<"$blank_output" || \
  fail "cartoon mutation blank-boundary missed expected failure: $blank_output"
cp "$CARTOON" "$blank_root/scripts/cartoon.py"
(cd "$blank_root" && python3 scripts/cartoon.py --snapshot 6 \
  --output "$blank_root/blank-boundary.svg")
assert_snapshot_scene "$blank_root/blank-boundary.svg" guardrails prop-seal
mutation_count=$((mutation_count + 1))

boundary_before="$tmp_dir/boundary-mutant-before.svg"
boundary_after="$tmp_dir/boundary-mutant-after.svg"
run_cartoon --snapshot 5.9 --output "$boundary_before"
run_cartoon --snapshot 6.1 --output "$boundary_after"
replace_once "$boundary_after" \
  'id="scene-problem" style="opacity: 0.000;"' \
  'id="scene-problem" style="opacity: 1.000;"'
boundary_rc=0
boundary_output="$(assert_boundary_files \
  "$boundary_before" "$boundary_after" 5.9 6.1 problem guardrails 2>&1)" || \
  boundary_rc=$?
[ "$boundary_rc" -ne 0 ] || fail "cartoon mutation boundary-transition survived"
grep -Fq 'scene-problem remains visible at 6.1' <<<"$boundary_output" || \
  fail "cartoon mutation boundary-transition missed expected failure: $boundary_output"
run_cartoon --snapshot 6.1 --output "$boundary_after"
assert_boundary_files \
  "$boundary_before" "$boundary_after" 5.9 6.1 problem guardrails
mutation_count=$((mutation_count + 1))

hidden_scene="$tmp_dir/hidden-scene.svg"
cp "$boundary_after" "$hidden_scene"
replace_once "$hidden_scene" \
  '<g id="scene-guardrails" style="opacity: 1.000;">' \
  '<g id="scene-guardrails" display="none" style="opacity: 1.000;">'
hidden_scene_rc=0
hidden_scene_output="$(assert_snapshot_scene "$hidden_scene" \
  guardrails prop-seal 2>&1)" || hidden_scene_rc=$?
[ "$hidden_scene_rc" -ne 0 ] || fail "cartoon mutation hidden-scene survived"
grep -Fq 'scene-guardrails has display=none' <<<"$hidden_scene_output" || \
  fail "cartoon mutation hidden-scene missed expected failure: $hidden_scene_output"
cp "$boundary_after" "$hidden_scene"
assert_snapshot_scene "$hidden_scene" guardrails prop-seal
mutation_count=$((mutation_count + 1))

run_source_failure cycle-duration 'scene stop must end at 27' \
  'CYCLE_SECONDS = 28' 'CYCLE_SECONDS = 27'
run_file_failure reduced-motion 'cartoon reduced-motion block differs' mutate_drop_motion
run_file_failure inverted-reduced-motion 'cartoon reduced-motion block differs' \
  mutate_inverted_motion
run_file_failure missing-desc 'cartoon lacks desc' mutate_drop_desc
run_file_failure script-element 'cartoon contains forbidden element: script' mutate_script
run_file_failure external-href 'cartoon href must start with #' mutate_external_href
run_file_failure relative-href 'cartoon href must start with #' mutate_relative_href
run_file_failure dangling-href 'cartoon href target is missing: no-such-id' \
  mutate_dangling_href
run_file_failure doctype 'cartoon contains a DOCTYPE declaration' mutate_doctype
run_file_failure foreign-namespace-element \
  'cartoon element is outside the SVG namespace' mutate_foreign_namespace_element
run_file_failure missing-aria-labelledby 'cartoon aria-labelledby differs' \
  mutate_drop_aria_labelledby
run_file_failure missing-style-id 'cartoon style references missing id: no-such-id' \
  mutate_missing_style_id
run_file_failure style-url 'cartoon style contains url(' mutate_style_url
run_file_failure oversize 'cartoon exceeds 153600 bytes' mutate_oversize
run_emblem_file_failure emblem-reduced-motion \
  'emblem reduced-motion block differs' mutate_emblem_drop_motion
run_emblem_file_failure emblem-duration 'emblem style lacks 6s' \
  mutate_emblem_duration
run_emblem_file_failure emblem-renamed-target \
  'emblem animation target count differs: emblem-orbit-ring' \
  mutate_emblem_renamed_target
run_emblem_file_failure emblem-wrong-pivot \
  'emblem orbit pivot transform differs' mutate_emblem_wrong_pivot
run_emblem_file_failure inline-transform-origin \
  'emblem contains forbidden transform pivot shortcuts' \
  mutate_inline_transform_origin

tamper_root="$tmp_dir/tamper-root"
mkdir -p "$tamper_root/scripts"
cp "$CARTOON" "$tamper_root/scripts/cartoon.py"
cp "$EMBLEM" "$tamper_root/scripts/emblem.py"
git -C "$tamper_root" init -q
git -C "$tamper_root" add scripts/cartoon.py scripts/emblem.py
git -C "$tamper_root" -c user.name=t -c user.email=t@localhost \
  commit -q -m fixture
(cd "$tamper_root" && python3 scripts/cartoon.py >/dev/null)
(cd "$tamper_root" && python3 scripts/emblem.py >/dev/null)
(cd "$tamper_root" && python3 scripts/cartoon.py --provenance >/dev/null)
mkdir -p "$tamper_root/docs/evidence"
cat >"$tamper_root/README.md" <<'EOF_TAMPER_README'
[cartoon](docs/assets/orbit-cartoon.svg)
<img src="docs/assets/emblem.svg" alt="emblem">
EOF_TAMPER_README
cat >"$tamper_root/docs/evidence/README.md" <<'EOF_TAMPER_INDEX'
[cartoon](../assets/orbit-cartoon.svg)
[emblem](../assets/emblem.svg)
[transcript](../assets/CARTOON_TRANSCRIPT.md)
[provenance](../assets/CARTOON_PROVENANCE.md)
EOF_TAMPER_INDEX
printf '%s\n' '<!-- tampered -->' >>"$tamper_root/docs/assets/orbit-cartoon.svg"
tamper_rc=0
tamper_output="$(check_asset_group "$tamper_root" 2>&1)" || tamper_rc=$?
[ "$tamper_rc" -ne 0 ] || fail "cartoon mutation tampered-asset survived"
grep -Fq 'cartoon: regenerate the cartoon' <<<"$tamper_output" || \
  fail "cartoon mutation tampered-asset missed byte validation: $tamper_output"
(cd "$tamper_root" && python3 scripts/cartoon.py >/dev/null)
check_asset_group "$tamper_root" >/dev/null
mutation_count=$((mutation_count + 1))

replace_once "$tamper_root/docs/assets/CARTOON_PROVENANCE.md" \
  '| cycle seconds | 28 |' '| cycle seconds | 27 |'
stale_metadata_rc=0
stale_metadata_output="$(check_asset_group "$tamper_root" 2>&1)" || \
  stale_metadata_rc=$?
[ "$stale_metadata_rc" -ne 0 ] || \
  fail "cartoon mutation stale-provenance-metadata survived"
grep -Fq 'cartoon provenance cycle seconds differs' \
  <<<"$stale_metadata_output" || \
  fail "cartoon mutation stale-provenance-metadata missed expected failure: $stale_metadata_output"
replace_once "$tamper_root/docs/assets/CARTOON_PROVENANCE.md" \
  '| cycle seconds | 27 |' '| cycle seconds | 28 |'
check_asset_group "$tamper_root" >/dev/null
mutation_count=$((mutation_count + 1))

nonancestor_root="$tmp_dir/non-ancestor-root"
mkdir -p "$nonancestor_root/scripts"
cp "$CARTOON" "$nonancestor_root/scripts/cartoon.py"
cp "$EMBLEM" "$nonancestor_root/scripts/emblem.py"
git -C "$nonancestor_root" init -q
git -C "$nonancestor_root" add scripts/cartoon.py scripts/emblem.py
git -C "$nonancestor_root" -c user.name=t -c user.email=t@localhost \
  commit -q -m base
base_commit="$(git -C "$nonancestor_root" rev-parse HEAD)"
git -C "$nonancestor_root" checkout -q -b provenance-side
git -C "$nonancestor_root" -c user.name=t -c user.email=t@localhost \
  commit -q --allow-empty -m provenance
(cd "$nonancestor_root" && python3 scripts/cartoon.py >/dev/null)
(cd "$nonancestor_root" && python3 scripts/emblem.py >/dev/null)
(cd "$nonancestor_root" && python3 scripts/cartoon.py --provenance >/dev/null)
mkdir -p "$nonancestor_root/docs/evidence"
cat >"$nonancestor_root/README.md" <<'EOF_NONANCESTOR_README'
[cartoon](docs/assets/orbit-cartoon.svg)
<img src="docs/assets/emblem.svg" alt="emblem">
EOF_NONANCESTOR_README
cat >"$nonancestor_root/docs/evidence/README.md" <<'EOF_NONANCESTOR_INDEX'
[cartoon](../assets/orbit-cartoon.svg)
[emblem](../assets/emblem.svg)
[transcript](../assets/CARTOON_TRANSCRIPT.md)
[provenance](../assets/CARTOON_PROVENANCE.md)
EOF_NONANCESTOR_INDEX
git -C "$nonancestor_root" checkout -q -b publication "$base_commit"
git -C "$nonancestor_root" -c user.name=t -c user.email=t@localhost \
  commit -q --allow-empty -m publication
nonancestor_rc=0
nonancestor_output="$(check_asset_group "$nonancestor_root" 2>&1)" || \
  nonancestor_rc=$?
[ "$nonancestor_rc" -ne 0 ] || \
  fail "cartoon mutation non-ancestor-commit survived"
grep -Fq 'cartoon generator commit is not an ancestor of HEAD' \
  <<<"$nonancestor_output" || \
  fail "cartoon mutation non-ancestor-commit missed expected failure: $nonancestor_output"
git -C "$nonancestor_root" checkout -q provenance-side
check_asset_group "$nonancestor_root" >/dev/null
mutation_count=$((mutation_count + 1))

echo "PASS: cartoon generator contracts"

nongit_root="$tmp_dir/non-git-root"
mkdir -p "$nongit_root/scripts"
cp "$CARTOON" "$nongit_root/scripts/cartoon.py"
cp "$EMBLEM" "$nongit_root/scripts/emblem.py"
nongit_rc=0
nongit_output="$(cd "$nongit_root" && python3 scripts/cartoon.py \
  --provenance --provenance-output "$nongit_root/provenance.md" 2>&1)" || \
  nongit_rc=$?
[ "$nongit_rc" -ne 0 ] || fail "non-repository cartoon provenance guard did not fail"
grep -Fq 'cartoon: git status failed; cannot verify the generator is committed' \
  <<<"$nongit_output" || fail "non-repository cartoon status failure is missing"
[ ! -e "$nongit_root/provenance.md" ] || \
  fail "non-repository cartoon provenance guard wrote an output"
nongit_rc=0
nongit_output="$(cd "$nongit_root" && python3 scripts/emblem.py 2>&1)" || \
  nongit_rc=$?
[ "$nongit_rc" -ne 0 ] || fail "non-repository emblem generator guard did not fail"
grep -Fq 'emblem: git status failed; cannot verify the generator is committed' \
  <<<"$nongit_output" || fail "non-repository emblem status failure is missing"
[ ! -e "$nongit_root/docs/assets/emblem.svg" ] || \
  fail "non-repository emblem generator guard wrote an output"

revparse_root="$tmp_dir/revparse-root"
mkdir -p "$revparse_root/scripts" "$revparse_root/docs/assets"
cp "$CARTOON" "$revparse_root/scripts/cartoon.py"
cp "$EMBLEM" "$revparse_root/scripts/emblem.py"
git -C "$revparse_root" init -q
printf '%s\n' 'scripts/' 'docs/' >>"$revparse_root/.git/info/exclude"
(cd "$revparse_root" && python3 scripts/cartoon.py \
  --output docs/assets/orbit-cartoon.svg \
  --transcript-output docs/assets/CARTOON_TRANSCRIPT.md)
(cd "$revparse_root" && python3 scripts/emblem.py --output docs/assets/emblem.svg)
revparse_rc=0
revparse_output="$(cd "$revparse_root" && python3 scripts/cartoon.py \
  --provenance --provenance-output "$revparse_root/provenance.md" 2>&1)" || \
  revparse_rc=$?
[ "$revparse_rc" -ne 0 ] || fail "missing-HEAD provenance guard did not fail"
grep -Fq 'cartoon: git rev-parse HEAD failed; cannot record provenance' \
  <<<"$revparse_output" || fail "missing-HEAD provenance failure is missing"
[ ! -e "$revparse_root/provenance.md" ] || \
  fail "missing-HEAD provenance guard wrote an output"

guard_root="$tmp_dir/guard-root"
mkdir -p "$guard_root/scripts" "$guard_root/docs/assets"
cp "$CARTOON" "$guard_root/scripts/cartoon.py"
cp "$EMBLEM" "$guard_root/scripts/emblem.py"
git -C "$guard_root" init -q
git -C "$guard_root" add scripts/cartoon.py scripts/emblem.py
git -C "$guard_root" -c user.name=t -c user.email=t@localhost \
  commit -q -m fixture
(cd "$guard_root" && python3 scripts/cartoon.py \
  --output docs/assets/orbit-cartoon.svg \
  --transcript-output docs/assets/CARTOON_TRANSCRIPT.md)
(cd "$guard_root" && python3 scripts/emblem.py --output docs/assets/emblem.svg)

printf '\n# dirty cartoon\n' >>"$guard_root/scripts/cartoon.py"
(cd "$guard_root" && python3 scripts/cartoon.py \
  --output "$tmp_dir/dirty-cartoon.svg" \
  --transcript-output "$tmp_dir/dirty-transcript.md") || \
  fail "both cartoon output overrides did not bypass the clean guard"
guard_rc=0
guard_output="$(cd "$guard_root" && python3 scripts/cartoon.py --provenance 2>&1)" || \
  guard_rc=$?
[ "$guard_rc" -ne 0 ] || fail "dirty cartoon provenance guard did not fail"
grep -Fq 'cartoon: commit the generator before regenerating' <<<"$guard_output" || \
  fail "dirty cartoon provenance refusal is missing"
[ ! -e "$guard_root/docs/assets/CARTOON_PROVENANCE.md" ] || \
  fail "dirty cartoon provenance guard wrote an output"
git -C "$guard_root" add scripts/cartoon.py
git -C "$guard_root" -c user.name=t -c user.email=t@localhost \
  commit -q -m 'dirty cartoon committed'
(cd "$guard_root" && python3 scripts/cartoon.py --provenance)
[ -f "$guard_root/docs/assets/CARTOON_PROVENANCE.md" ] || \
  fail "clean cartoon provenance run wrote no output"

rm -f "$guard_root/docs/assets/CARTOON_PROVENANCE.md"
printf '\n# dirty emblem\n' >>"$guard_root/scripts/emblem.py"
(cd "$guard_root" && python3 scripts/emblem.py \
  --output "$tmp_dir/dirty-emblem.svg") || \
  fail "emblem output override did not bypass the clean guard"
guard_rc=0
guard_output="$(cd "$guard_root" && python3 scripts/cartoon.py --provenance 2>&1)" || \
  guard_rc=$?
[ "$guard_rc" -ne 0 ] || fail "dirty emblem provenance guard did not fail"
grep -Fq 'cartoon: commit the generator before regenerating' <<<"$guard_output" || \
  fail "dirty emblem provenance refusal is missing"
[ ! -e "$guard_root/docs/assets/CARTOON_PROVENANCE.md" ] || \
  fail "dirty emblem provenance guard wrote an output"
git -C "$guard_root" add scripts/emblem.py
git -C "$guard_root" -c user.name=t -c user.email=t@localhost \
  commit -q -m 'dirty emblem committed'
(cd "$guard_root" && python3 scripts/cartoon.py --provenance)
[ -f "$guard_root/docs/assets/CARTOON_PROVENANCE.md" ] || \
  fail "clean emblem provenance run wrote no output"
(cd "$guard_root" && python3 scripts/cartoon.py --provenance \
  --provenance-output "$tmp_dir/override-provenance.md")
[ -f "$tmp_dir/override-provenance.md" ] || \
  fail "cartoon provenance output override did not write output"
missing_git_root="$tmp_dir/missing-git-root"
mkdir -p "$missing_git_root/scripts" "$missing_git_root/bin"
cp "$CARTOON" "$missing_git_root/scripts/cartoon.py"
cp "$EMBLEM" "$missing_git_root/scripts/emblem.py"
git -C "$missing_git_root" init -q
git -C "$missing_git_root" add scripts/cartoon.py scripts/emblem.py
git -C "$missing_git_root" -c user.name=t -c user.email=t@localhost \
  commit -q -m fixture
ln -s "$(command -v python3)" "$missing_git_root/bin/python3"
missing_git_rc=0
missing_git_output="$(cd "$missing_git_root" && \
  PATH="$missing_git_root/bin" python3 scripts/cartoon.py \
  --provenance --provenance-output "$missing_git_root/provenance.md" 2>&1)" || \
  missing_git_rc=$?
[ "$missing_git_rc" -ne 0 ] || fail "cartoon mutation git-missing survived"
grep -Fq 'cartoon: git status failed; cannot verify the generator is committed' \
  <<<"$missing_git_output" || \
  fail "cartoon mutation git-missing missed expected failure: $missing_git_output"
[ ! -e "$missing_git_root/provenance.md" ] || \
  fail "cartoon mutation git-missing wrote a provenance output"
missing_git_rc=0
missing_git_output="$(cd "$missing_git_root" && \
  PATH="$missing_git_root/bin" python3 scripts/emblem.py 2>&1)" || \
  missing_git_rc=$?
[ "$missing_git_rc" -ne 0 ] || fail "missing-git emblem guard did not fail"
grep -Fq 'emblem: git status failed; cannot verify the generator is committed' \
  <<<"$missing_git_output" || fail "missing-git emblem status failure is missing"
[ ! -e "$missing_git_root/docs/assets/emblem.svg" ] || \
  fail "missing-git emblem guard wrote an output"
(cd "$missing_git_root" && python3 scripts/cartoon.py \
  --output docs/assets/orbit-cartoon.svg \
  --transcript-output docs/assets/CARTOON_TRANSCRIPT.md)
(cd "$missing_git_root" && python3 scripts/emblem.py --output docs/assets/emblem.svg)
(cd "$missing_git_root" && python3 scripts/cartoon.py \
  --provenance --provenance-output "$missing_git_root/provenance.md")
[ -f "$missing_git_root/provenance.md" ] || \
  fail "restored git PATH wrote no provenance output"
mutation_count=$((mutation_count + 1))

untracked_root="$tmp_dir/untracked-generator-root"
mkdir -p "$untracked_root/scripts" "$untracked_root/docs/assets"
cp "$CARTOON" "$untracked_root/scripts/cartoon.py"
cp "$EMBLEM" "$untracked_root/scripts/emblem.py"
printf '%s\n' 'scripts/emblem.py' >"$untracked_root/.gitignore"
git -C "$untracked_root" init -q
git -C "$untracked_root" add .gitignore scripts/cartoon.py
git -C "$untracked_root" -c user.name=t -c user.email=t@localhost \
  commit -q -m fixture
(cd "$untracked_root" && python3 scripts/cartoon.py \
  --output docs/assets/orbit-cartoon.svg \
  --transcript-output docs/assets/CARTOON_TRANSCRIPT.md)
(cd "$untracked_root" && python3 scripts/emblem.py \
  --output docs/assets/emblem.svg)
untracked_rc=0
untracked_output="$(cd "$untracked_root" && python3 scripts/cartoon.py \
  --provenance --provenance-output "$untracked_root/provenance.md" 2>&1)" || \
  untracked_rc=$?
[ "$untracked_rc" -ne 0 ] || fail "cartoon mutation untracked-generator survived"
grep -Fq 'cartoon: generator paths are not tracked; cannot record provenance' \
  <<<"$untracked_output" || \
  fail "cartoon mutation untracked-generator missed expected failure: $untracked_output"
[ ! -e "$untracked_root/provenance.md" ] || \
  fail "cartoon mutation untracked-generator wrote a provenance output"
git -C "$untracked_root" add -f scripts/emblem.py
git -C "$untracked_root" -c user.name=t -c user.email=t@localhost \
  commit -q -m 'track emblem'
(cd "$untracked_root" && python3 scripts/cartoon.py \
  --provenance --provenance-output "$untracked_root/provenance.md")
[ -f "$untracked_root/provenance.md" ] || \
  fail "restored tracked generators wrote no provenance output"
mutation_count=$((mutation_count + 1))
echo "PASS: cartoon generator provenance guard"

asset_group_ran=0
if [ "${CARTOON_SKIP_ASSET_GROUP:-0}" = 1 ]; then
  echo "SKIP: cartoon asset group (source-only mode; not a publication pass)"
else
  check_asset_group "$REPO_ROOT"
  if [ "$asset_group_ran" -eq 1 ]; then
    echo "PASS: cartoon asset contracts"
  fi
fi

if [ "$mutation_count" -ne "$expected_mutations" ]; then
  fail "cartoon mutation count mismatch: $mutation_count != $expected_mutations"
fi
if [ "$asset_group_ran" -eq 0 ]; then
  echo "PASS: cartoon source contracts ($mutation_count mutations; asset group skipped)"
else
  echo "PASS: cartoon contracts ($mutation_count mutations; restored suite passed)"
fi
