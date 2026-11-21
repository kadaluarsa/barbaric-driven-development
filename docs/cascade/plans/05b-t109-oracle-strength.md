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
| T2 | — | AC1–AC4, AC6, AC7 | Copy `docs/cascade/prototypes/t109/mutants.py` to `tests/lib/mutants.py` and `mutants.sh` to `tests/mutants.sh` (spec items 6–15). |
| T3 | — | AC3, AC5 | Apply `docs/cascade/prototypes/t109/existing-files.patch`: the gate in `tests/lib/oracle.py` (item 16), and the human-owned equivalent rows in `tests/lib/laws.py`, `.githooks/pre-commit` and `.claude/hooks/hop_guard.py` (item 15). |
| T4 | T2, T3 | AC1–AC7 | Run the oracle. Then `bash tests/ac/t89_frozen_oracle.sh`, `bash tests/ac/t91_scorecard_routing.sh`, `bash tests/ac/t106_lessons.sh` and the pre-commit and hop_guard tests that `bash tests/affected.sh` names (their fixtures do not copy `tests/mutants.sh`, so the gate check does not apply there). |
| T5 | — | AC8 | `USAGE.md` B28 (item 17); release 3.5.11 (item 18). Human decision 2026-11-20: add `mutants` to the `tests/lib/*.py` and `tests/*.sh` alternations of T69 AC9's shipped-path allowlist (`tests/ac/t69_gradle_tuning.sh`), nothing else in T69; name it in the CHANGELOG. Ship list: `tests/mutants.sh` and `tests/lib/mutants.py` in the install manifest if the installer lists files one by one. |
| T6 | T4 | item 5 | Measure t108: clone this repository at `ef9c6f7` into the scratchpad, copy t108's state there, and run the engine from **outside** the clone (`python3 <this repo>/tests/lib/mutants.py <clone>`), so the engine files are not in the clone's diff and are not mutated. Base `7e2c539`, t108's frozen oracle. Background, under caffeinate. Put `MUTANTS k/n` and the time in the hop report. A t108 survivor is reported, not fixed: t108 is accepted. |
| T7 | T4, T5 | all | `bash tests/enforcement.sh`. A conflict with an accepted test is a STOP for the human. |
| T8 | T7 | all | `bash tests/loop.sh` until `LOOP n/n`, under `caffeinate -dim` in the background. The loop runs `bash tests/mutants.sh` on this hop's own diff (in place, about 30 s per mutant). A survivor is a send-back to GENERATE or a row that only the human signs: ask the human (AskUserQuestion) with each survivor's id, line and the draft reason, or on a run with no human end with `AUTOPILOT HALT: decision needed` naming the ids. Expected after EXECUTE 1: the mtime bump (APFS has nanosecond mtimes, so no test here can see it) and a few lines that cannot change behavior (`sys.path.insert` of the script's own directory, `return ""` before a falsy fall-through). Print `bash tests/scorecard.sh` and `bash tests/switch.sh`. |

## Order and risk

- T2 → T4 is the build; T3, T5 and T6 are independent.
- Risk: the loop's mutants line runs the t109 oracle once per mutant (about 30 s each), up to `MUTANTS_MAX` + 1 = 41
  times per loop pass: about 20 minutes. The edge commit re-runs the loop: run both in the background.
- Risk: mutants run in place, so do not edit files while the loop runs; the lock stops a second mutants run, and a
  killed run is repaired at the next start.
- Risk: the installer ships files by a list. T5 checks it, and T7 (T96, drift) finds a miss.
- Skills: test-driven-development applies through the frozen oracle (red now, green after T2–T5).
