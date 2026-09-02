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

One per line: `D# | law | validator command`. A D# with no validator, `TODO`, or `none`
is **not in force** (I13) — the agent must STOP and ask, not code around it. Once in
force, `tests/loop.sh` fails any hop that omits it and `tests/barbar.sh merge` refuses
while it is red.

Whole D# lines are human-owned (same mechanism). The agent proposes laws in the PRD; the human writes them here.

<EDIT>
D1 | {{balance MUST NOT go negative}} | TODO
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
