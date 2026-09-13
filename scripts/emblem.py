#!/usr/bin/env python3
"""Generate the deterministic animated orbit-infra emblem."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys
import tempfile


DEFAULT_OUTPUT = Path("docs/assets/emblem.svg")


def render() -> str:
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 160" role="img" aria-labelledby="emblem-title emblem-desc">',
        '  <title id="emblem-title">Orbit-infra verified shield</title>',
        '  <desc id="emblem-desc">A checked shield protected by a circling orbit ring.</desc>',
        "  <style>",
        "    @keyframes orbit-turn {",
        "      0.000% { transform: rotate(0.000deg); }",
        "      100.000% { transform: rotate(360.000deg); }",
        "    }",
        "    @keyframes shield-pulse {",
        "      0.000%, 100.000% { transform: scale(1.000); }",
        "      50.000% { transform: scale(1.045); }",
        "    }",
        "    #emblem-orbit-ring { animation: orbit-turn 6s linear infinite; }",
        "    #emblem-shield { animation: shield-pulse 6s linear infinite; }",
        "    @media (prefers-reduced-motion: reduce) {",
        "      #emblem-orbit-ring, #emblem-shield { animation: none; }",
        "    }",
        "  </style>",
        '  <g id="emblem-shield-pivot" transform="translate(80 80)">',
        '    <g id="emblem-shield">',
        '      <path d="M0 -57 L48 -38 V-4 C48 31 28 52 0 65 C-28 52 -48 31 -48 -4 V-38Z" fill="#0f766e" stroke="#17324d" stroke-width="7" stroke-linejoin="round"/>',
        '      <path d="M-24 2 L-7 22 L28 -22" fill="none" stroke="#f8fafc" stroke-width="11" stroke-linecap="round" stroke-linejoin="round"/>',
        "    </g>",
        "  </g>",
        '  <g id="emblem-orbit-pivot" transform="translate(80 80)">',
        '    <g id="emblem-orbit-ring">',
        '      <ellipse rx="72" ry="28" fill="none" stroke="#38bdf8" stroke-width="7"/>',
        '      <circle cx="72" r="8" fill="#facc15" stroke="#17324d" stroke-width="4"/>',
        "    </g>",
        "  </g>",
        "</svg>",
        "",
    ]
    return "\n".join(lines)


def ensure_clean_generator(paths: tuple[str, ...] = ("scripts/emblem.py",)) -> None:
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain", "--", *paths],
            capture_output=True,
            text=True,
            check=False,
        )
    except (OSError, FileNotFoundError):
        print(
            "emblem: git status failed; cannot verify the generator is committed",
            file=sys.stderr,
        )
        raise SystemExit(1)
    if result.returncode != 0:
        print(
            "emblem: git status failed; cannot verify the generator is committed",
            file=sys.stderr,
        )
        raise SystemExit(1)
    if not result.stdout.strip():
        return
    dirty = ", ".join(line[3:] for line in result.stdout.splitlines())
    print(
        f"emblem: commit the generator before regenerating (dirty: {dirty})",
        file=sys.stderr,
    )
    raise SystemExit(1)


def write_output(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def check_asset() -> int:
    if not DEFAULT_OUTPUT.is_file():
        print(f"emblem: {DEFAULT_OUTPUT} is missing", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory(prefix="emblem-check-") as directory:
        candidate = Path(directory) / DEFAULT_OUTPUT.name
        write_output(candidate, render())
        if candidate.read_bytes() != DEFAULT_OUTPUT.read_bytes():
            print("emblem: regenerate the emblem", file=sys.stderr)
            return 1
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check and args.output is not None:
        parser.error("--check cannot be combined with --output")
    return args


def main() -> int:
    args = parse_args()
    if args.check:
        return check_asset()
    if args.output is None:
        ensure_clean_generator()
    write_output(args.output or DEFAULT_OUTPUT, render())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
