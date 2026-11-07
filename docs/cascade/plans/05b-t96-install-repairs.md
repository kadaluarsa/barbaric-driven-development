# Stage 05b — t96-install-repairs — PLAN

**Spec:** [`../05b-t96-install-repairs.md`](../05b-t96-install-repairs.md). This plan runs only after the human signs the EXECUTE edge.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds the oracle command, `bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset`. Write the goal for slice `t96-install-repairs`. |
| T2 | T1 | AC1 | Add `docs/cascade/hop-state.template.md`. In `install.sh`, copy the template and seed the hop state from it. |
| T3 | — | AC2 | Add the deny forms to `.claude/hooks/bash_guard.py`. Keep each allow form allowed. |
| T4 | — | AC3 | Add `tests/drift.sh`. Ship it from `install.sh`. Add a step to `control-line.yml`. |
| T5 | T4 | AC4 | Confirm that a same-version reinstall commits through the real hook. Add no manifest rule. |
| T6 | — | AC5 | Add the hash of each earlier pack copy of the skill to `install.sh`. Replace a matching file, and keep the conflict for any other file. |
| T7 | — | AC6 | Set `timeout-minutes: 60` on the `eval` job. |
| T8 | — | AC7 | Add `evals/fixtures/*/.cascade/` to `install.sh` and `.gitignore`. |
| T9 | — | AC9 | Add the protected paths to `.claude/hooks/hop_guard.py`, limited to a repo with `.cascade/manifest`. Cover the Write path and `codex_patch_deny`. |
| T10 | — | AC10, AC11 | In `tests/enforcement.sh`, add the pack test and the SKIP lines for T52, T53, T54 and T74. |
| T11 | T10 | all | Add T96 to `tests/enforcement.sh`. Change every `T8–T93` text to `T8–T96`. |
| T12 | T11 | AC8 | Confirm that T96 runs `tests/ac/codex_compatibility.sh` through the oracle's AC8. Do not change that test. |
| T13 | T12 | AC8 | Set 3.5.1 in `VERSION` and the three manifests. Add the dated `## 3.5.1` section to `CHANGELOG.md`, with the note for the seeded hop. |
| T14 | T2–T13 | all | Run `bash tests/loop.sh`. Report the result. Stop at the edge. |

## Order and risk

- T3 and T9 change hooks that guard this session. Run the AC after each change.
- T14 can take about 100 minutes on this machine, because AC10 and AC11 run the suite and the farm. Run it in the background.
- Do not change the oracle. A wrong oracle is a send-back to GENERATE.
