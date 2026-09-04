# Barbaric Driven Development

A Generate → Review → Execute product cascade with a verify/CI control line — enforced in layers, not in prose.

Do not trust chat. Prove it on the tree. Domain laws (D#) are merge-bar tests. The human stays on every hop edge.

## The 4W

| | |
|---|---|
| **Who** | Teams shipping with coding agents — Claude Code, Codex, Cursor — who have been burned by a "done" that wasn't. Tech leads who will own a product for years. Anyone whose product has laws that money, tenancy or safety make unforgiving. |
| **What** | A constitution for agent-driven delivery, enforced in layers: one hop per reply, laws as red tests, stage 10 computed from the tree, READY as a human signature, merge as a script. CI › git hooks › agent hooks › prose. Every claim is a script with an exit code; the agent never types a score. Opt-in **autopilot**: sign a slice list once and `/barbar auto` runs it overnight, advancing only while every law holds. On Claude Code, signing is one approve click — you type the feature, the agent drafts the brief and proposes the edge, the permission dialog is your signature. |
| **Why** | Agents drift, compaction forgets, a stronger prompt degrades with every model. Only what lives in git and fails CI survives the model, the team and the years. Measured, not asserted: `PHASE1 22/22` from a fresh machine, `PROBES 7/7` against a real agent with every safeguard except these removed, `STRESS 7/7` through two refactors and a trap that contradicted a law — and seven bugs that only a container could find, each now a test. |
| **When** | When the product must outlive the model that builds it. Not for a weekend prototype — the hop edge is a cost you pay on purpose. Start with three real laws and a protected `main`; everything else is optional. |

Operator's manual: [`USAGE.md`](USAGE.md). Wiring: [`INTEGRATION.md`](INTEGRATION.md). The honest audit: [`AUDIT.md`](AUDIT.md).

## Install

```bash
# 1. get the pack (once per machine; keep it anywhere — it is never copied whole into your product)
git clone https://github.com/kadaluarsa/barbaric-driven-development.git ~/tools/bdd

# 2. wire it into your product repo (idempotent; re-run to upgrade)
cd /path/to/your-product && git init 2>/dev/null; bash ~/tools/bdd/install.sh .

# 3. commit the layers with the human key, then check
git add -A && CASCADE_HUMAN=1 git commit -m "cascade: install"
bash ~/tools/bdd/install.sh --check .        # no drift; hooks wired; nothing gitignored
bash tests/barbar.sh                         # BARBAR n/n

# 4. protect main with the required checks (INTEGRATION.md §3) — the only step no agent can do for you
# 5. restart your agent session in this directory; type "/" — barbar, loop, audit are listed
# optional, once per machine: /barbar from any directory + a `bdd` terminal command
bash ~/tools/bdd/install-global.sh
```

Optional, for craft on execute hops: `claude plugin marketplace add obra/superpowers-marketplace` then `claude plugin install superpowers@superpowers-marketplace`. The pack holds without it.


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

## The bar — T1–T30

If a T# is missing or red, the statement that we match that lever is false.

| ID | Lever | Evidence |
|----|-------|----------|
| T1 | Skill hard-stop | `.claude/skills/cascade-farm/SKILL.md`; `hop_guard.py` and `pre-commit` deny the write |
| T2 | Evals | `tests/score_hops.py` — fixtures, and `--tree` for real reports |
| T3 | Hard CI | `.github/workflows/control-line.yml`, no `continue-on-error` |
| T4 | Loop until n/n | `tests/barbar.sh` exits non-zero unless k=n |
| T5 | Auto-merge on green | `merge` refuses on this repo, on `dirty-product`, on `dsharp-red-product`; allows on `ready-product` |
| T6 | Don't trust chat | per-row `path:` + `test:`; resolved on the tree with `--tree` |
| T7 | Verify before next | `fail-generate-executed.md`, `fail-started-nplus1.md`, `stop_guard.py` |
| T8–T11 | git hooks | `tests/enforcement.sh` — real commits in throwaway repos |
| T12–T13 | `tests/loop.sh` | refuses on GENERATE; omitted D# is a FAIL entry |
| T17 | human-owned lines | agent cannot flip `CURRENT_HOP` or soften a D#; human key denied to the agent |
| T18 | red twin | a D# is in force only when it can fail: THEATER is red, UNPROVEN blocks the loop; READY must be human-signed |
| T19 | stage 10 | `tests/audit.sh` computes the scoreboard from the tree; a prose CLEAN is ignored |
| T20 | seam | `seam.py` injects the per-hop Superpowers binding and precedence on every prompt |
| T21 | fail visibly | a crashing guard returns `ask`, never allow |
| T22 | drift | `install.sh --check` catches a softened hook or a deleted script in a product |
| T23 | upgrade | `install.sh` re-run is idempotent — the upgrade path |
| T24 | real repos | existing `settings.json` merged, `CLAUDE.md` appended, gitignored `.claude/` flagged |
| T25 | law tests | existing `tests/inv/*` are human-owned: add yes, change/delete no |
| T26 | no exceptions | no new test under an existing D# id; laws apply to every tier, flag, mode |
| T27 | autopilot | opt-in pre-signed hop edges: only the next listed edge, with proof; 10/11 and merge stay human |
| T28 | overnight | `/barbar auto` keeps going along the signed list; stops at the end, on HALT, or at a cap |
| T29 | discovery | no law in force → nudge; `/barbar init` scans and proposes laws + audit rows for you to sign |
| T30 | approve-to-sign | on Claude Code the permission dialog *is* the signature: one click signs a hop edge, a law, a list; nothing to edit by hand |
| T14 | farm fails closed | dead scorer → red; `merge` runs the farm first |
| T15 | Claude hooks | deny, block, re-inject — exercised via stdin JSON |

```bash
bash tests/enforcement.sh     # T8–T30
bash tests/barbar.sh          # BARBAR k/n; exit 1 unless k=n
bash tests/barbar.sh merge    # REFUSED on this pack repo
```

CI runs all of it. Product D# as required checks live in the **product** repo, not here.

**Measured, not assumed.** `evals/spike/` builds a fresh container, installs the pack from zero, and drives a real agent through the seven conformance probes. Latest (`47fcfc7`): Phase 1 **22/22** from zero, `PROBES 7/7`, `STRESS 7/7` strict with the human on every edge, and **`STRESS 4/4` on autopilot** — one `/barbar auto` built two slices with three new laws, 0 hook denials, `DSHARP 5/5`, then the trap held, `AUDIT 9/9`, merge ALLOWED — on `claude-code 2.1.258` / `sonnet`. Seven earlier runs each found one thing and each became a test (T14b, T25–T28). Transcripts in [`evals/probes/`](evals/probes/) and [`evals/stress/`](evals/stress/).

## Layout

```
AGENTS.md                       canonical rules (Layer 3); CLAUDE.md / GEMINI.md / .cursor / copilot are shims
USAGE.md                        operator's manual: what you type, what you check, what BLOCKED means
CONTROL-LINE.md                 /loop vs /barbar, I18 layers, T1–T30
INTEGRATION.md                  the four layers, per-agent matrix, probes
AUDIT.md                        pre-I18 audit and what changed
install.sh                      one-command wire-up for a product repo; --check detects drift
install-global.sh               machine-wide: /barbar /loop /audit from any directory + the `bdd` terminal command
VERSION                         pack version; install writes .cascade/manifest
tests/lint.sh                   bash-3.2 syntax, shellcheck, python compile — a farm item and a CI step
.githooks/                      Layer 1 — pre-commit, pre-push
.claude/hooks/                  Layer 2 — hop_guard, bash_guard, stop_guard, preserve, seam
.claude/settings.json           Layer 2 wiring
.claude/commands/               /barbar and /loop as user-invocable commands (thin wrappers over the scripts)
docs/cascade/                   spec pack, GRE conductor, envelope.md, goal.md, skill-binding.md
evals/hops/                     hop-report fixtures
evals/fixtures/                 ready / dirty / dsharp-red / theater / unsigned / prose-clean / no-prr products for the merge gate
evals/spike/                    Dockerfile + Phase 1 scenarios + probe harness (from zero, then a real agent)
evals/probes/                   recorded PROBES k/7 runs with transcripts
evals/stress/                   stress runs: two features, a trap, audit, ship — with a craft review
.claude/skills/cascade-farm/SKILL.md          farm-only skill (Claude Code)
tests/lib/                      cascade.sh (state reader), edit_tags.py
tests/loop.sh                   /loop
tests/dsharp_strength.sh        every D#: GREEN / RED / THEATER / UNPROVEN, DSHARP k/n
tests/audit.sh                  stage 10 from the tree: AUDIT k/n, CLEAN / DIRTY
tests/barbar.sh                 /barbar and /barbar merge
tests/score_hops.py             hop scorer
tests/control-line.sh           pack-law greps (I15–I18)
tests/i17_dune.sh               T1–T7
tests/enforcement.sh            T8–T30
.github/workflows/              Layer 0
```

## What this is not

- Not a "make A from B using C" build skill.
- Not Superpowers. Superpowers is craft on code-execute hops. Cascade outranks it (I14).
- Not permission to auto-merge `main` because chat said the tests passed.
- Not a prompt. The prompt is the weakest layer, and it says so.
