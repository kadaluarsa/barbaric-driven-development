---
name: barbar
description: >-
  Use this when the user types /barbar, wants the eval farm scored, or asks
  BARBAR k/n. Farm only: run tests/barbar.sh, print the score, refuse merge
  unless CLEAN 10 + 11 READY. Do not implement features or start GRE stages.
---
Run the verify/CI eval farm. Do not build the product.

`/barbar` is her loop (I16). I17 is the Dune bar: T1–T7 in CONTROL-LINE.md must be green. The GRE conductor in `docs/cascade/product-e2e-gre-pipeline.md` is how you generate and execute. This skill is only the score.

## Hard stop

If the user asked to create, implement, or ship a feature (even "on A based on B using C"), do **not** treat that as `/barbar`. Say it is a GENERATE/EXECUTE hop, point them at the cascade conductor, and STOP.

Never GENERATE, EXECUTE, stitch, start N+1, or merge to main from this skill.

## Run the farm

1. If `tests/barbar.sh` exists in the current repo, run `bash tests/barbar.sh`.
2. Print the `BARBAR k/n` line. That is the whole result. Exit is non-zero unless k=n (T4).
3. If the script is missing, score the **current hop report** (or say there is no hop to score). Fail the hop if GENERATE also executed, `/loop` ran on GENERATE, N+1 started, `/barbar` ran product execute, `/barbar merge` ran before CLEAN 10 + 11 READY, `/loop` omitted an in-force D#, a one-shot was treated as `/barbar`, or IMPLEMENTED has no path/test.
4. STOP. Do not "fix" a red farm by writing product code. Red farm → send back the hop, or tell the human to `approved, execute` a punch list.

## Merge

Only if the user typed `/barbar merge` (or `bash tests/barbar.sh merge`):

- Stage 10 audit is CLEAN
- Stage 11 is READY (or READY WITH WAIVERS)
- Latest farm is n/n
- In-force D# required checks are green

Otherwise refuse. Shipping production already (brownfield) does not skip 10/11. ALLOWED prints the gate; it does not `git push` this methodology repo.

## `/loop` is not this skill

`/loop` is GRE execute on one approved hop (05b / 06–09 / 10 punch), `/goal` = ACs + in-scope D#, `LOOP k/n`, hop edge. If they wanted `/loop`, do not run this farm as a substitute.
