# Agent rules — Barbaric Driven Development

This repo runs a Generate → Review → Execute cascade. You may not finish the product
in one session. One hop per reply. The human stays on every hop edge.

Read before doing anything:

- `docs/cascade/hop-state.md` — current hop, stage, slice, `AUTOPILOT:` list.
- `docs/cascade/envelope.md` — D# domain laws, locked decisions, accepted artifacts. **These two are truth.**
  A repo installed before the split keeps both in `envelope.md`; every reader falls back to it.
- `docs/cascade/product-e2e-gre-pipeline.md` — the conductor, invariants I1–I18
- `docs/cascade/product-e2e-cascade.md` — the stage index; the spec shape for the stage you are on
  lives in `docs/cascade/stages/<NN>-*.md`. Load that one, not all twelve.
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
   in `docs/cascade/hop-state.md` (or `envelope.md` before the split) are human-owned: you never flip the hop, start the next stage, or change a
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

## Ending a hop reply

**Only when a hop is running** — `CURRENT_HOP:` in `docs/cascade/hop-state.md` is `GENERATE` or
`EXECUTE`. Print exactly one of:

- `STITCH NEEDED: review spec+plan for stage N` — with N the real stage, never the letter `N`
- `STITCH NEEDED: accept execute for stage N, or send back`

Then stop.

Do **not** reprint I1–I18 at a hop edge. They are pipeline rules, identical in every repo that
installs this pack, and `preserve.py` re-injects them on compact/clear/resume — the case the reprint
existed for — while `seam.py` carries the hop context on every prompt. Repeating ~1.2 KB of unchanged
process rules at every edge buries the two things that *are* specific to this hop: the evidence and
the edge line. Reprint the full block only when the session was just compacted, cleared, resumed,
rewound or switched models, where it is a live check that preservation worked. What is worth stating
at an edge is the product's own law — the D# in force with their validators and GREEN/RED — because
that is per-repo and can change. `NO LAW IN FORCE` is a complete and honest answer when it is true.

When no hop is running, end the reply normally: no edge line. A question,
an explanation, a status check or a refusal is not a hop, and an edge line printed over one is
noise that makes the real edge easier to miss. The Stop hook draws the same boundary — it is
silent unless the envelope says a hop is open.

## What enforces this

These rules are advisory. The bar is not: git hooks reject product writes on a GENERATE
hop and any `<EDIT>` change; CI runs the farm and every D# validator; main is protected.
On Claude Code, `.claude/hooks/` also denies the tool call itself. You cannot talk past
any of these. Do not weaken a layer to make a hop pass (I18).
