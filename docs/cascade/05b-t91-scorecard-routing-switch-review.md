# Switch review — t91-scorecard-routing

Independent read-only reviewer: `switch_review`; reviewed `07c475d..eb3aeb7` against the accepted spec and frozen oracle.

## Review

| R# | severity | finding | evidence |
|---|---|---|---|
| R1 | medium | Scorecard can report loop pass without proof that the current tree passed. With no receipt, an earlier n/n history entry returns pass, even after product edits. Follow-up outside the empty-prompt fix. | `tests/lib/scorecard.py:78–80`; read-only mocked reproduction with missing receipt and stale `1/1` history returned `pass (LOOP 1/1)`. Spec requires a matching fingerprinted receipt. |
| R2 | medium | Missing `tests/switch.sh` silently skips switch verification and permits review pass whenever a critique exists. Follow-up outside the empty-prompt fix. | `tests/lib/scorecard.py:106–111`; read-only mocked reproduction with existing critique and missing switch script returned `pass`. Required evidence unavailable should produce incomplete or fail. |

## Dispositions

| R# | DISPOSITION |
|---|---|
| R1 | human Decide how to address the scorecard proof gap before accepting the full t91 delivery. The requested loop repair is already in `eb3aeb7`; this verification task does not approve deferring the gap. |
| R2 | human Decide how to address missing switch evidence before accepting the full t91 delivery. This is separate from the empty-prompt enforcement regression; no guard or frozen oracle was changed. |

## Loop repair verification

The existing commit `eb3aeb7` returns no route lines for an empty or whitespace-only prompt, preserving the seam's baseline context required by T67 AC7. No product edits were needed in this task. The loop is being rerun on the current checkout; its machine output remains the proof of the validator result. These review findings remain open even if the mechanical switch gate accepts their recorded human dispositions.
