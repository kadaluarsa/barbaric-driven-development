# Stage 05b — t110-lesson-escalation — PLAN

**Spec:** [`../05b-t110-lesson-escalation.md`](../05b-t110-lesson-escalation.md). This plan runs only after the EXECUTE
edge is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t110_lesson_escalation.sh`,
`bash tests/mutants.sh` (the frozen manifest's second `run:` line), D1's check
`bash tests/inv/D1_context_budget.sh --grow 400` (every law in force), `bash tests/lint.sh # standing`,
`bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset` (it moves the t109 lines to `docs/cascade/regress.md`). Write the goal for slice `t110-lesson-escalation` with the lines above. |
| T2 | — | AC1–AC4 | Copy `docs/cascade/prototypes/t110/escalate.py` to `tests/lib/escalate.py` (spec items 1–4). |
| T3 | T2 | AC1–AC3 | Apply `docs/cascade/prototypes/t110/patterns.patch` to `tests/patterns.sh` (items 5–9). |
| T4 | T2, T3 | AC1–AC4 | Run the oracle. Then `bash tests/ac/t104_pattern_report.sh`, `bash tests/ac/t106_lessons.sh` and `bash tests/ac/t107_lesson_recall.sh` (accepted; they must pass with no change). |
| T5 | — | AC5 | `USAGE.md` B29 (item 10); release 3.5.12: `VERSION`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, the README release line (item 11). Human decision 2026-11-24: add `escalate` to the `tests/lib/*.py` alternation of T69 AC9's shipped-path allowlist (`tests/ac/t69_gradle_tuning.sh`), nothing else in T69; name it in the CHANGELOG. Run `bash tests/briefs.sh archive` (t102): it moves the closed t109 brief to `docs/cascade/05b-briefs-archive.md`. |
| T6 | T4, T5 | all | `bash tests/enforcement.sh`. A conflict with an accepted test is a STOP for the human. |
| T7 | T6 | all | `bash tests/loop.sh` until `LOOP n/n`, under `caffeinate -dim` in the background. The loop runs `bash tests/mutants.sh` on this hop's diff (in place; the oracle takes about 3 s; the GENERATE simulation gave `MUTANTS 15/15 killed` in 37 s). A survivor is a send-back to GENERATE or a row that only the human signs: ask the human (AskUserQuestion) with each survivor's id, line and draft reason, or on a run with no human end with `AUTOPILOT HALT: decision needed` naming the ids. Print `bash tests/scorecard.sh` and `bash tests/switch.sh`. |

## Order and risk

- T2 → T3 → T4 is the build; T5 is independent.
- Risk: `tests/patterns.sh` is the prompt hook's `--recall` source (t107). The import sits after the `--recall` exit,
  and AC3 checks `--recall` with no module.
- Risk: the installer ships `tests/lib/` whole, so the new module ships; T69 AC9 is changed by the human decision and
  T96 (drift) finds a miss.
- Risk: the mutants line mutates the bash part of `tests/patterns.sh` and all of `tests/lib/escalate.py`; the
  heredoc lines are not mutated. That is why the rule is in the module.
- Skills: test-driven-development applies through the frozen oracle (red now, green after T2–T5).
