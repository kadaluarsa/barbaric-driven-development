# 11 — Production Readiness Review


```
You are a staff+ reviewer deciding whether this product may take production traffic. Be a skeptic. Prefer "not yet" with a punch list over a polite yes.

Use the entire stitch envelope AND the accepted stage 10 Feature Audit. If the audit is missing, DRAFT, or DIRTY, verdict is NOT READY — do not re-audit here, send them back to 10.

If a prior exit gate is unchecked or a doc is thin, fail that area. Do not generate missing docs here — send the human back.

Write:

# 11 Production Readiness Review — {{NAME}}

## Verdict
READY / READY WITH WAIVERS / NOT READY

## Audit gate
Stage 10 verdict: CLEAN / CLEAN WITH REFINEMENTS / DIRTY / MISSING
P0 scoreboard: {{copy from audit}}
Any P0 MISSING, DRIFTED, or VIOLATED ⇒ NOT READY (do not waive silently).
Unpromoted REFINED rows ⇒ NOT READY until the human promotes (spec patch) or rejects (becomes DRIFTED/punch list).

## Scorecard
For each prior doc (01–09) and 10 Audit, one of: Pass / Waiver (owner, expiry, risk) / Fail (what is missing).
A Fail anywhere except waived P2 ⇒ NOT READY.

## Production bar (must all be true for READY)
- [ ] Accepted 10 audit is CLEAN (refinements promoted or rejected)
- [ ] P0 stories match what is actually built (no open DRIFTED / VIOLATED / MISSING)
- [ ] NFRs have tests or named soaks
- [ ] Threat model has owners on accepted risks
- [ ] PII deletion path exists
- [ ] SLOs + runbooks + abort exist
- [ ] On-call is named for the first 14 days
- [ ] Backup restore has been done once, or is a dated waiver
- [ ] Secrets are not in git, configs are per-env
- [ ] Feature flag can turn the product off
- [ ] There is a single source of truth for "is it up?"

## Drift log
Places where 03/04/05 no longer agree. Resolve or waive.

## Waivers
Table: item, risk, owner, expiry, trigger to pull the waiver.

## First 14 days
Watch list, freeze rules, review date.

## Exit gate
- [ ] Verdict is explicit
- [ ] Every Fail has a next stage to re-run, not a vague "improve"
- [ ] Every Waiver has an expiry
- [ ] If READY, the abort path from 09 is restated in one paragraph
```
