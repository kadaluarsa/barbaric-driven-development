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

Rows T8 and later, with each test's red twin, are in [`docs/cascade/control-line-evidence.md`](docs/cascade/control-line-evidence.md). Read that file when you change or debug a control. It is not required reading on a hop.


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
| **I10** | `stop_guard.py` + the `loop.sh` receipt, or `audit.sh` at stage 10 — **T41**; a check that cannot finish refuses instead of passing — **T59** |
| **I11** | **partly — T43.** A send-back had no machine signal at all: it happened in chat and nothing downstream knew. The accept edge now asks for the verdict and a send-back is written to the run log with its reason, so "this hop was rejected" is at least recorded and the fix is told to start from a clean tree. Still not *enforced*: no hook can see whether the human actually rewound. The loop receipt (I10) limits the damage — stacked work cannot reuse the old evidence. |
| **I12** | **partly.** "must not change Current hop, locks or plan" is enforced — those are protected lines (T17, T30). "must not change files in this hop" is prose: a tangent editing a legitimately-writable path is indistinguishable from the hop's own work. |
| I13 | `loop.sh`, `dsharp_strength.sh`, `hop_guard.py`, `pre-commit` — T13, T18, T25, T26 |
| I14 | `control-line.sh`, `seam.py` — T20 |
| I15 | `pre-commit`, `pre-push`, `hop_guard.py`, `bash_guard.py` — T10, T11, T17, T27, T30, T33 |
| I16, I17 | `barbar.sh`, `i17_dune.sh` — T1–T7, T14 |
| I18 | every layer — T8–T94, and `enforcement.sh` itself |

T8–T94 run in throwaway git repos, not as greps. Run: `bash tests/enforcement.sh`
