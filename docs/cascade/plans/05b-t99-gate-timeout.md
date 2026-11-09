# Stage 05b — t99-gate-timeout — PLAN

**Spec:** [`../05b-t99-gate-timeout.md`](../05b-t99-gate-timeout.md). This plan runs only after the EXECUTE edge is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t99_gate_timeout.sh`,
`bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset`. Write the goal for slice `t99-gate-timeout`. |
| T2 | — | AC1, AC2 | In `.claude/hooks/hop_guard.py`, add `HOOK_SECONDS`, `SWITCH_SECONDS`, `MARGIN`. In `autopilot_ok`, import `loop_minutes` from `tests/lib/autopilot.py`, calculate `M` and the timeout, pass `BDD_AUTOPILOT_LOOP_MINUTES=M` in the child's environment, and return a reason for `TimeoutExpired` and for other exceptions. Remove the temporary files in a `finally`. |
| T3 | — | AC4 | Add `"timeout": 4200` to the `hop_guard` entry in `hooks/hooks.json` and `.claude/settings.json`. |
| T4 | T3 | AC5 | In the `install.sh` settings merge, set our `timeout` on an existing entry with the same command when it has none or a smaller one. |
| T5 | — | AC6 | Change step 4 in `.claude/commands/barbar.md` and `commands/barbar.md`. |
| T6 | T2–T5 | — | Set 3.5.2 in `VERSION`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and `README.md`. Add the dated `## 3.5.2` section to `CHANGELOG.md`. Update the T-range text in `tests/enforcement.sh` if earlier slices did. |
| T7 | T1–T6 | all | Run `bash tests/loop.sh` in the background. Report the result. Stop at the edge. |

## Order and risk

- T2 changes a hook that guards this session. Run `bash tests/ac/t99_gate_timeout.sh` after T2.
- T3 changes `.claude/settings.json`, which `hop_guard` guards (a signature dialog in an installed repo; in the pack it
  is a normal edit — the dialog decides).
- Do not change the oracle. A wrong oracle is a send-back to GENERATE.
