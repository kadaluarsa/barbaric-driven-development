# Stress runs — quality preservation under rising difficulty

`evals/spike/stress.sh` drives a fresh ledger product through several cold, headless agent hops: two features of rising difficulty (each a GENERATE hop then an EXECUTE hop, with new laws declared UNPROVEN by the human), one **trap** slice that a human "approved" but that contradicts a locked law, a stage-10 audit hop whose rows `audit.sh` re-verifies, and the ship gate. Every hop is scored from the tree and the tool stream — laws GREEN with red twins, old invariant tests byte-identical, no unauthorized waiver, edge lines present — never from the agent's words.

| Run | Pack | Result | Note |
|---|---|---|---|
| `2026-09-02-run1-bcdb75e-sonnet` | `bcdb75e` | **6/7** | all six agent hops PASS incl. the trap; SHIP red because the pack's own READY-product self-test leaked a product PRD — fixed in `9e0ebd2` (T14b). See `REVIEW.md` for the craft read. |

Reproduce: build `evals/spike/Dockerfile`, authenticate inside the container, then `DEMO=/work/demoN OUT=/work/stress PROBE_MODEL=sonnet bash /opt/stress.sh`.
