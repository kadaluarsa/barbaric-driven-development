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
- **The configuration cache (since 2.7.0).** A batched build gets `--configuration-cache` unless you have said anything about the cache yourself: a `--[no-]configuration-cache` or `-Dorg.gradle.configuration-cache…` on the line, `GRADLE_OPTS`, or any `org.gradle.configuration-cache…` key (`problems=warn` included) in the project's, `~/.gradle`'s or `$GRADLE_HOME`'s `gradle.properties`. Then your setting wins, and the pack adds nothing. A repeat pass then skips configuration. Lines that run alone never get it.
  - **If your build rejects it,** the wave is run again without it and the reason is logged in `.cascade/loop/tuning.log`; `.cascade/gradle/tuning.tsv` remembers the drop until a build file or the Gradle version changes, so you pay the rejected build once.
  - **The cost:** with the cache on, Gradle runs a build's tasks at the same time, so a wave's `:core:test` and `:app:test` may overlap. Tests that share a port or a file then fail in the batched build; it proves nothing and those lines run alone, so the verdict is the alone verdict. To keep the old behaviour, set `org.gradle.configuration-cache=false` in `gradle.properties`, or run with `BDD_GRADLE_TUNING=off`.
  - The `loop:` line names what was added (`; tuning: --configuration-cache`) and any daemon a build had to start (`; daemon: 1 started (…)`; `unknown` when a `-q` log hid it).

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

### B11. Affected laws: a hop runs what its diff can break

Since t66, an EXECUTE hop requires the laws its diff can reach, not every law in the repo. The merge gate and the
nightly run still prove every law; selection is a hop-time tool only.

- **Map a law with what you already write.** A law guards the file(s) in its `path:` (a directory guards everything
  under it; the documented `:symbol` suffix is stripped, so `src/wallet.py:withdraw()` guards `src/wallet.py`) and
  the Gradle module its `check:` names (`./gradlew :app:test` guards `:app`). A change in `:core` also reaches
  `:app` when `:app` depends on `:core` — the selector reads that graph from Gradle once per hop.
- **A law that guards neither keeps running everywhere.** No `path:` and no one-module Gradle `check:` means the
  full set. Mapping is opt-in per law, and the fail-closed default is exactly the old behavior.
- **The base is the commit that opened this hop**, not the branch point: the newest commit touching
  `docs/cascade/hop-state.md`, whose `CURRENT_HOP/STAGE/SLICE` match the working tree. Earlier hops on the same
  branch are not paid for again. If no such commit exists, or the hop state differs, the full set runs.
- **Three states, never a quiet pass.** `affected` must be in `/goal`; `not affected` is printed by name and is
  neither `k` nor `n`; a law omitted from `/goal` that is affected is still `FAIL` (I13). A validator you list
  anyway still runs — selection removes a requirement, never evidence.
- **It fails closed.** Build logic (`settings.gradle`, `build.gradle`, `gradle/`, `buildSrc/`, …), a signed
  `- AFFECTED_SHARED_MODULES: :core, :api` line, an unreadable module map, an unknown module, an unmapped file,
  an unmapped law, or an unparseable Gradle selector all print `AFFECTED full — <reason>` and require every law.
  `docs/` and `*.md` are ignored unless a law guards them with `path:`.
- **Look before you write `/goal`:** `bash tests/affected.sh` (or `--list`, `--why`, `--base REV` for a report).
  `tests/loop.sh` computes the same set itself, with no environment override for the base; an environment variable
  cannot hide a law.
- **The schedule.** Each hop: affected checks. Merge (`tests/barbar.sh merge`) and stage 10: every check and every
  Red twin — selection never reaches a merge decision (I18:49, AGENTS rule 6). Nightly:
  `.github/workflows/nightly.yml` runs every check and twin with no base and no selector.
- **Measured (E1, Gradle 9.7.1, warm daemon, 20 laws over 3 modules):** full hop 20 checks in 15.26s; affected hop
  5 checks in 3.71s; the module map alone 0.42s. The saving grows with the number of laws the diff cannot reach.

### B12. The verdict cache: a law's GREEN is reused when nothing it declares changed

Since t65, `tests/dsharp_strength.sh` remembers each law's GREEN in `.cascade/verdicts/<id>.json` (git-ignored, local)
and reuses it, printed `GREEN     D7  <law>  (cached)`, only when it computes exactly the same key. That speeds up
`doctor.sh`, the signing hook and your own re-runs while you fix a law. It never touches an audit or a merge.

- **What is in the key.** The law's `check:` and `break:`; every file it declares — its `path:` (`:symbol` stripped)
  and every existing file its commands name, documents included — and, for a Gradle law naming one `:module:task`, every file under that
  module and the modules it depends on (t66's map, read fresh each run); every build-logic file, every file in a
  signed shared module, and every non-doc file that no law or module declares; the toolchain (`./gradlew --version`,
  OS, bash, python); the pack version and the scoring scripts' own hashes; and the verdict-relevant environment
  (`INV_*`, `DSHARP_*` except the four speed switches, JVM/Gradle options, `PATH`, `VIRTUAL_ENV`, `CONDA_PREFIX`,
  `PYTHONPATH`, `NODE_PATH` and similar, any `$VAR` a law's commands use). `docs/` and `*.md` are inputs only for a
  law that names them, an unmapped law, or under `tree` scope. Git-ignored dependency trees (`node_modules`,
  `~/.m2`, a virtualenv's packages) are not hashed: name what matters in `path:`.
- **Declare what a law reads.** A law whose test reads a file it does not declare — a helper owned by another
  module, or a file another law names in `path:` — can keep a stale cached GREEN after that file changes. Name it
  in `path:` or map the law to its module. For a repo that cannot, sign `- DSHARP_CACHE_SCOPE: tree` inside `<EDIT>`
  in the envelope: then any edit, documents included, invalidates every law, and only an unchanged tree reuses one.
- **Only GREEN, only proven, only on an unchanged tree.** RED, THEATER and UNPROVEN always re-run and are never
  stored. A GREEN is stored only when the worktree's fingerprint after the run equals the one before (a law that
  writes into the tree, or an edit during the run, stores nothing: `CACHE     not stored — …`).
- **Any doubt is a miss.** No git, a failed module map, a failed `--version`, an unknown shared module, or any error
  in the cache prints `CACHE     off — <reason>` and scores every law the old way. A forged or corrupt entry (wrong
  key, wrong id, not exactly `GREEN`, bad JSON, a symlink) is ignored. The last line before `DSHARP k/n` says
  `CACHE     <h> hit, <m> run`.
- **Where it is off.** `DSHARP_CACHE=off` (or any value other than `on`; empty counts as unset) is the pre-t65
  script exactly. `tests/audit.sh` always runs with it off — IMPLEMENTED needs a test that passes now (AGENTS
  rule 4) — and so do the merge gate (`tests/barbar.sh merge`) and the nightly's dsharp step: a remembered verdict
  is not tree evidence (I18:49). A run with no declared law does nothing at all.
- **The cache is not evidence.** Anyone who can run `tests/lib/verdict_cache.py` can write a correctly keyed entry.
  That is why nothing that decides an edge, an audit or a merge reads it.
- **Gradle's build cache, for the law build only.** With the cache on, the t64 law build runs with
  `--build-cache`, so unchanged modules compile FROM-CACHE; the law copies themselves stay `cacheIf { false }` and
  always execute. A law whose own command says `--no-build-cache` keeps it. A remote cache is used only when
  `- DSHARP_GRADLE_BUILD_CACHE_URL: https://…` is signed inside `<EDIT>` and committed, and it is applied after the
  project's settings script, so the project cannot change its URL or turn `push` back on. No flag is ever added to
  a law's own `check:` or `break:`.
- **Clear it:** `rm -rf .cascade/verdicts`.
- **Measured.** E1 (stub, 20 laws over 3 modules): cold 40 law commands, warm 0, a `:core` edit 10. E2 (Gradle
  9.1.0 wrapper, 6 laws over 3 modules, warm daemon, harness signed): cache off 6.38s, cold 6.99s, warm 4.52s, a
  `:core` edit 6.35s; after `clean` the law build compiles FROM-CACHE and every copy still executes.


### B13. Law shards: laws in more than one file

Since t67, laws may live in `docs/cascade/laws/<module>.md` as well as in `envelope.md`. A hop reads the envelope
and only the shards it touches, so the read cost follows the change, not the number of laws ever written.

- **Same laws, same format.** A shard holds `### D#` blocks (or legacy one-liners) inside `<EDIT>`, exactly as the
  envelope does. `tests/lib/laws.py` reads the envelope, then every `docs/cascade/laws/*.md` in filename order, as
  one set: `DSHARP k/n`, the merge gate, `/goal` and stage 10 see the same laws split or not. `README.md` in that
  directory is documentation, never a shard.
- **One id, one law.** An id in two places — two shards, a shard and the envelope, or the envelope twice — is FATAL:
  `dsharp_strength.sh` prints `FATAL`, `loop.sh` refuses, `audit.sh` is DIRTY, and nothing runs until a human
  gives one of them a new id. `/barbar init` lists every existing id before it proposes.
- **Splitting is yours to sign.** Moving a law out of the envelope, adding, editing or removing one in a shard, and
  renaming or deleting a shard are D# changes: pre-commit and the agent hook guard them like the envelope's. Sign
  with the dialog or `bash tests/sign.sh` (it sees new untracked shards and removed ones) and commit.
- **Index the shards.** List each shard, inside `<EDIT>`, in the envelope's `## Law shards` section. `tests/lint.sh`
  fails on a shard missing from the list or a listed file that does not exist; the laws are read either way.
- **Decisions stay in the envelope.** `DSHARP_GRADLE_HARNESS`, `AFFECTED_SHARED_MODULES` and the other locked
  decisions are read only there; lint flags one written in a shard.
- **What a hop reads.** The prompt hook prints `LAW SHARDS THIS HOP`: before a slice's spec exists, every shard with
  its law count and id range; once it exists, the shards it names; on an EXECUTE hop, also run
  `bash tests/affected.sh --shards` for the shards the diff reaches. After a compact, preserve re-injects the
  envelope's laws in full and one line per shard.
- **Your own scripts.** Anything that greps `envelope.md` for D# lines misses shard laws. Call
  `python3 tests/lib/laws.py docs/cascade/envelope.md --declared --shards docs/cascade/laws` instead.
- **Measured (E1, 2,000 laws in 20 shards):** what a hop reads drops from ~444 KB (~111k tokens) to ~21 KB (the
  envelope and one shard); preserve's injected context from ~174 KB to ~4 KB; `laws.py` reads all 2,000 either way
  in under 0.1 s.


### B14. Retiring a law, families, and the laws report

Since t68, a law you no longer need is retired, not deleted — and a failing law can never be retired to make a gate
pass.

- **Retire with a signed line** under the law's heading (envelope or shard):
  `retired: 2027-03-01 — superseded by D19` or `retired: 2027-03-01 — removed — the wallet API was dropped`.
  The law stops being scored (`dsharp_strength.sh` prints `RETIRED   D7 … — <reason> (<date>)` and leaves it out of
  `DSHARP k/n`), stops being required in `/goal`, and an audit row for it reads `RETIRED (not scored)`. Its id stays
  taken; the block stays in the file and in git. The line is a D# change: sign it like any other.
- **A bad line keeps the law in force.** A date that does not parse, `superseded by` a law that is missing or itself
  has a `retired:` line (so a cycle is invalid both ways), or another shape → `WARNING … the law stays in force`.
  Retiring a law that others name in `superseded by` is refused until you re-point them.
- **Only GREEN laws leave force inside a hop.** While `CURRENT_HOP` is GENERATE or EXECUTE — at HEAD or in what you
  stage — a law may be retired or have its block deleted only if it is GREEN on HEAD's tree (its check passes, its
  break fails). A RED, THEATER or UNPROVEN law is refused, signature or `CASCADE_HUMAN=1` alike: fix it, or close the
  hop and retire it with no hop running. The merge gate checks the same thing from git (`bash tests/retirements.sh`),
  so `--no-verify` does not get around it.
- **Families.** Several laws may share one `check:` (one test class, distinct `break:` mutant switches). On the
  two-command path the shared check runs once per scoring run, before any break; each law's own break still runs.
  On the Gradle law harness (B10) each law keeps its own copy.
- **The report.** `bash tests/laws_report.sh [--years N]` lists laws worth a second look — `MISSING-PATH`,
  `DUPLICATE` (same check and break), `UNEXPLAINED` (no `reason:`), `STALE` (its `path:` file untouched for N years,
  default 3) — and families as `FAMILY` (information). It never edits or retires anything.

### B15. Gradle tuning you can sign, and the split nightly

Since 2.7.0 (t69) the pack tunes only the builds it builds itself — the loop's batched builds (B9) and the law build
(B10). A line run alone, a law's own `check:`/`break:` and your own builds are never changed, and
`BDD_GRADLE_TUNING=off` turns every pack-added setting off (the commands are then exactly 2.6's). Two settings are
faster but can change a test result, so each needs your signature inside the envelope's Locked decisions `<EDIT>`,
committed:

- **`- GRADLE_OFFLINE: on — locked <date> — reason: <why>`** adds `--offline` to batched and law builds. The risk: a
  `-SNAPSHOT` or `1.+` dependency is tested from the cached copy, not the one an online build would fetch. A build
  that misses a dependency offline is rerun online and the drop is remembered.
- **`- DSHARP_GRADLE_FORKS: on — locked <date> — reason: <why>`** runs each law's *check* copy with
  `maxParallelForks = max(yours, CPUs / 2)`. It helps only a law whose check selects several test classes. The risk:
  classes that fail when they share one JVM pass in separate forks, so such a law can read GREEN in a hop. The merge
  gate never uses the law build, so it still scores that law RED. The *mutant* copy never forks: a race there could
  fake its failure.

**The nightly, split by module.** `.github/workflows/nightly.yml` plans the laws into parts by Gradle module
(`tests/lib/nightly_plan.py`; `workflow_dispatch` takes `parts`, default 4), scores each part on its own runner
(`dsharp_strength.sh --part`), and joins them (`--join`). The join prints exactly what one run would print for those
verdicts, or `FATAL     join: …` with no score when a part is missing, a result is doubled or misplaced, or the parts
scored other laws or another plan. Laws listed in `DSHARP_SERIAL` stay in one part, in order. Laws are assumed
hermetic, as with `DSHARP_JOBS`; the nightly reports, and the merge gate — one run, one machine — decides. A product
gets the workflow with `install.sh --with-nightly`, which never overwrites a `nightly.yml` you already have.

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
