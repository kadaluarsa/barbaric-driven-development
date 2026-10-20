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
2. **Approve a dialog** that says *HUMAN SIGNATURE NEEDED*. It shows exactly what the agent proposes to change (usually: which slices to build, or a product rule). Approve = "yes, do this". Deny = "no, rethink". That click is your signature; the agent cannot click it for you. This works the same on **Claude Code Remote and the web** — approve the dialog right there; you never need to pull the repo to a local machine to sign. (`bash tests/sign.sh` is only a fallback for hand-editing from a plain git client.)
3. **Say "ship it"** when the work is done — the agent runs the audit, you approve one more dialog (READY), and it opens a pull request for a human to merge.

**Words you'll see:**

| Word | Meaning |
|---|---|
| **law** (D1, D2…) | a rule the product must never break — *"balance MUST NOT go negative"*. Laws are tested every time; a broken law blocks everything. |
| **slice** | one small feature or change, about the size of one pull request |
| **hop** | one step: either *plan a slice* or *build a slice*. The agent stops after each one. |
| **autopilot** | you approve a list of slices once; the agent builds them all, unattended, and stops if any law breaks |
| **HALT** | the agent stopped on purpose and says why. Not an error — read the reason; someone decides. |
| **diverge** | tag a feature's brief `[diverge]` and, before any plan is written, you see 3 (or N) different designs — the first always the simple, boring one — each saying what it gives up, when you'd regret it, and a quick test that would prove it wrong. You name the one you want; your approval in the dialog makes it final. The agent never picks. |
| **critique** | before you review a feature's plan, a second AI that did not write it lists at most 10 concerns, each with proof you can check (a command to run, or a line to read), and the author answers every one: *fixed*, *rejected because…*, or a question for you. It advises; it never decides. The plan also shows a before/after diagram and a plain benefits-and-trade-offs table. |

**What can't happen:** the agent cannot skip the checks, sign for you, weaken a law, or merge. If it needs a decision it stops and asks. If you're unsure what a dialog means, deny it and ask — denying is always safe.

---

## §B — If you write code

### B1. Install (once per machine)

```bash
claude plugin marketplace add kadaluarsa/barbaric-driven-development
claude plugin install bdd@bdd
```

That's the install. Every Claude Code session on this machine now has the hooks, `/barbar` `/loop` `/audit` `/doctor`, and the skill.

Run `/doctor` (or `bdd doctor`) after a clone, an upgrade or a bad merge: it walks the enforcement layers in I18 order and prints `DOCTOR k/n`, so a dead layer shows up now rather than the next time a guard silently fails to fire. `bdd check` verifies the shipped *files*; doctor asks whether the pipeline still *works* — the difference that matters most is `core.hooksPath`, which is git config and does not travel with a clone.

Need the pipeline out of the way while you debug something unrelated? `bdd disable` stands down Layer 1 (git hooks) and Layer 2 (agent hooks) and records exactly what it replaced under `.cascade/disabled/`; `bdd enable` puts both back byte-for-byte. **It never touches Layer 0.** CI still runs the farm and the merge gate still refuses, so work done while disabled cannot merge — a disable that reached Layer 0 would be a merge bypass with a friendly name. Every status surface (`bdd status`, `/doctor`, `bdd check`, the session seam) leads with `BDD DISABLED` so a forgotten stand-down cannot pass for a green pipeline, and `.cascade/disabled/` is gitignored so it stays local to you.

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
| **several features overnight** | type them all, approve the list once (put `10 audit` last), then `/barbar auto` (or `bdd auto` in a terminal) | same, unattended: slices, then the audit — ends at `AUDIT n/n CLEAN` or a halt |
| **a bug fix, refactor, dep bump, typo** | just type it | no hop, no dialog; laws still hold via pre-push and CI |
| **to ship** | say so; `/audit` → **approve** READY → `/barbar merge` → `ALLOWED` → open the PR | stage 10 is computed from the tree; stage 11 is your signature |

Rule of thumb: **changes what the product promises → feature (an edge); doesn't → chore (just work).**

### B4. The one thing that matters: laws

A law is one line in `docs/cascade/envelope.md`, four fields:

```
D1 | balance MUST NOT go negative | pytest tests/inv/test_D1.py | INV_MUTANT=D1 pytest tests/inv/test_D1.py
```

The envelope ships with a commented example only — a line starting with `#` or containing `{{…}}` is never a law, so a fresh repo runs autopilot with zero laws (and nags you to add some). Validator must pass; the **red twin** must *fail* — it's the bug the law forbids, made runnable. `bash tests/dsharp_strength.sh` scores every law GREEN / RED / **THEATER** (the twin passed: the test can't fail — fix the test) / UNPROVEN (missing pieces — blocks the loop). Declare a law before the slice that could break it; the agent may build the validator and twin. Cover the *failure path* — the script proves the test can fail, only you can see it fails for the right reason.

Three real laws — money, tenancy, idempotency, data loss, entitlement — do more for long-run correctness than anything else in this document.

### B5. When the agent halts

`AUTOPILOT HALT: <reason>` or a refusal means: a law is RED and it can't fix it inside the slice; a signed edge was blocked; or the request contradicts a law. Read the reason, then either change the law (approve the dialog) or drop the request. Never `--no-verify`, never set `CASCADE_HUMAN` for an agent, never hand-edit the envelope when a dialog would do.

### B6. Upgrading

**Two halves.** `claude plugin update bdd@bdd` refreshes the machine-wide half (hooks, commands, skill). Each repo's `tests/`, `.githooks/` and commands come from `install.sh`.

**Since 2.6.0 the plugin refreshes each repo itself.** The first session after a plugin update runs the plugin's `install.sh` over the repo, when all of these hold:
- the cascade is idle (`CURRENT_HOP: NONE`);
- the working tree is clean;
- no shipped file was edited since it was installed;
- the plugin is newer than the repo;
- no other session is refreshing it.

Your `goal.md`, envelope and hop state are never touched. The refresh runs in a temporary git worktree and is checked with `install.sh --check` there. It reaches your tree in one atomic step, and only if your tree is still clean, so a failure leaves the repo untouched. The session then tells you to commit it: `git add -A && git commit -m 'cascade: update pack to X'`. When a condition fails, you get one line saying which one, and the command to run by hand. `BDD_AUTO_REFRESH=0` turns the refresh off. Standalone installs have no plugin, so you re-run `install.sh` as before. `install.sh --check .` reports drift either way.


Plugin: `claude plugin update bdd@bdd`, then in each repo `bash "$(claude plugin list 2>/dev/null | grep -A1 bdd | tail -1 | sed 's/.*: //')/install.sh" .` — or simpler, ask the agent: *"upgrade BDD in this repo"* (it runs the plugin's `install.sh`; idempotent, keeps your envelope, laws and settings). `install.sh --check .` in CI reports drift: a softened hook, a deleted script, an unwired hook, a gitignored layer.

### B7. Messages and scores

| You see | Meaning | Do |
|---|---|---|
| `LOOP k/n`, k<n | a validator or in-force law failed | fix in the slice, or send back; never delete a test |
| `LOOP REFUSED … GENERATE` | someone asked for a loop on a spec hop | nothing — correct |
| `LOOP REFUSED … not in force` | a law lacks validator or twin | complete it, or `WAIVE_DSHARP: D2 <reason>` in `goal.md` (you, in writing) |
| `DSHARP THEATER D2` | D2's twin passed — its test can't fail | fix the test |
| `CRITIQUE k/n`, k<n | a 05b spec reached its edge without a committed, fully answered critique (or without its before/after diagram and trade-offs table) | run the spec critic, commit its rows verbatim, answer each one, re-run `bash tests/critique.sh` |
| `CRITIQUE n/a` | not a GENERATE 05b hop | nothing |
| `DIVERGE k/n — waiting on your choice` | a `[diverge]` slice's options are ready | read them, name one; approve the dialog |
| `DIVERGE k/n`, k<n | a `[diverge]` slice's options are incomplete, copied, rewritten, or the pick is unsigned/uncommitted | fix what the FAIL line names; the pick is always yours |
| `AUDIT k/n DIRTY` | a row has no path, a red test, or a PRD item has no row | punch list, re-audit |
| `could not fingerprint the tree` / `tests/audit.sh did not finish` / `tests/critique.sh did not finish` (Stop hook) | a check behind the edge could not finish — it timed out or crashed; until 2.1.0 this passed silently | run the named command by hand and read its output; in a plugin-mode repo, re-run `install.sh` first. The hook sends the agent back once, it is not a wall |
| `LOOP n/n, but the tree could not be fingerprinted` | every validator passed, but git could not describe the working tree, so no receipt was written | `git status` shows why; fix that, re-run the loop |
| `receipt and this repo's fingerprint come from different pack versions` | the loop receipt predates an upgrade | run `bash tests/loop.sh` once; if it repeats, re-run `install.sh` so the repo's `tests/` match the plugin |
| `loop: 6 lines — 4 proven in 2 gradle build(s) (14s), 2 ran alone (9s)` | plain Gradle lines were batched (B9); the rest ran one by one, as before 2.6.0 | nothing. Logs are in `.cascade/loop/` |
| indented `\| …` lines and `log: .cascade/loop/3.log` under a `FAIL` | the failing tests Gradle printed, then the end of that line's output | read them before re-running anything |
| `BDD REFRESHED: … 2.5.0 to 2.6.0` | the plugin updated this repo's shipped scripts at session start | review the diff, then `git add -A && git commit -m 'cascade: update pack to 2.6.0'` |
| `BDD VERSION DRIFT … not refreshed automatically: <why>` | the plugin is newer, but a refresh was not safe (open hop, dirty tree, an edited shipped file, …) | fix what `<why>` names and start a new session, or run the printed command |
| `HUMAN SIGNATURE NEEDED` (dialog) | the agent proposes a hop edge, law, list, `<EDIT>` or law-test change | approve = sign; deny = send back |
| `BLOCKED …` (commit) | an agent tried a human-owned change without a signature | send back; if the change is right, approve it via the dialog |
| `BARBAR merge REFUSED` | one of the four gate conditions is missing — the line names it | fix that condition; never "fix" the farm with product code |
| `/barbar` not listed | session started before install, or plugin not installed | restart the session; `claude plugin list` |

### B8. Measured

`PROBES k/7` (agent conformance) and `STRESS k/n` (features + a law-contradicting trap) in `evals/`. Re-run after a model change — `evals/spike/README.md`. The number to watch overnight is `DSHARP k/n`.


### B9. Gradle products: what the loop batches

`tests/loop.sh` used to run each `VALIDATOR:` line as its own build, so a Gradle product paid its configuration time once per line. Since 2.6.0, consecutive plain `./gradlew …` and `gradle …` lines share builds. They run at their place in the goal, so a Gradle line still sees whatever an earlier shell line did. The loop reports a line as passing only when Gradle's own task results prove it. Every other line, and every failure, runs alone exactly as before, so a verdict never changes.

- **Which lines are batched.** A line qualifies when all of these hold:
  - it is a task list (`:app:testDebugUnitTest`, `test`), optionally with `--tests <pattern>`;
  - its options are common ones such as `-q`, `--offline`, `-Pk=v` or `-x task`;
  - it has no shell syntax: no `&&`, `|`, `$VAR` or `cd …`;
  - there are at least two such lines in a row.

  Anything else runs alone. It needs a Gradle version verified on real Gradle: 8.5 to 9.1.x, today. On any other version every line runs alone, as before, until that version is verified.
- **Exact (the default).** Lines that use the same test task with *different* `--tests` filters can't share a build, so they go into separate waves, one build each. On a two-module fixture with four lines: 29s → 18s per pass.
- **Merged (you opt in).** Add `- LOOP_GRADLE_MERGE: on — locked <date> — reason: <why>` inside the `<EDIT>` block of the envelope's Locked decisions, then sign and commit it. An uncommitted line does nothing, and the last such line wins, so a later `off` turns it back off.
  - Filters on one test task are then unioned into a single run. On the same fixture: 29s → 9s, and 7s on a pass where nothing changed.
  - **The cost:** tests from different lines share one test JVM, as `./gradlew test` and CI run them. A test that only passes because another line's test ran first could pass the loop.
  - A law's `check:` line is never merged, and every failure is still re-run alone.
- **Turn it off:** `BDD_LOOP_RUNNER=shell bash tests/loop.sh`. No environment variable can turn merging *on*.
- **The biggest lever is yours:** `org.gradle.configuration-cache=true` in the product's `gradle.properties` makes every repeat build skip configuration. Batching works with it (measured), and the pack never turns it on for you.

### B10. Gradle laws: one build instead of two per law

Every law costs two commands, its `check:` and its `break:`. On a Gradle product each is a whole build. Since t64
`tests/dsharp_strength.sh` can prove a Gradle law GREEN from one shared law build, if you opt in.

- **Write the law in this shape**, which is also the only one that is scored correctly by its own two commands:

  ```
  ### D7 — <MUST / MUST NOT, one sentence>
  check:  ./gradlew :core:test --tests 'com.x.D7*'
  break:  INV_MUTANT=D7 ./gradlew :core:test --tests 'com.x.D7*' --rerun
  ```

  The test applies the mutation in test wiring when `System.getenv("INV_MUTANT")` is its own id.
  - `--rerun` matters. The environment is not a Gradle task input, so without it a `break:` run right after its
    passing `check:` is `UP-TO-DATE` and passes, which reads as THEATER.
  - `-Dinv.mutant=…` on the command line never reaches the test JVM.
- **Sign the switch.** Add `- DSHARP_GRADLE_HARNESS: on — locked <date> — reason: <why>` inside the `<EDIT>` block
  of the envelope's Locked decisions, then sign and commit it. Off, or uncommitted, every law runs its own two
  commands, as before.
- **What it proves.** Only GREEN. A law whose test task has a `doFirst`/`doLast`, an `onlyIf`, a `finalizedBy`, a
  different environment, or a task input the copy does not reproduce is scored by its own two commands. So is a
  law in another shape, on an unverified Gradle version (8.5 to 9.1.x today), or whose result is RED or THEATER.
  `.cascade/laws/law-harness.tsv` says why for each law.
- **The merge gate never uses it.** `tests/barbar.sh merge` scores every law with its own two commands.
- `DSHARP_HARNESS=off bash tests/dsharp_strength.sh` turns it off for one run.

---

## §C — If you are the agent

The binding rules are in `AGENTS.md`; the hooks enforce them. This is the operating contract in one page.

**Read first, every hop:** `docs/cascade/hop-state.md` (hop, stage, slice, autopilot list), `docs/cascade/envelope.md` (laws, locks), `docs/cascade/goal.md`, `CONTROL-LINE.md`. Durable truth is git; chat is not.

**You may:** write specs and plans under `docs/cascade/` on a GENERATE hop; write product code, tests and `goal.md` on an EXECUTE hop; create the exact `tests/inv/` file a law names; run `bash tests/loop.sh`, `bash tests/barbar.sh`, `bash tests/audit.sh`, `bash tests/doctor.sh`, `bash tests/dsharp_strength.sh` and report their output verbatim; propose laws in `docs/cascade/proposals.md`; **propose** a hop edge, an `AUTOPILOT:` line, a law line, a READY verdict — by editing the file and letting the human approve the dialog.

**You may not:** type a score (`LOOP`, `BARBAR`, `DSHARP`, `AUDIT` are script output); flip the hop or sign anything yourself; set `CASCADE_HUMAN`; touch `cascade-human-ok` / `cascade-sign-pending`; change or delete an existing `tests/inv/*` file; add a test under an existing D# id; carve an exception into a law for a tier, flag, mode or currency; use `--no-verify`, push `main`, `gh pr merge`, or re-point `core.hooksPath`; start stage N+1 or merge.

**Every hop ends with** the invariant block and exactly one line: `STITCH NEEDED: review spec+plan for stage N` or `STITCH NEEDED: accept execute for stage N, or send back`. The Stop hook will not let you end without it.

**Under autopilot, never ask and wait.** Resolve what is mechanical. If a decision is needed (scope, an ambiguous brief, a hypothesis that changes the build), state your recommended default and end with `AUTOPILOT HALT: decision needed — <question>`.

**Stage 10 on the list.** `AUTOPILOT: 05b a, 05b b, 10 audit` runs the audit too. Its GENERATE hop dispatches an
*independent* reviewer (a fresh subagent that did not write the code, briefed to be hostile to narrative) to find each
FR/NFR/D#'s artifact and test; its rows go into `docs/cascade/10-audit.md` unchanged and `tests/audit.sh` decides.
Its EXECUTE hop punches DIRTY rows — real fixes only, never by editing the row or deleting a test — up to three rounds,
then halts. **Stage 11 (READY) and merge can never be signed onto a list**: `autopilot.py` refuses them.

**Autopilot protocol** (`/barbar auto`): `python3 tests/lib/autopilot.py --status .` → `off` (stop: only a human signs the list) · `done` (write `AUTOPILOT HALT: list complete`, stop) · `next <HOP> <stage> <slice>` → do that hop, then advance the envelope to exactly that edge (the hooks verify: the spec doc `docs/cascade/<stage>-<slice>.md` — that exact name, since 2.1.0 — before EXECUTE, `loop.sh` n/n before the next slice), repeat. **HALT** — last line `AUTOPILOT HALT: <reason>` — when a law is RED/THEATER/UNPROVEN and only a human can change it, an edge is blocked, or a slice contradicts a law. Never work around a block.

**When the human asks for a feature and no hop is running:** write a one-paragraph brief per slice into `docs/cascade/05b-briefs.md`; propose the edge in the envelope (`AUTOPILOT: 05b <slug>`, or `CURRENT_HOP: GENERATE` for one hop); the dialog is their signature; commit; proceed. If it's a question, just answer.

**When no BDD is installed in the repo** (plugin active): offer `bash $BDD_PLUGIN_ROOT/install.sh .`; their approval of that command is consent; commit `cascade: install`; then the flow above.
