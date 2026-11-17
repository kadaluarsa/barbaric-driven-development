# Stage 05b — t103-log-source — PLAN

**Spec:** [`../05b-t103-log-source.md`](../05b-t103-log-source.md). This plan runs only after the EXECUTE edge is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t103_log_source.sh`,
`bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset`. Write the goal for slice `t103-log-source`. |
| T2 | — | AC1, AC3, AC8 | In `tests/lib/decisions.py`: the trailing field (items 1–3), rotation that drops test lines first (item 2a), `source()`, `display()`, the filtered `tail()`, `--tail-all` (items 4–6), the docstring (item 14). |
| T3 | T2 | AC3, AC5 | `tests/lib/recall.py` `halt()`: skip `src=test`, print through `display()` (item 7). Keep the import optional: an older `decisions.py` without `display` leaves the line as it is. |
| T4 | T2 | AC4 | `tests/handover.sh`: print `decisions.py --tail 5` (item 8). |
| T5 | T2 | AC6, AC7 | Export `BDD_LOG_SRC=test` in the first 25 lines of `tests/enforcement.sh` and `tests/regress.sh`; in `tests/barbar.sh` write each call `BDD_LOG_SRC=test run_farm` (no export: `merge_gate` keeps the caller's source); in `tests/loop.sh` set it in the goal line's subshell only (items 10–11). |
| T6 | T5 | — | Run `bash tests/ac/t85_recall_index.sh` and the T40 block of `tests/enforcement.sh`. Report the results; change neither test. |
| T7 | — | — | USAGE.md §B22, CHANGELOG `## 3.5.5`, `VERSION`, the three manifests, `README.md` (item 13). Check whether `tests/ac/t69_gradle_tuning.sh` AC9 still passes: this slice adds no shipped file. |
| T8 | T1–T7 | all | Run `bash tests/loop.sh` in the background. Report the result. Stop at the edge. |

## Order and risk

- T2 changes a line format that four readers parse. The field goes at the end, so positional readers do not move.
  AC3 and AC4 guard the old format and the display output.
- T5 changes the loop. The receipt and the `LOOP k/n` line must not change; only the goal line's environment does.
- Do not change the oracle. A wrong oracle is a send-back to GENERATE.
