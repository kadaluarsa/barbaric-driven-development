# Product E2E — Generate → Review → Execute

This is the pipeline you described. A coding agent (Claude, Codex, Cursor, …) may **not** run the whole product in one shot. It runs **one hop**, then stops.

**`<EDIT>` markers:** anything inside `<EDIT>…</EDIT>` is yours to fill or stitch. The agent must not invent those lines. Replace the `{{…}}` (or example) inside the tags. Leave `UNKNOWN` if you do not know yet. After you fill a tag you may leave it in place so later hops can see it was human-authored.

The agent must not write inside `<EDIT>` tags. If a required `<EDIT>` is still `{{…}}`, STOP and ask.

Every stage has two hops:

1. **Generate** — spec + plan for this stage only
2. **You review** — stitch: lock, cut, rewrite, approve or send back
3. **Execute** — do only the approved plan, produce artifacts
4. **You review the artifacts** — accept or send back
5. Next stage

If the agent starts stage N+1 without an accepted execute for N, it is doing it wrong.

---

## Conductor prompt (paste this to the coding agent)

Attach this file plus `product-e2e-cascade.md` (the spec shapes). Then paste:

```
You are running a Generate → Review → Execute product cascade with a preserved-invariant agentic loop. You are not allowed to finish the product in one session.

Default models: GENERATE / audit / PRR → Opus + /effort high. EXECUTE of an approved plan → Sonnet + /effort low. Raise /effort or /model only after /usage says the hop is worth it.

INVARIANTS (re-print this block at the end of every hop, and immediately after /compact, /clear, /resume, /rewind, or /model change — that reprint is how they are preserved):
I1 One hop per reply. GENERATE or EXECUTE of one stage. Never both, never N+1.
I2 Envelope in git (`docs/cascade/`) is durable truth. /memory is a session cache of that envelope. Chat residue is not. Do not reconstruct locks from compacted conversation or from `docs/superpowers/`.
I3 /compact and /clear may not add, drop, or rewrite locks. Missing lock after compact → STOP and ask for the envelope.
I4 No product code before 05 spec is accepted. 05b is the only build hop. One named slice. No silent expansion.
I5 HYPOTHESIS and UNKNOWN stay labeled. Do not launder into FRs.
I6 Locked decisions are law. Conflict → stop with options, do not override.
I7 Stage 10: IMPLEMENTED needs tree evidence. Execute reports are not proof. Statuses: IMPLEMENTED | DRIFTED | VIOLATED | REFINED | MISSING.
I8 No stage 11 on DIRTY audit. REFINED is not canonical until the human promotes or rejects.
I9 /goal is this hop's DoD only. /loop until that validator passes. /goal clear before STOP or on send-back.
I10 Execute may not ask for accept without /diff, then the required review command for that hop.
I11 Send-back of an execute → /rewind (or abandon the /branch). Do not stack fixes on a dirty tree.
I12 Tangents go to /btw. They must not change Current hop, locks, plan, or files in this hop.
I13 Domain invariants D# in the envelope are product physics. /loop /goal do not invent them and may not pass a hop that breaks one. A D# without a validator command is not in force yet — STOP and ask, do not code around it.
I14 Superpowers is a code-hop toolkit, not a second product process. Cascade Current hop + I1–I13 + D# + `<EDIT>` outrank any Superpowers skill. On conflict: follow cascade, name the skipped skill in the hop report.
I15 Control line. GENERATE stops at spec+plan — a conductor eval FAILS if GENERATE starts EXECUTE or stage N+1. EXECUTE of 05b / 06–09 / 10 punch: `/goal` = this hop's ACs + in-scope D# validators, `/loop` until those tests, CI is red if any in-force D# fails (the merge bar). `/loop` is illegal on 01–04, on any GENERATE hop, and on 11. Auto-merge is illegal until CLEAN 10 + 11 READY. The human stays on every hop edge.

PRESERVE protocol (run at hop start if /context is fat, and after compact/clear/resume/rewind/model switch):
1. /memory read
2. Re-attach the stitch envelope from `docs/cascade/envelope.md` if it exists, else human paste, else /memory. Never from recalled chat or `docs/superpowers/`.
3. Print INVARIANTS I1–I15 and every D# with its validator
4. Confirm Current hop is unchanged unless the human changed it
5. /goal clear any leftover, then /goal this hop's DoD
6. Only then work

ADD protocol (run when the human stitches — this is how new invariants enter the loop):
- New lock → append envelope Locked decisions AND /memory write. Never chat-only.
- New domain law → envelope Domain invariants as D#, plus /memory. Must include validator command. Prose-only ("don't go negative") is not added.
- Killed idea → /memory as "do not revive: …"
- Promoted REFINED → spec patch in envelope, status becomes IMPLEMENTED baseline
- Rejected REFINED → treat as DRIFTED, punch list
- Accepted execute artifact → envelope Artifacts accepted AND commit under `docs/cascade/`
- Superpowers plan file (if written) → envelope "this hop plan" path. Specs under `docs/superpowers/specs/` are scratch until copied into `docs/cascade/`.
If it is not in the git envelope (or /memory cache of it), it is not an invariant. Next /compact will lawfully forget it.

COMMAND BINDING:
- Session start: /init /doctor /memory /permissions. Fix /mcp /agents /skills /plugin /hooks /status if /doctor is red.
- Hop start: /context. Overflow → /compact then PRESERVE. Never /clear mid-hop.
- GENERATE 01–09 and 11: /model opus, /effort high, /plan, then spec+plan, STOP
- GENERATE 10: /model opus, /effort high, read-only audit, no feature /plan
- EXECUTE 01–04: /model sonnet, /effort low
- EXECUTE 05 / 05b / 06–09 / 10 punch list: /branch named `{stage}-{slice}`, /plan, /batch if the change is many files, /goal = slice DoD AND every D# validator the slice can touch, /loop until those tests pass, long jobs /background (hop waits on the result, does not start N+1). /loop on "tests pass" without D# commands does not preserve balance/tenancy laws. /loop is illegal on 01–04, GENERATE, and 11 (I15).
- After execute, before STITCH NEEDED: /diff. Then /code-review on 05b and punch-list code. /security-review on 06 and any authn/authz/PII change. /simplify is quality-only — never to "fix" DIRTY rows, never to delete tests
- Experiment off the slice: /branch, not edits on the hop branch
- Come back later: /resume then PRESERVE
- Human says send-back or /goal clear: stop /loop, /goal clear, /rewind if the tree is dirty
- /cost /usage before any /model or /effort upgrade
- Superpowers (if installed): GENERATE uses writing-plans only as THIS hop's PLAN, saved under `docs/cascade/plans/`. EXECUTE of 05 / 05b / 06–09 / 10 punch may use TDD, verification-before-completion, using-git-worktrees, executing-plans, requesting-code-review. brainstorming must not open a parallel product spec. subagent-driven-development may run tasks *inside* an approved execute; it may not cross the hop boundary (I1 still STOP). finishing-a-development-branch must not merge to main until the human accepted the execute.

Hard rules:
- After GENERATE: spec + plan, print INVARIANTS, last line STITCH NEEDED: review spec+plan for stage N. Do not execute. (I15 eval FAIL if this hop wrote product code, started EXECUTE, or started N+1.)
- After EXECUTE: artifacts + /diff + review, print INVARIANTS, last line STITCH NEEDED: accept execute for stage N, or send back. CI must be red if an in-force D# failed.
- Never start stage N+1 until execute N is accepted.
- If an exit gate fails, do not proceed. Name the failed boxes.
- Never fill, guess, or delete `<EDIT>…</EDIT>` fields. Those are human. Empty required EDIT → STOP.
- Superpowers skills never override I1–I15. `docs/cascade/` wins over `docs/superpowers/`.
- Auto-merge to main is forbidden until CLEAN 10 + 11 READY. Human stays on the hop edge.

Current hop: <EDIT>{{GENERATE or EXECUTE}} stage {{N — TITLE}}</EDIT>
Stitch envelope:
<EDIT>
{{paste envelope}}
</EDIT>

Human stitch notes (optional):
<EDIT>{{paste}}</EDIT>

Run PRESERVE, then do only that hop.
```

You still change `Current hop` each time. After compact/clear/resume, you should also see the agent reprint I1–I15 before it works. If it doesn't, the invariants were not preserved — resend the conductor.

---


## Loop constitution (invariants + slash commands)

These commands are not decoration. Each one either **adds** an invariant, **preserves** one across a context break, or **enforces** one during a hop.

Two kinds of invariant, do not mix them:

| Kind | Examples | Who writes it | What `/loop` `/goal` do |
|------|----------|---------------|-------------------------|
| Process (I1–I15) | one hop, envelope is truth, no code before 05, audit needs tree evidence, GENERATE must not execute, D# on the CI merge bar | this pack | Keep the *loop* from rotting after `/compact` |
| Domain (D1…Dn) | balance MUST NOT go negative; tenant MUST NOT read another tenant; refund MUST NOT exceed capture | **you, in intake/PRD** | Only if a **validator command** is in `/goal`. They will not infer "don't go negative" from vibes |

`/loop` until "the tests pass" preserves whatever the test file currently asserts. If D1 is not a test, a green `/loop` can still ship negative balances. Define D# in the document, then 07 names the test, then 05b `/goal` includes that test.

### Add (write the invariant somewhere that survives compact)

| When | Command | What gets added |
|------|---------|-----------------|
| Human locks a decision | `/memory` write + envelope lock line | A law the next hop cannot reopen |
| Human kills an idea | `/memory` "do not revive" | Stops the agent from rediscovering it after `/compact` |
| Human accepts an artifact | envelope Artifacts accepted | Proof trail for stage 10 |
| Human promotes a REFINED row | spec patch in envelope | New IMPLEMENTED baseline |
| Hop begins | `/goal` = this hop's DoD **plus D# validators the slice can touch** | `/loop` only preserves laws that are in `/goal` |
| Human names a product law ("balance never negative") | envelope D# + validator test + `/memory` | Domain physics. Without this row, `/loop` will not protect it |
| Session begins | `/init` `/memory` `/permissions` | Tooling and existing locks |

If it was only said in chat, **it was not added**. `/compact` is allowed to forget it.

### Preserve (re-hydrate after the session is squeezed or moved)

| Break | Command | Preserve step |
|-------|---------|----------------|
| Context filling up | `/context` then `/compact` | PRESERVE protocol before the next token of work |
| Nuclear reset | `/clear` | Only between hops. Then full conductor + envelope + I1–I15. Never mid-hop. |
| Pause / continue | `/resume` | PRESERVE immediately. Current hop must match the envelope, not the agent's vibe. |
| Undo a bad execute | `/rewind` | Tree rolls back. Locks do **not**. Reprint I1–I15. |
| Safe experiment | `/branch` | Hop branch stays clean. Merge only after accept. |
| Model swap | `/model` | PRESERVE. A cheaper model does not get a looser I4/I7/I8. |

**Preserve test:** after `/compact` or `/resume`, the agent must print I1–I15, every D#, and the Current hop *before* editing. If it starts coding instead, stop it.

### Enforce (during the hop)

| Hop moment | Command | Invariant it enforces |
|------------|---------|------------------------|
| GENERATE spec/plan, 10 audit, 11 PRR | `/model` opus, `/effort` high, `/plan` | Think before large edits (I1, I6) |
| EXECUTE approved plan | `/model` sonnet, `/effort` low | Don't pay opus for boilerplate. `/usage` first if you want to upgrade. |
| Many-file mechanical change | `/batch` | One change, thirty files, still one hop |
| Tests / soaks | `/loop` until `/goal` validators pass, including every in-scope D# | I9 + I13. Green suite that omits D1 does not preserve D1 |
| Long job | `/background` | Does not unlock stage N+1 |
| Tangent | `/btw` | I12. Main thread stays the hop |
| Before asking accept | `/diff` then `/code-review` or `/security-review` | I10 |
| Quality pass | `/simplify` | Cosmetic only. Never a substitute for 07 tests or a DIRTY fix |
| Stop early | `/goal clear` | Human abort. Agent stops `/loop` and does not "just finish" |
| Tooling broken | `/doctor` `/mcp` `/agents` `/skills` `/plugin` `/hooks` `/status` | Do not fake an execute if tools are red |

Opus-plan / Sonnet-execute is the cost invariant: `/effort` and `/model` are the two knobs that change the bill. GENERATE and audit stay expensive. EXECUTE stays cheap unless `/security-review` or a failed `/loop` justifies a one-hop upgrade, declared in the report.


---

## Superpowers complement (no clash)

[obra/superpowers](https://github.com/obra/superpowers) is the **craft** for writing code. This cascade is the **constitution** for shipping a product. They stack. They do not share a steering wheel.

| Layer | Owns | Must not own |
|-------|------|----------------|
| Cascade (this pack) | Current hop, envelope, D#, stage 10/11, `<EDIT>`, one-hop STOP | How a failing test is written |
| Superpowers skills | TDD, bite-sized plans, worktrees, verify-before-claim, code review | Starting a parallel spec, skipping stitches, merging without accept |

**Precedence (I14):** user instructions in this pack > cascade envelope > Superpowers skill. Superpowers' own `using-superpowers` already says user instructions outrank skills. Use that. If a skill says "don't pause" and I1 says STOP, STOP and name the skill in the report.

### Durable tree (what lasts 10 years)

Prompt packs and skill filenames will churn. Put product law in git:

```
docs/cascade/
  envelope.md          # locks, D#, stage state, artifact list
  00-intake.md
  01-problem.md        # accepted specs only
  …
  10-audit.md
  11-prr.md
  plans/               # this hop's Superpowers-style plan (disposable after accept)
  adr/                 # from stage 05
tests/… or the repo's real test tree
  inv/D1-…             # D# validators. CI merge bar. This is the 10-year asset.
```

Rules:
- Stitch = commit to `docs/cascade/`. Chat `/memory` is a cache of that commit.
- A Superpowers spec under `docs/superpowers/specs/` is **not** accepted until copied or linked from `docs/cascade/` and stitched.
- Stage 10 reads `docs/cascade/` + the repo tree. It does not read chat.
- Prefer a command that scores spec IDs vs tests (`test:inv:D1-…`) over a once-a-launch essay. Until that command exists, GENERATE 10 is the command.
- Superpowers skill *names* may change. Keep these **intents** even if the skill is renamed: test first, evidence before claim, isolated branch, review before accept, no code before an approved design for this hop.

### Skill binding (installed Superpowers)

| Superpowers skill | Cascade allows | Forbidden |
|-------------------|----------------|-----------|
| using-superpowers | Skill check at hop start is fine | Using a skill to leave Current hop |
| brainstorming | Clarifying questions on GENERATE if intake has UNKNOWN. "Design approved" = human stitch of **this stage** spec | A parallel product spec in `docs/superpowers/specs/`. Do not restart intake |
| writing-plans | GENERATE: this hop's PLAN. Save to `docs/cascade/plans/stage-NN-*.md` and put the path in the envelope | A second PRD. Do not execute the plan in the same reply (I1) |
| executing-plans | EXECUTE of the **approved** hop plan only | Running remaining stages / remaining slices |
| subagent-driven-development | Inside one approved **code** execute (05b, 06–09, 10 punch). Tasks may run without pausing *inside* that hop | Crossing STITCH NEEDED. "Do not pause between tasks" is overridden by I1 at the hop boundary |
| test-driven-development | 05b and any production code. If the slice can break a D#, write that D# failing test first | Product code on 01–04 (I4). Skipping D# because the feature test is green |
| verification-before-completion | Every execute before asking accept. Stage 10 IMPLEMENTED rows | Treating a green slice as CLEAN audit |
| using-git-worktrees | Maps to `/branch {stage}-{slice}` | Merging to main before human accept |
| requesting-code-review / receiving-code-review | After `/diff`, before STITCH NEEDED on 05b / punch-list code | Skipping `/security-review` on 06 / PII |
| systematic-debugging | Bugs during execute. Does not change Current hop | "While I'm here" feature work |
| finishing-a-development-branch | After 05b execute, present merge options | Merge / ship without accepted execute + (later) CLEAN 10 + 11 READY |
| writing-skills | Only if the human asked to save a repeated hop | Turning the cascade into a new skill mid-hop |

### Clash overrides (explicit)

1. Superpowers: implement the whole plan without pausing. **Cascade: STOP at hop end.** The hop plan is the plan, not the product.
2. Superpowers: brainstorm → `docs/superpowers/specs/` → writing-plans. **Cascade: 00 intake + GENERATE this stage into `docs/cascade/`.** No second constitution.
3. Superpowers: tests passing = done. **Cascade: tests passing = this execute may be accepted.** Product done = CLEAN 10 + 11 READY, D# on the merge bar.
4. Superpowers: user approved a design, so code. **Cascade: user approved *this hop's* spec+plan.** 01–04 still do not write the app.

If Superpowers is not installed, skip this section. The cascade still runs. If it is installed, do not disable it — bind it.

---

## Stitch envelope (add execute state)

Use the envelope from the spec pack, and add:

```
#### Stage state
<EDIT>
- 01: spec {{draft|accepted}} / execute {{not-started|draft|accepted}}
- 02: spec … / execute …
- 03: spec … / execute …
- 04: spec … / execute …
- 05: spec … / execute …
- 05b Implementation slices: {{slice name: spec/execute status}}
- 06 … 11: same
</EDIT>

#### Artifacts accepted (paths, PRs, files)
<EDIT>
- {{path or URL}} — from stage {{N}} — accepted {{date}}
</EDIT>

#### Canonical tree (git — 10-year truth)
Root: `docs/cascade/`
This hop Superpowers plan (if any): <EDIT>{{docs/cascade/plans/… or none}}</EDIT>
`docs/superpowers/` is hop scratch. Envelope + `docs/cascade/` win on conflict.
```

---

## What each stage generates vs executes

Execute is not always "write the app". If you let the agent code during 01–04, you skip the wedge.

| Stage | Generate (you review) | Execute after you approve |
|-------|------------------------|---------------------------|
| 00 Intake | You fill this. Agent may only ask clarifying questions, not invent. | — |
| 01 Problem | Problem & Opportunity spec + evidence plan | Collect evidence: competitor notes, UNKNOWN list with how to resolve, cheap tests. No product code. |
| 02 Users | Users & JTBD spec + validation plan | Interview script, hypothesis tests, what would falsify a persona. No product code. |
| 03 PRD | PRD + delivery plan (P0/P1/P2, tickets) | Ticket breakdown, acceptance-criteria checklist, tracking events list. Still no app. Optional: spike only if the plan named it and you approved. |
| 04 UX | UX spec + prototype plan | Flows, empty/error copy, prototype or wireframe files, event-to-surface map. |
| 05 Tech design | Technical design + spike/bootstrap plan | ADRs, repo bootstrap, CI skeleton, named spikes. **Not** the full product. |
| 05b Build (repeat per P0 slice) | Slice spec (stories + files + test list + DoD) | Implement that slice only. PR + tests green for that slice. |
| 06 Sec/privacy | Threat model + controls plan | Land controls in repo: authz checks, retention/deletion, secrets, audit logs. Tests for tenancy if relevant. |
| 07 Quality | Test plan | Automate the merge bar: unit/integration/E2E named in the plan. |
| 08 SRE | SLOs + telemetry + runbooks | Dashboards-as-code, alerts, runbook files, log redaction. |
| 09 Launch | Launch plan | Flags, abort/rollback, support macros, ramp checklist in repo. |
| 10 Feature Audit | Scoreboard: each spec item IMPLEMENTED / DRIFTED / VIOLATED / REFINED / MISSING | Punch list only: fix DIRTY rows. No new features. Then re-GENERATE 10. |
| 11 PRR | Verdict + waivers | Only punch-list leftovers the human still wants. Then re-audit 10 if code changed, then 11. |

Stage 10 is an evidence gate. Stage 11 is the ship gate. READY means traffic is allowed, not "the agent finished 05b."

---

## Generate hop — required output shape

Every GENERATE hop must return exactly:

```
# Stage {{N}} — {{TITLE}} — SPEC

{{the document, using headings from product-e2e-cascade.md}}

# Stage {{N}} — PLAN

## Goal
One paragraph: what execute will produce.

## In scope this execute
- [ ] Task → artifact (file/PR/doc)

## Out of scope this execute
- (tempting extras the agent must not do)

## Definition of done
Measurable. "Looks good" is not DoD.

## Risks / UNKNOWNs that still block
- …

## Ask of you
Decisions you must lock before execute. Number them.

## Invariants this hop
- PRESERVE run: yes/no (if compacted: envelope source)
- /goal set to: {{DoD}}
- /model /effort: {{}}
- /plan: used / skipped (why)
- INVARIANTS I1–I15: held, or named break
```

Then stop. Print I1–I15. Last line STITCH NEEDED.

Your stitch on generate: answer the asks, cut scope, lock decisions. Reply with `approved, execute stage N` or `send back:` plus notes.

---

## Execute hop — required output shape

Every EXECUTE hop must return:

```
# Stage {{N}} — EXECUTE REPORT

## Done
- Task → artifact path / PR

## Not done (and why)
- …

## Diff vs approved spec
Drift, if any. Do not hide it.

## Tests / proof
Commands run and results. If no code, say what evidence was collected.

## Leftover for later stages
- …

## Recommended next hop
GENERATE stage {{N+1}}  (only if DoD met)
or  re-EXECUTE stage N

## Invariants this hop
- /branch: {{name or n/a}}
- /diff: shown
- Reviews: /code-review and/or /security-review and/or skipped (why)
- /simplify: not used to drop tests or DIRTY rows
- /loop validator: {{command}} → pass/fail
- /goal: cleared
- /memory writes: {{locks added}}
- INVARIANTS I1–I15: held, or named break
```

Then stop. Print I1–I15. Last line STITCH NEEDED.

Your stitch on execute: `accepted, generate stage N+1` or `send back:` plus notes.

---


---

## Stage 10 — audit hop output shape

GENERATE stage 10 does **not** use the normal spec+plan template. It uses the Feature Audit document in `product-e2e-cascade.md`.

Then stop with: `STITCH NEEDED: review audit for stage 10.`

Your stitch:

- Promote a REFINED row: `promote {{ID}}: {{one-line spec patch}}`
- Reject a REFINED row: `reject {{ID}} as drift` (it becomes DRIFTED / punch list)
- `send back:` if the audit itself is wrong or incomplete
- `approved, execute stage 10` to fix Blocking rows only
- `accepted, generate stage 11` only on CLEAN

EXECUTE stage 10 uses the normal execute report, with DoD = every Blocking ID addressed, no new features. After accept, **re-generate stage 10** (re-audit). Do not jump to 11 off an old audit.

## Stage 05b — how the product actually gets built

Do not "execute the whole PRD." After 05 spec is accepted:

1. GENERATE 05b slice 1 — smallest P0 vertical slice (one user journey that works)
2. You review
3. EXECUTE slice 1 — Superpowers TDD + worktree/`/branch 05b-slice-1`, `/plan`, `/loop` until named tests **and D# validators** pass, `/diff` + `/code-review` (Superpowers requesting-code-review OK), STOP. Do not finish-and-merge.
4. You review the PR. Send-back → `/rewind` that branch, do not patch dirty.
5. Repeat for slice 2 on a **new** `/branch`. Do not keep stacking on slice 1's branch after accept.
6. Only then GENERATE 06

Slice generate must name:

- User story IDs from the PRD
- Files likely touched
- Tests that must pass
- What the user can do when the slice is done that they could not do before
- What the agent must not touch
- D# IDs this slice can break, and the exact validator commands that must be in `/goal`

If a slice grows mid-execute, stop and re-GENERATE the slice. Do not silently expand.

---

## Suggested commands you type to the agent

| You type | Agent does |
|----------|------------|
| `generate stage 01` | Spec + plan for Problem. Stop. |
| `send back: …` | Same hop, revised. Stop. |
| `approved, execute stage 01` | Evidence artifacts only. Stop. |
| `accepted, generate stage 02` | Next spec + plan. Stop. |
| … | … |
| `approved, execute stage 05` | Bootstrap + spikes, not the app. Stop. |
| `accepted, generate 05b slice 1` | First vertical slice plan. Stop. |
| `approved, execute 05b slice 1` | Implement that slice. Stop. |
| `accepted, generate stage 06` | Only after all P0 slices accepted. |
| `generate stage 10` | Feature audit vs repo. Stop. |
| `approved, execute stage 10` | Punch list only. Stop. Then `generate stage 10` again. |
| `accepted, generate stage 11` | Only if audit is CLEAN (refinements resolved). PRR. Stop. |

You can paste those lines as-is.

Agent-side commands you should also expect to see (not for you to type unless you want to force them):

| You may type | Why |
|--------------|-----|
| `/compact` or `/context` | Session is fat. Agent must PRESERVE after. |
| `/clear` | Only between hops, then re-paste conductor + envelope. |
| `/rewind` | Execute was wrong. Invariants stay, tree rolls back. |
| `/resume` | Continue later. Agent must PRESERVE first. |
| `/goal clear` | Abort the in-hop `/loop`. |
| `/model` `/effort` | Override the Opus-plan / Sonnet-execute default. Check `/usage` first. |



---

## Control line (eligible)

This pack is **eligible** as a verify/CI control line (same job as a Dune-style merge bar and a conductor eval). Same purpose as "do not trust chat; prove it on the tree." Different loop than an eval hill-climb: GRE `/loop` is **one approved execute**, not "keep going until 10/10."

```
GENERATE  → spec+plan → STITCH NEEDED
you: approved, execute stage N
EXECUTE   → /goal = ACs + D# → /loop until those tests → CI red if D# fail → /diff
you: accepted, generate stage N+1
```

| Their bar | GRE law (this pack) |
|-----------|---------------------|
| Skill / conductor | This file. Eval of the conductor **fails** if GENERATE starts EXECUTE or N+1 |
| Hard CI (Dune) | In-force D# validators are **required checks** on the merge bar (stage 07 names them; 05b `/goal` runs them) |
| `/loop` until score | `/loop` only on **05b / 06–09 / 10 punch**, and only until `/goal` (ACs + those D#) |
| Auto-merge on green | Illegal until **CLEAN 10 + 11 READY**. Human stitch stays on every hop edge |

**Pack eval (must FAIL the hop / the PR):**

1. GENERATE produced product code, started EXECUTE, or started N+1
2. `/loop` ran on 01–04, a GENERATE hop, or 11
3. A PR merged (or was auto-merged) with a failing in-force D#, or before CLEAN 10 + 11 READY
4. Green feature tests that omit an in-force D# were treated as the merge bar

**CI contract:** a D# without a validator command is not in force (I13). Once in force, breaking it is a red required check, not a waiver the agent may skip. Stage 10 scores a broken D# as VIOLATED.

The human is the hop-edge control. Do not encode "keep looping until READY."


---

## What "production grade" means here

The product is not production grade when the agent has executed 05b.

It is production grade when **stage 10 audit is CLEAN** (every REFINED promoted or rejected) **and stage 11 says READY** (or READY WITH WAIVERS with owners and expiry). The scoreboard is about the **repo**, not the drafts.

Fail closed:
- P0 MISSING, DRIFTED, or VIOLATED ⇒ DIRTY audit ⇒ no PRR READY
- Unpromoted REFINED ⇒ not CLEAN ⇒ no PRR READY
- Any other Fail that is not a dated waiver ⇒ NOT READY ⇒ send back, do not keep building features
- Any hop that cannot reprint I1–I15 after `/compact` / `/resume` is invalid. Re-paste the conductor. Do not accept its artifacts.
