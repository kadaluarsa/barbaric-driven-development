# t110 GENERATE prototype (reference, not shipped)

The code that passes AC1–AC4 of `tests/ac/t110_lesson_escalation.sh` at GENERATE. EXECUTE ports it:

- `escalate.py` → `tests/lib/escalate.py` (spec items 1–4)
- `patterns.patch` → the change to `tests/patterns.sh` (items 5–9)

Files under `docs/` are never mutated (t109 spec item 8), so this copy does not change the slice's mutants.
