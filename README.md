# Barbaric Driven Development

A Generate → Review → Execute product cascade with a verify/CI control line — enforced in layers, not in prose.

Do not trust chat. Prove it on the tree. Domain laws (D#) are merge-bar tests. The human stays on every hop edge.

This pack is how you run a product from intake to production-grade **without** letting a coding agent skip hops, execute while generating, or auto-merge before CLEAN 10 + 11 READY.

100% match of the [verify/CI talk](https://www.youtube.com/watch?v=Cmoh-yR-usA&t=2466s) means a **red test**, not a stronger prompt (I17). Where that test lives is I18: CI, then git hooks, then agent hooks, then — last — the rules file.

## Quick start

```bash
bash install.sh /path/to/your-product-repo     # all four layers, idempotent
```

Then fill `docs/cascade/envelope.md`, name your D# with validator commands, protect `main`. Details: [`INTEGRATION.md`](INTEGRATION.md).

Works with Claude Code, Codex, Cursor, Copilot, Gemini CLI, Aider, Windsurf, and anything that commits through git. Enforcement strength differs per agent — the doc says exactly how, and ships probes to measure it.

## Enforcement layers (I18)

| Layer | Mechanism | Binds | Agents |
|---|---|---|---|
| 0 | CI + branch protection | yes, non-bypassable | all |
| 1 | git hooks — `.githooks/` | yes, locally | all |
| 2 | agent hooks — `.claude/hooks/` | yes, at the tool call | Claude Code |
| 3 | rules — `AGENTS.md` + shims | no | all |

Commands are scripts. `/loop` is `bash tests/loop.sh`. `/barbar` is `bash tests/barbar.sh`. `LOOP k/n` and `BARBAR k/n` are machine output; the agent never types them.

## Two loops (I16)

Do not mix them.

| Command | Whose | Does |
|---------|-------|------|
| `/loop` | Ours (GRE) | One approved execute. `goal.md` = ACs + every in-force D#. `tests/loop.sh` prints `LOOP k/n`, refuses on GENERATE, fails an omitted D#. Stop at hop edge. |
| `/barbar` | Hers (eval farm) | `tests/barbar.sh` hill-climbs control-line evals to `BARBAR n/n`. No product stages. `merge` runs the farm and every D# validator, then the CLEAN 10 + 11 READY gate. |

A prompt like "create feature on A based on B using C" is a GENERATE hop. It is not `/barbar`.

## Sequence

```
GENERATE  → spec+plan → STITCH NEEDED
you: approved, execute stage N
EXECUTE   → goal.md = ACs + D# → bash tests/loop.sh → LOOP n/n → /diff
you: accepted, generate stage N+1
… later, CLEAN 10 + 11 READY …
bash tests/barbar.sh        → BARBAR n/n
bash tests/barbar.sh merge  → ALLOWED
```

Control lines (type these; do not paraphrase into a one-shot):

- `generate stage N`
- `approved, execute stage N`
- `accepted, generate stage N+1`
- `send back:`
- `generate 05b slice K`
- `promote ID:` / `reject ID as drift`
- `/loop` / `/barbar` / `/barbar merge`

`<EDIT>…</EDIT>` is human. The agent must not fill, guess, or delete those tags — and `pre-commit` rejects the commit if it does.

## Stages

00 Intake → 01 Problem → 02 Users → 03 PRD → 04 UX → 05 Tech → **05b** one named P0 slice per hop → 06 Sec → 07 Test → 08 SLOs → 09 Launch → **10 Feature Audit** → **11 PRR**.

Production-grade = CLEAN 10 + 11 READY + green D#. 01–04 are evidence/design, not the app. The app starts at 05b.

Greenfield and brownfield use the same commands. Brownfield execute may only stitch a named slice onto the existing tree.

## The bar — T1–T16

If a T# is missing or red, the statement that we match that lever is false.

| ID | Lever | Evidence |
|----|-------|----------|
| T1 | Skill hard-stop | `skills/barbar/SKILL.md`; `hop_guard.py` and `pre-commit` deny the write |
| T2 | Evals | `tests/score_hops.py` — fixtures, and `--tree` for real reports |
| T3 | Hard CI | `.github/workflows/control-line.yml`, no `continue-on-error` |
| T4 | Loop until n/n | `tests/barbar.sh` exits non-zero unless k=n |
| T5 | Auto-merge on green | `merge` refuses on this repo, on `dirty-product`, on `dsharp-red-product`; allows on `ready-product` |
| T6 | Don't trust chat | per-row `path:` + `test:`; resolved on the tree with `--tree` |
| T7 | Verify before next | `fail-generate-executed.md`, `fail-started-nplus1.md`, `stop_guard.py` |
| T8–T11 | git hooks | `tests/enforcement.sh` — real commits in throwaway repos |
| T12–T13 | `tests/loop.sh` | refuses on GENERATE; omitted D# is a FAIL entry |
| T14 | farm fails closed | dead scorer → red; `merge` runs the farm first |
| T15 | Claude hooks | deny, block, re-inject — exercised via stdin JSON |

```bash
bash tests/enforcement.sh     # T8–T16
bash tests/barbar.sh          # BARBAR k/n; exit 1 unless k=n
bash tests/barbar.sh merge    # REFUSED on this pack repo
```

CI runs all of it. Product D# as required checks live in the **product** repo, not here.

## Layout

```
AGENTS.md                       canonical rules (Layer 3); CLAUDE.md / GEMINI.md / .cursor / copilot are shims
CONTROL-LINE.md                 /loop vs /barbar, I18 layers, T1–T16
INTEGRATION.md                  the four layers, per-agent matrix, probes
AUDIT.md                        pre-I18 audit and what changed
install.sh                      one-command wire-up for a product repo
.githooks/                      Layer 1 — pre-commit, pre-push
.claude/hooks/                  Layer 2 — hop_guard, bash_guard, stop_guard, preserve
.claude/settings.json           Layer 2 wiring
docs/cascade/                   spec pack, GRE conductor, envelope.md, goal.md
evals/hops/                     hop-report fixtures
evals/fixtures/                 ready / dirty / dsharp-red products for the merge gate
skills/barbar/SKILL.md          farm-only skill (Claude Code)
tests/lib/                      cascade.sh (state reader), edit_tags.py
tests/loop.sh                   /loop
tests/barbar.sh                 /barbar and /barbar merge
tests/score_hops.py             hop scorer
tests/control-line.sh           pack-law greps (I15–I18)
tests/i17_dune.sh               T1–T7
tests/enforcement.sh            T8–T16
.github/workflows/              Layer 0
```

## What this is not

- Not a "make A from B using C" build skill.
- Not Superpowers. Superpowers is craft on code-execute hops. Cascade outranks it (I14).
- Not permission to auto-merge `main` because chat said the tests passed.
- Not a prompt. The prompt is the weakest layer, and it says so.
