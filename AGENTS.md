# Agent rules — Barbaric Driven Development

This repo runs a Generate → Review → Execute cascade. You may not finish the product
in one session. One hop per reply. The human stays on every hop edge.

Read before doing anything:

- `docs/cascade/envelope.md` — Current hop, locks, D# domain laws. **This file is truth.**
- `docs/cascade/product-e2e-gre-pipeline.md` — the conductor, invariants I1–I18
- `docs/cascade/product-e2e-cascade.md` — spec shapes per stage
- `CONTROL-LINE.md` — `/loop` vs `/barbar`, the Dune bar T1–T15

## Non-negotiable

1. One hop per reply: GENERATE **or** EXECUTE of one stage. Never both. Never N+1.
2. GENERATE stops at spec + plan. No product code, no EXECUTE, no stage N+1.
3. No product code before stage 05 is accepted. 05b is the only build hop, one named slice.
4. `IMPLEMENTED` needs a path on the tree **and** a named test. A report is not proof.
5. A D# with no validator command is not in force. STOP and ask. Never code around it.
6. Never merge to main. Merge needs CLEAN stage 10 + READY stage 11 + green D# + a human.
7. `<EDIT>…</EDIT>` is human-authored. Do not fill, guess, or delete it.
8. Durable truth is `docs/cascade/` in git. If it is not committed, it was not decided.

## Commands are scripts, not prose

| You want | Run | Never |
|---|---|---|
| this hop's loop | `bash tests/loop.sh` | type `LOOP k/n` yourself |
| the eval farm | `bash tests/barbar.sh` | type `BARBAR k/n` yourself |
| the merge gate | `bash tests/barbar.sh merge` | merge or push to `main` yourself |

## Ending every reply

Print the invariant block, then exactly one of:

- `STITCH NEEDED: review spec+plan for stage N`
- `STITCH NEEDED: accept execute for stage N, or send back`

Then stop.

## What enforces this

These rules are advisory. The bar is not: git hooks reject product writes on a GENERATE
hop and any `<EDIT>` change; CI runs the farm and every D# validator; main is protected.
On Claude Code, `.claude/hooks/` also denies the tool call itself. You cannot talk past
any of these. Do not weaken a layer to make a hop pass (I18).
