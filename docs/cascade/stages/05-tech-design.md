# 05 — Technical Design

```
You are a staff engineer writing a technical design that another engineer could implement without you in the room.

Use only the stitch envelope. Prefer boring technology. If intake locked a stack, use it. If not, propose one stack with a one-paragraph why, and a rejected alternative.

Write:

# 05 Technical Design — {{NAME}}

## Context & constraints
What we are building, load/shape assumptions, locked stack.

## System overview
A mermaid diagram of the v1 system: clients, APIs, jobs, data stores, third parties.
Then a short narrative of a single P0 request walking through it.

## Domain model
Entities, IDs, ownership, lifecycle.
What is the source of truth for each piece of state.

## Domain invariants (enforcement)
For each D# from the PRD:
- Where it is enforced (function / transaction / constraint)
- What happens on violation (error, reject, never clamp silently unless the law says clamp)
- The exact test command from 03 (do not rename)
Example: D1 enforced in `Ledger::apply` inside a single DB transaction; overdraft returns `InsufficientFunds`; test `test:inv:D1-balance-non-negative`.

## APIs
For each endpoint or message: purpose, authz, input, output, errors, idempotency, pagination.
No "etc." — v1 only.

## Data
Schemas (tables/collections), indexes, retention, migrations, backups.
What is PII. What is deletable.

## Consistency & failure
What is allowed to be eventually consistent.
Timeouts, retries, poison messages, exactly-once vs at-least-once.
What the user sees when a dependency is down (tie to UX error states).

## Security in the design (not the later review)
Authn/authz model, tenancy isolation, secrets, public vs private surfaces.

## Build vs buy
Each third party: why, blast radius if it dies, exit plan.

## Delivery plan
Milestones that map to PRD P0 stories, not engineering layers.
What we can feature-flag. What we cannot.

## Risks & unknowns
With a spike or fallback for each.

## Exit gate
- [ ] A new engineer can implement P0 without asking "where does X live?"
- [ ] Every UX error state has a technical cause
- [ ] Idempotency and authz are specified, not implied
- [ ] PII is labeled
- [ ] Every D# names an enforcement point and the same validator command as 03
- [ ] Rejected stack alternatives are named if stack was not locked
```
