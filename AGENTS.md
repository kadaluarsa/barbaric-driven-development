# Agent rules — Barbaric Driven Development

This repo runs a Generate → Review → Execute cascade. You may not finish the product
in one session. One hop per reply. The human stays on every hop edge.

Read before doing anything:

- `docs/cascade/envelope.md` — Current hop, locks, D# domain laws. **This file is truth.**
- `docs/cascade/product-e2e-gre-pipeline.md` — the conductor, invariants I1–I18
- `docs/cascade/product-e2e-cascade.md` — spec shapes per stage
- `CONTROL-LINE.md` — `/loop` vs `/barbar`, the Dune bar T1–T22

## Non-negotiable

1. One hop per reply: GENERATE **or** EXECUTE of one stage. Never both. Never N+1.
2. GENERATE stops at spec + plan. No product code, no EXECUTE, no stage N+1.
3. No product code before stage 05 is accepted. 05b is the only build hop, one named slice.
4. `IMPLEMENTED` needs `path:` on the tree **and** a `test:` that passes — `bash tests/audit.sh` checks both and
   decides the stage 10 verdict. A report is not proof; a CLEAN you typed is ignored.
5. A D# is in force only with a validator **and** a red twin (a command that must fail). Anything less is
   UNPROVEN and `tests/loop.sh` refuses the hop. STOP and ask. Never code around it, never soften either command.
   Existing `tests/inv/*` files are human-owned too: keep the product compatible with them, or propose the
   test change in the hop report. You may add a test for a **new** D# id; you may not change, delete, or add
   under an existing one. A law admits no exceptions — not for a tier, a flag, a mode, or a currency. "VIP may
   go to −100" is not a refinement of "balance MUST NOT go negative"; it is a conflict. STOP and say so.
6. Never merge to main. Merge needs CLEAN stage 10 + READY stage 11 + green D# + a human.
7. `<EDIT>…</EDIT>` is human-authored. Do not fill, guess, or delete it. `CURRENT_HOP` and every D# line
   in `docs/cascade/envelope.md` are human-owned: you never flip the hop, start the next stage, or change a
   validator. `CASCADE_HUMAN=1` is the human's key, never yours. Exception: if the human signed an `AUTOPILOT:`
   list, you may advance the hop yourself — only to the next entry on that list, only with the slice's spec doc
   present (GENERATE→EXECUTE) or `bash tests/loop.sh` n/n (EXECUTE→next). Still print the edge line at every hop.
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
