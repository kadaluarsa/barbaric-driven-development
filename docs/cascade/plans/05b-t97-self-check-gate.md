# Stage 05b — t97-self-check-gate — PLAN

**Spec:** [`../05b-t97-self-check-gate.md`](../05b-t97-self-check-gate.md). This plan runs only after the human signs the EXECUTE edge.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds the oracle command, `bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | AC6 | Run `bash tests/goal.sh reset`. In the new `regress.md` line, add `T96_FAST=1`. Do not run `carry-out`. Write the goal for slice `t97-self-check-gate`. |
| T2 | T1 | AC1, AC2, AC3 | In the `self-check` job, replace the run step: run `gate`, print its output, and pass only on the two stated reasons. |
| T3 | T1 | AC4, AC5 | Set `timeout-minutes: 20` and add `fetch-depth: 0` to the job's checkout. Add no other key. |
| T4 | — | AC7 | Add `.github/workflows/pack-install-repair.yml`. Do not add it to `install.sh`. |
| T5 | T2, T3, T4 | all | Run `bash tests/ac/t97_self_check_gate.sh`. Run `actionlint` on both workflows. |
| T6 | T5 | evidence limit | In a scratch clone of the committed work, run the extracted step one time. Record the result, its time and the `REGRESS k/n` in the hop report. |
| T7 | T6 | all | Run `bash tests/loop.sh`. Report the result. Stop at the edge. |

## Time

The oracle takes seconds. The loop reruns `tests/enforcement.sh` and `tests/regress.sh`. The t96 loop took about 3.5 hours on this machine, and most of that was the full t96 oracle. This loop has no such oracle, so it must be shorter. The time is not measured.
