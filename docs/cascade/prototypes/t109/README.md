# t109 GENERATE prototype (reference, not shipped)

The engine that passes AC1–AC7 of `tests/ac/t109_oracle_strength.sh` at GENERATE (critique C7). EXECUTE ports it:

- `mutants.py` → `tests/lib/mutants.py`
- `mutants.sh` → `tests/mutants.sh`
- `existing-files.patch` → the changes to `tests/lib/oracle.py` (gate, item 15), `tests/lib/laws.py`,
  `.githooks/pre-commit` and `.claude/hooks/hop_guard.py` (human-owned equivalent rows, item 14)

Files under `docs/` are never mutated (spec item 8), so this copy does not change the slice's mutants.
