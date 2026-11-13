# Stage 05b — t106-lessons — PLAN

**Spec:** [`../05b-t106-lessons.md`](../05b-t106-lessons.md). This plan runs only after the EXECUTE edge is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t106_lessons.sh`,
`bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset`. Write the goal for slice `t106-lessons`. |
| T2 | — | AC1, AC4 | In the Python block of `tests/patterns.sh`: read `docs/cascade/lessons.md` when it exists; parse the lines inside `<EDIT>` (items 1–3); keep valid lessons; report malformed lines with their line numbers. |
| T3 | T2 | AC3 | Keep every event per group with no `--since` filter (item 6), next to the filtered groups t104 prints. Compute before/after hops by author time (item 5), the rates (item 7) and the marks (item 8). Print the lesson block before the `PATTERNS:` line (items 9–10). |
| T4 | T2 | AC2, AC5 | Add `--propose` to the argument parser and the usage line. Print the drafts and `PROPOSALS:` (item 11). Write nothing (item 12). |
| T5 | T2–T4 | AC7 | Run `bash tests/ac/t104_pattern_report.sh`: the t104 output must not change when there is no lesson. |
| T6 | — | AC8 | `USAGE.md` `### B24`; `CHANGELOG.md` `## 3.5.7`; `VERSION`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json` and `README.md` to 3.5.7 (item 13). Update the header comment of `tests/patterns.sh`. |
| T7 | T1–T6 | all | Run `bash tests/loop.sh` in the background. Report the result and `bash tests/patterns.sh --propose` on this repository. Stop at the edge. |

## Order and risk

- T2–T4 change one existing file, `tests/patterns.sh`. With no `lessons.md` the output must stay the t104 output
  (AC5, AC7); `tests/ac/t104_pattern_report.sh` is in the regression suite and checks it.
- No hook, gate or shipped file changes: the signature is the existing `<EDIT>` scan (AC6 checks it on a scratch copy).
- `lessons.md` is not created in this repository by this slice. The first lesson is a human signature, after the
  slice is accepted.
- Do not change the oracle. A wrong oracle is a send-back to GENERATE.
