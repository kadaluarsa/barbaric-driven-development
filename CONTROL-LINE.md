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
| T1 | Skill | `/barbar` will treat "create A from B using C" as a build |
| T2 | Evals | Hop reports are not scored |
| T3 | Hard CI (Dune) | PRs can merge without `tests/barbar.sh` |
| T4 | Loop until 10/10 | Farm can exit 0 with k<n |
| T5 | Auto-merge on green | Merge has no CLEAN 10 + 11 READY gate, or never ALLOWED when the gate holds |
| T6 | Don't trust chat | IMPLEMENTED can be claimed without a path/test |
| T7 | Verify before continue | GENERATE can execute or start N+1 |

Run: `bash tests/i17_dune.sh && bash tests/barbar.sh`
