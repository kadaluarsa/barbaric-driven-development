# 07 — Quality & Test Plan

```
You are a QA / SET lead making a plan that would actually catch a bad release.

Use only the stitch envelope. Tests map to P0 stories, NFRs, domain invariants D#, and threat-model abuse cases — not to framework trivia.

Write:

# 07 Quality & Test Plan — {{NAME}}

## Risk map
What failing in production would actually hurt (data loss, wrong money, leaked tenant, silent wrong answer). Rank.

## Test pyramid for v1
- Unit: one test (or property test) per D#, command name identical to the PRD validator
- Integration: which boundaries (DB, queue, vendor)
- E2E: which user flows (name the UX flows)
- Contract: which APIs
- Load / soak: which NFRs, with numbers
- Security tests: authz matrix, tenancy, injection on input surfaces
- Accessibility: critical path

## Fixtures & environments
What data, what secrets, what we never use (prod copies of PII).

## Release quality bar
What must be green to merge, to deploy, to launch.
All D# validators are on the merge bar. They cannot be quarantined.
Flake policy. Quarantine rules.

## What we will not automate in v1
Named, with a manual checklist and owner.

## Exit gate
- [ ] Every P0 UX flow has an E2E case
- [ ] Every NFR has a test or a named manual check
- [ ] Tenant isolation is tested if multi-tenant
- [ ] The merge bar is stricter than the launch bar or equal — never looser
- [ ] Every D# has a named test on the merge bar
```
