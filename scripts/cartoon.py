#!/usr/bin/env python3
"""Generate the deterministic orbit-infra cartoon and transcript."""

from __future__ import annotations

import argparse
import hashlib
import html
import math
from pathlib import Path
import subprocess
import sys
from typing import TypeAlias


CYCLE_SECONDS = 28
PROBLEM_SUMMARY = "Putting an app on the cloud is easy; doing it so nothing leaks, nothing is left running and billing you, and every step can be checked by a stranger is hard."
GUARDRAILS_SUMMARY = "The project takes a friend's app, builds the cloud plumbing around it, and wraps every action in rules: changes must pass gates before they merge, every environment has a lease that expires and cleans itself up, and only signed images can run."
PROOF_SUMMARY = "Instead of trusting a demo, the repo records evidence: terminal recordings, a permission-by-permission test against AWS's own policy simulator, and checks that fail if the docs drift from the code."
STOP_SUMMARY = "The whole system is shown working on a local emulator and the permissions are proven on the real account; the live deployment tail was deliberately not paid for, because the cost is real and the audience is small."
SCENES = (
    ("problem", 0, 6, "The problem", PROBLEM_SUMMARY),
    ("guardrails", 6, 14, "Guardrails", GUARDRAILS_SUMMARY),
    ("proof", 14, 21, "Proof", PROOF_SUMMARY),
    ("stop", 21, 28, "Stop", STOP_SUMMARY),
)
DEFAULT_SVG = Path("docs/assets/orbit-cartoon.svg")
DEFAULT_TRANSCRIPT = Path("docs/assets/CARTOON_TRANSCRIPT.md")
DEFAULT_PROVENANCE = Path("docs/assets/CARTOON_PROVENANCE.md")

Transform: TypeAlias = tuple[str, float] | tuple[str, float, float]
Value: TypeAlias = float | str | Transform
Track: TypeAlias = tuple[str, str, tuple[tuple[float, Value], ...]]


def validate_scenes() -> None:
    if tuple(scene[0] for scene in SCENES) != ("problem", "guardrails", "proof", "stop"):
        raise ValueError("scene ids must be problem, guardrails, proof, stop")
    expected_start = 0
    for scene_id, start, end, _title, _summary in SCENES:
        if start != expected_start:
            raise ValueError(f"scene {scene_id} must begin at {expected_start}")
        if end <= start:
            raise ValueError(f"scene {scene_id} has an empty interval")
        expected_start = end
    if expected_start != CYCLE_SECONDS:
        raise ValueError(f"scene stop must end at {CYCLE_SECONDS}")


def scene_track(scene_id: str, start: int, end: int) -> Track:
    visible_start = float(start)
    visible_end = float(end)
    if start == 0:
        points: tuple[tuple[float, Value], ...] = (
            (0.0, 1.0),
            (visible_end - 0.001, 1.0),
            (visible_end, 0.0),
            (CYCLE_SECONDS - 0.001, 0.0),
            (float(CYCLE_SECONDS), 1.0),
        )
    else:
        points = (
            (0.0, 0.0),
            (visible_start - 0.001, 0.0),
            (visible_start, 1.0),
            (visible_end - 0.001, 1.0),
            (visible_end, 0.0),
        )
        if end < CYCLE_SECONDS:
            points += ((float(CYCLE_SECONDS), 0.0),)
    return (f"scene-{scene_id}", "opacity", points)


def animation_tracks() -> tuple[Track, ...]:
    def move(x: float, y: float) -> Transform:
        return ("translate", float(x), float(y))
    def rotate(degrees: float) -> Transform:
        return ("rotate", float(degrees))
    def scale(amount: float) -> Transform:
        return ("scale", float(amount))
    def scale_xy(x: float, y: float) -> Transform:
        return ("scale", float(x), float(y))
    transform, opacity, fill = "transform", "opacity", "fill"
    off, green, red = "#53657a", "#4ade80", "#fb7185"
    guardrail_move = ((0, move(0, 0)), (9.45, move(0, 0)), (10.05, move(430, 0)), (10.75, move(430, 0)), (11.25, move(0, 0)), (28, move(0, 0)))
    guardrail_left_arm = ((0, rotate(0)), (6, rotate(0)), (6.4, rotate(-38)), (6.8, rotate(22)), (7.2, rotate(-38)), (7.6, rotate(22)), (8, rotate(-12)), (28, rotate(-12)))
    guardrail_right_arm = ((0, rotate(0)), (6, rotate(0)), (6.35, rotate(42)), (6.75, rotate(-36)), (7.15, rotate(42)), (7.55, rotate(-36)), (8, rotate(5)), (9.9, rotate(5)), (10.25, rotate(-58)), (10.55, rotate(-15)), (28, rotate(-15)))
    guardrail_opacity_behind = ((0, 1.0), (9.805, 1.0), (9.806, 0.0), (10.952, 0.0), (10.953, 1.0), (28, 1.0))
    guardrail_opacity_front = ((0, 0.0), (9.805, 0.0), (9.806, 1.0), (10.952, 1.0), (10.953, 0.0), (28, 0.0))
    beats: tuple[Track, ...] = (
        ("friend-hand", opacity, ((0, 0.0), (.1, 1.0), (1.45, 1.0), (1.7, 0.0), (28, 0.0))),
        ("friend-hand", transform, ((0, move(-220, 35)), (.35, move(-30, 0)), (1.15, move(30, -24)), (1.7, move(165, 38)), (28, move(165, 38)))),
        ("pip-toss", opacity, ((0, 0.0), (.1, 1.0), (5.999, 1.0), (6, 0.0), (28, 0.0))),
        ("pip-toss", transform, ((0, move(-330, -20)), (.45, move(-270, -105)), (1.05, move(-170, -165)), (1.55, move(-75, -120)), (2, move(0, 0)), (28, move(0, 0)))),
        ("pip-face-happy", opacity, ((0, 1.0), (2.45, 1.0), (2.5, 0.0), (28, 0.0))),
        ("pip-face-worried", opacity, ((0, 0.0), (2.45, 0.0), (2.5, 1.0), (10.45, 1.0), (10.5, 0.0), (28, 0.0))),
        ("pip-face-relieved", opacity, ((0, 0.0), (10.45, 0.0), (10.5, 1.0), (20.999, 1.0), (21, 0.0), (28, 0.0))),
        ("pip-face-proud", opacity, ((0, 0.0), (20.999, 0.0), (21, 1.0), (28, 1.0))),
        ("leak-drip-1", opacity, ((0, 0.0), (2.65, 0.0), (2.7, 1.0), (5.7, 1.0), (5.9, 0.0), (28, 0.0))),
        ("leak-drip-1", transform, ((0, move(0, -12)), (2.7, move(0, -12)), (5.9, move(0, 72)), (28, move(0, 72)))),
        ("leak-drip-2", opacity, ((0, 0.0), (3.15, 0.0), (3.2, 1.0), (5.75, 1.0), (5.95, 0.0), (28, 0.0))),
        ("leak-drip-2", transform, ((0, move(0, -12)), (3.2, move(0, -12)), (5.95, move(0, 66)), (28, move(0, 66)))),
        ("leak-drip-3", opacity, ((0, 0.0), (3.65, 0.0), (3.7, 1.0), (5.8, 1.0), (5.98, 0.0), (28, 0.0))),
        ("leak-drip-3", transform, ((0, move(0, -12)), (3.7, move(0, -12)), (5.98, move(0, 62)), (28, move(0, 62)))),
        ("prop-server-glow", opacity, ((0, .55), (1, 1.0), (2, .55), (3, 1.0), (4, .55), (5, 1.0), (6, .55), (28, .55))),
        ("prop-server-glow", transform, ((0, scale(.94)), (1, scale(1.06)), (2, scale(.94)), (3, scale(1.06)), (4, scale(.94)), (5, scale(1.06)), (6, scale(.94)), (28, scale(.94)))),
        ("coin-1", opacity, ((0, 0.0), (.55, 0.0), (.6, 1.0), (2.3, 1.0), (2.4, 0.0), (28, 0.0))),
        ("coin-1", transform, ((0, move(0, -60)), (.6, move(0, -60)), (1.45, move(12, -100)), (2.4, move(55, -67)), (28, move(55, -67)))),
        ("coin-2", opacity, ((0, 0.0), (1.35, 0.0), (1.4, 1.0), (3.15, 1.0), (3.25, 0.0), (28, 0.0))),
        ("coin-2", transform, ((0, move(0, -60)), (1.4, move(0, -60)), (2.25, move(8, -105)), (3.25, move(43, -76)), (28, move(43, -76)))),
        ("coin-3", opacity, ((0, 0.0), (2.3, 0.0), (2.35, 1.0), (4.55, 1.0), (4.7, 0.0), (28, 0.0))),
        ("coin-3", transform, ((0, move(0, -60)), (2.35, move(0, -60)), (3.35, move(15, -108)), (4.7, move(70, -82)), (28, move(70, -82)))),
        ("actor-orbit-ring", transform, ((0, rotate(0)), (28, rotate(720)))),
        ("actor-bill-needle", transform, ((0, rotate(-65)), (.5, rotate(-65)), (5.8, rotate(1015)), (6, rotate(120)), (13.15, rotate(120)), (13.55, rotate(-65)), (28, rotate(-65)))),
        ("orbit-left-arm-behind", transform, guardrail_left_arm),
        ("orbit-right-arm-behind", transform, guardrail_right_arm),
        ("orbit-guardrails-behind", transform, guardrail_move),
        ("orbit-guardrails-behind", opacity, guardrail_opacity_behind),
        ("orbit-left-arm-front", transform, guardrail_left_arm),
        ("orbit-right-arm-front", transform, guardrail_right_arm),
        ("orbit-guardrails-front", transform, guardrail_move),
        ("orbit-guardrails-front", opacity, guardrail_opacity_front),
        ("gate-assembly", transform, ((0, move(0, 175)), (6.25, move(0, 175)), (7.85, move(0, 0)), (28, move(0, 0)))),
        ("prop-gate-light-1", fill, ((0, off), (8, off), (8.1, green), (28, green))),
        ("prop-gate-light-2", fill, ((0, off), (8.7, off), (8.8, green), (28, green))),
        ("prop-gate-light-3", fill, ((0, off), (9.4, off), (9.5, green), (28, green))),
        ("gate-door", transform, ((0, scale_xy(1, 1)), (9.55, scale_xy(1, 1)), (10.25, scale_xy(1, .04)), (28, scale_xy(1, .04)))),
        ("prop-lease-timer", opacity, ((0, 0.0), (10.2, 0.0), (10.3, 1.0), (13.55, 1.0), (13.8, 0.0), (28, 0.0))),
        ("prop-lease-timer-hand", transform, ((0, rotate(0)), (10.3, rotate(0)), (13.35, rotate(360)), (28, rotate(360)))),
        ("prop-seal", opacity, ((0, 0.0), (9.899, 0.0), (9.9, 1.0), (28, 1.0))),
        ("prop-seal", transform, ((0, move(0, -155)), (9.95, move(0, -155)), (10.35, move(0, 0)), (28, move(0, 0)))),
        ("seal-strike", transform, ((0, scale(1)), (10.34, scale(1)), (10.48, scale(1.24)), (10.65, scale(.84)), (10.85, scale(1)), (28, scale(1)))),
        ("pip-seal-squash", transform, ((0, scale(1)), (10.34, scale(1)), (10.52, scale(.82)), (10.72, scale(1.08)), (10.9, scale(1)), (28, scale(1)))),
        ("broombot-guardrails", transform, ((0, move(-300, 0)), (11.35, move(-300, 0)), (13.85, move(500, 0)), (28, move(500, 0)))),
        ("broombot-broom", transform, ((0, rotate(-28)), (11.4, rotate(-28)), (11.8, rotate(30)), (12.2, rotate(-30)), (12.6, rotate(30)), (13, rotate(-30)), (13.4, rotate(30)), (13.85, rotate(-28)), (28, rotate(-28)))),
        ("cloud-guardrails", transform, ((0, move(0, 0)), (13.05, move(0, 0)), (13.9, move(520, 20)), (28, move(520, 20)))),
        ("scout-entry", transform, ((0, move(900, 0)), (14, move(900, 0)), (14.8, move(0, 0)), (28, move(0, 0)))),
        ("scout-lean", transform, ((0, rotate(0)), (14.75, rotate(0)), (15.25, rotate(-10)), (18.9, rotate(-10)), (19.2, rotate(0)), (28, rotate(0)))),
        ("scout-head", transform, ((0, rotate(0)), (19.15, rotate(0)), (19.5, rotate(15)), (19.85, rotate(-7)), (20.25, rotate(0)), (28, rotate(0)))),
        ("scout-brow", transform, ((0, move(0, 0)), (19, move(0, 0)), (19.35, move(0, 7)), (28, move(0, 7)))),
        ("prop-rec-reel", transform, ((0, rotate(0)), (14, rotate(0)), (21, rotate(1080)), (28, rotate(1080)))),
        ("prop-permission-row-1", fill, ((0, off), (15, off), (15.1, green), (28, green))),
        ("prop-permission-row-2", fill, ((0, off), (15.7, off), (15.8, green), (28, green))),
        ("prop-permission-row-3", fill, ((0, off), (16.4, off), (16.5, green), (28, green))),
        ("prop-permission-row-4", fill, ((0, off), (17.1, off), (17.2, green), (28, green))),
        ("prop-code-card", transform, ((0, move(0, -300)), (17, move(0, -300)), (18, move(0, 0)), (18.2, move(8, 0)), (19, move(0, 0)), (28, move(0, 0)))),
        ("prop-doc-card", transform, ((0, move(0, -300)), (17, move(0, -300)), (18, move(0, 0)), (18.2, move(-8, 0)), (19, move(0, 0)), (28, move(0, 0)))),
        ("prop-contract-lamp", fill, ((0, off), (18, off), (18.05, red), (18.8, red), (19, green), (28, green))),
        ("prop-runway", opacity, ((0, .35), (21, .35), (21.4, 1.0), (28, 1.0))),
        ("runway-sparkle-1", opacity, ((0, 0.0), (21.3, 0.0), (21.55, 1.0), (22, .15), (22.45, 1.0), (22.9, .15), (23.35, 1.0), (24.1, 1.0), (24.5, .15), (24.9, 1.0), (25.3, .15), (25.7, 1.0), (26.1, .15), (26.5, 1.0), (26.9, .15), (27.2, 1.0), (28, 1.0))),
        ("runway-sparkle-2", opacity, ((0, 0.0), (21.55, 0.0), (21.9, 1.0), (22.35, .15), (22.8, 1.0), (23.25, .15), (23.7, 1.0), (24.1, 1.0), (24.35, .15), (24.75, 1.0), (25.15, .15), (25.55, 1.0), (25.95, .15), (26.35, 1.0), (26.75, .15), (27.15, 1.0), (28, 1.0))),
        ("runway-sparkle-3", opacity, ((0, 0.0), (21.8, 0.0), (22.15, 1.0), (22.6, .15), (23.05, 1.0), (23.5, .15), (23.95, 1.0), (24.1, 1.0), (24.6, .15), (25, 1.0), (25.4, .15), (25.8, 1.0), (26.2, .15), (26.6, 1.0), (27, .15), (27.2, 1.0), (28, 1.0))),
        ("orbit-rope-arm", transform, ((0, rotate(-68)), (21.25, rotate(-68)), (23.2, rotate(48)), (28, rotate(48)))),
        ("prop-velvet-rope", transform, ((0, move(0, -470)), (21.7, move(0, -470)), (23.2, move(0, 0)), (28, move(0, 0)))),
        ("wallet-flap", transform, ((0, rotate(58)), (23.15, rotate(58)), (23.45, rotate(-8)), (23.62, rotate(4)), (23.8, rotate(0)), (28, rotate(0)))),
        ("prop-wallet", transform, ((0, scale(1)), (23.2, scale(1)), (23.5, scale(.92)), (23.75, scale(1)), (28, scale(1)))),
        ("bill-face-greedy", opacity, ((0, 1.0), (21.7, 1.0), (21.8, 0.0), (28, 0.0))),
        ("bill-face-sulk", opacity, ((0, 0.0), (21.7, 0.0), (21.8, 1.0), (28, 1.0))),
        ("spectator-1-left-arm", transform, ((0, rotate(-25)), (21.4, rotate(-25)), (21.75, rotate(25)), (22.1, rotate(-25)), (22.45, rotate(25)), (22.8, rotate(-25)), (23.15, rotate(25)), (28, rotate(25)))),
        ("spectator-1-right-arm", transform, ((0, rotate(25)), (21.4, rotate(25)), (21.75, rotate(-25)), (22.1, rotate(25)), (22.45, rotate(-25)), (22.8, rotate(25)), (23.15, rotate(-25)), (28, rotate(-25)))),
        ("spectator-2-left-arm", transform, ((0, rotate(-25)), (21.55, rotate(-25)), (21.9, rotate(25)), (22.25, rotate(-25)), (22.6, rotate(25)), (22.95, rotate(-25)), (23.3, rotate(25)), (28, rotate(25)))),
        ("spectator-2-right-arm", transform, ((0, rotate(25)), (21.55, rotate(25)), (21.9, rotate(-25)), (22.25, rotate(25)), (22.6, rotate(-25)), (22.95, rotate(25)), (23.3, rotate(-25)), (28, rotate(-25)))),
        ("prop-endcard", opacity, ((0, 0.0), (24.399, 0.0), (24.4, 1.0), (28, 1.0))),
        ("wipe-ring", opacity, ((0, 0.0), (27.199, 0.0), (27.2, 1.0), (28, 1.0))),
        ("wipe-ring", transform, ((0, scale(.08)), (27.2, scale(.08)), (27.98, scale(8.4)), (28, scale(8.4)))),
        ("wipe-cloud-outline", opacity, ((0, 0.0), (27.84, 0.0), (27.96, 1.0), (28, 1.0))),
    )
    scenes = tuple(scene_track(scene_id, start, end) for scene_id, start, end, _, _ in SCENES)
    return scenes + beats


def interpolate(left: Value, right: Value, fraction: float) -> Value:
    if isinstance(left, float) and isinstance(right, float):
        return left + ((right - left) * fraction)
    if isinstance(left, tuple) and isinstance(right, tuple) and left[0] == right[0]:
        return (left[0], *(a + (b - a) * fraction for a, b in zip(left[1:], right[1:])))
    return left


def css_percentage(second: float) -> float:
    return float(f"{second / CYCLE_SECONDS * 100:.3f}")


def validate_keyframe_percentages(tracks: tuple[Track, ...]) -> None:
    for target, prop, points in tracks:
        seen: set[float] = set()
        for second, _value in points:
            percentage = css_percentage(second)
            if percentage in seen:
                name = f"track-{target}-{prop}"
                raise ValueError(
                    f"duplicate keyframe percentage after formatting: "
                    f"{name} {percentage:.3f}%"
                )
            seen.add(percentage)


def evaluate(points: tuple[tuple[float, Value], ...], second: float) -> Value:
    percentage = css_percentage(second % CYCLE_SECONDS)
    css_points = tuple((css_percentage(at), value) for at, value in points)
    for (left_at, left), (right_at, right) in zip(css_points, css_points[1:]):
        if percentage <= right_at:
            fraction = (percentage - left_at) / (right_at - left_at)
            return interpolate(left, right, fraction)
    return css_points[-1][1]


def css_value(value: Value) -> str:
    if isinstance(value, float):
        return f"{value:.3f}"
    if isinstance(value, str):
        return value
    if value[0] == "translate":
        return f"translate({value[1]:.3f}px, {value[2]:.3f}px)"
    if value[0] == "rotate":
        return f"rotate({value[1]:.3f}deg)"
    if value[0] == "scale" and len(value) == 3:
        return f"scale({value[1]:.3f}, {value[2]:.3f})"
    return f"scale({value[1]:.3f})"


def snapshot_styles(second: float | None, tracks: tuple[Track, ...]) -> dict[str, str]:
    if second is None:
        return {}
    declarations: dict[str, list[str]] = {}
    for target, prop, points in tracks:
        declarations.setdefault(target, []).append(
            f"{prop}: {css_value(evaluate(points, second))};"
        )
    return {target: " ".join(values) for target, values in declarations.items()}


def ident(element_id: str, styles: dict[str, str]) -> str:
    style = f' style="{html.escape(styles[element_id], quote=True)}"' if element_id in styles else ""
    return f'id="{element_id}"{style}'


def actor_pip(styles: dict[str, str]) -> str:
    return f"""    <g {ident("actor-pip", styles)}><rect x="-55" y="-44" width="110" height="88" rx="22" fill="#7dd3fc" stroke="#082f49" stroke-width="6"/><path d="M-38 -34 Q0 -55 38 -34" fill="#bae6fd" stroke="#082f49" stroke-width="5"/><g {ident("pip-face-happy", styles)}><circle cx="-20" cy="-8" r="9" fill="#082f49"/><circle cx="20" cy="-8" r="9" fill="#082f49"/><path d="M-24 13 Q0 36 24 13" fill="none" stroke="#082f49" stroke-width="6" stroke-linecap="round"/></g><g {ident("pip-face-worried", styles)}><circle cx="-20" cy="-5" r="9" fill="#082f49"/><circle cx="20" cy="-5" r="9" fill="#082f49"/><path d="M-32 -22 L-12 -16 M12 -16 L32 -22 M-22 27 Q0 5 22 27" fill="none" stroke="#082f49" stroke-width="6" stroke-linecap="round"/></g><g {ident("pip-face-relieved", styles)}><path d="M-30 -5 Q-20 7 -10 -5 M10 -5 Q20 7 30 -5 M-22 19 Q0 34 22 19" fill="none" stroke="#082f49" stroke-width="6" stroke-linecap="round"/></g><g {ident("pip-face-proud", styles)}><path d="M-31 -5 Q-20 -17 -9 -5 M9 -5 Q20 -17 31 -5 M-25 14 Q0 37 25 14" fill="none" stroke="#082f49" stroke-width="6" stroke-linecap="round"/></g></g>"""


def actor_orbit(styles: dict[str, str]) -> str:
    return f"""    <g {ident("actor-orbit", styles)}><path d="M-42 -28 Q-42 -48 -22 -48 H22 Q42 -48 42 -28 V44 Q42 62 24 62 H-24 Q-42 62 -42 44Z" fill="#e2e8f0" stroke="#082f49" stroke-width="6"/><rect x="-27" y="-14" width="54" height="42" rx="12" fill="#0e7490" stroke="#082f49" stroke-width="5"/><circle cx="-12" cy="7" r="8" fill="#67e8f9"/><circle cx="14" cy="7" r="8" fill="#facc15"/><path d="M-25 62 L-34 80 M25 62 L34 80" stroke="#e2e8f0" stroke-width="14" stroke-linecap="round"/><g {ident("actor-orbit-ring-pivot", styles)} transform="translate(0 -72)"><g {ident("actor-orbit-ring", styles)}><ellipse rx="52" ry="19" fill="none" stroke="#22d3ee" stroke-width="9"/><circle cx="52" r="8" fill="#facc15" stroke="#082f49" stroke-width="4"/></g></g><circle cy="-72" r="26" fill="#cffafe" stroke="#082f49" stroke-width="6"/><circle cx="-9" cy="-76" r="7" fill="#082f49"/><circle cx="9" cy="-76" r="7" fill="#082f49"/><path d="M-12 -60 Q0 -51 12 -60" fill="none" stroke="#082f49" stroke-width="5" stroke-linecap="round"/></g>"""


def actor_scout(styles: dict[str, str]) -> str:
    return f"""    <g {ident("actor-scout", styles)}><ellipse cy="22" rx="48" ry="56" fill="#a78bfa" stroke="#312e81" stroke-width="6"/><path d="M-42 22 Q-72 48 -42 69 M42 22 Q72 48 42 69" fill="#8b5cf6" stroke="#312e81" stroke-width="6"/><path d="M-24 72 L-35 88 M24 72 L35 88" stroke="#facc15" stroke-width="8" stroke-linecap="round"/><g {ident("scout-head-pivot", styles)} transform="translate(0 -27)"><g {ident("scout-head", styles)}><path d="M-46 -14 L-31 -53 L-10 -27 Q0 -34 10 -27 L31 -53 L46 -14 Q54 30 0 40 Q-54 30 -46 -14Z" fill="#c4b5fd" stroke="#312e81" stroke-width="6"/><circle cx="-20" cy="-5" r="19" fill="#ffffff" stroke="#312e81" stroke-width="5"/><circle cx="20" cy="-5" r="19" fill="#ffffff" stroke="#312e81" stroke-width="5"/><circle cx="-17" cy="-3" r="9" fill="#111827"/><circle cx="17" cy="-3" r="9" fill="#111827"/><path d="M-9 18 L0 31 L9 18Z" fill="#facc15" stroke="#312e81" stroke-width="4"/><g {ident("scout-brow", styles)}><path d="M-38 -27 L-10 -20 M10 -20 L38 -32" stroke="#312e81" stroke-width="7" stroke-linecap="round"/></g><g {ident("actor-scout-lens", styles)}><circle cx="36" cy="12" r="26" fill="none" stroke="#facc15" stroke-width="8"/><path d="M54 31 L73 51" stroke="#facc15" stroke-width="10" stroke-linecap="round"/></g></g></g></g>"""


def actor_bill(styles: dict[str, str]) -> str:
    return f"""    <g {ident("actor-bill", styles)}><path d="M-58 -38 L-43 -62 L-25 -42 Q0 -55 25 -42 L43 -62 L58 -38 V38 Q58 58 38 58 H-38 Q-58 58 -58 38Z" fill="#fb7185" stroke="#4c0519" stroke-width="6"/><circle cx="-34" cy="-18" r="9" fill="#fef08a"/><circle cx="34" cy="-18" r="9" fill="#fef08a"/><g {ident("bill-face-greedy", styles)}><path d="M-43 -31 L-25 -23 M25 -23 L43 -31 M-28 14 Q0 43 28 14" fill="none" stroke="#4c0519" stroke-width="6" stroke-linecap="round"/><path d="M-17 25 L-9 15 L0 27 L9 15 L17 25" fill="#ffffff"/></g><g {ident("bill-face-sulk", styles)}><path d="M-43 -24 L-25 -31 M25 -31 L43 -24 M-27 32 Q0 6 27 32" fill="none" stroke="#4c0519" stroke-width="6" stroke-linecap="round"/></g><rect x="-42" y="9" width="84" height="55" rx="14" fill="#f8fafc" stroke="#4c0519" stroke-width="6"/><path d="M-30 48 A34 34 0 0 1 30 48" fill="none" stroke="#facc15" stroke-width="7"/><g {ident("actor-bill-needle-pivot", styles)} transform="translate(0 48)"><g {ident("actor-bill-needle", styles)}><path d="M0 0 L0 -31" stroke="#4c0519" stroke-width="7" stroke-linecap="round"/></g></g><path d="M-58 12 Q-77 22 -47 42 M58 12 Q77 22 47 42" fill="none" stroke="#fb7185" stroke-width="15" stroke-linecap="round"/></g>"""


def actor_broombot(styles: dict[str, str]) -> str:
    return f"""    <g {ident("actor-broombot", styles)}><circle cy="-8" r="38" fill="#fbbf24" stroke="#78350f" stroke-width="6"/><rect x="-27" y="-20" width="54" height="30" rx="14" fill="#fef3c7" stroke="#78350f" stroke-width="5"/><circle cx="-13" cy="-5" r="7" fill="#0f172a"/><circle cx="13" cy="-5" r="7" fill="#0f172a"/><circle cy="36" r="18" fill="#64748b" stroke="#0f172a" stroke-width="6"/><g {ident("broombot-broom-pivot", styles)} transform="translate(31 8)"><g {ident("broombot-broom", styles)}><path d="M0 0 L47 58" stroke="#92400e" stroke-width="8" stroke-linecap="round"/><path d="M34 47 L65 39 M39 54 L70 48 M44 61 L73 58" stroke="#f59e0b" stroke-width="8" stroke-linecap="round"/></g></g></g>"""


def orbit_guardrails(suffix: str, styles: dict[str, str]) -> str:
    return f"""      <g transform="translate(150 305)"><g {ident(f"orbit-guardrails-{suffix}", styles)}><use href="#actor-orbit"/><g transform="translate(-42 -25)"><g id="actor-orbit-left-shoulder-pivot-{suffix}" transform="translate(0 0)"><g {ident(f"orbit-left-arm-{suffix}", styles)}><path d="M0 0 L-38 48" stroke="#e2e8f0" stroke-width="18" stroke-linecap="round"/><circle cx="-41" cy="51" r="12" fill="#67e8f9" stroke="#082f49" stroke-width="5"/></g></g></g><g transform="translate(42 -25)"><g id="actor-orbit-right-shoulder-pivot-{suffix}" transform="translate(0 0)"><g {ident(f"orbit-right-arm-{suffix}", styles)}><path d="M0 0 L42 45" stroke="#e2e8f0" stroke-width="18" stroke-linecap="round"/><circle cx="45" cy="48" r="12" fill="#67e8f9" stroke="#082f49" stroke-width="5"/><path d="M45 47 L69 70" stroke="#92400e" stroke-width="9"/><rect x="55" y="62" width="42" height="24" rx="6" fill="#94a3b8" stroke="#082f49" stroke-width="5"/></g></g></g></g></g>"""


def gate(styles: dict[str, str]) -> str:
    gate_frame = '<path d="M-118 142 V-92 H118 V142 M-118 -92 H118" fill="none" stroke="#cbd5e1" stroke-width="20" stroke-linecap="round"/><path d="M-92 -64 H92" stroke="#22d3ee" stroke-width="8"/>'
    gate_door = f'<g id="gate-door-pivot" transform="translate(0 -64)"><g {ident("gate-door", styles)}><g transform="translate(0 64)"><rect x="-91" y="-48" width="182" height="186" rx="10" fill="#1e3a5f" class="outline"/><path d="M-65 -18 H65 M-65 20 H65 M-65 58 H65 M-65 96 H65" stroke="#64748b" stroke-width="9"/></g></g></g>'
    gate_lights = f'<g {ident("prop-gate-lights", styles)} transform="translate(0 -120)"><g {ident("prop-gate-light-1", styles)} transform="translate(-48 0)"><circle r="16" stroke="#052e16" stroke-width="5"/></g><g {ident("prop-gate-light-2", styles)}><circle r="16" stroke="#052e16" stroke-width="5"/></g><g {ident("prop-gate-light-3", styles)} transform="translate(48 0)"><circle r="16" stroke="#052e16" stroke-width="5"/></g></g>'
    return (
        f'      <g {ident("prop-gate", styles)} transform="translate(405 274)">'
        f'<g {ident("gate-assembly", styles)}>'
        f"{gate_frame}{gate_door}{gate_lights}</g></g>"
    )


def style_block(tracks: tuple[Track, ...], snapshot: float | None) -> list[str]:
    lines = [
        "    .outline { stroke: #082f49; stroke-width: 6; stroke-linejoin: round; }",
        "    .rec-text, .end-text { fill: #ffffff; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-weight: 800; }",
        "    #reduced-motion-summary { display: none; }",
    ]
    if snapshot is not None:
        lines.append(
            "    /* Static snapshot: animation is represented by inline styles. */"
        )
        return lines
    animations: dict[str, list[str]] = {}
    seen: set[tuple[str, str]] = set()
    for target, prop, points in tracks:
        pair = (target, prop)
        if pair in seen:
            raise ValueError(f"duplicate animation track: {target} {prop}")
        seen.add(pair)
        name = f"track-{target}-{prop}"
        lines.append(f"    @keyframes {name} {{")
        for second, value in points:
            percentage = css_percentage(second)
            lines.append(f"      {percentage:.3f}% {{ {prop}: {css_value(value)}; }}")
        lines.append("    }")
        animations.setdefault(target, []).append(name)
    for target, names in animations.items():
        declarations = ", ".join(
            f"{name} 28s linear infinite" for name in names
        )
        lines.append(f"    #{target} {{ animation: {declarations}; }}")
    lines += ["    @media (prefers-reduced-motion: reduce) {", "      #movie { display: none; }", "      #reduced-motion-summary { display: inline; }", "    }"]
    return lines


def render(snapshot: float | None = None) -> str:
    validate_scenes()
    tracks = animation_tracks()
    validate_keyframe_percentages(tracks)
    styles = snapshot_styles(snapshot, tracks)
    desc = " ".join(scene[4] for scene in SCENES)
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 540" role="img" aria-labelledby="cartoon-title cartoon-desc">',
        '  <title id="cartoon-title">Orbit-infra: guardrails, proof, and a deliberate stop</title>',
        f'  <desc id="cartoon-desc">{html.escape(desc)}</desc>',
        "  <style>",
        *style_block(tracks, snapshot),
        "  </style>",
        "  <defs>",
        actor_pip(styles),
        actor_orbit(styles),
        actor_scout(styles),
        actor_bill(styles),
        actor_broombot(styles),
        "  </defs>",
        '  <rect width="960" height="540" fill="#0f172a"/>',
        f"  <g {ident('movie', styles)}>",
        f'    <g transform="translate(835 465)"><g {ident("prop-wallet", styles)}><path d="M-78 -50 H62 Q82 -50 82 -30 V50 H-78 Q-94 50 -94 32 V-32 Q-94 -50 -78 -50Z" fill="#a16207" class="outline"/><rect x="10" y="-18" width="82" height="44" rx="12" fill="#fbbf24" class="outline"/><g transform="translate(-72 -50)"><g {ident("wallet-flap-pivot", styles)} transform="translate(0 0)"><g {ident("wallet-flap", styles)}><path d="M0 0 H125 Q142 0 142 17 V38 H0Z" fill="#d97706" class="outline"/></g></g></g></g></g>',
        f'    <g transform="translate(850 342)"><g {ident("prop-coin-slot", styles)}><use href="#actor-bill"/></g></g>',
        f"    <g {ident('scene-problem', styles)}>",
        f'      <g transform="translate(102 275)"><g {ident("friend-hand", styles)}><path d="M-110 -28 H-10 L38 -58 Q54 -68 65 -53 Q72 -40 57 -28 L35 -10 L89 -2 Q108 2 105 19 Q102 34 84 32 L25 24 Q2 21 -14 8 H-110Z" fill="#f5c2a7" stroke="#7c2d12" stroke-width="6"/><path d="M-112 -30 H-38 V38 H-112Z" fill="#2563eb" stroke="#082f49" stroke-width="6"/></g></g>',
        f'      <g transform="translate(690 172)"><g {ident("prop-server-glow", styles)}><rect x="-76" y="-76" width="152" height="152" rx="22" fill="#164e63" class="outline"/><rect x="-48" y="-42" width="96" height="84" rx="14" fill="#22d3ee" stroke="#083344" stroke-width="6"/><path d="M-30 -20 H30 M-30 2 H30 M-30 24 H12" stroke="#ecfeff" stroke-width="8" stroke-linecap="round"/><circle cx="43" cy="24" r="9" fill="#facc15"/></g></g>',
        f'      <g {ident("prop-cloud", styles)} transform="translate(400 300)"><path d="M-185 38 C-218 -42 -116 -105 -42 -58 C-4 -146 145 -110 151 -18 C238 -12 246 110 143 116 H-142 C-231 111 -250 60 -185 38Z" fill="#dbeafe" class="outline"/></g>',
        f'      <g transform="translate(400 225)"><g {ident("pip-toss", styles)}><use href="#actor-pip"/></g></g>',
        f'      <g {ident("prop-leak", styles)}><g transform="translate(505 390)"><g {ident("leak-drip-1", styles)}><path d="M0 -18 C-15 2 -14 19 0 27 C14 19 15 2 0 -18Z" fill="#38bdf8" stroke="#075985" stroke-width="4"/></g></g><g transform="translate(545 400)"><g {ident("leak-drip-2", styles)}><path d="M0 -18 C-14 1 -13 18 0 26 C13 18 14 1 0 -18Z" fill="#38bdf8" stroke="#075985" stroke-width="4"/></g></g><g transform="translate(585 387)"><g {ident("leak-drip-3", styles)}><path d="M0 -18 C-15 2 -14 19 0 27 C14 19 15 2 0 -18Z" fill="#38bdf8" stroke="#075985" stroke-width="4"/></g></g></g>',
        f'      <g {ident("prop-coins", styles)}><g transform="translate(792 438)"><g {ident("coin-1", styles)}><circle r="17" fill="#facc15" class="outline"/><path d="M0 -9 V9" stroke="#854d0e" stroke-width="5"/></g></g><g transform="translate(807 446)"><g {ident("coin-2", styles)}><circle r="17" fill="#facc15" class="outline"/><path d="M0 -9 V9" stroke="#854d0e" stroke-width="5"/></g></g><g transform="translate(780 452)"><g {ident("coin-3", styles)}><circle r="17" fill="#facc15" class="outline"/><path d="M0 -9 V9" stroke="#854d0e" stroke-width="5"/></g></g></g>',
        "    </g>",
        f"    <g {ident('scene-guardrails', styles)}>",
        orbit_guardrails("behind", styles),
        gate(styles),
        orbit_guardrails("front", styles),
        f'      <g transform="translate(700 360)"><g {ident("cloud-guardrails", styles)}><path d="M-162 25 C-187 -43 -98 -90 -38 -52 C0 -126 126 -92 130 -17 C206 -9 211 91 124 98 H-124 C-199 94 -218 45 -162 25Z" fill="#dbeafe" class="outline"/><g transform="translate(-18 -72)"><g {ident("pip-seal-squash", styles)}><use href="#actor-pip"/></g></g><g {ident("prop-lease-timer", styles)} transform="translate(94 -116)"><circle r="52" fill="#f8fafc" class="outline"/><path d="M-22 -62 H22 M0 -62 V-50" stroke="#facc15" stroke-width="11" stroke-linecap="round"/><g {ident("prop-lease-timer-hand-pivot", styles)} transform="translate(0 0)"><g {ident("prop-lease-timer-hand", styles)}><path d="M0 0 V-34" stroke="#0f766e" stroke-width="9" stroke-linecap="round"/></g></g><circle r="8" fill="#0f766e"/></g><g transform="translate(24 -52)"><g {ident("prop-seal", styles)}><g {ident("seal-strike", styles)}><circle r="34" fill="#4ade80" class="outline"/><path d="M-17 0 L-5 15 L21 -18" fill="none" stroke="#052e16" stroke-width="9" stroke-linecap="round"/></g></g></g></g></g>',
        f'      <g transform="translate(370 443)"><g {ident("broombot-guardrails", styles)}><use href="#actor-broombot"/></g></g>',
        "    </g>",
        f"    <g {ident('scene-proof', styles)}>",
        f'      <g transform="translate(138 310)"><g {ident("scout-entry", styles)}><g id="scout-lean-pivot" transform="translate(0 0)"><g {ident("scout-lean", styles)}><g transform="scale(.8)"><use href="#actor-scout"/></g></g></g></g></g>',
        f'      <g {ident("prop-rec-reel-pivot", styles)} transform="translate(292 116)"><g {ident("prop-rec-reel", styles)}><circle r="52" fill="#e2e8f0" class="outline"/><circle cx="-21" cy="-13" r="11" fill="#082f49"/><circle cx="21" cy="-13" r="11" fill="#082f49"/><circle cy="25" r="11" fill="#082f49"/></g></g>',
        '      <rect x="359" y="82" width="84" height="52" rx="12" fill="#dc2626"/><text class="rec-text" x="401" y="117" text-anchor="middle" font-size="24">REC</text>',
        f'      <g transform="translate(250 190)"><g {ident("prop-permission-row-1", styles)}><rect width="235" height="28" rx="14" stroke="#052e16" stroke-width="4"/></g><g {ident("prop-permission-row-2", styles)} transform="translate(0 44)"><rect width="235" height="28" rx="14" stroke="#052e16" stroke-width="4"/></g><g {ident("prop-permission-row-3", styles)} transform="translate(0 88)"><rect width="235" height="28" rx="14" stroke="#052e16" stroke-width="4"/></g><g {ident("prop-permission-row-4", styles)} transform="translate(0 132)"><rect width="235" height="28" rx="14" stroke="#052e16" stroke-width="4"/></g></g>',
        f'      <g {ident("code-doc-nudge", styles)}><g transform="translate(490 180)"><g {ident("prop-code-card", styles)}><rect width="126" height="170" rx="16" fill="#dbeafe" class="outline"/><path d="M25 48 H101 M25 82 H82 M25 116 H96" stroke="#2563eb" stroke-width="11" stroke-linecap="round"/></g></g><g transform="translate(640 180)"><g {ident("prop-doc-card", styles)}><rect width="126" height="170" rx="16" fill="#fef3c7" class="outline"/><path d="M25 48 H101 M25 82 H92 M25 116 H103" stroke="#d97706" stroke-width="11" stroke-linecap="round"/></g></g></g>',
        f'      <g transform="translate(665 416)"><path d="M-44 16 H44 L30 62 H-30Z" fill="#475569" stroke="#0f172a" stroke-width="5"/><g {ident("prop-contract-lamp", styles)} transform="translate(0 -15)"><circle r="42" class="outline"/><circle r="18" fill="#ffffff" opacity=".5"/></g></g>',
        "    </g>",
        f"    <g {ident('scene-stop', styles)}>",
        f'      <g {ident("prop-runway", styles)}><path d="M145 455 L365 175 H745 L900 455Z" fill="#334155" stroke="#cbd5e1" stroke-width="8" stroke-dasharray="22 14"/></g>',
        '      <g id="proof-lights-stop" transform="translate(500 205)"><circle cx="-66" r="17" fill="#4ade80" stroke="#052e16" stroke-width="5"/><circle cx="-22" r="17" fill="#4ade80" stroke="#052e16" stroke-width="5"/><circle cx="22" r="17" fill="#4ade80" stroke="#052e16" stroke-width="5"/><circle cx="66" r="17" fill="#4ade80" stroke="#052e16" stroke-width="5"/></g>',
        f'      <g transform="translate(360 324)"><g {ident("runway-sparkle-1", styles)}><path d="M0 -18 L6 -6 L18 0 L6 6 L0 18 L-6 6 L-18 0 L-6 -6Z" fill="#fef08a"/></g></g><g transform="translate(570 290)"><g {ident("runway-sparkle-2", styles)}><path d="M0 -19 L6 -6 L19 0 L6 6 L0 19 L-6 6 L-19 0 L-6 -6Z" fill="#67e8f9"/></g></g><g transform="translate(730 385)"><g {ident("runway-sparkle-3", styles)}><path d="M0 -18 L6 -6 L18 0 L6 6 L0 18 L-6 6 L-18 0 L-6 -6Z" fill="#fef08a"/></g></g>',
        f'      <g transform="translate(155 336)"><use href="#actor-orbit"/><g transform="translate(-42 -25)"><g id="orbit-stop-left-shoulder-pivot" transform="translate(0 0)"><g id="orbit-stop-left-arm"><path d="M0 0 L-35 46" stroke="#e2e8f0" stroke-width="18" stroke-linecap="round"/><circle cx="-38" cy="49" r="12" fill="#67e8f9" stroke="#082f49" stroke-width="5"/></g></g></g><g transform="translate(42 -25)"><g id="orbit-rope-shoulder-pivot" transform="translate(0 0)"><g {ident("orbit-rope-arm", styles)}><path d="M0 0 L52 10" stroke="#e2e8f0" stroke-width="18" stroke-linecap="round"/><circle cx="56" cy="11" r="12" fill="#67e8f9" stroke="#082f49" stroke-width="5"/></g></g></g></g>',
        '      <g transform="translate(470 350)"><use href="#actor-pip"/></g>',
        f'      <g {ident("prop-velvet-rope", styles)}><path d="M205 455 V300 M825 455 V300" stroke="#facc15" stroke-width="22" stroke-linecap="round"/><circle cx="205" cy="300" r="17" fill="#facc15"/><circle cx="825" cy="300" r="17" fill="#facc15"/><path d="M205 317 Q515 470 825 317" fill="none" stroke="#e11d48" stroke-width="26" stroke-linecap="round"/></g>',
        f'      <g {ident("spectators", styles)}><g transform="translate(680 435)"><circle cy="-34" r="18" fill="#fde68a" class="outline"/><path d="M0 -16 V30" stroke="#60a5fa" stroke-width="18"/><g transform="translate(-7 -6)"><g id="spectator-1-left-pivot" transform="translate(0 0)"><g {ident("spectator-1-left-arm", styles)}><path d="M0 0 L-24 -24" stroke="#fde68a" stroke-width="9" stroke-linecap="round"/></g></g></g><g transform="translate(7 -6)"><g id="spectator-1-right-pivot" transform="translate(0 0)"><g {ident("spectator-1-right-arm", styles)}><path d="M0 0 L24 -24" stroke="#fde68a" stroke-width="9" stroke-linecap="round"/></g></g></g></g><g transform="translate(755 435)"><circle cy="-34" r="18" fill="#fbcfe8" class="outline"/><path d="M0 -16 V30" stroke="#a78bfa" stroke-width="18"/><g transform="translate(-7 -6)"><g id="spectator-2-left-pivot" transform="translate(0 0)"><g {ident("spectator-2-left-arm", styles)}><path d="M0 0 L-24 -24" stroke="#fbcfe8" stroke-width="9" stroke-linecap="round"/></g></g></g><g transform="translate(7 -6)"><g id="spectator-2-right-pivot" transform="translate(0 0)"><g {ident("spectator-2-right-arm", styles)}><path d="M0 0 L24 -24" stroke="#fbcfe8" stroke-width="9" stroke-linecap="round"/></g></g></g></g></g>',
        f'      <g {ident("prop-endcard", styles)}><rect x="205" y="52" width="550" height="112" rx="28" fill="#166534" stroke="#86efac" stroke-width="7"/><text class="end-text" x="480" y="119" text-anchor="middle" font-size="30">PROVED. STOPPED ON PURPOSE.</text></g>',
        f'      <g {ident("wipe-ring-pivot", styles)} transform="translate(400 300)"><g {ident("wipe-ring", styles)}><circle r="68" fill="#0f172a" stroke="#bae6fd" stroke-width="24"/></g><g {ident("wipe-cloud-outline", styles)}><path d="M-185 38 C-218 -42 -116 -105 -42 -58 C-4 -146 145 -110 151 -18 C238 -12 246 110 143 116 H-142 C-231 111 -250 60 -185 38Z" fill="#0f172a" stroke="#dbeafe" stroke-width="9"/></g></g>',
        "    </g>",
        "  </g>",
        f"  <g {ident('reduced-motion-summary', styles)}>",
        '    <rect x="25" y="92" width="215" height="356" rx="26" fill="#1e3a5f" class="outline"/><path d="M54 315 C38 257 98 226 140 252 C167 205 237 247 215 311Z" fill="#dbeafe" stroke="#082f49" stroke-width="5"/><rect x="82" y="166" width="110" height="88" rx="22" fill="#7dd3fc" stroke="#082f49" stroke-width="6"/><circle cx="112" cy="198" r="9" fill="#082f49"/><circle cx="162" cy="198" r="9" fill="#082f49"/><path d="M113 225 Q137 242 161 225" fill="none" stroke="#082f49" stroke-width="6"/>',
        '    <rect x="255" y="92" width="215" height="356" rx="26" fill="#1e3a5f" class="outline"/><path d="M292 370 V188 H430 V370 M292 188 H430" fill="none" stroke="#4ade80" stroke-width="18"/><rect x="320" y="225" width="82" height="108" rx="14" fill="#e2e8f0" stroke="#082f49" stroke-width="6"/><ellipse cx="361" cy="191" rx="53" ry="19" fill="none" stroke="#22d3ee" stroke-width="9"/><circle cx="333" cy="253" r="9" fill="#67e8f9"/><circle cx="389" cy="253" r="9" fill="#facc15"/>',
        '    <rect x="485" y="92" width="215" height="356" rx="26" fill="#1e3a5f" class="outline"/><ellipse cx="563" cy="285" rx="50" ry="64" fill="#a78bfa" stroke="#312e81" stroke-width="6"/><path d="M520 238 L535 191 L557 222 L584 191 L604 238" fill="#c4b5fd" stroke="#312e81" stroke-width="6"/><circle cx="548" cy="245" r="19" fill="#fff" stroke="#312e81" stroke-width="5"/><circle cx="579" cy="245" r="19" fill="#fff" stroke="#312e81" stroke-width="5"/><circle cx="605" cy="280" r="27" fill="none" stroke="#facc15" stroke-width="8"/><path d="M624 300 L646 324" stroke="#facc15" stroke-width="10"/>',
        '    <rect x="715" y="92" width="220" height="356" rx="26" fill="#1e3a5f" class="outline"/><path d="M740 395 L790 196 H850 L910 395Z" fill="#475569" stroke="#cbd5e1" stroke-width="6"/><path d="M746 282 Q824 390 907 282" fill="none" stroke="#e11d48" stroke-width="24"/><circle cx="824" cy="220" r="24" fill="#4ade80" stroke="#052e16" stroke-width="6"/><path d="M812 220 L822 232 L840 207" fill="none" stroke="#052e16" stroke-width="7"/>',
        "  </g>",
        "</svg>",
        "",
    ]
    return "\n".join(lines)


def render_transcript() -> str:
    lines = ["# Orbit-infra cartoon transcript", ""]
    for _scene_id, start, end, title, summary in SCENES:
        lines.append(f"- **{start}-{end} s, {title}.** {summary}")
    lines += ["", "End card: `PROVED. STOPPED ON PURPOSE.`", "", "Generated by `scripts/cartoon.py`.", ""]
    return "\n".join(lines)


def ensure_clean_generator(paths: tuple[str, ...]) -> None:
    try:
        result = subprocess.run(["git", "status", "--porcelain", "--", *paths], capture_output=True, text=True)
    except (OSError, FileNotFoundError):
        print("cartoon: git status failed; cannot verify the generator is committed", file=sys.stderr)
        raise SystemExit(1)
    if result.returncode != 0:
        print("cartoon: git status failed; cannot verify the generator is committed", file=sys.stderr)
        raise SystemExit(1)
    if not result.stdout.strip():
        return
    dirty = ", ".join(line[3:] for line in result.stdout.splitlines())
    print(f"cartoon: commit the generator before regenerating (dirty: {dirty})", file=sys.stderr)
    raise SystemExit(1)


def write_output(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def check_assets() -> int:
    expected = ((DEFAULT_SVG, render(), "cartoon"), (DEFAULT_TRANSCRIPT, render_transcript(), "transcript"))
    for path, content, label in expected:
        if not path.is_file():
            print(f"cartoon: {path} is missing", file=sys.stderr)
            return 1
        if content.encode() != path.read_bytes():
            print(f"cartoon: regenerate the {label}", file=sys.stderr)
            return 1
    return 0


def sha256(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"cartoon: {path} is missing")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_provenance(path: Path) -> None:
    ensure_clean_generator(("scripts/cartoon.py", "scripts/emblem.py"))
    try:
        result = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        print("cartoon: git rev-parse HEAD failed; cannot record provenance", file=sys.stderr)
        raise SystemExit(1)
    commit = result.stdout.strip()
    try:
        subprocess.run(
            [
                "git",
                "ls-files",
                "--error-unmatch",
                "scripts/cartoon.py",
                "scripts/emblem.py",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        print(
            "cartoon: generator paths are not tracked; cannot record provenance",
            file=sys.stderr,
        )
        raise SystemExit(1)
    rows = (("generator commit", commit), ("cartoon sha256", sha256(DEFAULT_SVG)), ("transcript sha256", sha256(DEFAULT_TRANSCRIPT)), ("emblem sha256", sha256(Path("docs/assets/emblem.svg"))), ("scene count", str(len(SCENES))), ("cycle seconds", str(CYCLE_SECONDS)), ("command", "python3 scripts/cartoon.py --provenance"))
    lines = ["# Cartoon provenance", "", "| field | value |", "| --- | --- |"]
    lines.extend(f"| {name} | {value} |" for name, value in rows)
    write_output(path, "\n".join((*lines, "")))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--transcript-output", type=Path)
    parser.add_argument("--snapshot", type=float)
    parser.add_argument("--scenes", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--provenance", action="store_true")
    parser.add_argument("--provenance-output", type=Path)
    args = parser.parse_args()
    if sum((args.scenes, args.check, args.provenance, args.snapshot is not None)) > 1:
        parser.error("--scenes, --check, --provenance, and --snapshot are exclusive")
    if (args.check or args.scenes) and any((args.output, args.transcript_output, args.provenance_output)):
        mode = "--check" if args.check else "--scenes"
        parser.error(f"{mode} cannot be combined with output options")
    if args.provenance_output is not None and not args.provenance:
        parser.error("--provenance-output requires --provenance")
    if args.provenance and (args.output is not None or args.transcript_output is not None):
        parser.error("--provenance cannot be combined with cartoon outputs")
    if args.snapshot is not None and (not math.isfinite(args.snapshot) or args.snapshot < 0):
        parser.error("--snapshot must be finite and nonnegative")
    if args.snapshot is not None and args.output is None:
        parser.error("--snapshot requires --output")
    if args.snapshot is not None and args.transcript_output is not None:
        parser.error("--snapshot cannot be combined with --transcript-output")
    return args


def main() -> int:
    args = parse_args()
    try:
        validate_scenes()
    except ValueError as error:
        print(f"cartoon: {error}", file=sys.stderr)
        return 1
    if args.scenes:
        for scene_id, start, end, _title, _summary in SCENES:
            print(scene_id, start, end)
        return 0
    if args.check:
        return check_assets()
    if args.provenance:
        write_provenance(args.provenance_output or DEFAULT_PROVENANCE)
        return 0
    if args.snapshot is not None:
        write_output(args.output, render(args.snapshot))
        return 0
    if not (args.output is not None and args.transcript_output is not None):
        ensure_clean_generator(("scripts/cartoon.py",))
    write_output(args.output or DEFAULT_SVG, render())
    write_output(args.transcript_output or DEFAULT_TRANSCRIPT, render_transcript())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
