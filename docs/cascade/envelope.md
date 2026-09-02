# Stitch envelope

This file is the memory of the cascade. It lives in git. Chat and `/memory` are caches of it.

## Hop state (machine-read)

These lines are parsed by `.githooks/`, `.claude/hooks/`, `tests/loop.sh`, and `tests/barbar.sh merge`.
Only a human changes them, at a hop edge. `NONE` means no cascade is running.

CURRENT_HOP: NONE
CURRENT_STAGE:
CURRENT_SLICE:

## Domain laws (machine-read)

One per line: `D# | law | validator command`. A D# with no validator, `TODO`, or `none`
is **not in force** (I13) — the agent must STOP and ask, not code around it. Once in
force, `tests/loop.sh` fails any hop that omits it and `tests/barbar.sh merge` refuses
while it is red.

D1 | <EDIT>{{balance MUST NOT go negative}}</EDIT> | TODO

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
