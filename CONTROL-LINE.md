# Control line — eligibility

This repo's pack is **eligible** as a verify/CI control line. Same job as a hard merge bar: do not trust chat; prove it on the tree.

It is **not** an eval hill-climb. GRE `/loop` is one approved execute, not "keep going until 10/10." Auto-merge does not skip stitches or stage 11.

## Mapping

| Verify/CI bar | GRE law |
|---------------|---------|
| Skill / conductor | `docs/cascade/product-e2e-gre-pipeline.md`. Eval **fails** if GENERATE starts EXECUTE or N+1 |
| Hard CI | In-force D# validators are **required checks** (stage 07 names them; 05b `/goal` runs them) |
| `/loop` until score | `/loop` only on **05b / 06–09 / 10 punch**, until `/goal` = ACs + those D# |
| Auto-merge on green | Illegal until **CLEAN 10 + 11 READY**. Human stitch on every hop edge |

## Sequence

```
GENERATE  → spec+plan → STITCH NEEDED
you: approved, execute stage N
EXECUTE   → /goal = ACs + D# → /loop until those tests → CI red if D# fail → /diff
you: accepted, generate stage N+1
```

## Pack eval (must FAIL)

1. GENERATE produced product code, started EXECUTE, or started N+1
2. `/loop` ran on 01–04, a GENERATE hop, or 11
3. A PR merged (or was auto-merged) with a failing in-force D#, or before CLEAN 10 + 11 READY
4. Green feature tests that omit an in-force D# were treated as the merge bar

## CI contract (product repos using this pack)

- A D# without a validator command is not in force (I13).
- Once in force, breaking it is a red required check. The agent may not skip it.
- Stage 10 scores a broken D# as VIOLATED, never DRIFTED.
- This methodology repo's own CI is `tests/control-line.sh` (the pack must keep I15). Product D# tests live in the product repo, not here.

## Human stays on the hop edge

Do not encode "keep looping until READY." Stitches are the process.
