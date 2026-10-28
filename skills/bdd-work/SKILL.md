---
name: bdd-work
description: >-
  Optional craft-workflow router for BDD repositories. Reads the current hop and slice,
  then selects investigation, bug-fix, feature, refactor, or verification. It does not
  grant cascade authority or advance human-owned state.
---

# /bdd-work — choose the craft workflow

Use this optional entry point for non-trivial engineering work in a BDD repository. First read `AGENTS.md`, `docs/cascade/hop-state.md` (or `docs/cascade/envelope.md` in a pre-split repo), the current slice spec when present, and only the law shards applicable to this hop. State the route and the evidence needed before acting.

## Routes

- **Investigation:** explain behavior or inspect a failure without changing files. Open the source and cite paths or commands.
- **Bug fix:** reproduce the defect, identify its cause, add or use a regression check, then report the observed result.
- **Feature:** tie changed behavior to the accepted slice and its acceptance checks. Do not widen the slice.
- **Refactor:** state which behavior stays constant and run the existing checks for it.
- **Verification:** inspect or execute the actual artifact and report the command and result; do not infer from a proxy.

Resolve overlapping intent in this order: read-only explanation is investigation; a requested fix is bug-fix (including its verification); read-only checking of an existing result is verification; new behavior is feature; an explicitly behavior-preserving structural change is refactor. If work spans independent tasks, name the smallest first route and leave the rest outside the slice.

## Cascade boundaries

The route selects craft steps only. The BDD cascade, accepted spec, laws, and human signatures remain authoritative.

- `CURRENT_HOP: NONE`: answer questions directly. A change request goes through the existing brief and signed-edge flow; do not start a cascade or edit hop state.
- `GENERATE`: help with the brief, spec, and plan only. Do not implement product code.
- `EXECUTE`: follow the accepted plan for the named slice only. Do not replace the plan, expand scope, start N+1, or cross the hop edge.
- Never change `CURRENT_HOP`, `CURRENT_STAGE`, `CURRENT_SLICE`, a signed `AUTOPILOT:` list, a D# law/validator, or `<EDIT>` content. Do not weaken a law to fit a requested feature.

If the request conflicts with the accepted spec, an in-force law, or the current hop boundary, state the conflict and stop at the existing human decision edge. Ask only when repository context cannot resolve a product-intent distinction. A route recommendation is never approval.

Give a short route card: **Route**, **why**, **evidence**, and **next permitted action**. Name missing optional tooling instead of claiming it ran. Do not claim this skill mechanically enforces laws or transitions; scripts and hooks do that.
