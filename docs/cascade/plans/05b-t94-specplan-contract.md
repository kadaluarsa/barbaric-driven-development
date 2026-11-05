# Stage 05b — t94-specplan-contract — PLAN

## Goal

EXECUTE adds a check that binds each new spec and plan to the contract fields and the signed language rules, on every host. EXECUTE also adds a benchmark scorer and moves the test table out of required reading.

**Spec:** [`../05b-t94-specplan-contract.md`](../05b-t94-specplan-contract.md).

## In scope this execute

- [ ] Check → `tests/lib/specplan.py`, `tests/specplan.sh`
- [ ] Rules, for the human's signature → `docs/cascade/specplan-rules.md`
- [ ] Layers → `tests/critique.sh`, `.githooks/pre-commit`, `.github/workflows/control-line.yml`, `tests/control-line.sh`
- [ ] Rule text → `AGENTS.md`, `docs/cascade/product-e2e-gre-pipeline.md`
- [ ] Benchmark → `tests/lib/specbench.py`, `tests/specbench.sh`, `evals/specbench/fixture.jsonl`, `evals/specbench/tasks.tsv`
- [ ] Table → `docs/cascade/control-line-evidence.md`, `CONTROL-LINE.md`, `tests/lint.sh`, `install.sh`
- [ ] Search → `.ignore`
- [ ] Records → `tests/enforcement.sh` (T94), `README.md`, `USAGE.md`, `CHANGELOG.md`

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | REQ-1, REQ-2, REQ-3 | Build the check and its three named functions. |
| T2 | T1 | REQ-6 | Guard the rules and the off line, then add the rules file. |
| T3 | T1, T2 | REQ-4 | Wire the check into the critique, the hook and CI. |
| T4 | T1 | REQ-5 | Add the rule to `AGENTS.md`, the hop shape and the critic brief. |
| T5 | — | REQ-7 | Build the scorer, its fixture and its task set. |
| T6 | — | REQ-8 | Move the table, then change `tests/lint.sh` and `install.sh`. |
| T7 | T3, T4, T5, T6 | REQ-9 | Add T94, then run the full validators. |

## Out of scope this execute

- An instruction compiler.
- The t88 briefs archive.
- A stage-order check.
- A paid benchmark run, or an agent driver for that run.
- A dictionary file, or a claim of conformance.
- A rewrite of an accepted spec.
- A version bump.

## Definition of done

`bash tests/loop.sh` prints n/n with these validators:

- `bash tests/ac/t94_specplan_contract.sh`
- `bash tests/enforcement.sh # standing`
- `bash tests/lint.sh # standing`

## Risks / UNKNOWNs that still block

- Existing fixtures can break. `tests/enforcement.sh` copies `docs/` into its fixtures, so a fixture can hold the rules file and a spec with no contract. EXECUTE must keep each existing assertion at the same strength. If a fix needs a weaker test, EXECUTE stops and sends the slice back.
- A `--no-verify` commit can land an unsigned off line, and CI cannot detect it. The human's PR review covers this case.
- The limits are not verified against Issue 9.
- Stages 01 to 04 have no slice id, so the rule stays prose there.
- The task set holds requests only. Hidden tests do not exist until the human plans a paid run.
- The benefit stays unmeasured. This slice does not prove a gain.
- The AICL proposal is not a published standard, as far as this hop knows. The slice takes its ideas and does not claim its format.

## Ask of you

1. Open Issue 9. The site refused this agent.
2. Confirm the limits of 20 words and 25 words. Do this before you accept EXECUTE.
3. Accept that the check does not prove conformance, because the pack ships no dictionary.
4. Accept that stages 01 to 04 stay prose-only. Critique row C1 names this gap.
5. Resolve review row R4 for t93: the merge and the 3.5.0 release came before the signed close.
6. Answer each `human` row in the critique.

## Invariants this hop

- PRESERVE run: no. No compaction happened in this hop.
- /goal set to: the three validators above, on EXECUTE.
- /model /effort: claude-opus-5-5, medium effort from the seam.
- /plan: skipped. The human stated the design in the brief. This hop skipped `brainstorming` and `writing-plans` for the same reason.
- INVARIANTS I1–I18: held.
- reads: manifest for this stage: exceeded. The hop also read `tests/lib/critique.py`, `tests/lib/oracle.py`, `tests/lint.sh` and `CONTROL-LINE.md`, because the plan changes them or the gates that use them.
