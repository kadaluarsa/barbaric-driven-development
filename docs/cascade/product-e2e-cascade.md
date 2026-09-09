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
**Rule (I18):** Enforcement is layered — CI + branch protection, then git hooks, then agent hooks, then prose. Commands are scripts (`tests/loop.sh`, `tests/barbar.sh`); `LOOP k/n` and `BARBAR k/n` are never typed. Never weaken a layer to pass a hop. T8–T22 in `tests/enforcement.sh` are required.
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

## Stage prompts

Each stage's prompt, template and exit gate lives in its own file, so a hop loads the one stage
it is running instead of all twelve. Always attach the stitch envelope. Always produce the named
document in the named shape. Always end with an **Exit gate** the human must pass before the next
hop.

Three stages stay in this file: their templates carry `<EDIT>` blocks, which are human-authored,
and moving those lines between files is a change only the human can sign. That is a rule, not a
list of exceptions — a template stays here exactly when it carries `<EDIT>`, and
`bash tests/stage_templates.sh` checks that correspondence in both directions.

| Stage | Template |
|-------|----------|
| 00 — Intake | in this file (carries `<EDIT>`) |
| 01 — Problem & Opportunity | [`stages/01-problem.md`](stages/01-problem.md) |
| 02 — Users & Jobs-to-be-Done | [`stages/02-users.md`](stages/02-users.md) |
| 03 — PRD (Product Requirements) | in this file (carries `<EDIT>`) |
| 04 — UX Spec | [`stages/04-ux.md`](stages/04-ux.md) |
| 05 — Technical Design | [`stages/05-tech-design.md`](stages/05-tech-design.md) |
| 06 — Security, Privacy, Compliance | [`stages/06-security.md`](stages/06-security.md) |
| 07 — Quality & Test Plan | [`stages/07-quality.md`](stages/07-quality.md) |
| 08 — Observability, SLOs, Runbooks | [`stages/08-observability.md`](stages/08-observability.md) |
| 09 — Launch Plan | [`stages/09-launch.md`](stages/09-launch.md) |
| 10 — Feature Audit (AI) | in this file (carries `<EDIT>`) |
| 11 — Production Readiness Review | [`stages/11-prr.md`](stages/11-prr.md) |

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
- A D# test must cover the **failure path** (the attempt that must be rejected) as well as the success path. The strength script proves the test can fail; only you can see that it fails for the right reason.
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

These rows are machine-read. `bash tests/audit.sh` re-scores every row against the tree: `path:` must exist, `test:` must exit 0, D# rows take their status from `tests/dsharp_strength.sh`, and REFINED is canonical only when the human moved the row inside `<EDIT>`. The verdict you write is advisory; the script's verdict is the one the merge gate uses.

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
