# How to install and use BDD

Three readers, three sections. Read yours; skim the others.

- **§A — You don't write code.** What it is, what you'll be asked to click, what "halt" means.
- **§B — You write code.** Install, daily use, laws, shipping, upgrades, troubleshooting.
- **§C — You are the agent.** The operating contract, in one page. `AGENTS.md` in the repo is the binding text; this is the quick reference.

---

## §A — If you don't write code

**What BDD is.** A set of rules and checks that make a coding agent *prove* its work instead of describing it. The agent builds; scripts check; you sign the decisions that matter. Nothing reaches the main branch on the agent's word alone.

**What you'll be asked to do — only ever these three things:**

1. **Describe what you want**, in plain language, in the chat. *"Add multi-currency balances."* The agent turns it into a plan.
2. **Approve a dialog** that says *HUMAN SIGNATURE NEEDED*. It shows exactly what the agent proposes to change (usually: which slices to build, or a product rule). Approve = "yes, do this". Deny = "no, rethink". That click is your signature; the agent cannot click it for you.
3. **Say "ship it"** when the work is done — the agent runs the audit, you approve one more dialog (READY), and it opens a pull request for a human to merge.

**Words you'll see:**

| Word | Meaning |
|---|---|
| **law** (D1, D2…) | a rule the product must never break — *"balance MUST NOT go negative"*. Laws are tested every time; a broken law blocks everything. |
| **slice** | one small feature or change, about the size of one pull request |
| **hop** | one step: either *plan a slice* or *build a slice*. The agent stops after each one. |
| **autopilot** | you approve a list of slices once; the agent builds them all, unattended, and stops if any law breaks |
| **HALT** | the agent stopped on purpose and says why. Not an error — read the reason; someone decides. |

**What can't happen:** the agent cannot skip the checks, sign for you, weaken a law, or merge. If it needs a decision it stops and asks. If you're unsure what a dialog means, deny it and ask — denying is always safe.

---

## §B — If you write code

### B1. Install (once per machine)

```bash
claude plugin marketplace add kadaluarsa/barbaric-driven-development
claude plugin install bdd@bdd
```

That's the install. Every Claude Code session on this machine now has the hooks, `/barbar` `/loop` `/audit`, and the skill.

*Prefer no plugin?* Standalone works on any agent and gives the same git-level enforcement: `git clone https://github.com/kadaluarsa/barbaric-driven-development.git ~/tools/bdd`, then in each repo `bash ~/tools/bdd/install.sh .` and `git commit -am "cascade: install"` (no key needed for the install). `bash ~/tools/bdd/install-global.sh` adds a `bdd` terminal command.

### B2. First time in a repo (five minutes)

1. Open Claude Code in the repo and **type the first thing you want built.** With no BDD in the repo the agent offers to install the repo-side layers — git hooks, `tests/`, the envelope, `AGENTS.md`. **Approve.** It commits them as `cascade: install`.
2. **`/barbar init`** — the agent scans the repo (commit log, tests, docs, the money/auth/export paths) and writes `docs/cascade/proposals.md`: candidate laws with validator and red-twin ideas, plus audit rows for what already exists. Say which laws you accept; it edits the envelope; **approve the dialog**. Laws are yours to sign, never the agent's to invent.
3. **Protect `main`** — one command, `INTEGRATION.md` → Layer 0. Until then a refused merge is advisory.
4. Restart the session once so it re-reads the repo.

### B3. Daily use

| You want | Do | What happens |
|---|---|---|
| **a feature** | type it | agent drafts the brief, proposes the edge → **approve** → spec → build to `LOOP n/n` → next … → `AUTOPILOT HALT: list complete` |
| **several features overnight** | type them all, approve the list once, then `/barbar auto` (or `bdd auto` in a terminal) | same, unattended; halts on anything a law refuses |
| **a bug fix, refactor, dep bump, typo** | just type it | no hop, no dialog; laws still hold via pre-push and CI |
| **to ship** | say so; `/audit` → **approve** READY → `/barbar merge` → `ALLOWED` → open the PR | stage 10 is computed from the tree; stage 11 is your signature |

Rule of thumb: **changes what the product promises → feature (an edge); doesn't → chore (just work).**

### B4. The one thing that matters: laws

A law is one line in `docs/cascade/envelope.md`, four fields:

```
D1 | balance MUST NOT go negative | pytest tests/inv/test_D1.py | INV_MUTANT=D1 pytest tests/inv/test_D1.py
```

Validator must pass; the **red twin** must *fail* — it's the bug the law forbids, made runnable. `bash tests/dsharp_strength.sh` scores every law GREEN / RED / **THEATER** (the twin passed: the test can't fail — fix the test) / UNPROVEN (missing pieces — blocks the loop). Declare a law before the slice that could break it; the agent may build the validator and twin. Cover the *failure path* — the script proves the test can fail, only you can see it fails for the right reason.

Three real laws — money, tenancy, idempotency, data loss, entitlement — do more for long-run correctness than anything else in this document.

### B5. When the agent halts

`AUTOPILOT HALT: <reason>` or a refusal means: a law is RED and it can't fix it inside the slice; a signed edge was blocked; or the request contradicts a law. Read the reason, then either change the law (approve the dialog) or drop the request. Never `--no-verify`, never set `CASCADE_HUMAN` for an agent, never hand-edit the envelope when a dialog would do.

### B6. Upgrading

Plugin: `claude plugin update bdd@bdd`, then in each repo `bash "$(claude plugin list 2>/dev/null | grep -A1 bdd | tail -1 | sed 's/.*: //')/install.sh" .` — or simpler, ask the agent: *"upgrade BDD in this repo"* (it runs the plugin's `install.sh`; idempotent, keeps your envelope, laws and settings). `install.sh --check .` in CI reports drift: a softened hook, a deleted script, an unwired hook, a gitignored layer.

### B7. Messages and scores

| You see | Meaning | Do |
|---|---|---|
| `LOOP k/n`, k<n | a validator or in-force law failed | fix in the slice, or send back; never delete a test |
| `LOOP REFUSED … GENERATE` | someone asked for a loop on a spec hop | nothing — correct |
| `LOOP REFUSED … not in force` | a law lacks validator or twin | complete it, or `WAIVE_DSHARP: D2 <reason>` in `goal.md` (you, in writing) |
| `DSHARP THEATER D2` | D2's twin passed — its test can't fail | fix the test |
| `AUDIT k/n DIRTY` | a row has no path, a red test, or a PRD item has no row | punch list, re-audit |
| `HUMAN SIGNATURE NEEDED` (dialog) | the agent proposes a hop edge, law, list, `<EDIT>` or law-test change | approve = sign; deny = send back |
| `BLOCKED …` (commit) | an agent tried a human-owned change without a signature | send back; if the change is right, approve it via the dialog |
| `BARBAR merge REFUSED` | one of the four gate conditions is missing — the line names it | fix that condition; never "fix" the farm with product code |
| `/barbar` not listed | session started before install, or plugin not installed | restart the session; `claude plugin list` |

### B8. Measured

`PROBES k/7` (agent conformance) and `STRESS k/n` (features + a law-contradicting trap) in `evals/`. Re-run after a model change — `evals/spike/README.md`. The number to watch overnight is `DSHARP k/n`.

---

## §C — If you are the agent

The binding rules are in `AGENTS.md`; the hooks enforce them. This is the operating contract in one page.

**Read first, every hop:** `docs/cascade/envelope.md` (hop state, laws, autopilot list), `docs/cascade/goal.md`, `CONTROL-LINE.md`. Durable truth is git; chat is not.

**You may:** write specs and plans under `docs/cascade/` on a GENERATE hop; write product code, tests and `goal.md` on an EXECUTE hop; create the exact `tests/inv/` file a law names; run `bash tests/loop.sh`, `bash tests/barbar.sh`, `bash tests/audit.sh`, `bash tests/dsharp_strength.sh` and report their output verbatim; propose laws in `docs/cascade/proposals.md`; **propose** a hop edge, an `AUTOPILOT:` line, a law line, a READY verdict — by editing the file and letting the human approve the dialog.

**You may not:** type a score (`LOOP`, `BARBAR`, `DSHARP`, `AUDIT` are script output); flip the hop or sign anything yourself; set `CASCADE_HUMAN`; touch `cascade-human-ok` / `cascade-sign-pending`; change or delete an existing `tests/inv/*` file; add a test under an existing D# id; carve an exception into a law for a tier, flag, mode or currency; use `--no-verify`, push `main`, `gh pr merge`, or re-point `core.hooksPath`; start stage N+1 or merge.

**Every hop ends with** the invariant block and exactly one line: `STITCH NEEDED: review spec+plan for stage N` or `STITCH NEEDED: accept execute for stage N, or send back`. The Stop hook will not let you end without it.

**Autopilot protocol** (`/barbar auto`): `python3 tests/lib/autopilot.py --status .` → `off` (stop: only a human signs the list) · `done` (write `AUTOPILOT HALT: list complete`, stop) · `next <HOP> <stage> <slice>` → do that hop, then advance the envelope to exactly that edge (the hooks verify: spec doc before EXECUTE, `loop.sh` n/n before the next slice), repeat. **HALT** — last line `AUTOPILOT HALT: <reason>` — when a law is RED/THEATER/UNPROVEN and only a human can change it, an edge is blocked, or a slice contradicts a law. Never work around a block.

**When the human asks for a feature and no hop is running:** write a one-paragraph brief per slice into `docs/cascade/05b-briefs.md`; propose the edge in the envelope (`AUTOPILOT: 05b <slug>`, or `CURRENT_HOP: GENERATE` for one hop); the dialog is their signature; commit; proceed. If it's a question, just answer.

**When no BDD is installed in the repo** (plugin active): offer `bash $BDD_PLUGIN_ROOT/install.sh .`; their approval of that command is consent; commit `cascade: install`; then the flow above.
