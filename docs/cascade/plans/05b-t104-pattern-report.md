# Stage 05b — t104-pattern-report — PLAN

**Spec:** [`../05b-t104-pattern-report.md`](../05b-t104-pattern-report.md). This plan runs only after the EXECUTE edge
is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t104_pattern_report.sh`,
`bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

**Before EXECUTE:** the human decides spec item 12 at the GENERATE edge (extend the T69 allowlist, or do not ship the
script). The loop cannot pass without one of the two, because `tests/enforcement.sh` runs T69.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset`. Write the goal for slice `t104-pattern-report`. |
| T2 | — | AC1–AC7 | Write `tests/patterns.sh`: argument parsing and exit 64 (item 1); one inline Python block (as `tests/laws_report.sh`) that reads the log, filters by `src=` and verdict (items 4–5), reads the send-back commits (item 5a), normalizes the reason and keeps law ids (item 6), finds the hop by author time from `git log -- docs/cascade/hop-state.md` (item 7), and prints the groups and the last line (items 8–10). Read only: no write call, no `mkdir`, `git log` only (item 2). |
| T3 | T2 | AC8 | `USAGE.md` `### B23`; `CHANGELOG.md` `## 3.5.6`; `VERSION`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json` and `README.md` to 3.5.6 (item 11). |
| T4 | T2 | — | Apply the human's item-12 decision: add `patterns` to the `tests/(…)\.sh` group of `tests/ac/t69_gradle_tuning.sh:368`, or add an `install.sh` exception. Then run `bash tests/ac/t69_gradle_tuning.sh` and report AC9. |
| T5 | T2 | — | Run `bash tests/patterns.sh` and `bash tests/patterns.sh --min 1` on this repository and put the output in the hop report. |
| T6 | T1–T5 | all | Run `bash tests/loop.sh` in the background. Report the result. Stop at the edge. |

## Order and risk

- T2 is a new file. No existing reader changes, so no current behavior can break.
- The hop lookup reads `git log`. In a shallow clone (CI) old hop-state commits can be absent: events then fall in an
  earlier hop or in hop `-`. The counts of events stay correct; only `M` can be lower. A rebase keeps author times, so
  hops do not move (item 7).
- Do not change the oracle. A wrong oracle is a send-back to GENERATE.
