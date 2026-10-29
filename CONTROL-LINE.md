# Control line — `/loop` vs `/barbar`

Same job as a hard merge bar: do not trust chat; prove it on the tree. Two commands. Do not mix them.

## `/loop` (ours, GRE)

Follows and enhances GRE execute.

- Legal only after `approved, execute` of **05b / 06–09 / 10 punch**
- `/goal` = named AC tests **and** every in-force D# the slice can touch
- Print `LOOP k/n` with per-validator pass/fail (her 10/10 *shape*, our physics)
- An in-force D# omitted from `/goal` is **FAIL**, not skip
- STOP at hop edge. Never GENERATE. Never N+1.

## `/barbar` (hers, enhanced)

Follows her eval/CI farm. Enhances it so it cannot skip the hop edge.

- Hill-climb **control-line evals** until `BARBAR 10/10` (pack eval + in-force D# required checks)
- Must **not** GENERATE, EXECUTE, stitch, or start N+1
- `/barbar merge` is legal **only if** stage 10 is CLEAN **and** stage 11 is READY **and** BARBAR is 10/10 **and** in-force D# are green. Otherwise refuse.
- That is her auto-merge, gated by GRE ship law.

## Sequence

```
GENERATE  → spec+plan → STITCH NEEDED
you: approved, execute stage N
EXECUTE   → /goal = ACs + D# → /loop until LOOP n/n → CI red if D# fail → /diff
you: accepted, generate stage N+1
… later, CLEAN 10 + 11 READY …
/barbar → BARBAR 10/10
/barbar merge   # only then
```

## Pack eval (must FAIL)

1. GENERATE produced product code, started EXECUTE, or started N+1
2. `/loop` ran on 01–04, a GENERATE hop, or 11
3. `/barbar` ran a product stage, or `/barbar merge` fired before CLEAN 10 + 11 READY
4. A PR merged with a failing in-force D#, or green tests that omit D# were treated as the bar

## CI contract

- A D# without a validator command is not in force (I13).
- Once in force, breaking it is a red required check.
- Stage 10 scores a broken D# as VIOLATED.
- This repo's CI is `tests/control-line.sh` + `tests/i17_dune.sh` + `tests/barbar.sh` (I15 + I16 + I17). Product D# tests live in the product repo.

The human stays on the hop edge. `/barbar` does not mean "keep looping until READY."

## Run

```
bash tests/i17_dune.sh        # T1–T7
bash tests/barbar.sh          # farm → BARBAR k/n
bash tests/barbar.sh merge    # refuse unless CLEAN 10 + 11 READY
```

n/n is her 10/10. This pack repo has no product D#, so merge must refuse unless `BARBAR_ROOT` points at a CLEAN 10 + READY 11 tree.

## I17 Dune bar (evidence)

100% match means a violation is a **red test**, not a stronger prompt. T1–T7 are the talk.

| ID | Talk | If this test is red, the statement is false |
|----|------|-----------------------------------------------|
| T1 | Skill | *presence:* the skill no longer hard-stops a feature one-shot |
| T2 | Evals | *runs the scorer:* a one-shot build and an evidence-free IMPLEMENTED are no longer caught |
| T3 | Hard CI (Dune) | *presence:* PRs can merge without `tests/barbar.sh` |
| T4 | Loop until 10/10 | *runs the gate:* it exits 0 on a product that is not n/n |
| T5 | Auto-merge on green | *runs the gate on both fixtures:* a READY product is not ALLOWED, or a dirty one is not REFUSED |
| T6 | Don't trust chat | *runs the scorer:* IMPLEMENTED without a path/test is not scored as a failure |
| T7 | Verify before continue | *runs the scorer:* a GENERATE hop that executed, or one that started N+1, is not caught |

T0, T1 and T3 are presence checks by design — they guard against an instruction file or a CI job being
deleted, which is what a presence check is for. T2 and T4–T7 used to be presence checks too, asserting that
`barbar.sh` contained the string `exit 1` and that fixture files existed without ever scoring them. A test
that cannot fail for the reason it claims is THEATER by this pack's own standard; those five run things now.

Run: `bash tests/i17_dune.sh && bash tests/barbar.sh`

## I18 Enforcement layers (evidence)

I17 says a violation must be a red test. I18 says where that test lives. Each control sits at the lowest layer that can enforce it, and a hop may not weaken a layer to pass.

| Layer | Mechanism | Binds | Agents |
|---|---|---|---|
| 0 | CI + branch protection (`.github/workflows/`) | yes, non-bypassable | all |
| 1 | git hooks (`.githooks/pre-commit`, `pre-push`) | yes, locally | all |
| 2 | agent hooks (`.claude/hooks/`) | yes, at the tool call | Claude Code |
| 3 | prose (`AGENTS.md` + shims) | no | all |

Commands are scripts. `/loop` = `bash tests/loop.sh`. `/barbar` = `bash tests/barbar.sh`. The agent never types `LOOP k/n` or `BARBAR k/n`.

| ID | Layer | If this test is red, the statement is false |
|----|-------|-----------------------------------------------|
| T8 | 1 | pre-commit rejects product code on a GENERATE hop |
| T9 | 1 | pre-commit allows spec on GENERATE and product code on EXECUTE |
| T10 | 1 | pre-commit rejects a changed `<EDIT>`; allows adding one |
| T11 | 1 | pre-push rejects `main`; allows a slice branch |
| T12 | script | `tests/loop.sh` refuses on a GENERATE hop |
| T13 | script | an in-force D# omitted from `/goal` is a FAIL entry; `LOOP k/n` is machine output |
| T14 | script | the farm is red when the scorer dies; `merge` runs the farm first |
| T15 | 2 | Claude hooks deny product Write on GENERATE, deny ship escapes, block an open hop, re-inject after compact |
| T16 | 2 | `install.sh` places the skill under `.claude/skills/` and hooks under `.claude/hooks/` — where the agent loads them; the installed farm is n/n |
| T17 | 1+2 | hop state and D# lines are human-owned: the agent cannot flip `CURRENT_HOP` or soften a validator; a human commits with `CASCADE_HUMAN=1`, which the agent is denied |
| T18 | script | red twin: a D# is in force only when it can fail — THEATER is red, UNPROVEN blocks `loop.sh`, a written waiver lifts it, `DSHARP k/n` is machine output; merge also requires READY human-signed inside `<EDIT>` |
| T19 | script | stage 10 is computed by `tests/audit.sh`: `path:` must exist, `test:` must pass, REFINED needs `<EDIT>`, PRD IDs without rows are MISSING, a prose CLEAN is ignored |
| T20 | 2 | the seam hook injects the per-hop Superpowers allow/deny list and cascade precedence on every prompt; silent outside a cascade |
| T21 | 2 | a crashing guard returns `ask`, never allow; CRLF envelopes still parse |
| T22 | install | `install.sh --check` reports a softened hook or a deleted script (drift) and a version mismatch |
| T23 | install | `install.sh` is idempotent: a re-run nests nothing, drops stale files, leaves no drift, farm still n/n |
| T24 | install | a real product: an existing `settings.json` is merged (theirs kept), `CLAUDE.md` gets `@AGENTS.md` appended, a gitignored `.claude/` is flagged by install and `--check` |
| T25 | 1+2 | a law's test is the law: existing `tests/inv/*` are human-owned — the agent can add a law test, never change or delete one; a human accepts changes with the key |
| T26 | 1+2 | a slice cannot carve an exception into a law: no new test under an existing D# id; the seam states laws admit no exceptions every prompt |
| T27 | 1+2 | autopilot: off by default; a human-signed `AUTOPILOT:` list lets the agent take only the next signed edge — spec doc before EXECUTE, `loop.sh` n/n before the next slice; list end, 10/11, READY and merge stay human |
| T28 | 2 | `/barbar auto`: the Stop hook keeps the session going while signed edges remain; stops at the list end, on `AUTOPILOT HALT:`, or at a cap — never spins |
| T29 | 2 | first-knowledge discovery: with no law in force the seam and session-start hooks nudge toward `/barbar init`, which scans and writes `docs/cascade/proposals.md` — proposals, never signed laws |
| T30 | 1+2 | approve-to-sign: a signable change (hop edge, AUTOPILOT/D# line, `<EDIT>` content, a law test) answers `ask` interactively — the human's approval is the signature, recorded as a one-shot token pre-commit accepts for exactly that content; `deny` when permissions are bypassed; the agent cannot mint tokens |
| T31 | plugin | manifest, marketplace and hooks.json valid; plugin-mode install wires no project hooks; the seam offers the install in a bare repo; a tool call is judged once when both plugin and project hooks are present |
| T32 | 1 | a hook-style `GIT_DIR`/`GIT_WORK_TREE` never leaks into the farm's throwaway repos — the pre-push farm once flipped a real product to `core.bare=true` and re-pointed its worktree HEAD |
| T33 | 1 | a human editing by hand can sign from any git client: `tests/sign.sh` mints the same one-shot token for the human-owned files they changed, and the agent is denied running it |
| T34 | 2 | a repo whose shipped scripts are older than the plugin is told at session start, with the refresh command; silent when in sync or plugin-less |
| T35 | 1+2 | plugin-mode repo: Layer 2 resolved from the plugin so the farm reaches n/n; an existing `AGENTS.md` keeps its rules and gains the cascade ones; `--check` clean |
| T36 | 1+2 | stage 10 can be signed onto the autopilot list and is gated by `audit.sh` (rows first, CLEAN to advance); stage 11 never can; the audit hop uses an independent reviewer and a capped punch list |
| T37 | 2+3 | the edge-line ritual is scoped to open hops in both layers: the Stop hook is silent when idle and names the real stage when not, and `AGENTS.md` says the same |

| T38 | plugin | every file the plugin ships under `commands/` and `skills/` is a real file and byte-identical to the `.claude/` copy the repo runs — a symlink is not followed by the loader, and a frozen copy silently degrades plugin-mode sessions |
| T39 | 2 | a fresh clone is told Layer 1 is off — `core.hooksPath` is git config and never travels with the repo — with the one-line fix, and goes quiet once wired; friendly-format laws reach session start |
| T40 | 1+2 | every layer appends its decisions to `.cascade/decisions.log` — denials, signatures, law verdicts, halts — without the log ever becoming a gate or dirtying the tree; signing a law runs its strength check on the spot |
| T41 | 2 | I10 is mechanical: the accept edge needs a `loop.sh` receipt naming this hop and fingerprinting this tree — none, stale, or from another stage is refused; a failing loop writes none; the receipt is never committed |
| T42 | install | plugin-mode install strips Layer 2 from a product but never from the pack, whose `.claude/hooks` are the source that gets packaged — running it in the pack once deleted the product |
| T43 | 2 | an unsigned autopilot list asks the human which slice to run and signs their pick through the dialog, halting only when headless or when they decline — no `sed`, no stitch key, no retyping what the agent already knows |
| T44 | 1+2 | hop state lives in `docs/cascade/hop-state.md`, human-owned at Layer 1 like the envelope and read in preference to it, with laws staying in the envelope; a repo without the file still reads hop state from the envelope, and installing never creates it under a running hop |
| T45 | 1 | the git hooks resolve the real git dir instead of assuming `$ROOT/.git`, so every guard still runs — and still refuses — inside a worktree, where `.git` is a file |
| T46 | 2 | the git dir is sealed against the agent on every hop — signature ledger, pending list, hooks and refs — so a signature can only come from a human approving a dialog or running `tests/sign.sh`; ordinary product writes are untouched |
| T47 | 1 | Layer 1 does not fail open on a large commit — no pipeline feeds `grep -q` under `pipefail`, where an early-exiting grep makes the writer take SIGPIPE and the guard behind it is skipped — and cleanup runs from an EXIT trap, so an unlinkable scratch path can never abort a commit whose checks passed |
| T48 | 0+1 | the pre-push gate defers the pack's own meta-suite to CI and labels the score `(fast: … not a full farm)`; lint and the hop scorer still run locally; `barbar merge` unsets fast mode and CI never sets it, so nothing reaches main unchecked |
| T49 | 2 | every shared hook helper is defined once, in `.claude/hooks/_common.py`, and each hook still loads, answers a trivial event silently, and asks rather than failing open when the module cannot be used |
| T50 | 2 | the git dir is sealed against the agent from inside a linked worktree too, where `$GIT_DIR` is `<main>/.git/worktrees/<name>` and therefore outside the worktree root — the path that let the agent mint its own signature while every plain-repo test passed; ordinary product writes in a worktree are untouched |
| T51 | 2 | quoting an argument does not defeat `bash_guard` — the ledger, `tests/sign.sh`, `--no-verify` and a push to main are denied quoted or bare, while the reads and commit-message prose that merely name them stay allowed |
| T52 | 2 | `bash tests/doctor.sh` goes red once per dead layer — `core.hooksPath` unset, no CI workflow running the farm, a hop open on a slice with no spec — never counts a skipped check as green, never implies it verified branch protection (a GitHub setting it cannot read), diagnoses a bare repo instead of crashing, and keeps one command file byte-identical in both trees |
| T53 | 2 | `bdd disable` stands down Layers 1 and 2 only — the CI workflow is byte-identical across a disable and the merge gate still refuses, so work done while disabled can never merge; a disable that reached Layer 0 would be a merge bypass with a friendly name |
| T54 | 1 | `install.sh` compares repositories, not paths — installing from a linked worktree of the pack into the pack itself keeps Layer 2. The path-only comparison once let `bdd install .` delete `.claude/hooks/*.py` out of the pack's own repo, so every later plugin install would have shipped no agent hooks and approve-to-sign would be dead in every clone |
| T57 | 1+2 | The spec critic gates the GENERATE 05b edge: the Stop hook refuses `review spec+plan` while `bash tests/critique.sh` is red — checked before the autopilot branch, so signed edges cannot carry a red critique past it — and autopilot refuses GENERATE→EXECUTE; a green critique passes both, and stage 06 is untouched. The checker's own red twins (missing, unanswered, rewritten, deleted, unescaped pipe, no diagram, over the cap, no or vague evidence, answered in the same commit, untracked) are `tests/ac/t57_spec_critic.sh`. |
| T58 | 1+2 | Divergence: the pick is the human's at every layer that can see it. Before the pick the Stop hook refuses `review spec+plan` but accepts the decision-needed halt as the reply's ending, and autopilot will not advance; filling the committed `<EDIT>CHOSEN:</EDIT>` placeholder answers `ask` interactively and `deny` with no human present (Layer 2); a shell-made pick is refused at commit without the key (Layer 1); after a signed pick both spec gates pass. The checker's own red twins (15 mutants: missing, short, clone, same constraint, same falsifier, no baseline, no falsifier, empty field, rewritten, pre-chosen, no placeholder, second block, uncommitted pick, bad choice, spec mismatch) are `tests/ac/t58_divergence.sh`. |
| T59 | 2 | A Stop-hook check that cannot finish sends the agent back — it never passes silently. The loop-receipt fingerprint, the stage-10 audit and the spec gates each refuse once on a timeout or crash, naming the cause and the command (red twin: the old silent pass, in a copy of the whole hooks directory); an empty fingerprint is refused; a pre-t59 receipt is told apart ("different pack versions"), while a plugin-mode repo whose `tests/` predate the plugin still compares normally; `loop.sh` writes no receipt it cannot back; the retry stop passes, because this is the soft layer. The fingerprint's cost — constant git processes at any file count, nothing written to `.git` — and `sign.sh`'s and autopilot's scale fixes are `tests/ac/t59_scale_hardening.sh`, each with a red twin; `tests/stress/ten_year.sh` reproduces the 60,000-file numbers. |
| T60 | script | `dsharp_strength.sh` warns when `reason:` uses a mutation type not in the registry — `WARNING` is printed and exit is non-zero (red twin: a registered type passes cleanly). The 8 registered types (`REMOVED_GUARD`, `INVERTED_CONDITION`, `WRONG_CONSTANT`, `SKIPPED_STEP`, `BYPASSED_AUTH`, `WRONG_STATE`, `REMOVED_ENCRYPTION`, `ALLOWED_OVERFLOW`) live in `docs/cascade/mutation-types.md`. |
| T61 | script | `dsharp_strength.sh` warns when `path:` points to a file that does not exist in the repo — `WARNING` is printed and exit is non-zero (red twin: a real file passes cleanly). An optional `:symbol` suffix is also grepped against the file. |
| T62 | 2+script | `loop.sh` batches consecutive plain Gradle `VALIDATOR:` lines through `tests/lib/gradle_runner.py`, at their place in the goal, on verified Gradle versions, and reports only passes it can prove from Gradle's own task outcomes; every other line, every failure included, runs alone by the pre-t62 path. Exact mode (default) runs one build per wave of non-clashing lines; filters on one test task are merged only with `- LOOP_GRADLE_MERGE: on` signed inside `<EDIT>` in the envelope and committed, never by env var and never for an in-force D# `check:`. Verdicts equal each line run alone (red twins in `tests/ac/t62_loop_runners.sh`: no surely-selected test, no failure-count check, no D# exclusion, a runner that passes everything). In plugin mode the SessionStart hook refreshes a repo's shipped scripts when the plugin is newer and the cascade is idle, the tree clean and no shipped file edited, staging the install in a temporary worktree and applying it atomically; otherwise it says why. |
| T63 | 2+script | The Stop hook never exits 2 or writes stderr, which Claude Code shows the human as a "Stop hook error": every nudge for the agent (I1 edge, I10 evidence, HALT block, spec gate, autopilot continue) goes in `additionalContext`, and every stop meant for the human (budget, continuation cap, punch cap, nudge cap) goes in `systemMessage`. An edge quoted in a code span or fence is not an edge. Identical nudges cap at two per human prompt. A crash exits 0 silently and logs `CRASH`. Red twins: the pre-t63 hook, `unquoted()` as identity, the counter and the prompt marker removed, and an unwrapped `main()` (`tests/ac/t63_quiet_stop_guard.sh`) |
| T64 | 2+script | `dsharp_strength.sh` proves eligible Gradle laws GREEN from one law build (`tests/lib/law_harness.py` + `law_harness.init.gradle`), only when `- DSHARP_GRADLE_HARNESS: on` is signed inside `<EDIT>` and committed. A law is eligible when its `break:` is `INV_MUTANT=<id> <check> --rerun`, its one `:module:test` selector resolves to a Test task the copy reproduces (inputs, actions, `onlyIf`, `finalizedBy`, environment compared, fail closed), and the Gradle version is verified. The harness only ever proves GREEN: RED, THEATER and every other law run their own two commands. The merge gate exports `DSHARP_HARNESS=off` before `audit.sh` and its own check. Red twins: unsigned/uncommitted switch, a leaked mutant, §4 reduced to "the mutant failed", fidelity checks removed (real Gradle) |
| T65 | 2+script | `dsharp_strength.sh` reuses a law's GREEN (`(cached)`) only when `tests/lib/verdict_cache.py` computes the stored key exactly: the law's commands, its declared files and module closure (t66's map, fresh each run), every build-logic, shared-module and undeclared non-doc file, the toolchain, the pack and scorers, and the verdict-relevant environment. Only GREEN is stored, only when the worktree fingerprint (cascade_worktree_sha's scheme) is unchanged after the run; every doubt is `CACHE off — <reason>`. Any `DSHARP_CACHE` other than `on` is the pre-t65 script; `audit.sh`, the merge gate and the nightly set it off. The t64 law build adds `--build-cache` (copies stay uncacheable); a remote is read-only and only from a signed, committed https URL. Red twins: no module closure, no key comparison, storing THEATER, no fingerprint re-check (`tests/ac/t65_verdict_cache.sh`); real Gradle in `tests/stress/verdict_cache.sh` |
| T66 | 2+script | `loop.sh` requires the laws a hop's diff can break, selected by each law's `path:` (`:symbol` stripped) and the Gradle module its one `:module:task` `check:` names, plus the modules that depend on a changed one. The base is the newest commit touching `docs/cascade/hop-state.md` with the same hop fields; earlier hops are not diffed. An unaffected law prints `not affected` and is neither `k` nor `n`; omitting an affected one is the same I13 FAIL. Every ambiguity is `AFFECTED full — <reason>`: no/mismatched base, build logic, a signed `AFFECTED_SHARED_MODULES` line, an unreadable map, an unknown module, an unmapped file or law, or an unparseable selector. No environment switch can narrow; `--base` is report-only. The merge gate, stage-10 audit and `dsharp_strength.sh` do not read it; `.github/workflows/nightly.yml` runs the full set. Red twins: a selector that drops the dependent law, and a loop that hides omissions (`tests/ac/t66_affected_laws.sh`); the map's real `app -> core` edge and E1 are `tests/stress/affected.sh` |
| T67 | 2+script | Laws may live in `docs/cascade/laws/*.md` (README.md is not a shard): `tests/lib/laws.py` reads the envelope, then every shard by filename, as one set; every pack caller passes the repo's shard directory, so a temporary envelope copy never drops shard laws or reads a stray one. One id twice anywhere is FATAL: laws.py prints no rows (exit 2), dsharp prints FATAL, loop is REFUSED, audit is DIRTY, affected goes full, the seam says LAWS UNREADABLE, gradle_runner merges nothing. Pre-commit (with `--no-renames`), hop_guard and sign.sh guard shard D# lines like the envelope's, new, removed and renamed shards included. Lint checks the envelope's signed `## Law shards` index and flags decisions in shards. The seam lists the shards a hop reads; `affected.sh --shards` names the affected ones; preserve summarises the rest. Red twins: no duplicate check, no shard guard (`tests/ac/t67_envelope_shards.sh`) |
| T68 | 2+script | A `### D#` block may carry `retired: <date> — superseded by D<N>` or `— removed — <reason>`, a human-owned line (laws.py PROTECTED; protected lines now compared as a multiset, so a duplicate line is a change). A valid retirement takes the law out of `--declared/--in-force/--count` — dsharp prints `RETIRED` and leaves it out of k/n, loop does not require it, audit does not score its row — and its id stays taken; an invalid one (bad date, missing or retired target, a cycle) keeps it in force with a WARNING. Inside an open hop (HEAD or staged hop state) a law may leave force, retired or deleted, only if GREEN on HEAD's tree: `tests/lib/retirement_guard.py` in pre-commit, before the human key, and `tests/retirements.sh` in the merge gate from git. A check: shared by several laws runs once, before any break. `tests/laws_report.sh` lists candidates and edits nothing. Red twins: a check-only guard, a verdict-less backstop, an always-pass memo (`tests/ac/t68_law_retirement.sh`) |
| T69 | script | Only Gradle builds the pack builds itself are tuned (`tests/lib/gradle_tuning.py`): the loop runner's batched builds get `--configuration-cache` unless the user set any configuration-cache key on the line, in `GRADLE_OPTS` or in the project's, user home's or install's `gradle.properties`; a build that rejects it is rerun without it and the drop is remembered in `.cascade/gradle/tuning.tsv` until build logic or the Gradle version changes. `--offline` (runner and harness) and check-copy forks (harness) only when `GRADLE_OFFLINE: on` / `DSHARP_GRADLE_FORKS: on` are signed and committed; the mutant copy never forks and is now compared to the original too. A line run alone and a law's own `check:`/`break:` are never changed; `BDD_GRADLE_TUNING=off` is byte-identical to 8d5b269. The nightly splits laws by module (`tests/lib/nightly_plan.py`, `dsharp_strength.sh --part/--join`); the join prints one run's output or FATAL. Red twins: a runner ignoring drop rows, a join skipping a missing law (`tests/ac/t69_gradle_tuning.sh`); forks on the mutant on real Gradle (`tests/stress/gradle_tuning.sh`) |
| T74 | 2+script | A new file under `tests/inv/` must carry a D# id in its name, and every id counts: an undeclared id (a new law's test or red twin, `tests/inv/mutants/D49.patch`) lands; a declared id lands only on a path that law's commands name, compared token for token; a file with no id (a `conftest.py`) or under a declared law it does not name is BLOCKED by name. An existing file changed, removed or type-changed (a symlink swapped in) is BLOCKED; renames are a removal plus an addition (`--no-renames`). Paths are read whole (`-z`); ids by bash's own regex. An ERR trap names the line of any unexpected failure, so the hook never exits 1 in silence (it once did on any non-`test_D` name). `hop_guard.py` applies the same rule to Write/Edit. Red twins: the pre-t74 extraction, a skipped no-id branch (`tests/ac/fixtures/t74_twins.py`) |
| T77 | script | A goal is one hop's definition of done (`tests/loop.sh`, `tests/lib/goal_history.py`, `tests/goal.sh`): a goal whose last column-0 `GOAL_SLICE` names another slice than `CURRENT_SLICE` is `LOOP REFUSED` before any validator runs (absent or `<placeholder>` is not). Validators an earlier version of `goal.md` held under another slice are counted and named on every pass (one `git log -p`, last 200 versions, whitespace collapsed); `# standing` lines and in-force law checks never count, unless the marker was added to a line an earlier slice's goal held unmarked while marking others. Above 10 — or a `GOAL_CARRY_MAX` signed inside `<EDIT>` and committed — the loop is refused. Unreadable history (shallow clone) checks no cap and says so. `install.sh` seeds `goal.md` from `goal.template.md`, which runs nothing. Red twins: a counter of law checks, an install seeded from the pack's goal, no late-marker guard (`tests/ac/t77_goal_hygiene.sh`) |
| T78 | 2+script | Accepted slices' tests live in `docs/cascade/regress.md` (`REGRESS:` lines): `goal.sh reset` carries the replaced goal out (from the file itself; it refuses an uncommitted goal), `goal.sh carry-out` moves carried and dropped lines; `tests/regress.sh` runs them. The merge gate runs `--gate`: HEAD's lines plus every line the merge base had that HEAD dropped, minus `REGRESS_RETIRED` lines signed in the envelope; a dirty suite or a shallow clone is refused, no runner is refused, and with no lines the gate's output is unchanged. CI's `regress` job runs `--gate --ci`, skipping `# gate-only` lines as skipped, never passed. Pre-commit BLOCKS a removed or changed line unless the staged blob is signed (`sign.sh` lists the suite) and a deleted suite without the key; hop_guard asks. The loop names dropped lines. Red twins: a reset without carry-out, a HEAD-only gate, a count-only guard, skips counted as passes (`tests/ac/t78_carry_out.sh`) |
| T79 | script | A pass means a test ran (`tests/lib/test_count.py`): after a Gradle or `xcodebuild test` line exits 0, the run's own results are read — the task's fresh JUnit XML (a task that did not execute this run is `not inspected`), or the result bundle (`-resultBundlePath`, `-derivedDataPath`, the default DerivedData unless `DSHARP_JOBS` > 1), else the log's `Executed n, k skipped` / Swift Testing count. Zero executed, or a `--tests` filter / `-only-testing:` target with no executed test, is `FAIL … ran no tests` in `loop.sh` and `regress.sh`, keeps a line out of t62's batched proof, and is `RED … validator ran no tests` for a law (counted before the twin; a family once). Anything unreadable is `not inspected`, printed only when a goal has a recognised line. Red twins: a proof without the executed-case requirement, a reader that always says `ran 1` (`tests/ac/t79_zero_test_guard.sh`) |
| T80 | script | `README.md`'s "Reading the codes" explains what every screen shows — the stage table and why `05b` has a "b", a slice id (`t80-…` = slice 80, proven by T80), `GENERATE` / `EXECUTE` / `NONE`, `D#`, `LOOP k/n`, `REGRESS k/n`, `STITCH NEEDED`, `AUTOPILOT HALT` — with a worked line and links to `product-e2e-cascade.md`, `hop-state.md` and this file. `USAGE.md` §B16 says carried lines match exactly and records why filter matching was not built (0 of dream-camera's 63 lines would change) (`tests/ac/t80_carry_matching.sh`) |
| T81 | 1+script | An autopilot edge gets the verdict the human's own loop would print (`tests/lib/autopilot.py`): in a repo with `docs/cascade/hop-state.md` the pre-edge hop state goes to the gates as `CASCADE_HOPSTATE`, so laws are read from the envelope and shards (handing it over as `CASCADE_ENVELOPE` emptied the law set: the edge check failed open); a pre-split repo keeps `CASCADE_ENVELOPE`. `tests/loop.sh` runs validators with both variables unset; `tests/lib/affected.py` reads the pre-edge hop. A refusal names up to five FAIL / LOOP REFUSED / BOTTLENECK lines; the loop runs in its own session with a 60-minute limit (`BDD_AUTOPILOT_LOOP_MINUTES`) and a timeout kills the whole group. Real edges through the real pre-commit hook; red twins: the old hand-over, a leaking loop (split and pre-split), a selector reading the post-edge hop, gates with no variable (`tests/ac/t81_autopilot_edge_envelope.sh`) |
| T82 | script | `/bdd-work` selects one of five craft routes from the request while respecting NONE/GENERATE/EXECUTE and the accepted slice; negative route fixtures reject misrouting and scope expansion, plugin and standalone skill copies/install agree (`tests/ac/t82_task_routing.sh`). P8 is a recorded real-agent probe, scoped to its model/version. |
| T83 | script | Shared `bdd-work` skill copies agree; standalone installation creates the Agent Skills path, keeps identical bytes unchanged, and rejects conflicting bytes without overwrite; plugin installation leaves project skill state absent (`tests/ac/t83_work_routing_portability.sh`). |

## Invariant coverage (I1–I18)

An invariant with no test is a wish. This is the honest map — where each is actually enforced, and which are still prose.

| I# | Enforced by |
|----|-------------|
| I1 | `stop_guard.py`, `seam.py`, `preserve.py` — T15, T28, T37 |
| I2, I3 | `preserve.py`, `bash_guard.py` — T15, T21 |
| I4 | `pre-commit`, `hop_guard.py` — T8, T9, T15 |
| I5, I6 | `enforcement.sh`, `seam.py` — T20 |
| I7 | `audit.sh`, `barbar.sh` — T6, T19 |
| I8 | `audit.sh` — T19 |
| I9 | `loop.sh` — T12, T13 |
| **I10** | `stop_guard.py` + the `loop.sh` receipt, or `audit.sh` at stage 10 — **T41**; a check that cannot finish refuses instead of passing — **T59** |
| **I11** | **partly — T43.** A send-back had no machine signal at all: it happened in chat and nothing downstream knew. The accept edge now asks for the verdict and a send-back is written to the run log with its reason, so "this hop was rejected" is at least recorded and the fix is told to start from a clean tree. Still not *enforced*: no hook can see whether the human actually rewound. The loop receipt (I10) limits the damage — stacked work cannot reuse the old evidence. |
| **I12** | **partly.** "must not change Current hop, locks or plan" is enforced — those are protected lines (T17, T30). "must not change files in this hop" is prose: a tangent editing a legitimately-writable path is indistinguishable from the hop's own work. |
| I13 | `loop.sh`, `dsharp_strength.sh`, `hop_guard.py`, `pre-commit` — T13, T18, T25, T26 |
| I14 | `control-line.sh`, `seam.py` — T20 |
| I15 | `pre-commit`, `pre-push`, `hop_guard.py`, `bash_guard.py` — T10, T11, T17, T27, T30, T33 |
| I16, I17 | `barbar.sh`, `i17_dune.sh` — T1–T7, T14 |
| I18 | every layer — T8–T83, and `enforcement.sh` itself |

T8–T83 run in throwaway git repos, not as greps. Run: `bash tests/enforcement.sh`
