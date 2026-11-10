# Stage 05b — t100-isolated-gradle-merge — PLAN

**Spec:** [`../05b-t100-isolated-gradle-merge.md`](../05b-t100-isolated-gradle-merge.md). This plan runs only after the EXECUTE edge is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t100_isolated_gradle_merge.sh`,
`bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset`. Write the goal for slice `t100-isolated-gradle-merge`. |
| T2 | — | AC2, AC3 | In `tests/lib/law_harness.init.gradle`, add `BDD_LAW_KINDS=check`: register only check copies, skip the `INV_MUTANT` rule, keep Gradle's up-to-date check for the copy, keep `cacheIf { false }`. Unset: no change. |
| T3 | T2 | AC1–AC4 | In `tests/lib/gradle_runner.py`, pick copy lines (spec items 3–5), write the plan (item 6), run the copy build (item 7), and prove each copy line (item 11). Keep the merged plan and the exact waves for every other line. Add `BDD_LOOP_COPIES=off`. |
| T4 | T3 | AC5 | Confirm that no copy task exists outside the copy build, and that outputs stay under `.cascade/gradle/copies`. |
| T5 | T3 | — | Run `bash tests/ac/t62_loop_runners.sh`, `bash tests/ac/t64_*.sh`, and `bash tests/stress/law_harness.sh` and `bash tests/stress/gradle_runner.sh` with Gradle 8.5 and 9.1.0. Report the results; change none of these files. |
| T6 | T3 | — | Add the oracle step to the `gradle-runner` job. Update USAGE.md §B9. Set 3.5.3 in `VERSION`, the three manifests and `README.md`; add the dated `## 3.5.3` section to `CHANGELOG.md`. |
| T7 | T1–T6 | all | Run `bash tests/loop.sh` in the background. Report the result. Stop at the edge. |

## Order and risk

- T2 changes the law harness's init script. B10 must not change: T5 runs its tests.
- The stub-based `tests/ac/t62_loop_runners.sh` may expect exact waves for same-task lines. If its fixture lines become
  copy lines, the stub cannot run a copy build; the runner then proves nothing and those lines run alone, which keeps
  t62's verdicts. If a t62 assertion counts builds and breaks, stop and report: it is an accepted slice's test.
- Do not change the oracle. A wrong oracle is a send-back to GENERATE.
