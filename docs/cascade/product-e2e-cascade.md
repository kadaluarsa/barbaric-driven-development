# Product E2E Cascade — Prompt Pack

A staged prompt chain that takes a product from a raw idea to a production-grade pack. You run one stage at a time. Between stages you **stitch**: edit the output, lock decisions, kill ideas, then feed the edited pack into the next prompt.

**`<EDIT>` markers:** anything inside `<EDIT>…</EDIT>` is yours to fill or stitch. The agent must not invent those lines. Replace the `{{…}}` (or example) inside the tags. Leave `UNKNOWN` if you do not know yet. After you fill a tag you may leave it in place so later hops can see it was human-authored.


Do not skip stitches. The quality of later stages is only as good as the documents you actually accept.

---

## How to run it

Default operating loop is **Generate → you review → Execute → you review**, one hop at a time. Spec shapes live in this file. The conductor, execute meanings, and agent control lines live in `product-e2e-gre-pipeline.md`. Hand **both** files to a coding agent.

1. Fill in `00 — Intake` once. That is the source of truth.
2. **Generate** stage N: spec + plan only. Agent stops.
3. You stitch the spec/plan (lock, cut, rewrite) or send back.
4. **Execute** stage N: only the approved plan. Agent stops. 01–04 are evidence/design artifacts, not the app. 05 is bootstrap/spikes. The app is 05b, one P0 slice per hop.
5. You accept artifacts, then generate N+1. Do not skip an execute review.

**Rule:** later stages may not silently override a locked decision. They must flag a conflict and propose options.
**Rule:** a coding agent never generates and executes in the same reply, and never starts N+1 before execute N is accepted.
**Rule:** loop invariants I1–I18 in `product-e2e-gre-pipeline.md` must be reprinted after every hop and after `/compact`, `/clear`, `/resume`, `/rewind`. Durable locks live in `docs/cascade/` (git). `/memory` is a cache. Opus+`/plan` for GENERATE/audit/PRR; Sonnet for approved EXECUTE unless `/usage` justifies a one-hop upgrade.
**Rule (I15):** GENERATE never executes and never starts N+1 (conductor eval fails if it does). `/loop` only on 05b / 06–09 / 10 punch. D# validators are the CI merge bar. Auto-merge is forbidden until CLEAN 10 + 11 READY.
**Rule (I16):** `/loop` is GRE execute (this hop, LOOP k/n). `/barbar` is her eval farm (BARBAR k/n until 10/10). `/barbar` must not run product stages. `/barbar merge` only after CLEAN 10 + 11 READY.
**Rule (I17):** T1–T7 in CONTROL-LINE.md are required. Chat is not evidence. CI must run `tests/barbar.sh` and `tests/i17_dune.sh`.
**Rule (I18):** Enforcement is layered — CI + branch protection, then git hooks, then agent hooks, then prose. Commands are scripts (`tests/loop.sh`, `tests/barbar.sh`); `LOOP k/n` and `BARBAR k/n` are never typed. Never weaken a layer to pass a hop. T8–T18 in `tests/enforcement.sh` are required.
**Rule:** [Superpowers](https://github.com/obra/superpowers) is the code-hop toolkit. Binding and clash overrides live in the GRE file. Cascade outranks Superpowers. One spec tree: `docs/cascade/`.

---

## Stitch envelope

Copy this block under every stage prompt. Keep it updated. This is the memory of the cascade.

```
### Stitch envelope

Product: <EDIT>{{NAME}}</EDIT>
Stage just completed: <EDIT>{{N — TITLE}}</EDIT>
Stage about to run: <EDIT>{{N+1 — TITLE}}</EDIT>

#### Intake (stable)
<EDIT>
{{paste 00 — Intake, including any later corrections}}
</EDIT>

#### Accepted docs (canonical, already stitched)
- 01 Problem & Opportunity: <EDIT>{{paste or "not yet"}}</EDIT>
- 02 Users & JTBD: <EDIT>{{paste or "not yet"}}</EDIT>
- 03 PRD: <EDIT>{{paste or "not yet"}}</EDIT>
- 04 UX Spec: <EDIT>{{paste or "not yet"}}</EDIT>
- 05 Technical Design: <EDIT>{{paste or "not yet"}}</EDIT>
- 06 Security, Privacy, Compliance: <EDIT>{{paste or "not yet"}}</EDIT>
- 07 Quality & Test Plan: <EDIT>{{paste or "not yet"}}</EDIT>
- 08 Observability, SLOs, Runbooks: <EDIT>{{paste or "not yet"}}</EDIT>
- 09 Launch Plan: <EDIT>{{paste or "not yet"}}</EDIT>
- 10 Feature Audit: <EDIT>{{paste or "not yet"}}</EDIT>
- 11 Production Readiness Review: <EDIT>{{paste or "not yet"}}</EDIT>

#### Locked decisions (do not reopen unless a conflict is explicit)
<EDIT>
- {{decision}} — locked by {{who}} on {{date}} — reason: {{why}}
</EDIT>

#### Domain invariants (product physics — D1… Dn)
Format: D# | MUST / MUST NOT | subject | validator command | slices that may touch it
<EDIT>
- D1 | MUST | user.balance_cents >= 0 after every command | `test:inv:D1-balance-non-negative` | any money slice
- D2 | MUST NOT | cross-tenant read | `test:inv:D2-tenant-isolation` | any data slice
</EDIT>
If a D# has no validator command, it is not an invariant yet. /goal may not start 05b until every D# the slice can touch has a test name.

#### Stitch notes for this hop (human edits since last generation)
<EDIT>
- Changed: {{what you rewrote}}
- Killed: {{ideas you rejected, and why}}
- Open: {{questions this next stage must resolve}}
- Constraints added: {{new limits}}
</EDIT>

#### Non-goals / out of scope
<EDIT>
- {{item}}
</EDIT>

#### Evidence & constraints
<EDIT>
- Stack / vendors already chosen: {{or "none"}}
- Compliance regimes: {{e.g. none / GDPR / SOC2 / HIPAA / PCI}}
- Scale targets: {{users, QPS, data size, latency}}
- Deadline / launch window: {{or "none"}}
- Team shape: {{roles, size}}
</EDIT>

#### Canonical tree (git — 10-year truth)
Root: <EDIT>{{docs/cascade/}}</EDIT>
This hop Superpowers plan (if any): <EDIT>{{docs/cascade/plans/… or none}}</EDIT>
`docs/superpowers/` is hop scratch. This tree + envelope win on conflict.
```

---

## 00 — Intake

Fill this yourself. Do not generate it until you have at least a sentence for each field. Incomplete intake is fine; mark unknowns as `UNKNOWN`.

```
<EDIT>
# 00 Intake — {{PRODUCT NAME}}

One-liner: {{what it is, for whom, what changes}}
Problem in their words: {{quote or paraphrase}}
Who it is for (primary): {{role, context}}
Who it is not for: {{}}
Why now: {{trigger}}
Success in 90 days looks like: {{observable outcome}}
Hard constraints: {{time, money, stack, legal, brand}}
Known unknowns: {{list}}
References: {{docs, competitors, tickets, mockups}}

Domain invariants (must-never / must-always — you write these; /loop will not invent them):
- D1: {{e.g. user balance_cents MUST be >= 0 after every command. Overdraft is rejected, never negative.}}
- D2: {{e.g. a tenant MUST NOT read another tenant's rows.}}
- D3: {{e.g. money movement MUST be a double-entry pair in one transaction.}}
</EDIT>
If you cannot name one yet, write D1: UNKNOWN — then stage 03 must either lock it or keep UNKNOWN. Empty means "no laws," which is how balances go negative.
```

---

## Stage prompts

Each prompt below is copy-paste. Always attach the stitch envelope. Always produce the named document in the named shape. Always end with an **Exit gate** the human must pass before the next hop.

---

### 01 — Problem & Opportunity

```
You are a product lead writing the Problem & Opportunity doc for a product that must reach production grade.

Use only the stitch envelope. Do not invent users, market size, or quotes. If evidence is missing, write UNKNOWN and say what would confirm it.

Write the document in this exact structure:

# 01 Problem & Opportunity — {{NAME}}

## Problem
- Who hurts, in what situation, how often, what they do today
- Cost of the status quo (time, money, risk, trust) — mark UNKNOWN if unmeasured
- Why existing tools fail (be specific, not "they are outdated")

## Opportunity
- The change we make, in one paragraph
- Why this team / this moment can win
- Wedge: the smallest valuable first surface

## Alternatives considered
- Do nothing
- Buy / partner
- Build a thinner version
For each: why it loses to the proposed path, or when it would win

## Risks if we are wrong
- Top 5, with a cheap test for each

## Exit gate (you fill this, then the human confirms)
- [ ] Problem is stated without mentioning our solution
- [ ] Primary user and situation are named
- [ ] Wedge is smaller than the vision
- [ ] At least one UNKNOWN is explicit
- [ ] A skeptic could disagree with the opportunity without asking "what is this product?"

Do not write requirements, screens, or architecture.
```

---

### 02 — Users & Jobs-to-be-Done

```
You are a product researcher turning an accepted Problem & Opportunity doc into Users & JTBD.

Use only the stitch envelope. Do not create fictional quotes. If you lack research, label personas as HYPOTHESIS and list the cheapest validation.

Write:

# 02 Users & JTBD — {{NAME}}

## Primary user
- Role, environment, constraints, tools already in hand
- Job-to-be-done (when… I want… so I can…)
- Success / failure from their point of view
- Frequency and urgency of the job

## Secondary users (max 2)
Same shape. If a secondary user can veto, say so.

## Anti-user
Who we will disappoint on purpose, and why that is acceptable.

## Journey (current vs desired)
A short table: trigger → current path → pain → desired path → proof we succeeded

## Edge cases that are in scope vs out
- In: …
- Out: …

## Validation plan
3 cheap tests before we freeze the PRD (interview, support-log pull, prototype, waitlist, etc.)

## Exit gate
- [ ] Primary JTBD does not mention our UI
- [ ] Anti-user is named
- [ ] At least one persona is marked HYPOTHESIS if unvalidated
- [ ] Secondary users cannot quietly expand scope

Do not write the PRD yet.
```

---

### 03 — PRD (Product Requirements)

```
You are a product manager writing a production-bound PRD. Ambiguity here becomes production incidents later.

Use only the stitch envelope. Locked decisions are law. If a requirement fights a lock, stop and list the conflict — do not paper over it.

Write:

# 03 PRD — {{NAME}}

## Summary
Problem, who, wedge, 90-day success — 8 lines max.

## Goals & non-goals
Goals as measurable outcomes (metric, baseline, target, window).
Non-goals as things we will be asked for and will refuse.

## Scope
### In for v1 (wedge)
User stories: As a… I can… so that…
Each story has: acceptance criteria (Given/When/Then), priority (P0/P1/P2), owner function (eng/design/ops).

### Explicitly out
List. Include the tempting ones.

## Requirements
Functional, numbered FR-1…
Non-functional, numbered NFR-1… covering: latency, availability, throughput, data retention, accessibility, i18n, auditability, offline/online.
Every NFR has a number, not a vibe ("fast", "secure").

## Domain invariants
Promote intake D# rows into a table. Add any the PRD discovered. These are not NFRs (those are numeric targets). These are laws that remain true in every state.

| ID | Law (MUST / MUST NOT) | Bad example (the bug this forbids) — becomes the **red twin** command in the envelope | Validator (test command) | Owner stage |
|----|------------------------|------------------------------------|--------------------------|-------------|
<EDIT>
| D1 | user.balance_cents MUST be >= 0 after every command | debit 100 when balance is 50 succeeds | `test:inv:D1-balance-non-negative` | 05 / 05b / 07 |
| D2 | … | … | … | … |
</EDIT>

Rules:
- A story that can break a D# and has no validator is not P0-ready. A validator with no red twin is not in force either: the bad example must be runnable and must fail (`tests/dsharp_strength.sh`).
- /loop and /goal do not infer D# from prose. Only the validator command counts.
- UNKNOWN D# stays UNKNOWN until locked here. Do not silently invent money/tenancy laws.

## Analytics & success
Events we must emit, properties, and the dashboard questions they answer.
Guardrail metrics we must not tank.

## Dependencies & assumptions
External systems, teams, vendors, legal. What happens if each slips.

## Open questions
Only questions that block v1. Owner + decide-by date.

## Changelog
v0 generated. Human stitch notes will append.

## Exit gate
- [ ] Every P0 story has Given/When/Then
- [ ] Every NFR is numeric or binary
- [ ] Non-goals include at least 3 things stakeholders will ask for
- [ ] No requirement contradicts a locked decision
- [ ] Every D# has a law, a bad example, and a validator command (or is explicitly UNKNOWN)
- [ ] Scope is a wedge, not the vision

Do not design screens or pick infrastructure unless the intake already locked it.
```

---

### 04 — UX Spec

```
You are a product designer writing an implementation-ready UX spec, not a mood board.

Use only the stitch envelope. Cover P0 stories completely. P1 only if it costs little. Ignore P2.

Write:

# 04 UX Spec — {{NAME}}

## Surfaces
Every screen / surface / state the user can land on in v1. Name them. One job per surface.

## Flows
For each P0 story: happy path, empty, loading, error, permission-denied, partial-failure.
Name the states. Do not leave "and then it works" gaps.

## Information architecture
Nav, hierarchy, what is global vs contextual.
What we do not put in the UI yet.

## Content & empty states
Key copy. Empty states that teach the job, not "nothing here".

## Interaction rules
- Destructive actions
- Undo / confirm
- Keyboard / a11y
- Mobile vs desktop if both exist
- Defaults that prevent the most common mistake

## Instrumentation in the UI
Where each PRD event fires (surface + action).

## Open design questions
Only blockers. Options, not essays.

## Exit gate
- [ ] Every P0 story has happy + empty + error
- [ ] No flow depends on an FR that is not in the PRD
- [ ] Destructive paths are specified
- [ ] Copy is written for empty and error, not "TBD"

Do not pick a visual design system unless intake locked one. Do not invent features.
```

---

### 05 — Technical Design

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

---

### 06 — Security, Privacy, Compliance

```
You are a security & privacy engineer reviewing a system that will run in production, not a compliance theater checklist.

Use only the stitch envelope. Threat-model the actual design. If a control is not in v1, say "accepted risk" with owner and expiry — do not hide it.

Write:

# 06 Security, Privacy, Compliance — {{NAME}}

## Data inventory
What we collect, why (purpose), where stored, who can access, retention, deletion path.
Mark special categories (auth secrets, payment, health, kids, location).

## Threat model (STRIDE-lite)
For each trust boundary in the technical design:
- Spoofing, tampering, repudiation, info disclosure, denial of service, elevation
Only real threats. Skip generic "use HTTPS".

## Controls
Authn, authz, session, secrets, encryption (in transit / at rest), tenancy, supply chain, logging of security events, rate limits, admin paths.
Each control maps to a threat or a legal requirement.

## Privacy
Lawful basis if relevant, DSR (access/export/delete) flow, subprocessors, tracking, consent.
If no regime applies, still define deletion and access.

## Abuse & misuse
How a motivated user or attacker would use v1 wrongly. Mitigations or accepted risk.

## Compliance mapping
Only regimes named in intake. If none: "none locked — residual risk: …"

## Exit gate
- [ ] Every PII field has retention + deletion
- [ ] Admin / break-glass paths are specified
- [ ] At least one accepted risk is written, or an explicit "no accepted risks"
- [ ] Threats are about THIS system, not a generic app
```

---

### 07 — Quality & Test Plan

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

---

### 08 — Observability, SLOs, Runbooks

```
You are an SRE writing the production nervous system before the first deploy.

Use only the stitch envelope. If you cannot name the symptom a human would see, the SLO is wrong.

Write:

# 08 Observability, SLOs, Runbooks — {{NAME}}

## User journeys to watch
The 3–5 journeys that ARE the product. Map each to a golden signal (latency, traffic, errors, saturation).

## SLIs / SLOs / error budget
For each journey: SLI definition, measurement (where), SLO target, window, error-budget policy (what we stop shipping).

## Telemetry
Metrics, logs, traces — what we emit, cardinality limits, PII rules in logs (must match 06).
Required dashboards. Required alerts (symptom-based, not "CPU high").

## Alert routing
Who wakes up, when, for what. No alert without a runbook link.

## Runbooks (v1)
For each P0 failure mode from technical design + threat model:
- Symptom
- Dashboard
- Immediate mitigation (feature flag, failover, degrade)
- Diagnosis steps
- When to page next
- Customer comms one-liner

## Capacity & restore
Backup, restore drill, RPO/RTO, dependency SLOs we inherit.

## Exit gate
- [ ] Every P0 journey has an SLO
- [ ] Every page-worthy alert has a runbook
- [ ] Logs are forbidden from containing the PII listed in 06, or redaction is specified
- [ ] There is a degrade mode, not only "site down / site up"
```

---

### 09 — Launch Plan

```
You are a product + eng lead writing a launch that can be aborted.

Use only the stitch envelope.

Write:

# 09 Launch Plan — {{NAME}}

## Launch type
Dogfood / private beta / public / ramped %. Why this one.

## Audience & eligibility
Who gets it, how they are chosen, how they are excluded, how they opt out.

## Sequencing
Flag name, % steps, soak time, success criteria to raise, abort criteria to roll back.
Who has the abort button (named role).

## Comms
Internal, support, customers, status page. Templates, not "we will tweet".

## Support readiness
Known issues, macros, escalation, what support can and cannot promise.

## Legal / billing / ops checkoffs
Only items that exist in this product.

## Rollback
Technical rollback AND product rollback (what users already did that we must preserve).

## Exit gate
- [ ] Abort criteria are numeric
- [ ] Rollback preserves user data already written
- [ ] Support has macros before public traffic
- [ ] First ramp is small enough that a total failure is embarrassing, not existential
```

---

### 10 — Feature Audit (AI)

This is the last *evidence* hop. It inspects accepted specs against the repo (and other accepted artifacts). It does not write features. It does not take the agent's word for what it built.

Statuses (exactly one primary per item):

- **IMPLEMENTED** — present, and it matches the accepted spec. Proof is a file path + a test (or a named manual check from 07).
- **DRIFTED** — something in this feature area exists, but behavior / API / UX / data does not match the accepted spec, and no stitch locked the change. Silent divergence.
- **VIOLATED** — breaks a locked decision, a non-goal, an NFR, a 06 control, or tenancy/PII rules. Violation beats other labels.
- **REFINED** — differs from the original spec in a way that looks like an improvement (simpler, safer, clearer), with evidence. Not yet canonical until the human promotes it into the spec or rejects it as drift.
- **MISSING** — no artifact. Required so unbuilt P0s cannot hide. Treat as blocking when the item is P0.

Precedence: VIOLATED > MISSING (for P0) > DRIFTED > REFINED > IMPLEMENTED.

```
You are an independent auditor, not the author of the code. Be hostile to narrative. If you did not open a file, you may not call it IMPLEMENTED.

Inputs (all required):
- Stitch envelope with accepted docs 01–09
- The repository (read code, tests, configs, flags, runbooks)
- Accepted 05b slice list (what was supposed to land)

Do not audit drafts. Only accepted specs are the baseline.
Do not take execute reports as proof. Proof is in the tree.

Inventory every item below, even if "obviously done":
- Every domain invariant D# from PRD 03 (a broken D# is VIOLATED, never DRIFTED)
- Every P0 and P1 story / FR from PRD 03
- Every NFR from 03
- Every P0 UX flow (happy / empty / error) from 04
- Every v1 API from 05
- Every 06 control and PII deletion path
- Every 07 merge-bar test
- Every 08 SLO / page-worthy alert / runbook
- Every 09 flag / abort / rollback
- Extra behavior in the repo that is not in the spec (scope creep)

For each item write one table row:

| ID | Spec claim (quote, short) | Evidence (paths, tests, commands) | Primary status | Also-violates | Send back to stage | Notes |

Primary status is one of: IMPLEMENTED | DRIFTED | VIOLATED | REFINED | MISSING

Rules:
- IMPLEMENTED requires evidence in the repo. "We built this in 05b slice 2" is not evidence.
- DRIFTED requires a concrete delta: expected vs actual.
- VIOLATED must name the lock / NFR / non-goal / control that was broken.
- REFINED must say why it is better, and a one-line proposed spec patch. Do not auto-promote.
- Extra unspecced features: VIOLATED if they hit a non-goal; otherwise DRIFTED (scope creep) unless you argue REFINED.
- If you cannot find evidence, it is MISSING, not IMPLEMENTED.

Then write:

# 10 Feature Audit — {{NAME}}

## Method
What you opened (dirs, tests run). If tests were not run, say so.

## Scoreboard
- P0: n IMPLEMENTED / n DRIFTED / n VIOLATED / n REFINED / n MISSING
- P1: same
- NFR / controls / SLOs: same

## Blocking (must be empty for PRR READY)
Every P0 that is MISSING, DRIFTED, or VIOLATED.
Every NFR/control marked VIOLATED.
Each line: ID, status, send-back stage, proposed fix.

## Refinements awaiting you
Table: ID, current spec, what code does, why it might be better, promote vs reject.

## Drift map
Where 03, 04, 05, and code disagree.

## Punch list (for execute 10)
Ordered, smallest fixes first. No new P1/P2 features.

## Audit verdict
CLEAN / CLEAN WITH REFINEMENTS / DIRTY
- CLEAN: no P0 MISSING/DRIFTED/VIOLATED, no control violations
- CLEAN WITH REFINEMENTS: CLEAN except unpromoted REFINED rows (human must promote or reject before stage 11)
- DIRTY: anything in Blocking

## Exit gate
- [ ] Every P0 story has a row
- [ ] Every status other than MISSING has a path or test
- [ ] No IMPLEMENTED row lacks evidence
- [ ] Punch list maps to send-back stages
- [ ] Verdict is explicit
```

After the human reviews the audit:

- `send back:` plus notes → re-GENERATE 10
- `approved, execute stage 10` → agent performs only the punch list (fixes drift/violations/missing). No new features. Then STOP and the human runs `generate stage 10` again (re-audit).
- `accepted, generate stage 11` → only if verdict is CLEAN, or CLEAN WITH REFINEMENTS after every refinement was promoted or rejected.

Never go to 11 on a DIRTY audit.

---

### 11 — Production Readiness Review


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

---

## One-shot generator (optional)

Use this only to dump a **draft pack** you will then stitch stage by stage. Never treat the dump as production-grade.

```
You are generating a DRAFT document pack for a product that must later pass a production-readiness review. This is a first pass, not a ship decision.

Product intake:
<EDIT>{{PASTE 00 INTAKE}}</EDIT>

Known locks / constraints:
<EDIT>{{PASTE ANY}}</EDIT>

Generate documents 01 through 09 in the exact headings defined for this cascade:
01 Problem & Opportunity
02 Users & JTBD
03 PRD
04 UX Spec
05 Technical Design
06 Security, Privacy, Compliance
07 Quality & Test Plan
08 Observability, SLOs, Runbooks
09 Launch Plan

Rules:
- Mark every invented detail as HYPOTHESIS or UNKNOWN. Never present a guess as fact.
- Keep v1 a wedge. Put vision leftovers in non-goals or later.
- Number FRs, NFRs, APIs, threats, SLOs.
- After all docs, write a "Stitch hit list": the 15 most dangerous guesses a human must edit before running stage 10.
- Do not write stage 10 (Feature Audit) or 11 (PRR). Those are only valid after human stitches and real artifacts.

Then stop.
```

---

## Suggested stitch order

| Hop | Run | Human stitch (minimum) |
|-----|-----|------------------------|
| 0 | Fill 00 Intake | Kill UNKNOWNs you actually know |
| 1 | 01 Problem | Rewrite in the customer's language |
| 2 | 02 Users | Mark what is hypothesis vs evidence |
| 3 | 03 PRD | Cut scope. Freeze non-goals. |
| 4 | 04 UX | Walk every P0 flow out loud |
| 5 | 05 Tech design | Draw the diagram; delete unused boxes |
| 6 | 06 Sec/privacy | Accept or schedule every risk |
| 7 | 07 Test | Map tests to P0 + NFRs only |
| 8 | 08 SRE | Name on-call and one degrade mode |
| 9 | 09 Launch | Write abort numbers |
| 10 | 10 Feature Audit | Confirm every P0 row; promote or reject REFINED; send DIRTY back |
| 11 | 11 PRR | Verdict; cannot READY on a DIRTY audit |

If 10 is DIRTY, execute the punch list, re-audit 10, then 11. If 11 is NOT READY, re-run only the failing stages, then 10 → 11 again. Do not regenerate the whole pack.

---

## Editing convention (so stitches stay mergeable)

When you edit a generated doc, append:

```
<EDIT>
## Stitch — {{YYYY-MM-DD}} — {{your name}}
- Locked: …
- Cut: …
- Rewrote: …
- Sent back to stage: {{N or none}}
</EDIT>
```

Later prompts must treat the stitched version as canonical and the raw generation as discarded.
