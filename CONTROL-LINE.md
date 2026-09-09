# Control line — `/loop` vs `/barbar`

Same job as a hard merge bar: do not trust chat; prove it on the tree. Two commands. Do not mix them.

## `/loop` (ours, GRE)

Follows and enhances GRE execute.

- Legal only after `approved, execute` of **05b / 06–09 / 10 punch**
- `/goal` = named AC tests **and** every in-force D# the slice can touch
- Print `LOOP k/n` with per-validator pass/fail (her 10/10 *shape*, our physics)
- An in-force D# omitted from `/goal` is **FAIL**, not skip
- STOP at hop edge. Never GENERATE. Never N+1.

## `/barbar` (hers, enhanced)

Follows her eval/CI farm. Enhances it so it cannot skip the hop edge.

- Hill-climb **control-line evals** until `BARBAR 10/10` (pack eval + in-force D# required checks)
- Must **not** GENERATE, EXECUTE, stitch, or start N+1
- `/barbar merge` is legal **only if** stage 10 is CLEAN **and** stage 11 is READY **and** BARBAR is 10/10 **and** in-force D# are green. Otherwise refuse.
- That is her auto-merge, gated by GRE ship law.

## Sequence

```
GENERATE  → spec+plan → STITCH NEEDED
you: approved, execute stage N
EXECUTE   → /goal = ACs + D# → /loop until LOOP n/n → CI red if D# fail → /diff
you: accepted, generate stage N+1
… later, CLEAN 10 + 11 READY …
/barbar → BARBAR 10/10
/barbar merge   # only then
```

## Pack eval (must FAIL)

1. GENERATE produced product code, started EXECUTE, or started N+1
2. `/loop` ran on 01–04, a GENERATE hop, or 11
3. `/barbar` ran a product stage, or `/barbar merge` fired before CLEAN 10 + 11 READY
4. A PR merged with a failing in-force D#, or green tests that omit D# were treated as the bar

## CI contract

- A D# without a validator command is not in force (I13).
- Once in force, breaking it is a red required check.
- Stage 10 scores a broken D# as VIOLATED.
- This repo's CI is `tests/control-line.sh` + `tests/i17_dune.sh` + `tests/barbar.sh` (I15 + I16 + I17). Product D# tests live in the product repo.

The human stays on the hop edge. `/barbar` does not mean "keep looping until READY."

## Run

```
bash tests/i17_dune.sh        # T1–T7
bash tests/barbar.sh          # farm → BARBAR k/n
bash tests/barbar.sh merge    # refuse unless CLEAN 10 + 11 READY
```

n/n is her 10/10. This pack repo has no product D#, so merge must refuse unless `BARBAR_ROOT` points at a CLEAN 10 + READY 11 tree.

## I17 Dune bar (evidence)

100% match means a violation is a **red test**, not a stronger prompt. T1–T7 are the talk.

| ID | Talk | If this test is red, the statement is false |
|----|------|-----------------------------------------------|
| T1 | Skill | *presence:* the skill no longer hard-stops a feature one-shot |
| T2 | Evals | *runs the scorer:* a one-shot build and an evidence-free IMPLEMENTED are no longer caught |
| T3 | Hard CI (Dune) | *presence:* PRs can merge without `tests/barbar.sh` |
| T4 | Loop until 10/10 | *runs the gate:* it exits 0 on a product that is not n/n |
| T5 | Auto-merge on green | *runs the gate on both fixtures:* a READY product is not ALLOWED, or a dirty one is not REFUSED |
| T6 | Don't trust chat | *runs the scorer:* IMPLEMENTED without a path/test is not scored as a failure |
| T7 | Verify before continue | *runs the scorer:* a GENERATE hop that executed, or one that started N+1, is not caught |

T0, T1 and T3 are presence checks by design — they guard against an instruction file or a CI job being
deleted, which is what a presence check is for. T2 and T4–T7 used to be presence checks too, asserting that
`barbar.sh` contained the string `exit 1` and that fixture files existed without ever scoring them. A test
that cannot fail for the reason it claims is THEATER by this pack's own standard; those five run things now.

Run: `bash tests/i17_dune.sh && bash tests/barbar.sh`

## I18 Enforcement layers (evidence)

I17 says a violation must be a red test. I18 says where that test lives. Each control sits at the lowest layer that can enforce it, and a hop may not weaken a layer to pass.

| Layer | Mechanism | Binds | Agents |
|---|---|---|---|
| 0 | CI + branch protection (`.github/workflows/`) | yes, non-bypassable | all |
| 1 | git hooks (`.githooks/pre-commit`, `pre-push`) | yes, locally | all |
| 2 | agent hooks (`.claude/hooks/`) | yes, at the tool call | Claude Code |
| 3 | prose (`AGENTS.md` + shims) | no | all |

Commands are scripts. `/loop` = `bash tests/loop.sh`. `/barbar` = `bash tests/barbar.sh`. The agent never types `LOOP k/n` or `BARBAR k/n`.

| ID | Layer | If this test is red, the statement is false |
|----|-------|-----------------------------------------------|
| T8 | 1 | pre-commit rejects product code on a GENERATE hop |
| T9 | 1 | pre-commit allows spec on GENERATE and product code on EXECUTE |
| T10 | 1 | pre-commit rejects a changed `<EDIT>`; allows adding one |
| T11 | 1 | pre-push rejects `main`; allows a slice branch |
| T12 | script | `tests/loop.sh` refuses on a GENERATE hop |
| T13 | script | an in-force D# omitted from `/goal` is a FAIL entry; `LOOP k/n` is machine output |
| T14 | script | the farm is red when the scorer dies; `merge` runs the farm first |
| T15 | 2 | Claude hooks deny product Write on GENERATE, deny ship escapes, block an open hop, re-inject after compact |
| T16 | 2 | `install.sh` places the skill under `.claude/skills/` and hooks under `.claude/hooks/` — where the agent loads them; the installed farm is n/n |
| T17 | 1+2 | hop state and D# lines are human-owned: the agent cannot flip `CURRENT_HOP` or soften a validator; a human commits with `CASCADE_HUMAN=1`, which the agent is denied |
| T18 | script | red twin: a D# is in force only when it can fail — THEATER is red, UNPROVEN blocks `loop.sh`, a written waiver lifts it, `DSHARP k/n` is machine output; merge also requires READY human-signed inside `<EDIT>` |
| T19 | script | stage 10 is computed by `tests/audit.sh`: `path:` must exist, `test:` must pass, REFINED needs `<EDIT>`, PRD IDs without rows are MISSING, a prose CLEAN is ignored |
| T20 | 2 | the seam hook injects the per-hop Superpowers allow/deny list and cascade precedence on every prompt; silent outside a cascade |
| T21 | 2 | a crashing guard returns `ask`, never allow; CRLF envelopes still parse |
| T22 | install | `install.sh --check` reports a softened hook or a deleted script (drift) and a version mismatch |
| T23 | install | `install.sh` is idempotent: a re-run nests nothing, drops stale files, leaves no drift, farm still n/n |
| T24 | install | a real product: an existing `settings.json` is merged (theirs kept), `CLAUDE.md` gets `@AGENTS.md` appended, a gitignored `.claude/` is flagged by install and `--check` |
| T25 | 1+2 | a law's test is the law: existing `tests/inv/*` are human-owned — the agent can add a law test, never change or delete one; a human accepts changes with the key |
| T26 | 1+2 | a slice cannot carve an exception into a law: no new test under an existing D# id; the seam states laws admit no exceptions every prompt |
| T27 | 1+2 | autopilot: off by default; a human-signed `AUTOPILOT:` list lets the agent take only the next signed edge — spec doc before EXECUTE, `loop.sh` n/n before the next slice; list end, 10/11, READY and merge stay human |
| T28 | 2 | `/barbar auto`: the Stop hook keeps the session going while signed edges remain; stops at the list end, on `AUTOPILOT HALT:`, or at a cap — never spins |
| T29 | 2 | first-knowledge discovery: with no law in force the seam and session-start hooks nudge toward `/barbar init`, which scans and writes `docs/cascade/proposals.md` — proposals, never signed laws |
| T30 | 1+2 | approve-to-sign: a signable change (hop edge, AUTOPILOT/D# line, `<EDIT>` content, a law test) answers `ask` interactively — the human's approval is the signature, recorded as a one-shot token pre-commit accepts for exactly that content; `deny` when permissions are bypassed; the agent cannot mint tokens |
| T31 | plugin | manifest, marketplace and hooks.json valid; plugin-mode install wires no project hooks; the seam offers the install in a bare repo; a tool call is judged once when both plugin and project hooks are present |
| T32 | 1 | a hook-style `GIT_DIR`/`GIT_WORK_TREE` never leaks into the farm's throwaway repos — the pre-push farm once flipped a real product to `core.bare=true` and re-pointed its worktree HEAD |
| T33 | 1 | a human editing by hand can sign from any git client: `tests/sign.sh` mints the same one-shot token for the human-owned files they changed, and the agent is denied running it |
| T34 | 2 | a repo whose shipped scripts are older than the plugin is told at session start, with the refresh command; silent when in sync or plugin-less |
| T35 | 1+2 | plugin-mode repo: Layer 2 resolved from the plugin so the farm reaches n/n; an existing `AGENTS.md` keeps its rules and gains the cascade ones; `--check` clean |
| T36 | 1+2 | stage 10 can be signed onto the autopilot list and is gated by `audit.sh` (rows first, CLEAN to advance); stage 11 never can; the audit hop uses an independent reviewer and a capped punch list |
| T37 | 2+3 | the edge-line ritual is scoped to open hops in both layers: the Stop hook is silent when idle and names the real stage when not, and `AGENTS.md` says the same |

| T38 | plugin | every file the plugin ships under `commands/` and `skills/` is a real file and byte-identical to the `.claude/` copy the repo runs — a symlink is not followed by the loader, and a frozen copy silently degrades plugin-mode sessions |
| T39 | 2 | a fresh clone is told Layer 1 is off — `core.hooksPath` is git config and never travels with the repo — with the one-line fix, and goes quiet once wired; friendly-format laws reach session start |
| T40 | 1+2 | every layer appends its decisions to `.cascade/decisions.log` — denials, signatures, law verdicts, halts — without the log ever becoming a gate or dirtying the tree; signing a law runs its strength check on the spot |
| T41 | 2 | I10 is mechanical: the accept edge needs a `loop.sh` receipt naming this hop and fingerprinting this tree — none, stale, or from another stage is refused; a failing loop writes none; the receipt is never committed |
| T42 | install | plugin-mode install strips Layer 2 from a product but never from the pack, whose `.claude/hooks` are the source that gets packaged — running it in the pack once deleted the product |
| T43 | 2 | an unsigned autopilot list asks the human which slice to run and signs their pick through the dialog, halting only when headless or when they decline — no `sed`, no stitch key, no retyping what the agent already knows |
| T44 | 1+2 | hop state lives in `docs/cascade/hop-state.md`, human-owned at Layer 1 like the envelope and read in preference to it, with laws staying in the envelope; a repo without the file still reads hop state from the envelope, and installing never creates it under a running hop |
| T45 | 1 | the git hooks resolve the real git dir instead of assuming `$ROOT/.git`, so every guard still runs — and still refuses — inside a worktree, where `.git` is a file |
| T46 | 2 | the git dir is sealed against the agent on every hop — signature ledger, pending list, hooks and refs — so a signature can only come from a human approving a dialog or running `tests/sign.sh`; ordinary product writes are untouched |
| T47 | 1 | Layer 1 does not fail open on a large commit — no pipeline feeds `grep -q` under `pipefail`, where an early-exiting grep makes the writer take SIGPIPE and the guard behind it is skipped — and cleanup runs from an EXIT trap, so an unlinkable scratch path can never abort a commit whose checks passed |
| T48 | 0+1 | the pre-push gate defers the pack's own meta-suite to CI and labels the score `(fast: … not a full farm)`; lint and the hop scorer still run locally; `barbar merge` unsets fast mode and CI never sets it, so nothing reaches main unchecked |
| T49 | 2 | every shared hook helper is defined once, in `.claude/hooks/_common.py`, and each hook still loads, answers a trivial event silently, and asks rather than failing open when the module cannot be used |
| T50 | 2 | the git dir is sealed against the agent from inside a linked worktree too, where `$GIT_DIR` is `<main>/.git/worktrees/<name>` and therefore outside the worktree root — the path that let the agent mint its own signature while every plain-repo test passed; ordinary product writes in a worktree are untouched |
| T51 | 2 | quoting an argument does not defeat `bash_guard` — the ledger, `tests/sign.sh`, `--no-verify` and a push to main are denied quoted or bare, while the reads and commit-message prose that merely name them stay allowed |
| T52 | 2 | `bash tests/doctor.sh` goes red once per dead layer — `core.hooksPath` unset, no CI workflow running the farm, a hop open on a slice with no spec — never counts a skipped check as green, never implies it verified branch protection (a GitHub setting it cannot read), diagnoses a bare repo instead of crashing, and keeps one command file byte-identical in both trees |

## Invariant coverage (I1–I18)

An invariant with no test is a wish. This is the honest map — where each is actually enforced, and which are still prose.

| I# | Enforced by |
|----|-------------|
| I1 | `stop_guard.py`, `seam.py`, `preserve.py` — T15, T28, T37 |
| I2, I3 | `preserve.py`, `bash_guard.py` — T15, T21 |
| I4 | `pre-commit`, `hop_guard.py` — T8, T9, T15 |
| I5, I6 | `enforcement.sh`, `seam.py` — T20 |
| I7 | `audit.sh`, `barbar.sh` — T6, T19 |
| I8 | `audit.sh` — T19 |
| I9 | `loop.sh` — T12, T13 |
| **I10** | `stop_guard.py` + the `loop.sh` receipt, or `audit.sh` at stage 10 — **T41** |
| **I11** | **partly — T43.** A send-back had no machine signal at all: it happened in chat and nothing downstream knew. The accept edge now asks for the verdict and a send-back is written to the run log with its reason, so "this hop was rejected" is at least recorded and the fix is told to start from a clean tree. Still not *enforced*: no hook can see whether the human actually rewound. The loop receipt (I10) limits the damage — stacked work cannot reuse the old evidence. |
| **I12** | **partly.** "must not change Current hop, locks or plan" is enforced — those are protected lines (T17, T30). "must not change files in this hop" is prose: a tangent editing a legitimately-writable path is indistinguishable from the hop's own work. |
| I13 | `loop.sh`, `dsharp_strength.sh`, `hop_guard.py`, `pre-commit` — T13, T18, T25, T26 |
| I14 | `control-line.sh`, `seam.py` — T20 |
| I15 | `pre-commit`, `pre-push`, `hop_guard.py`, `bash_guard.py` — T10, T11, T17, T27, T30, T33 |
| I16, I17 | `barbar.sh`, `i17_dune.sh` — T1–T7, T14 |
| I18 | every layer — T8–T52, and `enforcement.sh` itself |

T8–T52 run in throwaway git repos, not as greps. Run: `bash tests/enforcement.sh`
