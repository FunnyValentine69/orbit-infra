#!/usr/bin/env python3
"""Generate the deterministic front-page process storyboard."""

from __future__ import annotations

import argparse
import html
import math
from pathlib import Path
import sys
import tempfile


CAPTIONS = (
    "Pull request opens",
    "Static gates: fmt, validate, lint, policy-size, conftest",
    "LocalStack plan posts a comment on the PR",
    "Preview lease opens: new generation, owner token",
    "Terraform applies; acceptance checks pass",
    "Close begins: Stage 1 destroy and verify",
    "Stage 2 sweep reclaims state and lock versions",
    "Supply chain: signed images verified at apply",
)
SCHEDULE = (0, 1, 2, 3, 4, 5, 6, 4)
SLOT_SECONDS = 3
CYCLE_SECONDS = 7 * SLOT_SECONDS
MAX_CAPTION_CHARS = 60
MAIN_TEXT_WIDTH = 468
SUPPLY_TEXT_WIDTH = 248
MAIN_CHAR_WIDTH = 8
SUPPLY_CHAR_WIDTH = 5.5
DEFAULT_OUTPUT = Path("docs/assets/storyboard.svg")


def validate_layout() -> None:
    for index, caption in enumerate(CAPTIONS):
        if len(caption) >= MAX_CAPTION_CHARS:
            raise ValueError(f"caption {index + 1} is not under 60 characters")
        width = len(caption) * (SUPPLY_CHAR_WIDTH if index == 7 else MAIN_CHAR_WIDTH)
        available = SUPPLY_TEXT_WIDTH if index == 7 else MAIN_TEXT_WIDTH
        if width > available:
            raise ValueError(f"caption {index + 1} exceeds its width heuristic")


def format_seconds(seconds: float) -> str:
    return str(int(seconds)) if seconds.is_integer() else f"{seconds:g}"


def render(snapshot: float | None = None) -> str:
    validate_layout()
    snapshot_slot = None
    snapshot_attribute = ""
    if snapshot is not None:
        snapshot_slot = int(snapshot // SLOT_SECONDS) % 7
        snapshot_attribute = f' data-snapshot="{format_seconds(snapshot)}"'

    style_lines = [
        "    :root { color-scheme: light dark; }",
        "    .background { fill: #253348; }",
        "    .heading { fill: #f7fafc; font: 700 24px system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }",
        "    .subheading { fill: #d7e0ea; font: 14px system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }",
        "    .panel rect { fill: #52657b; stroke: #90a4ba; stroke-width: 2; }",
        "    .caption { fill: #ffffff; font: 600 14px system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }",
        "    .supply .caption { font-size: 11.5px; }",
        "    .step-number { fill: #d7e0ea; font: 700 12px system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }",
        "    .connector { fill: none; stroke: #90a4ba; stroke-width: 2; }",
        "    .parallel { stroke-dasharray: 6 5; }",
    ]
    if snapshot is None:
        style_lines.extend(
            [
                "    @keyframes panel-lit {",
                "      0%, 13.9% { fill: #0f766e; stroke: #99f6e4; }",
                "      14.3%, 100% { fill: #52657b; stroke: #90a4ba; }",
                "    }",
                "    .panel rect { animation: panel-lit 21s linear infinite both; }",
            ]
        )
        for index, slot in enumerate(SCHEDULE):
            delay = -(CYCLE_SECONDS - (slot * SLOT_SECONDS))
            style_lines.append(
                f"    .panel-{index + 1} rect {{ animation-delay: {delay}s; }}"
            )
        style_lines.extend(
            [
                "    @media (prefers-reduced-motion: reduce) {",
                "      .panel rect { animation: none; fill: #0f766e; stroke: #99f6e4; }",
                "    }",
            ]
        )
    else:
        style_lines.append("    .panel.lit rect { fill: #0f766e; stroke: #99f6e4; }")
        style_lines.append(
            "    /* prefers-reduced-motion: this snapshot is already static. */"
        )

    panels = []
    for index, caption in enumerate(CAPTIONS[:7]):
        y = 86 + (index * 70)
        lit = " lit" if snapshot_slot == SCHEDULE[index] else ""
        panels.extend(
            [
                f'  <g id="step-{index + 1}" class="panel panel-{index + 1}{lit}" transform="translate(40 {y})">',
                '    <rect width="500" height="52" rx="12"/>',
                f'    <text class="step-number" x="16" y="31">{index + 1}</text>',
                f'    <text class="caption" x="46" y="32">{html.escape(caption)}</text>',
                "  </g>",
            ]
        )
        if index < 6:
            panels.append(f'  <path class="connector" d="M290 {y + 52} V{y + 70}"/>')

    supply_y = 86 + (4 * 70)
    supply_lit = " lit" if snapshot_slot == SCHEDULE[7] else ""
    panels.extend(
        [
            f'  <path class="connector parallel" d="M540 {supply_y + 26} H570"/>',
            f'  <g id="step-8" class="panel panel-8 supply{supply_lit}" transform="translate(570 {supply_y})">',
            '    <rect width="280" height="52" rx="12"/>',
            '    <text class="step-number" x="12" y="31">↳</text>',
            f'    <text class="caption" x="32" y="32">{html.escape(CAPTIONS[7])}</text>',
            "  </g>",
        ]
    )

    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 880 610" role="img"{snapshot_attribute}>',
        "  <title>How an orbit-infra change flows</title>",
        "  <desc>Eight stages from pull request gates through preview cleanup, with supply-chain verification running alongside apply.</desc>",
        "  <style>",
        *style_lines,
        "  </style>",
        '  <rect class="background" width="880" height="610" rx="18"/>',
        '  <text class="heading" x="40" y="42">How a change flows</text>',
        '  <text class="subheading" x="40" y="66">The highlighted stage advances every three seconds.</text>',
        *panels,
        "</svg>",
        "",
    ]
    return "\n".join(lines)


def write_output(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def check_asset() -> int:
    if not DEFAULT_OUTPUT.is_file():
        print(f"storyboard: {DEFAULT_OUTPUT} is missing", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory(prefix="storyboard-check-") as directory:
        candidate = Path(directory) / "storyboard.svg"
        write_output(candidate, render())
        if candidate.read_bytes() != DEFAULT_OUTPUT.read_bytes():
            print("storyboard: regenerate the storyboard", file=sys.stderr)
            return 1
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="compare the committed asset"
    )
    parser.add_argument("--output", type=Path, help="write to this path")
    parser.add_argument(
        "--snapshot", type=float, help="render a static state at N seconds"
    )
    args = parser.parse_args()
    if args.check and (args.output is not None or args.snapshot is not None):
        parser.error("--check cannot be combined with --output or --snapshot")
    if args.snapshot is not None and not math.isfinite(args.snapshot):
        parser.error("--snapshot must be finite")
    if args.snapshot is not None and args.snapshot < 0:
        parser.error("--snapshot must be nonnegative")
    if args.snapshot is not None and args.output is None:
        parser.error("--snapshot requires --output")
    return args


def main() -> int:
    args = parse_args()
    if args.check:
        return check_asset()
    write_output(args.output or DEFAULT_OUTPUT, render(args.snapshot))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
