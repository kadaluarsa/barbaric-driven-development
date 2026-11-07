# Stage 05b — t97-self-check-gate — PLAN

**Spec:** [`../05b-t97-self-check-gate.md`](../05b-t97-self-check-gate.md). This plan runs only after the human signs the EXECUTE edge.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds the oracle command, `bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset`. Write the goal for slice `t97-self-check-gate`. |
| T2 | T1 | AC1, AC2, AC3 | In the `self-check` job, replace the run step: run `gate`, print its output, and pass only on the two stated reasons. |
| T3 | T1 | AC4 | Set `timeout-minutes: 20` and add `fetch-depth: 0` to the job's checkout. |
| T4 | T2, T3 | all | Run `bash tests/ac/t97_self_check_gate.sh`. Run `actionlint` on the workflow. |
| T5 | T2 | evidence limit | Run the extracted step one time on the pack repo. Record the result and its time in the hop report. |
| T6 | T4, T5 | all | Run `bash tests/loop.sh`. Report the result. Stop at the edge. |

## Time

The oracle takes seconds. The loop reruns `tests/enforcement.sh` and `tests/regress.sh`, so it takes about as long as the t96 loop: about 3.5 hours on this machine.
