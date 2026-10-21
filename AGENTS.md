# Agent rules — Barbaric Driven Development

## Role labels

| Icon | Role | Reads | Acts |
|---|---|---|---|
| 🧑 | **HUMAN** | Every doc, every diff | Approves edges, signs laws, signs READY, clears halts |
| 🤖 | **AGENT** | `AGENTS.md`, `envelope.md`, `hop-state.md`, this stage's spec | Writes spec+plan, builds code, runs commands, stops at edges |
| ⚙️ | **SYSTEM** | `envelope.md` (D# lines), `goal.md`, git index | Git hooks, CI, `loop.sh`, `barbar.sh`, `audit.sh` — enforces mechanically |

---

This repo runs a Generate → Review → Execute cascade. You may not finish the product
in one session. One hop per reply. The human stays on every hop edge.

## 🤖 AGENT: Read these first — in order

1. `docs/cascade/hop-state.md` — current hop, stage, slice
2. `docs/cascade/envelope.md` — D# domain laws, locked decisions, accepted artifacts, the law-shard index. **Truth.**
   Law shards (`docs/cascade/laws/*.md`) are laws too: read only the ones the prompt hook lists for this hop
   (`LAW SHARDS THIS HOP`), and on EXECUTE those `bash tests/affected.sh --shards` names.
3. `docs/cascade/product-e2e-gre-pipeline.md` — the conductor, invariants I1–I18
4. `docs/cascade/product-e2e-cascade.md` — the stage index; load only this stage's file from `docs/cascade/stages/<NN>-*.md`
5. `CONTROL-LINE.md` — `/loop` vs `/barbar`, the Dune bar

## 🧑 HUMAN: At a glance — your touch points

| When | What you do | How |
|---|---|---|
| 🟡 Hop edge | Approve or send back | Permission dialog — your click is your signature |
| 🟡 New law | Sign a D# | Agent proposes, you approve the dialog |
| 🟡 AUTOPILOT list | Sign the list | Agent proposes, you approve the dialog |
| 🟡 HALT | Read the reason, clear the blocker | Follow `WHAT TO DO` in the halt block, then `resume` |
| 🟢 READY | Sign stage 11 READY | Dialog — only after CLEAN audit |
| 🔵 Merge | Merge the PR | GitHub UI — only after READY |
| 🛠 Install / clone | Wire git hooks | `bash install.sh .` or `git config core.hooksPath .githooks` |

---

## 🤖 AGENT: Non-negotiable rules

1. **One hop per reply.** GENERATE **or** EXECUTE of one stage. Never both. Never N+1.
2. **GENERATE stops at spec + plan.** No product code, no EXECUTE, no stage N+1.
3. **No product code before stage 05 is accepted.** 05b is the only build hop, one named slice.
4. **IMPLEMENTED needs tree evidence.** `path:` on the tree **and** a `test:` that passes — `bash tests/audit.sh` checks both.
   A report is not proof; a CLEAN you typed is ignored.
5. **D# = validator + red twin.** A D# is in force only with a validator **and** a red twin (a command that must fail).
   Anything less is UNPROVEN and `tests/loop.sh` refuses the hop. STOP and ask. Never code around it, never soften either command.
   Existing `tests/inv/*` files are human-owned: keep the product compatible with them, or propose the
   test change in the hop report. You may add a test for a **new** D# id; you may not change, delete, or add
   under an existing one. A new law's test or red twin goes in a **new** file under `tests/inv/` whose name carries
   its id (`tests/inv/mutants/D49.patch`, `tests/inv/twin_D49.tsv`); a file with no id there, a new file under a
   declared law that its commands do not name, and any change to an existing file there (a shared twins table
   included) are the human's to sign — the pre-commit hook names the file when it refuses.
   **A law admits no exceptions** — not for a tier, a flag, a mode, or a currency.
   "VIP may go to −100" is not a refinement of "balance MUST NOT go negative"; it is a conflict. STOP and say so.
6. **Never merge to main.** Merge needs CLEAN stage 10 + READY stage 11 + green D# + a human.
7. **`<EDIT>…</EDIT>` is human-authored.** Do not fill, guess, or delete it. `CURRENT_HOP` and every D# line
   in `docs/cascade/hop-state.md`, `envelope.md` or a law shard (`docs/cascade/laws/`) are human-owned: you never flip the hop, start the next stage, or change a
   validator. `CASCADE_HUMAN=1` is the human's key, never yours.
   Exception: if the human signed an `AUTOPILOT:` list, you may advance the hop yourself — only to the next entry on that list.
8. **Durable truth is git.** `docs/cascade/` in git. If it is not committed, it was not decided.

## 🤖 AGENT: Commands are scripts, not prose

| You want | Run | Never |
|---|---|---|
| this hop's loop | `bash tests/loop.sh` | type `LOOP k/n` yourself |
| the eval farm | `bash tests/barbar.sh` | type `BARBAR k/n` yourself |
| the merge gate | `bash tests/barbar.sh merge` | merge or push to `main` yourself |

## 🤖 AGENT: Ending a hop reply — how to end a hop reply

**Only when a hop is running** — `CURRENT_HOP:` in `docs/cascade/hop-state.md` is `GENERATE` or `EXECUTE`.
Print exactly one of these as the last line:

- `STITCH NEEDED: review spec+plan for stage N` — with N the real stage, never the letter `N`
- `STITCH NEEDED: accept execute for stage N, or send back`

Then **stop**. Do not continue. Do not start N+1. Do not execute.

**Do not reprint I1–I18 at a hop edge.** They are pipeline rules, identical in every repo that
installs this pack. Reprint only after compaction, clear, resume, rewind, or model switch.
What is worth stating at an edge is the product's own law — the D# in force — because that is
per-repo and can change. `NO LAW IN FORCE` is a complete and honest answer when it is true.

**When no hop is running**, end the reply normally: no edge line. A question,
an explanation, a status check or a refusal is not a hop.

## 🤖 AGENT: Error recovery — when things go wrong

| You see | What it means | What to do |
|---|---|---|
| `LOOP REFUSED` | GENERATE hop, stage 01–04/11, no goal, or UNPROVEN D# | Stop. Say why. Do not work around. |
| `THEATER` for a D# | The red twin passed — the test cannot detect violations | Fix the test, not the law. Run `dsharp_strength.sh` again. |
| `UNPROVEN` for a D# | Missing validator or red twin | Write them, or get a `WAIVE_DSHARP:` from the human. |
| `RED` for a D# | The product broke the law | Fix the product. |
| Hook BLOCKS an edge | Git hook refused the commit | Print the hook's reason. Do not bypass. |
| Send-back | Human rejected the hop | `git rewind` or checkout the pre-hop commit. Do not stack fixes on dirty tree. |

## 🧑 HUMAN: What enforces this

| Layer | Mechanism | Binds | Who can bypass |
|---|---|---|---|
| 0 | CI + branch protection | All agents | Nobody — GitHub settings |
| 1 | git hooks (`.githooks/`) | All agents | `git commit --no-verify` (local only) |
| 2 | agent hooks (`.claude/hooks/`) | Claude Code | Only on Claude Code |
| 3 | prose (this file) | Advisory | Any agent can ignore |

These rules are advisory at Layer 3. The bar is not: git hooks reject product writes on a GENERATE
hop and any `<EDIT>` change; CI runs the farm and every D# validator; main is protected.
On Claude Code, `.claude/hooks/` also denies the tool call itself. You cannot talk past
any of these. **Do not weaken a layer to make a hop pass (I18).**
