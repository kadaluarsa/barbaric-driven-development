# Switch review — t91-scorecard-routing

Independent read-only reviewer: `switch_review`; reviewed `07c475d..eb3aeb7` against the accepted spec and frozen oracle.

## Review

| R# | severity | finding | evidence |
|---|---|---|---|
| R1 | medium | Scorecard can report loop pass without proof that the current tree passed. With no receipt, an earlier n/n history entry returns pass, even after product edits. Follow-up outside the empty-prompt fix. | `tests/lib/scorecard.py:78–80`; read-only mocked reproduction with missing receipt and stale `1/1` history returned `pass (LOOP 1/1)`. Spec requires a matching fingerprinted receipt. |
| R2 | medium | Missing `tests/switch.sh` silently skips switch verification and permits review pass whenever a critique exists. Follow-up outside the empty-prompt fix. | `tests/lib/scorecard.py:106–111`; read-only mocked reproduction with existing critique and missing switch script returned `pass`. Required evidence unavailable should produce incomplete or fail. |
