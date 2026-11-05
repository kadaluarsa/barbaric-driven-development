# Stage 05b — t94-specplan-contract — PLAN

## Goal

EXECUTE adds a check that binds each new spec and plan to the contract fields and the signed language rules, on every host. EXECUTE also adds a benchmark scorer and moves the test table out of required reading.

**Spec:** [`../05b-t94-specplan-contract.md`](../05b-t94-specplan-contract.md).

## In scope this execute

- [ ] Check → `tests/lib/specplan.py`, `tests/specplan.sh`
- [ ] Rules, for the human's signature → `docs/cascade/specplan-rules.md`
- [ ] Layers → `tests/critique.sh`, `.githooks/pre-commit`, `.github/workflows/control-line.yml`
- [ ] Rule text → `AGENTS.md`, `docs/cascade/product-e2e-gre-pipeline.md`
- [ ] Benchmark → `tests/lib/specbench.py`, `tests/specbench.sh`, `evals/specbench/fixture.jsonl`, `evals/specbench/tasks.tsv`
- [ ] Table → `docs/cascade/control-line-evidence.md`, `CONTROL-LINE.md`, `tests/lint.sh`, `install.sh`
- [ ] Search → `.ignore`
- [ ] Records → `tests/enforcement.sh` (T94), `README.md`, `USAGE.md`, `CHANGELOG.md`

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
- An agent can delete the rules file, and the check then prints n/a. `tests/control-line.sh` must require the file in this repo. `bash install.sh --check` covers installed repos, and the critic must test this claim.
- The limits are not verified against Issue 9.
- The task set holds requests only. Hidden tests do not exist until the human plans a paid run.
- The benefit stays unmeasured. This slice does not prove a gain.

## Ask of you

1. Open Issue 9. The site refused this agent.
2. Confirm the limits of 20 words and 25 words. Do this before you sign the rules file on EXECUTE.
3. Accept that the check does not prove conformance, because the pack ships no dictionary.
4. Resolve review row R4 for t93: the merge and the 3.5.0 release came before the signed close.
5. Answer each `human` row in the critique, if one exists.

## Invariants this hop

- PRESERVE run: no. No compaction happened in this hop.
- /goal set to: the three validators above, on EXECUTE.
- /model /effort: claude-opus-5-5, medium effort from the seam.
- /plan: skipped. The human stated the design in the brief. This hop skipped `brainstorming` and `writing-plans` for the same reason.
- INVARIANTS I1–I18: held.
- reads: manifest for this stage: exceeded. The hop also read `tests/lib/critique.py`, `tests/lib/oracle.py`, `tests/lint.sh` and `CONTROL-LINE.md`, because the plan changes them or the gates that use them.
