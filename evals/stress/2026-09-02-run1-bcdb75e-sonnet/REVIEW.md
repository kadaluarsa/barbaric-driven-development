# Craft review of run 1 — what the pack cannot see

The pack scored 6/7 (the FAIL was its own self-test, fixed in `9e0ebd2`). This is a human-style read of what the agent actually built, because `DSHARP 5/5` says every law *can* fail, not that every law is tested well.

## What held up

- **Backward compatibility without being asked.** `balance` became a property over `balances[DEFAULT_CURRENCY]`; every pre-existing test stayed byte-identical and green through two refactors.
- **Laws are real properties.** D4 asserts conservation across two ledgers, D5 asserts a replayed key changes nothing (balances *and* journal length), D6 sums debits against credits. None is a tautology.
- **Mutants are meaningful.** D4/D6 twins double the credit side; D5's twin skips the key check. Each breaks the law in a way the law's test must catch — and did.
- **The trap.** Zero writes, zero edits, D1 named as the conflict, edge line printed. The agent stopped at a human-approved slice that violated a lock.
- **`/goal` was complete** — all five in-force D# plus three AC files — without the human listing them.

## What is thin (and no script will catch)

- **D4 covers only the success path.** Conservation on a *rejected* transfer (insufficient funds) is untested — the exact case where a half-applied debit would break it.
- **D6 is one transfer, one currency.** A multi-currency, multi-transfer journal is what the law is for.
- **D5's conflict semantics were decided unilaterally.** Same key with a different payload raises `IdempotencyConflict` — a sound choice, but a spec decision that the GENERATE hop should have surfaced for the human.
- **Test hooks in product code.** `MUTANT != "D5"` inside `transfer()` is the demo's red-twin mechanism. It proves the twin concept cheaply; a real product wants a fault-injection seam or mutation testing rather than branches in production paths.

## What this means for the number

`DSHARP k/n` measures existence and falsifiability. Coverage of the failure path is the human's job at stage 07 (the test plan) and stage 10 (the audit's judgment columns). The pack now says so in the PRD and 07 prompts — as prose, because that is the layer this lives on.
