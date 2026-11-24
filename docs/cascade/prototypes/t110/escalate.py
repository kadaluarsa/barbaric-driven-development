#!/usr/bin/env python3
"""Lesson escalation (t110): a signed lesson whose event keeps happening after its day is evidence that a prompt
line is not enough. tests/patterns.sh measures each lesson; this module decides ESCALATE and drafts a brief for a
check (a hook rule or a test) that refuses the event. It reads numbers and returns text: it never writes a file,
never signs and never builds. The human signs the draft into docs/cascade/05b-briefs.md, or drops it.

    escalate(b, a, hb, ha, mark)  True when the lesson is marked ESCALATE
    line(...)                     the ESCALATE report line
    brief(...)                    the --propose draft brief line
"""
from __future__ import annotations

MIN_HOPS = 3      # after-window hops before a lesson can be marked: fewer is too little evidence
MIN_EVENTS = 2    # events in the after-window that mark a lesson
RATE_HOPS = 10    # after-window hops before one event, at a rate not below the before-rate, marks it


def escalate(b: int, a: int, hb: int, ha: int, mark: str) -> bool:
    """b, a: events before and after the lesson's day; hb, ha: hops before and after; mark: the measure() mark."""
    if ha < MIN_HOPS or mark in ("NO MATCH", "SETTLED"):
        return False
    if a >= MIN_EVENTS:
        return True
    return ha >= RATE_HOPS and hb > 0 and a > 0 and a * hb >= b * ha


def line(lid: int, actor: str, verdict: str, a: int, ha: int) -> str:
    hops = "hop" if ha == 1 else "hops"
    return (f"ESCALATE L{lid}  {actor} {verdict}  after: {a} in {ha} {hops}"
            "  a prompt line is not enough: tests/patterns.sh --propose drafts a check")


def brief(lid: int, actor: str, verdict: str, prefix: str, on: str, do: str,
          b: int, a: int, hb: int, ha: int, today: str) -> str:
    return (f"BRIEF  - lesson-l{lid}-check: [feature] drafted {today} by tests/patterns.sh --propose from lesson L{lid}."
            f' The event {actor} {verdict} "{prefix}" happened {a} times in {ha} hops after {on}'
            f' ({b} in {hb} hops before), so the prompt line "{do}" is not enough.'
            " Build a check (a hook rule or a test) that refuses this event."
            " Done when a test shows the event is refused."
            f" Out of scope: changing or removing lesson L{lid}.")
