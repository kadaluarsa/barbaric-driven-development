# Stitch envelope

This file is the memory of the cascade. It lives in git. Chat and `/memory` are caches of it.

## Hop state (machine-read)

These lines are parsed by `.githooks/`, `.claude/hooks/`, `tests/loop.sh`, and `tests/barbar.sh merge`.
They are **human-owned by mechanism**: `pre-commit` and `hop_guard` reject any agent change to them.
A human commits a hop edge with `CASCADE_HUMAN=1 git commit …` — that key is denied to the agent.
`NONE` means no cascade is running.

<EDIT>
CURRENT_HOP: NONE
CURRENT_STAGE:
CURRENT_SLICE:
</EDIT>

## Domain laws (machine-read)

One per line: `D# | law | validator command | red twin command`. The **red twin** is the PRD's
"bad example" made executable: a command that MUST exit non-zero (e.g. `INV_MUTANT=D1 pytest tests/inv/test_D1.py`).
A D# is **in force** only when it has both (I13 + red twin). `tests/dsharp_strength.sh` scores each law
GREEN / RED / THEATER (twin passed — the validator cannot fail) / UNPROVEN. An UNPROVEN law blocks
`tests/loop.sh` until the human completes it or records `WAIVE_DSHARP:` in `goal.md`; anything but GREEN
refuses `tests/barbar.sh merge`.

Whole D# lines are human-owned (same mechanism). The agent proposes laws in the PRD; the human writes them here.

<EDIT>
D1 | {{balance MUST NOT go negative}} | TODO | TODO
</EDIT>

## Locked decisions
<EDIT>
- {{decision}} — locked {{date}}
</EDIT>

## Stage state
<EDIT>
- 01: spec {{draft|accepted}} / execute {{not-started|draft|accepted}}
- 05b slices: {{slice: spec/execute}}
</EDIT>

## Artifacts accepted (paths, PRs)
<EDIT>
- {{path}} — from stage {{N}} — accepted {{date}}
</EDIT>
