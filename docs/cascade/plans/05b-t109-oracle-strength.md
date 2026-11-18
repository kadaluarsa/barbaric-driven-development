# Stage 05b — t109-oracle-strength — PLAN

**Spec:** [`../05b-t109-oracle-strength.md`](../05b-t109-oracle-strength.md). This plan runs only after the EXECUTE
edge is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t109_oracle_strength.sh`,
`bash tests/mutants.sh` (the frozen manifest's second `run:` line), D1's check
`bash tests/inv/D1_context_budget.sh --grow 400` (every law in force), `bash tests/lint.sh # standing`,
`bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset` (it moves the t108 line to `docs/cascade/regress.md`). Write the goal for slice `t109-oracle-strength` with the lines above. |
| T2 | — | AC1–AC4, AC6, AC7 | Add `tests/lib/mutants.py` (spec items 6–14) and the wrapper `tests/mutants.sh`. The GENERATE prototype is this engine; port it. |
| T3 | — | AC5 | In `tests/lib/oracle.py`, the GENERATE 05b gate check of item 15. |
| T4 | T2, T3 | AC1–AC7 | Run the oracle. Then `bash tests/ac/t89_frozen_oracle.sh` and `bash tests/ac/t91_scorecard_routing.sh` (their fixtures do not copy `tests/mutants.sh`, so the gate check does not apply there). |
| T5 | — | AC8 | `USAGE.md` B28 (item 16); release 3.5.11 (item 17). Ship list: `tests/mutants.sh` and `tests/lib/mutants.py` in the install manifest if the installer lists files one by one. |
| T6 | T4 | item 5 | Run the engine on t108 (a clone at `ef9c6f7`, base `7e2c539`, t108's frozen oracle) in the background under caffeinate; put `MUTANTS k/n` and the time in the hop report. A t108 survivor is reported, not fixed: t108 is accepted. |
| T7 | T4, T5 | all | `bash tests/enforcement.sh`. A conflict with an accepted test is a STOP for the human. |
| T8 | T7 | all | `bash tests/loop.sh` until `LOOP n/n`, under `caffeinate -dim` in the background. The loop runs `bash tests/mutants.sh` on this hop's own diff: any survivor is answered in `docs/cascade/05b-t109-oracle-strength-mutants.md` or is a send-back. Print `bash tests/scorecard.sh` and `bash tests/switch.sh`. |

## Order and risk

- T2 → T4 is the build; T3, T5 and T6 are independent.
- Risk: the loop's mutants line runs the t109 oracle once per mutant (about 20 s each on the GENERATE prototype), up
  to `MUTANTS_MAX` + 1 times per loop pass.
- Risk: the installer ships files by a list. T5 checks it, and T7 (T96, drift) finds a miss.
- Skills: test-driven-development applies through the frozen oracle (red now, green after T2–T5).
