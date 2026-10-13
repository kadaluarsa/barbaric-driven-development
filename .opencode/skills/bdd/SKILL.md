---
name: BDD
name: Barbaric Driven Development
description: BDD cascade — Generate → Review → Execute with laws as red tests, machine-computed gates, and approve-to-sign hop edges. Use when building features inside a BDD-governed repository.
---

# BDD — Barbaric Driven Development

This repo runs a **Generate → Review → Execute** cascade. The human stays on every hop edge.

## Read before working

- `references/cascade/envelope.md` — D# domain laws, locked decisions, accepted artifacts. **Truth.**
- `references/cascade/hop-state.md` — current hop, stage, slice, AUTOPILOT list.
- `references/cascade/product-e2e-gre-pipeline.md` — the conductor, invariants I1–I18.
- `references/cascade/product-e2e-cascade.md` — the stage index.
- `references/control-line` — `/loop` vs `/barbar`, the Dune bar.
- `references/agents` — AGENTS.md rules.

## Key commands

| Command | What it does |
|---|---|
| `/loop` | `bash tests/loop.sh` — run this hop's GRE loop. Legal only on EXECUTE (05b/06–09/10 punch). Prints `LOOP k/n`. |
| `/barbar` | `bash tests/barbar.sh` — eval farm. `merge` → merge gate. `auto` → autopilot. `init` → first-knowledge discovery. |
| `/audit` | `bash tests/audit.sh` — score stage 10 from the tree. |
| `/doctor` | `bash tests/doctor.sh` — check the pipeline is working. |
| `/dsharp` | `bash tests/dsharp_strength.sh` — score domain invariants D#. |
| `/critique` | `bash tests/critique.sh` — 05b spec critic gate. |
| `/diverge` | `bash tests/diverge.sh` — 05b divergence checker. |
| `/enforce` | `bash tests/enforcement.sh` — I18 enforcement suite T8–T61. |
| `/goal` | Write `docs/cascade/goal.md` and run `/loop`. |

## Non-negotiable rules

1. One hop per reply: GENERATE **or** EXECUTE of one stage. Never both. Never N+1.
2. GENERATE stops at spec + plan. No product code, no EXECUTE, no stage N+1.
3. No product code before stage 05 is accepted. 05b is the only build hop, one named slice.
4. IMPLEMENTED needs a path on the tree **and** a passing test. `bash tests/audit.sh` checks both. Chat is not proof.
5. A D# is in force only with a validator **and** a red twin (a command that must fail). Anything less is UNPROVEN and `tests/loop.sh` refuses the hop. STOP and ask — never code around it.
6. Never merge to main. Merge needs CLEAN stage 10 + READY stage 11 + green D# + a human.
7. `<EDIT>…</EDIT>` is human-authored. Do not fill, guess, or delete it.
8. Commands are scripts, not prose: `/loop` = `bash tests/loop.sh`. Never type `LOOP k/n` or `BARBAR k/n` yourself.
9. A law admits no exceptions — not for a tier, a flag, a mode, or a currency. STOP if asked to carve one.

## Enforcement layers (I18)

| Layer | Mechanism | Binds |
|---|---|---|
| 0 | CI + branch protection (`.github/workflows/`) | all agents |
| 1 | git hooks (`.githooks/`) | all agents |
| 2 | agent hooks (`.claude/hooks/`) | Claude Code only |
| 3 | prose (`AGENTS.md`) | all agents (advisory) |

## Install

```bash
# Standalone (works with any agent including OpenCode)
git clone https://github.com/kadaluarsa/barbaric-driven-development.git ~/tools/bdd
cd your-repo
bash ~/tools/bdd/install.sh .
```

The `.opencode/` directory provides commands and references. For full Layer 2 enforcement (approve-to-sign, stop guards), use Claude Code with the `.claude-plugin/`.
