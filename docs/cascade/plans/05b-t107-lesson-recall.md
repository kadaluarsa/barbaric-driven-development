# Stage 05b — t107-lesson-recall — PLAN

**Spec:** [`../05b-t107-lesson-recall.md`](../05b-t107-lesson-recall.md). This plan runs only after the EXECUTE edge is
signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t107_lesson_recall.sh`,
D1's check `bash tests/inv/D1_context_budget.sh --grow 400` (the loop requires every law in force), `bash
tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset` (it moves the t106 lines to `docs/cascade/regress.md`). Write the goal for slice `t107-lesson-recall`: the oracle line and the lint, enforcement and regress gates. D1's check is added in T6, when the law is in force. |
| T2 | — | AC1–AC5 | In `tests/patterns.sh`: `--recall <class>` in the argument parser and both usage lines (spec item 1); keep each lesson's `do:` sentence; move the mark rule into one function that the lesson block and the recall use, which also counts the events in the latest 5 hops of the scope (item 2, no change of output); the recall block before the output (items 3–7). Update the header comment. |
| T3 | T2 | AC8 | Run `bash tests/ac/t106_lessons.sh` and `bash tests/ac/t104_pattern_report.sh`: their output must not change (the version check of t106 aside, T8). |
| T4 | T2 | AC6 | In `.claude/hooks/seam.py`: `lessons_line(root, cls)` (items 8–10) and one call right after `doc_parts_line`. |
| T5 | — | AC7 | Write `tests/inv/D1_context_budget.sh` (items 13–16). Its fixture repositories have no hooks (a new `git init`); do not set `core.hooksPath` and do not use `--no-verify`. The red twin wraps the measured hook; it does not edit `seam.py`. |
| T6 | T4, T5 | AC7 | Propose, in two edits that raise the signature dialog: the new shard `docs/cascade/laws/context.md` with D1 exactly as item 12, and the envelope's `## Law shards` index row inside a new `<EDIT>` block. The human's approval is the signature. Then add D1's check to the goal and run `bash tests/dsharp_strength.sh`: D1 must be `GREEN`. If the human does not sign, stop at the edge and say so. |
| T7 | — | AC7 | `install.sh` (item 17): remove unshipped shard rows from a newly created envelope. `.github/workflows/nightly.yml` (item 18): `fetch-depth: 0` on the `regress` job's checkout. |
| T8 | — | AC8 | Human decision (item 20): in `tests/ac/t106_lessons.sh` AC8, `VERSION >= 3.5.7`, `## 3.5.7` in `CHANGELOG.md`, 3.5.7 in `README.md`. Change nothing else in that file. |
| T9 | — | AC8 | `USAGE.md` `### B25`; `CHANGELOG.md` `## 3.5.8`; `VERSION`, the three manifests and `README.md` to 3.5.8 (item 19). |
| T10 | T1–T9 | all | Run `bash tests/loop.sh` in the background under `caffeinate`. Report the result, the `BUDGET` rows, `DSHARP`, and `bash tests/scorecard.sh`. Stop at the edge. |

## Order and risk

- T6 makes the first law of this repository. From then on, every hop's loop and the merge gate run D1 (about 10 s).
  The law, its lines and `tests/inv/D1_context_budget.sh` are the human's: after this slice, an agent changes none of
  them (AGENTS.md rule 5).
- T4 changes a hook that runs on every prompt. It fails open (item 10) and AC6 checks each failure case. It never
  blocks a prompt.
- T2 changes the code path of the t106 marks. The function moves the code; it does not change the rule. T3 checks it.
- T7 changes `install.sh` only for a new envelope: an existing envelope is never touched. AC7 checks a new install;
  `tests/enforcement.sh` keeps the other install checks (T69, T96, T67 AC8).
- T8 changes the frozen oracle of an accepted slice. It is the human's decision of 2026-11-14 and the same change as
  t104's at t106. It makes no check weaker except the exact version number.
- `docs/cascade/lessons.md` is still not created in this repository. The human signs the first lesson.
- Do not change the oracle. A wrong oracle is a send-back to GENERATE.
