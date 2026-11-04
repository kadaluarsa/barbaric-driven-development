# Draft critique — t93-adaptive-effort-routing

Independent read-only critic: `effort_spec_critic`, reviewing draft commit `1d2ab2b`.
These rows are preserved verbatim. This is a draft review, not the formal GENERATE critique: no t93 frozen
oracle exists, and the signed current hop remains t91 EXECUTE. The formal critic must review the pinned tests.

## Brief

| C# | severity | finding | evidence |
|---|---|---|---|
| C1 | BLOCKER—expected prerequisite | The frozen acceptance tests and oracle remain pending. This is explicitly disclosed and appropriate for this draft, but formal GENERATE acceptance remains blocked until the signed hop, pinned tests and subsequent independent review exist. | `docs/cascade/05b-t93-adaptive-effort-routing.md:224`, `docs/cascade/05b-t93-adaptive-effort-routing.md:269` |

## Spec

| C# | severity | finding | evidence |
|---|---|---|---|
| C2 | HIGH | Complete the input/output schema before freezing exact-output cases. Required context fields, hop/stage validation, nested `previous`/`failure` property names, state serialization, and profile `schema_version` handling are unspecified. Independent builders cannot reliably produce the same accepted protocol. | `docs/cascade/05b-t93-adaptive-effort-routing.md:81`, `docs/cascade/05b-t93-adaptive-effort-routing.md:92`, `docs/cascade/05b-t93-adaptive-effort-routing.md:123`, `docs/cascade/05b-t93-adaptive-effort-routing.md:158` |
| C3 | HIGH | Define precisely whether changed evidence for the **same failure fingerprint** escalates. Policy says “a new failure with new…evidence,” while AC3 requires “matching task + failure + changed evidence.” These permit different escalation predicates. Add cases for same failure/new evidence, new failure/same evidence, and first failure after a previous decision without fingerprints. | `docs/cascade/05b-t93-adaptive-effort-routing.md:136`, `docs/cascade/05b-t93-adaptive-effort-routing.md:232` |
| C4 | MEDIUM | Define the comparison used for below-target warnings. Many internal levels may map to one native value, and supported override/current values need not occur in any mapping. For `low=A, medium=A, high=B`, an override of A must have a specified comparison with medium; unmapped supported values need an explicit incomparable outcome. The next-session warning requires the same rule. | `docs/cascade/05b-t93-adaptive-effort-routing.md:143`, `docs/cascade/05b-t93-adaptive-effort-routing.md:161`, `docs/cascade/05b-t93-adaptive-effort-routing.md:194` |
| C5 | MEDIUM | Make transition precedence total. Unsupported target plus absent current setting matches both `unknown` and `unsupported`. The text only explicitly prioritizes invalidation over update rules. Specify the winning result and freeze this overlap alongside absent profile and equal-setting combinations. | `docs/cascade/05b-t93-adaptive-effort-routing.md:189`, `docs/cascade/05b-t93-adaptive-effort-routing.md:197`, `docs/cascade/05b-t93-adaptive-effort-routing.md:234` |
| C6 | MEDIUM | Define state behavior when a same-task call has no current failure: retain earlier fingerprints or clear them. Clearing loses the evidence needed to identify a later repeated failure; retaining changes the meaning of returned “current” state. Either can be deterministic, but the oracle must choose explicitly. | `docs/cascade/05b-t93-adaptive-effort-routing.md:93`, `docs/cascade/05b-t93-adaptive-effort-routing.md:123`, `docs/cascade/05b-t93-adaptive-effort-routing.md:139` |
| C7 | LOW | Identify how actual stage reaches hook advice while preserving `route_lines()`’s signature. That function currently receives root/hop/prompt/idle, whereas the proposed helper requires stage and phase precedence treats stages 10/11 specially. Avoid silently passing an empty stage and misclassifying audit advice. | `.claude/hooks/seam.py:69`, `docs/cascade/plans/05b-t93-adaptive-effort-routing.md:83`, `docs/cascade/plans/05b-t93-adaptive-effort-routing.md:109`, `docs/cascade/05b-t93-adaptive-effort-routing.md:128` |
