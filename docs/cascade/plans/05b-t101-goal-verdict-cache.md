# Stage 05b — t101-goal-verdict-cache — PLAN

**Spec:** [`../05b-t101-goal-verdict-cache.md`](../05b-t101-goal-verdict-cache.md). This plan runs only after the EXECUTE edge is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t101_goal_verdict_cache.sh`,
`bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset`. Write the goal for slice `t101-goal-verdict-cache`. |
| T2 | — | AC1–AC7, AC10 | Write `tests/lib/goal_cache.py` with `keys` and `store` (spec items 1–7a, 13–16). Import t65's and t66's helpers; do not copy them. For a D# line, call `verdict_cache.keys` for that law (item 6b). |
| T3 | T2 | AC1, AC5–AC9 | In `tests/loop.sh`, call `keys` before the first line, print hits as `PASS  <line>  (cached)`, keep hits out of the Gradle runner, call `store` after the last line, and add `C cached` to the `loop:` line (items 8–12, 17). |
| T4 | T3 | AC9 | Confirm that the loop reads no entry when `CASCADE_HOPSTATE` or `CASCADE_ENVELOPE` is set. Do not change `tests/lib/autopilot.py`. |
| T5 | T3 | — | Run `bash tests/ac/t62_loop_runners.sh`, `bash tests/ac/t65_verdict_cache.sh` and `bash tests/ac/t79_*.sh`. Report the results; change none of these files. |
| T5a | — | — | In `install.sh`, add `.cascade/goal-verdicts/` to the ignore list beside `.cascade/verdicts/` (item 18a). Run `bash tests/ac/t65_verdict_cache.sh` AC12 and `bash tests/ac/t96_install_repairs.sh`. |
| T6 | T3 | — | Add the oracle step to the `gradle-runner` job. Add USAGE.md §B20. Set 3.5.3 in `VERSION`, the three manifests and `README.md`; add the dated `## 3.5.3` section to `CHANGELOG.md`. |
| T7 | T1–T6 | all | Run `bash tests/loop.sh` in the background. Report the result. Stop at the edge. |

## Order and risk

- T3 changes the loop that decides every hop. The receipt and the `LOOP k/n` line must not change format.
- The Gradle runner reads indexes. Keep the hit lines out of its input, but keep each other line's index.
- Item 6c reads files under `~/.gradle`. Read only those named paths; a missing one is part of the key as absent.
- This repo's own goal lines are not Gradle lines. In this repo the cache gives a gain only for signed-path lines.
- Do not change the oracle. A wrong oracle is a send-back to GENERATE.
