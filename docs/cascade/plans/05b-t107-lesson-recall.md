# Stage 05b — t107-lesson-recall — PLAN

**Spec:** [`../05b-t107-lesson-recall.md`](../05b-t107-lesson-recall.md). This plan runs only after the EXECUTE edge is
signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t107_lesson_recall.sh`,
`bash tests/ac/context_budget.sh --grow 400`, `bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing`
and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset` (it moves the t106 lines to `docs/cascade/regress.md`). Write the goal for slice `t107-lesson-recall` with the five lines above. |
| T2 | — | AC1–AC5 | In `tests/patterns.sh`: `--recall <class>` in the argument parser and both usage lines (spec item 1); keep each lesson's `do:` sentence; move the mark rule into one function that the lesson block and the recall use (item 2, no change of output); the recall block before the output (items 3–7). Update the header comment. |
| T3 | T2 | AC8 | Run `bash tests/ac/t106_lessons.sh` and `bash tests/ac/t104_pattern_report.sh`: their output must not change (the version check of t106 aside, T6). |
| T4 | T2 | AC6 | In `.claude/hooks/seam.py`: `lessons_line(root, cls)` (items 8–10) and one call right after `doc_parts_line`. Do not change the hop context's `json.dump` line: the AC7 red twin patches it. |
| T5 | T4 | AC7 | Write `tests/ac/context_budget.sh` (items 12–15). Its fixture repositories have no hooks (a new `git init`); do not set `core.hooksPath` and do not use `--no-verify`. |
| T6 | — | AC8 | Human decision (item 18): in `tests/ac/t106_lessons.sh` AC8, `VERSION >= 3.5.7`, `## 3.5.7` in `CHANGELOG.md`, 3.5.7 in `README.md`. Change nothing else in that file. |
| T7 | — | AC8 | `USAGE.md` `### B25`; `CHANGELOG.md` `## 3.5.8`; `VERSION`, the three manifests and `README.md` to 3.5.8 (item 17). |
| T8 | T1–T7 | all | Run `bash tests/loop.sh` in the background under `caffeinate`. Report the result, the `BUDGET` rows, and `bash tests/scorecard.sh`. Stop at the edge. |

## Order and risk

- T4 changes a hook that runs on every prompt. It fails open (item 10) and AC6 checks each failure case. It never
  blocks a prompt.
- T2 changes the code path of the t106 marks. The function moves the code; it does not change the rule. T3 checks it.
- T6 changes the frozen oracle of an accepted slice. It is the human's decision of 2026-11-13 and the same change as
  t104's at t106. It makes no check weaker except the exact version number.
- `docs/cascade/lessons.md` is still not created in this repository. The human signs the first lesson.
- Do not change the oracle. A wrong oracle is a send-back to GENERATE.
