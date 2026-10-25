# Changelog

## 3.0.0 — 2026-10-25

**A goal is one hop's definition of done, and an accepted slice's tests keep running.** It carries t77 and t78.
Major: two new loop refusals and a stricter merge gate (2.8.0 was never tagged).

- **t77** — a goal for another slice is refused; validators carried from earlier slices' goals are counted on every
  pass and refused above a cap; `goal.sh reset`; new installs start from a goal template that runs nothing.
- **t78** — carried lines move to a regression suite the merge gate and CI run; removing one is the human's.

**The regression suite: accepted slices' tests, run where it counts.** (05b t78-carry-out)

### What changes for you

- **`docs/cascade/regress.md`** holds column-0 `REGRESS: <command>` lines under `### <slice>` headings.
  `bash tests/regress.sh` runs each line alone and prints `REGRESS k/n`.
- **`bash tests/goal.sh reset` carries the replaced goal out first:** every line that is not a `# standing` gate or a
  law check moves to the suite under its slice (`### unattributed` when the goal named none), then the template is
  written. It refuses an uncommitted goal. `bash tests/goal.sh carry-out` does the same for carried lines mid-hop,
  and picks up lines the previous slice's goal had that are now nowhere ("dropped").
- **The merge gate runs the suite** (`bash tests/barbar.sh merge`): the committed lines, plus every line the merge
  base had that the branch removed — a removal made with `--no-verify` gains nothing — minus lines you retire with
  `- REGRESS_RETIRED: <line> — <reason>` in the envelope's Locked decisions. An uncommitted suite or a shallow clone
  is refused. With no lines, the gate prints exactly what it printed before.
- **CI runs it on every pull request:** `control-line.yml` has a separate `regress` job
  (`bash tests/regress.sh --gate --ci`, full history). A line ending in `# gate-only` (e.g. `xcodebuild` on Linux) is
  skipped there, counted as skipped — never as passed — and run at the merge gate.
- **Removing or changing a regression line is yours:** the agent's Write/Edit asks you (your approval is the
  signature); a commit without a signature is BLOCKED by name; deleting the file needs `CASCADE_HUMAN=1`. Adding
  lines is free. `bash tests/sign.sh` signs it like a law shard.
- **The loop names dropped lines:** `goal: <d> validators of <slice>'s goal are in neither this goal, regress.md nor
  a law`. Never a refusal. t77's notice and cap refusal now name `bash tests/goal.sh carry-out`.
- **The nightly** gets a `regress` job (set its `runs-on` for platform-bound lines). An existing product nightly is
  kept; to add it, paste:

      regress:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - run: bash tests/regress.sh

### What t78 does not guard

- The test a line runs is product code: a line can stay byte-identical while its test is gutted. Review test diffs;
  a test that must never weaken belongs in a law (`tests/inv/`, human-owned).
- `REGRESS_RETIRED`, like `READY`, is trusted because it sits in an EDIT block; branch protection and your merge are
  the backstop against a `--no-verify` forgery.

**Goal hygiene: a goal is one hop's definition of done again.** (05b t77-goal-hygiene)

### What changes for you (t77)

- **A goal written for another slice is refused.** When the last `GOAL_SLICE:` in `docs/cascade/goal.md` names a
  slice other than `CURRENT_SLICE`, `tests/loop.sh` stops with `LOOP REFUSED: … is for slice <x>, this hop is <y>`
  (exit 3) and names the fix. No `GOAL_SLICE`, or the `<slice slug>` placeholder, runs as before.
- **Carried-over validators are counted on every pass.** Lines that were already in an earlier slice's goal are named,
  with the slices they came from: `goal: 7 of 12 validators were in earlier slices' goals (a, b), 2 standing — move
  the 7 to the project's CI or a law`. Mark gates every hop reruns (lint, the full suite) with the shell comment
  `# standing`; they run unchanged and are never counted as carried. Law checks are never counted.
- **…and refused above a cap.** More than **10** carried lines refuses the loop before any validator runs, until lines
  move or the human signs a different cap: `- GOAL_CARRY_MAX: <n>` in the envelope's Locked decisions EDIT block, committed.
  A `# standing` marker added to a line an earlier goal held unmarked (while marking others) still counts as carried.
  A shallow clone cannot read the history: the loop says `goal: history unreadable, carry cap not checked`.
- **`bash tests/goal.sh reset`** writes a clean goal for the current hop (the template, its stage and slice, no
  validators) and says how many validators it removed. Run it at the start of every EXECUTE hop.
  `bash tests/goal.sh show` prints the slice check and the counts without running anything.
- **New installs start from `docs/cascade/goal.template.md`**, which runs nothing. Every release since 2.0.0 seeded a
  new repo's goal from the pack's own live goal, including two placeholder `VALIDATOR:` lines that always failed.
  An existing `goal.md` is kept.

### On upgrade

- A goal that still names the pack's slice (seeded by an earlier install) or a previous slice is refused once:
  `bash tests/goal.sh reset`.
- A goal carrying more than 10 earlier slices' validators is refused until they move to CI or a law, or the human
  signs a higher `GOAL_CARRY_MAX`. Whitespace-only rewording is still matched; a line reworded or folded into another
  is not (the count can only be too low).

## 2.7.0 — 2026-10-23

**The scale release: Gradle laws in one build, a verdict cache, affected laws, law shards, signed retirement, a quiet
Stop hook — and the builds that still run, tuned.** It carries t63–t69 and t74. In short:

- **t63** — the Stop hook's nudges reach the agent quietly; no more "Stop hook error" for doing its job.
- **t64** — a signed Gradle law harness proves eligible laws GREEN from one build instead of two per law.
- **t65** — a law's GREEN is reused when nothing it declares changed; never at the merge gate or the nightly.
- **t66** — a hop runs the laws its diff can break, and fails closed to all of them.
- **t67** — laws may live in `docs/cascade/laws/*.md` shards, read and guarded as one set.
- **t74** — a new law's red twin can be committed; the pre-commit hook is never silent.
- **t68** — a law is retired by a signed, reasoned line, and a failing law can never leave force inside a hop.
- **t69** — the Gradle builds the pack still runs are tuned, never a verdict; the nightly splits across runners.

**Gradle tuning: faster pack builds, the same verdicts.** (05b t69-gradle-tuning)

### What changes for you

- **The loop's batched builds use Gradle's configuration cache** (`tests/lib/gradle_tuning.py`) — unless you said
  anything about it yourself: `--[no-]configuration-cache` or `-Dorg.gradle.configuration-cache…` on the line,
  `GRADLE_OPTS`, or any `org.gradle.configuration-cache…` key (`problems=warn` included) in the project's,
  `~/.gradle`'s or `$GRADLE_HOME`'s `gradle.properties`. This reverses 2.6's "the pack never turns it on", for the
  pack's own batched builds only. Lines that run alone and every law's own `check:`/`break:` are never changed.
  - **A build that rejects it** (E0: Gradle 8.5 "Configuration cache problems found", 9.1.0 "…unsupported with the
    configuration cache") is rerun once without it; `.cascade/loop/tuning.log` says why, and
    `.cascade/gradle/tuning.tsv` remembers the drop until a tracked build file or the Gradle version changes.
  - **The cost:** with the cache on, Gradle runs a build's tasks at the same time (E0: two modules' test tasks
    overlapped on 8.5 and 9.1.0). Tests sharing a port or file then fail in the batched build, which proves nothing,
    and their lines run alone — measured on both versions: same verdicts. `org.gradle.configuration-cache=false` or
    `BDD_GRADLE_TUNING=off` keeps the old behaviour.
- **Two faster settings need your signature**, because each can change a test result:
  - `- GRADLE_OFFLINE: on` adds `--offline` to batched and law builds (a `-SNAPSHOT` or `1.+` dependency is then
    tested from the cache). An offline miss is dropped and rerun online.
  - `- DSHARP_GRADLE_FORKS: on` runs each law's check copy with `maxParallelForks = max(yours, CPUs/2)`. It helps only
    a law whose check selects several classes; classes that fail when they share one JVM can then read GREEN in a hop
    — the merge gate, which never uses the law build, still scores them RED. The mutant copy never forks.
- **The law harness compares the mutant copy to the original too** (it compared only the check copy), and compares
  forks explicitly, since `maxParallelForks` is not a task input.
- **Daemons are reported:** the `loop:` line names any daemon a build had to start (`; daemon: 1 started (…)`), and
  says `unknown` when a `-q` log hid it.
- **`BDD_GRADLE_TUNING=off`** turns every pack-added setting off; loop and dsharp output and Gradle's argv are then
  byte-identical to 2.6.
- **The nightly splits across runners by module** — plan (`tests/lib/nightly_plan.py`), one job per part
  (`dsharp_strength.sh --part`), a join (`--join`) that prints exactly one run's output or `FATAL     join: …` with no
  score. `DSHARP_SERIAL` laws stay in one part. The merge gate stays one run. A product gets it with
  `bash install.sh --with-nightly`, which never overwrites a `nightly.yml` you have.
- **Fixed:** `tests/stress/law_harness.sh` compared a run with its own cached verdicts since t65 turned the cache on;
  it now pins `DSHARP_CACHE=off`.

### Measured (E1)

Gradle 9.1.0, 10 CPUs, warm daemon, the t62 fixture (two modules, a 5s configuration phase) with 20 harness-shaped
laws (`tests/stress/gradle_tuning.sh --timing`). "Before" is `BDD_GRADLE_TUNING=off`, which AC9 shows is 2.6's
commands byte for byte.

| Run | Before | After | Verdicts |
|---|---|---|---|
| Loop, 4 lines in 2 waves, first pass | 13s | 12s | same |
| Loop, unchanged repeat pass | 12s | **2s** | same |
| Farm, 20 laws, harness signed | 18s | 17s | DSHARP 20/20 both |
| Farm, + `DSHARP_GRADLE_FORKS: on` | — | 18s | DSHARP 20/20 (one class per law: forks cannot help) |
| Nightly, 20 laws | 18s, one runner | **13s** wall-clock (2 parts by module; slowest 13s, join 0s) | DSHARP 20/20 both |

The farm row is flat, as the spec said it would be (critique C2, answered by the human: report it as measured). The
farm's builds are the law build and each law's own commands, which t69 does not change by default; the speed-up is in
the loop's repeat pass and the nightly's wall-clock.

### Tests

- **T69** runs `tests/ac/t69_gradle_tuning.sh` (AC1–AC6, AC8, AC9; red twins: a runner ignoring drop rows, a join
  skipping a missing law). `tests/stress/gradle_tuning.sh` (in `pack-self-check.yml`, Gradle 8.5 and 9.1.0) proves
  the verdict matrix, a cache-incompatible module, a shared port, signed forks on the check copy only, the shared-JVM
  backstop and daemon reporting on real Gradle; red twin: forks on the mutant prove a racy THEATER law GREEN.

**Retiring a law: signed, reasoned, and never a way to drop a failing law inside a hop.** (05b t68-law-retirement)

### What changes for you

- **`retired: <date> — superseded by D<N>` or `— removed — <reason>`** under a law's heading takes it out of scoring,
  `/goal` and the audit, keeps its id and its text, and is a human-signed D# line. An invalid line keeps the law in
  force with a WARNING; supersession is one pass (a cycle is invalid both ways).
- **A failing law cannot leave force inside a hop.** While a hop is open at HEAD or in the staged hop state, a law
  may be retired or have its block deleted only if it is GREEN on HEAD's tree. RED, THEATER and UNPROVEN are refused —
  wider than the brief's "RED", because each of them fails the gate — and neither a signature nor `CASCADE_HUMAN=1`
  lifts it. `tests/barbar.sh merge` re-proves it from git with `tests/retirements.sh`, a new refusal condition.
- **Protected lines are compared as a multiset**, so a second identical `retired:` (or `check:`) line needs a
  signature too — it used to add no diff.
- **A shared `check:` runs once** per scoring run on the two-command path, before any break.
- **`bash tests/laws_report.sh`** lists missing paths, exact duplicates, unexplained and stale laws, and families.

### Tests

- **T68** runs `tests/ac/t68_law_retirement.sh` (AC1–AC9) with three red twins; AC7 and AC9 diff against `537c0c0`.

**A new law's red twin can be committed; the pre-commit hook is never silent.** (05b t74-inv-new-file-skip)

### What changes for you

- **Fixed: a silent exit 1.** `.githooks/pre-commit` ended with exit 1 and no message whenever a commit added a file
  under `tests/inv/` not named `test_D…` (a mutant patch, a twin table) — `grep` under `set -euo pipefail`. Reported
  from a downstream repo.
- **The rule for a new file under `tests/inv/` is now explicit, and never looser than before:** its name carries the
  law's id; an undeclared id (a new law's test or twin, `tests/inv/mutants/D49.patch`) lands; a declared id lands
  only on the exact path that law's commands name; a file with no id (`conftest.py`) or a new file under a declared
  law is BLOCKED by name and needs a human signature. A copy of a law's test in a subfolder (`sub/test_D1.sh`), which
  used to slip through on a basename match, is now blocked too. Changes to existing files are the human's, as before.
- **Every id in a name counts** (`test_D99_D1.sh` is D1's), the named path is compared token for token (a prefix is
  not the path), and an existing file whose type changes (a symlink swapped in for a law's test) is blocked like
  any change — a gap that predates t74. Paths are read whole (a name with a space no longer splits into two), and an
  ERR trap names the line of any unexpected hook failure.
- `hop_guard.py` applies the same rule to the agent's Write and Edit calls. A file written through the shell is
  caught only at commit; the loop can run with it in the working tree before then (a bash_guard rule is a follow-up).
- **AGENTS.md rule 5** says how to add a new law's twin. **Installed repos:** re-run `install.sh` for the hook;
  `install.sh` keeps an existing AGENTS.md, so merge the rule-5 sentence by hand — the hook's refusal message carries
  the same rule meanwhile.

### Tests

- **T74** in `tests/enforcement.sh`: four new-law files land, five forbidden ones are blocked by name, existing files
  stay blocked, a signed id-less file lands, an injected failure names its line, `hop_guard` agrees, and two red
  twins (`tests/ac/fixtures/t74_twins.py`: the pre-t74 extraction, a skipped no-id branch) go red. `tests/lint.sh`
  now also checks the suite's own T-range lines.

**Law shards: laws in more than one file, read as one set, guarded like the envelope.** (05b t67-envelope-shards)

### What changes for you

- **Laws may live in `docs/cascade/laws/<module>.md`**, in the envelope's format. `tests/lib/laws.py` reads the
  envelope and then every shard as one set, so a split repo gives the same `DSHARP k/n`, verdicts, `laws.py --count`,
  `/goal` requirement and affected selection as an unsplit one. Every pack caller reads the repo's own shard
  directory, so a temporary envelope copy (autopilot's pre-edge check) never loses shard laws.
- **A duplicate id is FATAL**, anywhere: every reader refuses (dsharp FATAL, loop REFUSED, audit DIRTY, affected
  full, the seam says LAWS UNREADABLE, Gradle merging off). In a repo with no shards this is one of two deliberate
  changes: an envelope that repeats an id used to be scored twice; and the tests/inv reuse check now sees
  `###`-form laws, not only legacy one-liners.
- **Shards are guarded like the envelope**: pre-commit (renames counted as removals), the agent hook (a new shard
  included) and `tests/sign.sh` (new untracked and removed shards included). `tests/lint.sh` checks the envelope's
  `## Law shards` index and flags decisions written in a shard.
- **A hop reads only its shards.** The prompt hook lists them (`LAW SHARDS THIS HOP`); `bash tests/affected.sh
  --shards` names the ones a diff reaches; preserve re-injects the envelope's laws and one line per shard. AGENTS.md
  and the conductor (I13, PRESERVE, ADD, the critic and divergence prompts) say laws live in the envelope or a shard.
- `install.sh` ships `docs/cascade/laws/README.md` (kept once yours) and never a shard. The nightly checks out full
  history, so T65's and T67's baseline comparisons run there.

### Measured (E1, 2,000 laws in 20 shards)

| | Unsplit | Split |
|---|---|---|
| What a hop reads | 444,318 bytes (~111k tokens) | 21,445 bytes (~5k tokens): the envelope and one shard |
| Preserve's injected context | 173,534 bytes | 3,634 bytes |
| `laws.py --count` | 2,000 in 0.07 s | 2,000 in 0.06 s |

### Tests

- **T67** runs `tests/ac/t67_envelope_shards.sh` (AC1–AC9): split vs unsplit parity, duplicate FATAL in every
  reader, the guards (with a red twin that drops the shard guard), byte parity with `505ec73` when there are no
  shards plus the two named changes, every reader, the index lint, the read-list and install. The duplicate check
  has its own red twin.

**The verdict cache: a law's GREEN is reused when nothing it declares changed, and never at the merge gate.** (05b t65-verdict-cache)

### What changes for you

- **A second `tests/dsharp_strength.sh` on the same bytes costs no law build.** Each GREEN is stored in
  `.cascade/verdicts/<id>.json` (git-ignored, also in installed repos) under a key of the law's commands, the files
  and Gradle modules (with their dependencies) it declares, every build-logic and undeclared non-doc file, the
  toolchain, the pack and the verdict-relevant environment. A hit prints `GREEN     D7  <law>  (cached)` and counts in
  `k` like any GREEN; `CACHE     <h> hit, <m> run` comes before `DSHARP k/n`.
- **It can make a run faster, not greener.** Only GREEN is stored, only when the worktree did not change during the
  run; RED, THEATER and UNPROVEN always re-run. Any doubt (no git, a failed module map or `--version`, an unknown
  shared module, a cache error) is `CACHE     off — <reason>` and the old path. Forged or corrupt entries are ignored.
- **No audit or merge decision reads it.** `tests/audit.sh` always runs `dsharp_strength.sh` with `DSHARP_CACHE=off`
  (IMPLEMENTED needs a test that passes now, AGENTS rule 4 — a code-review finding narrowed the spec here), and so
  do `tests/barbar.sh merge` and the nightly's dsharp step. Any value but `on` (empty counts as unset) is the
  pre-t65 script byte for byte. The brief's "the merge gate may opt out" is taken as "always" (Ask 1, I18:49).
- **Declared inputs, stated.** A law that reads a file it does not declare can be stale in a dev run; declare it, or
  sign `- DSHARP_CACHE_SCOPE: tree` to make any non-doc edit invalidate every law (USAGE.md §B12).
- **Gradle's build cache for the t64 law build.** With the cache on, the law build adds `--build-cache` (compile
  FROM-CACHE); law copies stay `cacheIf { false }` and always execute, and no flag is added to a law's own
  commands (Ask 3). A signed, committed `https` `- DSHARP_GRADLE_BUILD_CACHE_URL:` adds a read-only remote.
- A document a law's command names, `PATH` and the interpreter environment are in the key; `tree` scope and an
  unmapped law hash every file, documents included. A law's own `--no-build-cache` wins over the law build's
  `--build-cache`, and the signed remote is applied after the project's settings (`push = false` cannot be undone).
- The t56, t64 and t66 ACs export `DSHARP_CACHE=off`, as they assert uncached counts; no assertion in them changed.

### Measured

| Run | E1: stub, 20 laws / 3 modules | E2: Gradle 9.1.0, 6 laws / 3 modules, harness signed |
|---|---|---|
| cache off | — | 6.38s |
| cold | 3.46s, 40 law commands | 6.99s |
| warm, unchanged | 0.90s, 0 law commands | 4.52s (only RED/THEATER re-proved) |
| one `:core` edit | 1.58s, 10 law commands (core + app) | 6.35s (`:web` stays cached) |
| after `clean` | — | 7.30s, compile FROM-CACHE, every law copy executed |

A warm run still pays one module-map configure and one `--version` per Gradle entry (§6: the map is never cached,
so a map failure stays a fail-closed miss).

### Tests

- **T65** runs `tests/ac/t65_verdict_cache.sh` (AC1–AC12) on the Gradle stub, with red twins for a key without the
  module closure, a lookup without the key comparison, a store that keeps THEATER, and a store without the
  fingerprint re-check; AC7 diffs against the pre-t65 script at `219baef`; AC11 shows t64's AC goes red without
  its `export DSHARP_CACHE=off`.
- `tests/stress/verdict_cache.sh` (E2) runs on real Gradle: parity, warm hits, a `:core` edit, compile FROM-CACHE
  after `clean`, and a signed remote URL reaching Gradle ("Could not load entry … from remote build cache"). CI
  runs it in the gradle-runner job.

**Affected laws: a hop runs the laws its diff can break, and fails closed to all of them.** (05b t66-affected-laws)

### What changes for you

- **An EXECUTE hop stops paying for laws it cannot reach.** `tests/loop.sh` asks `tests/lib/affected.py` which
  in-force laws the hop's diff can break — by each law's `path:` (the `:symbol` suffix is stripped, as in
  `dsharp_strength.sh`) and the Gradle module its `check:` names, plus the modules that depend on a changed one.
  A law it cannot reach is printed `not affected` and is neither `k` nor `n`. `/goal` must still list every
  affected law; omitting one is the same `FAIL` (I13).
- **The base is the commit that opened this hop**, not the branch point: the newest commit touching
  `docs/cascade/hop-state.md` with the same `CURRENT_HOP/STAGE/SLICE`. No such commit, a mismatch, or a base that
  is not an ancestor means the full set. There is no `AFFECTED_BASE` environment switch; `--base` is report-only
  and `tests/loop.sh` never passes it.
- **Every ambiguity is the full set**, with the reason printed by `tests/affected.sh`: build logic, a signed
  `- AFFECTED_SHARED_MODULES:` line, an unreadable module map, a law naming a module the map lacks, an unmapped
  file, an unmapped law, or a Gradle selector that is not exactly one `:module:task`. `docs/` and `*.md` are
  ignored unless a law guards them.
- **The merge gate does not change.** `tests/dsharp_strength.sh`, `tests/audit.sh` and `tests/barbar.sh merge` run
  every law's check and every Red twin; none reads the selector (I18:49, AGENTS rule 6). The brief's "merge gate
  runs only affected twins" is recorded as a conflict in the t66 spec (Ask 3) and is not taken. A scheduled
  `.github/workflows/nightly.yml` is the full-set proof after merge.
- **Try it:** `bash tests/affected.sh` (or `--list`, `--why`). `USAGE.md` §B11 documents the mapping, the three
  states and the schedule. The module graph is read once per entry with
  `tests/lib/affected.init.gradle`; nothing is cached (t65 owns caching).

### Measured (E1, Gradle 9.7.1, warm daemon, 20 laws over `:core`, `:app` (:core), `:web`)

| Hop | Law checks | Time | Gradle invocations |
|---|---|---|---|
| full | 20 | 15.26s | 20 |
| affected (core diff) | 5 | 3.71s | 5 |
| module map alone | — | 0.42s | 1 |

### Tests

- **T66** runs `tests/ac/t66_affected_laws.sh` on the Gradle stub: one module's diff (AC1), every fail-closed
  trigger (AC2), omission and both red twins (AC3), the merge gate and `barbar.sh gate` running every check and
  twin with `AFFECTED_*` ignored (AC4), the nightly workflow (AC5), mapping edges including `:symbol`, renames and
  `CASCADE_ENVELOPE` (AC6), and a two-hop base (AC7). Both twins are shown to go red.
- `tests/stress/affected.sh` reads a real three-module build, asserts the map's `app -> core` edge and the
  D1–D5 selection, and prints E1's table. CI runs it in the gradle-runner job.

**Gradle laws: one law build instead of two builds per law, and a law shape that is scored right.** (05b t64-law-harness-jvm)

### What changes for you

- **Nothing, until you sign it.** With `- DSHARP_GRADLE_HARNESS: on` signed inside the envelope's Locked decisions
  and committed, `tests/dsharp_strength.sh` proves eligible Gradle laws GREEN from one law build
  (`tests/lib/law_harness.py`, `tests/lib/law_harness.init.gradle`). Unsigned, every law runs its own `check:` and
  `break:` exactly as before.
- **Only GREEN is ever the harness's.** RED, THEATER, UNPROVEN, and every law it cannot take, are scored by the
  law's own two commands, so no failing verdict comes from the fast path. The merge gate never uses it, either for
  its own check or for the one inside `tests/audit.sh`.
- **The Gradle law shape** (USAGE.md §B10): `break: INV_MUTANT=<id> <check> --rerun`. Measured on Gradle 8.5, 9.1.0
  and 9.7.1:
  - without `--rerun`, a twin run right after its passing check is `UP-TO-DATE` and passes, a false THEATER;
  - `-Dinv.mutant` never reaches the test JVM.
  Only this shape is eligible. Briefed as t72: say so when a THEATER is only an up-to-date task.
- **Copies are checked, not trusted.** For each law the build runs a check copy and a mutant copy of its test task,
  one after another. The law falls back to its own commands when the original has a `doFirst`/`doLast`, an
  `onlyIf`, a `finalizedBy`, a different environment, or an input the copy does not reproduce. The comparison
  fails closed: an unknown object-valued input makes the law ineligible.

### Measured (E1, Gradle 8.5, warm daemon, a fixture with fast configuration)

| 50 GREEN laws | Time | Gradle builds |
|---|---|---|
| per-command | 65s | 100 |
| per-command, `DSHARP_JOBS=4` | 38s | ~95 |
| law harness | 32s | 1 |

The fixture configures in under a second, so the saving shown is mostly client start and up-to-date checks. On a
build whose configuration takes T seconds, per-command pays 100 × T and the harness pays T once. Peak daemon RSS
for the 100 test tasks was 558 MB.

### Tests

- **T64** runs `tests/ac/t64_law_harness.sh` on the Gradle stub: one build, the signed switch, a leaked mutant,
  only-GREEN, eligibility and the merge gate, each with a red twin.
- `tests/stress/law_harness.sh` checks the verdict matrix, up-to-date state and configuration-cache reuse on real
  Gradle 8.5 and 9.1.0. Its red twins prove the fidelity checks and §4's conditions are what keep D7/D8/D3 honest.
  CI runs it in the gradle-runner job.

**The Stop hook stops showing you errors for doing its job.** (05b t63-quiet-stop-guard)

### What changes for you

- **No more "Stop hook error" when the agent forgets an edge line.** The hook used to send the agent back by
  exiting 2, and Claude Code shows that to you as an error. Its nudges now go in `additionalContext`: the
  agent reads them and replies again, and you see nothing extra. Measured on Claude Code 2.1.280, where
  `decision: block` also continues the turn but still shows you "Stop hook error occurred", so it is not used.
  On a Claude Code version without Stop `additionalContext` the nudge is dropped and the hop can end without its
  edge line; git hooks and CI are unaffected.
- **Stops meant for you now reach you.** The autopilot time budget, the continuation cap, the stage-10 punch
  cap and the new nudge cap each show one notice line (`systemMessage`). Before, they went to stderr on exit 0,
  which nobody sees.
- **An edge quoted in code is not an edge.** An explanation that mentions `STITCH NEEDED:` or `AUTOPILOT HALT`
  inside backticks or a code block no longer starts a signed autopilot run or closes a hop. A reply whose only
  edge line is inside code is asked to print it as plain text.
- **Identical nudges cap at two.** The third identical nudge in a row, within one prompt of yours, becomes a
  notice to you instead. Stage-10 punch rounds are not counted; the punch cap still decides those.
- **A crash inside the hook is silent** (exit 0, a `CRASH` line in `.cascade/decisions.log`) instead of a
  traceback, and every nudge now writes a decisions-log line (`NOEDGE`, `CONTINUE`, `NOHALTBLOCK` are new).
- **One instruction at the edge.** The I1 nudge and the conductor (`product-e2e-gre-pipeline.md`) no longer say
  to reprint I1–I18 at a hop edge, matching AGENTS.md.

### Tests

- **T63** runs `tests/ac/t63_quiet_stop_guard.sh` (AC1–AC8, each with a red twin; the pre-t63 hook is a
  fixture in `tests/ac/fixtures/t63-pre/`). Every other stop_guard assertion in `tests/enforcement.sh` reads
  the verdict through `sgv` instead of the exit code, with the same verdicts.
- Found while measuring: Claude Code gives a continuation the same `prompt_id`, so the hook judges only the
  first stop of each prompt. Autopilot therefore advances at most one edge per prompt. Unchanged here; briefed
  as t70.

## 2.6.0 — 2026-10-19

**A faster `/loop` for Gradle products, with no verdict changes, plus repos that upgrade themselves when the plugin does.** (05b t62-loop-runners)

### What changes for you

- **Gradle lines share builds.** `tests/loop.sh` used to run every `VALIDATOR:` line as its own build, so a Gradle product paid its configuration time once per line. Consecutive plain `./gradlew …` / `gradle …` lines now go through `tests/lib/gradle_runner.py`, at their place in the goal (a Gradle line still sees what an earlier shell line did). An init script (`gradle_runner.init.gradle`) records Gradle's own task outcomes and task graph.
  - The runner reports **only passes it can prove**. Every other line, and every failure, runs alone through the pre-2.6.0 path, so a FAIL is always the old verdict.
  - Measured on a two-module fixture with 4 lines and a 5s configuration phase, Gradle 8.14.3:

    | Mode | Builds | First pass | Unchanged pass |
    |---|---|---|---|
    | Each line alone (before 2.6.0) | 4 | 29s | 30s |
    | Exact (default) | 2 | 18s | 16s |
    | Merged (opt-in) | 1 | 9s | 7s |
- **Exact mode is the default and needs nothing from you.** Lines that use the same test task with different `--tests` filters go into separate waves, one build each, so every test task runs with the line's own filter. Batching only runs on Gradle versions verified on real Gradle: 8.5 to 9.1.x. On any other version every line runs alone, as before.
- **Merged mode is your call.** Sign and commit `- LOOP_GRADLE_MERGE: on — locked <date> — reason: <why>` inside the `<EDIT>` block of the envelope's Locked decisions. An uncommitted line does nothing, and the last such line wins.
  - Filters on one test task are then unioned into a single run, so repeat passes are `UP-TO-DATE`.
  - The cost: tests from different lines share one test JVM.
  - It never applies to an in-force D# `check:` line, which keeps its own run.
  - No environment variable can turn it on.
- **Every line has a log** in `.cascade/loop/` and a time. A FAIL shows Gradle's failed-test lines and the end of its log (at most 25 lines). One summary line comes before `LOOP k/n`. The `PASS`/`FAIL`/`LOOP` lines, the exit code and the receipt are unchanged.
- **`BDD_LOOP_RUNNER=shell`** turns the runner off. Goals with fewer than two Gradle lines never start it, and builds that would hold a single line are not run.
- **The plugin refreshes repos itself.** In plugin mode, every SessionStart (now including a plain `startup`) refreshes the repo's shipped scripts with the plugin's `install.sh` when the plugin is newer and these all hold:
  - the cascade is idle and the tree is clean;
  - no shipped file was edited;
  - no other session holds the lock;
  - `BDD_AUTO_REFRESH` is not `0`.

  `install.sh` runs in a temporary git worktree, never in your tree. The result is applied with a single atomic `git apply`, and only if `install.sh --check` passed there and your tree is still clean. A failure, a timeout or a concurrent edit therefore leaves the repo untouched. It never commits, and keeps `goal.md`, the envelope and the hop state byte-identical. Otherwise it prints why it didn't refresh, and the command. On startup it prints nothing when versions match (T15).
- `install.sh` now gitignores `.cascade/loop/` and `.cascade/gradle/`.

### Upgrade

Plugin mode: update the plugin. Your next session refreshes each idle, clean repo; commit what it wrote with
`git add -A && git commit -m 'cascade: update pack to 2.6.0'`. The first batched pass misses Gradle's
configuration cache once, because the new init script means a new cache key. Standalone: `bash <pack>/install.sh .` as before.

### Evidence

- `tests/ac/t62_loop_runners.sh`, using a stub Gradle whose `--tests` selections are recorded from real Gradle. On each of 16 matrix cases plus a shared-JVM side effect, every verdict equals the line run alone. Red twins that each go red:
  - no surely-selected-test check;
  - no failure-count check;
  - no D# exclusion;
  - a runner that passes every line;
  - no clean-tree checks before a refresh.

  The matrix includes shell lines before and between Gradle lines.

  It also covers the output contract against 2.5.0's frozen `loop.sh`, the upgrade from a real 2.5.0 install, and every refusal of the automatic refresh.
- `tests/stress/gradle_runner.sh` (AC7) checks the same claims on real Gradle 8.5, 8.14.3 and 9.1.0:
  - each pattern's selection;
  - the verdict matrix;
  - configurations per pass;
  - that the init script moves no task's up-to-date state;
  - configuration-cache reuse.

  CI runs it in `pack-self-check.yml` on 8.5 and 9.1.0.
- `tests/enforcement.sh` **T62**. T16 now also checks that the two new log directories are ignored.

## 2.5.0 — 2026-10-14

**Fail-closed verification: parser mismatch detection + strict metadata validation.**

- **`laws.py --count`** — new mode returns the number of declared laws (excluding templates).
- **Parser mismatch detection** — `dsharp_strength.sh` compares `--count` vs parsed laws.
  If they disagree, prints `FATAL` and exits 1. Catches silent parser failures.
- **Strict metadata validation** — if a law has ANY metadata field (`reason:`, `path:`, `tier:`),
  all required fields (`reason:` and `path:`) must be present. Partial metadata is flagged as
  `WARNING`. Laws with zero metadata (legacy format) continue to skip validation.



**Mutation type registry + path verification — AI can no longer invent fake red twins.**

Every D# law now requires structured metadata: `reason:` must use a registered mutation type,
and `path:` must point to a real file. `dsharp_strength.sh` validates both mechanically and
refuses the loop when metadata is invalid.

- **`docs/cascade/mutation-types.md`** — new registry of 8 approved mutation types
  (`REMOVED_GUARD`, `INVERTED_CONDITION`, `WRONG_CONSTANT`, `SKIPPED_STEP`, `BYPASSED_AUTH`,
  `WRONG_STATE`, `REMOVED_ENCRYPTION`, `ALLOWED_OVERFLOW`).
- **`tests/dsharp_strength.sh`** — validates `reason:` against the registry and `path:` file
  existence (plus optional `:symbol` grep). Prints `WARNING` and exits non-zero on invalid
  metadata. `DSHARP k/n` is unchanged; metadata validation is an additional gate.
- **`tests/lib/laws.py`** — parses `reason:`, `path:`, `tier:` fields alongside `check:` and `break:`.
- **`tests/enforcement.sh` T60** — asserts unregistered mutation types trigger WARNING
  (red twin: a registered type passes cleanly).
- **`tests/enforcement.sh` T61** — asserts non-existent `path:` triggers WARNING
  (red twin: a real file passes cleanly).
- **`docs/cascade/envelope.md`** — D# template now references the mutation type registry.
- **`tests/loop.sh`** — updated to parse 7-field pipe format from laws.py.



**Documentation role labels for dual human+AI readability — 🧑 HUMAN / 🤖 AGENT / ⚙️ SYSTEM.
Decision-point tables, error-recovery tables, structured D# format.**

Every doc in the cascade now has three distinct visual zones: what the human decides
(decision-point tables, emoji markers), what the agent reads and writes (structured
sections, consistent table formats), and what the system enforces mechanically.

- **AGENTS.md** — Added role-label table, 🧑 human touch-points table, 🤖 agent error-recovery
  table, ⚙️ enforcement layers table. Non-negotiable rules unchanged.
- **envelope.md** — Added decision-point table, D# format with `reason:`, `path:`, `tier:`
  fields, law status table with emoji codes (🟢 GREEN / 🔴 RED / 🎭 THEATER / ⚪ UNPROVEN).
- **hop-state.md** — Added decision-point table per field, agent reading rules table.
- **goal.md** — Added role labels, machine-parse format rules, agent write instructions,
  human review checklist.



**OpenCode v2 compatibility layer — commands, skills, references, and install.sh deployment.**

BDD is now usable from OpenCode v2 with the same slash commands and cascade references that
Claude Code users get, without needing the Claude Code–specific agent hooks (Layer 2).

- **`.opencode/commands/`** — 8 slash commands for OpenCode v2: `/loop`, `/barbar`, `/audit`,
  `/doctor`, `/dsharp`, `/critique`, `/diverge`, `/enforce`. Each runs the corresponding
  `tests/*.sh` script and reports its output verbatim.
- **`opencode.jsonc`** — root-level config with `references` to cascade docs (`envelope.md`,
  `hop-state.md`, `AGENTS.md`, `CONTROL-LINE.md`) and `skills` pointing at the existing
  `.claude/skills/` directory (auto-discovered by OpenCode v2).
- **`.opencode/skills/bdd/SKILL.md`** — a discoverable BDD skill that gives the agent the
  full cascade contract, non-negotiable rules, and enforcement layer map.
- **`install.sh`** updated to deploy `.opencode/` and `opencode.jsonc` into target repos
  alongside the existing Claude Code layers. The standalone install path now works for
  OpenCode v2 users.
- OpenCode v2 already auto-discovers `.claude/skills/` and reads `AGENTS.md` as instructions
  — no extra config needed for those.
- Enforcement suite T8–T59: **PASS: I18 T8–T59 enforced** (all 52 tests green).

## 2.2.0 — 2026-10-12

**Auto-report failure workflow with structured temporal metadata for AI-driven auto-fix.**

A new GitHub Actions workflow (`.github/workflows/auto-report-failure.yml`) runs a named
script and creates a deduplicated GitHub issue when it exits non-zero. Every issue body
embeds a JSON-LD metadata block with ISO-8601 / epoch / RFC-2822 timestamps, commit SHA,
git author time, run URL, severity and exit code — parseable by an automated fix agent to
reproduce the failure and understand the context without reading chat.

- **`workflow_dispatch` trigger** with inputs for script path, arguments, custom title,
  labels, severity (`bug / flaky / infra / performance / security`) and a dedup window
  (`max_issue_age_hours`, default 72).
- **Smart dedup lifecycle:** skips a recently-created open issue, closes a stale one
  older than the window and creates a fresh report, or reopens a matching closed issue
  and appends a comment linking the new failure.
- **`permissions: issues: write`** scoped to the workflow — no token leaks to other jobs.
- Existing workflows (`control-line.yml`, `pack-self-check.yml`) are untouched; this is an
  opt-in dispatch workflow, not a new CI gate.

## 2.1.0 — 2026-09-28

**Scale hardening (t59): the checks behind the hop edges now cost what changed, not what the repo weighs — and a check that cannot finish says so instead of passing.**

A stress test on a synthetic ten-year repo (60,060 files, 10,000 spec docs, 150 laws) showed the per-action layers staying flat, hooks included (under 100ms), but three things growing with the repo, two of which switched a check off without a word.

- **The loop receipt's fingerprint is built from a temporary copy of git's index.** git re-hashes only files whose stat data changed, so it takes 0.2–0.3s at 60,000 files instead of 235s (one `git hash-object` per file); `loop.sh` with one validator went from 217s to 0.4s. New blobs go to a temporary object directory, so nothing is written to `.git`, and the real index, its flags and HEAD are never touched. It is more precise than before: a `chmod +x`, a symlink retarget or an embedded repo moving to another commit now counts as a change, and edits hidden behind `assume-unchanged` or `skip-worktree` are still seen. A symlink is now recorded as a link; its target outside the repo is no longer followed.
- **A Stop-hook check that cannot finish sends the agent back, naming the cause and the command.** The receipt fingerprint (120s), the stage-10 audit (900s) and the 05b spec gates (120s) used to pass when they timed out or crashed — "cannot verify: do not invent a failure" — so past roughly 30,000 files the "tree changed after the loop passed" check was simply off. An empty fingerprint used to pass too. The hook is still the soft layer: it fires once per stop, so the agent's retry stop passes; CI and the merge gate are unchanged. A timed-out audit is not counted as a punch round.
- **`loop.sh` writes no receipt it cannot back.** If the tree cannot be fingerprinted it says so, prints no accept-edge line and exits 1, instead of writing a receipt the Stop hook would misreport as "the loop never passed".
- **`sign.sh` finds and diffs human-owned files in one `git grep` and one `git diff`**, not one `sh`+`grep` per doc and one `git diff` per stitched file: 38s at 10,000 docs becomes about 0.15s. It signs exactly what it signed before.
- **Autopilot needs the exact spec name `docs/cascade/<stage>-<slice>.md`** for GENERATE→EXECUTE. It used to accept any doc whose name *contained* the slug, so an old `06-audit-logging.md` stood in for a new `06 logging`. On 05b nothing changes: `critique.sh` already required the exact name.
- **After upgrading, run `bash tests/loop.sh` once per repo with an open EXECUTE hop.** Receipts now carry a scheme (`t2:`); the Stop hook compares it with what the repo's own `tests/lib/cascade.sh` prints, so an old receipt gets "different pack versions — run the loop once", and a plugin-mode repo whose `tests/` have not been refreshed yet keeps working until you re-run `install.sh`.
- `tests/stress/ten_year.sh` rebuilds the 60,000-file fixture and prints the numbers (opt-in; not in CI or the farm, since it writes 60,000 files). T59 and `tests/ac/t59_scale_hardening.sh` (red twins for each fix) are the evidence.

## 2.0.0 — 2026-09-27

**Major version: the 05b GENERATE contract changed.** No new behaviour beyond 1.10.0 and 1.11.0; this release marks them as breaking.

- **Every 05b spec now has to pass a gate before you review it** (t57, 1.10.0): a committed, fully answered critique from a fresh critic, plus `## Before vs after` diagrams and a `## Benefits and trade-offs` table. The Stop hook, autopilot and CI refuse the spec edge while `tests/critique.sh` is red.
- **A repo that upgrades while a 05b GENERATE hop is open will have that edge refused** until the critic has run and its rows are answered. Finish or send back an open 05b spec hop before upgrading, or run the critic after.
- **`[diverge]` briefs** (t58, 1.11.0) add a human-signed choice between designs before the spec. It is opt-in; untagged briefs are unaffected.
- **Autopilot's GENERATE→EXECUTE edge on 05b** now also requires `tests/critique.sh` and `tests/diverge.sh` green (`AGENTS.md` rule 7).

## 1.11.0 — 2026-09-27

**Divergence (t58): see several designs before one is chosen — and choose it yourself.**

Every spec was built on the agent's first idea; you could accept it or send it back, but never see the option you didn't know to ask for. Tag a brief `- <slug>: [diverge]` (or `[diverge N]`, 2–5) and its GENERATE hop starts by showing you options instead.

- **N fresh subagents, one design each.** O1 is always the boring baseline — the default to beat. Every other option works under its own forbidden pattern or single priority, and states what it gives up, when you'd regret it, and a **falsifier**: a command or concrete experiment, in backticks, whose result would prove this option wrong. Plain language; no code.
- **The pick is yours, at every layer that can see it.** The options land with one empty `<EDIT>CHOSEN:</EDIT>` placeholder and the reply halts with `decision needed`. You name an option; filling the placeholder is a change to existing `<EDIT>` content, so it asks you in the dialog (Layer 2) and is refused at commit without your signature (Layer 1), whatever tool made it. The agent never pre-fills a pick; an unattended run stops at the choice.
- **`bash tests/diverge.sh`** (`DIVERGE k/n`, `… — waiting on your choice` before the pick, `n/a` for untagged briefs) reads the options as committed at HEAD and checks completeness, a baseline O1, distinct constraints and falsifiers, no copy-pasted approaches, provenance, exactly one signed `CHOSEN`, and a spec whose `## Chosen design` names it. It never judges which design is better.
- **Limits, said out loud.** The overlap check catches copy-paste, not paraphrase — a reworded twin of one design passes it; the ranking and your reading are the defence. With `core.hooksPath` unset, a pick is as unguarded as every hop edge.
- The Stop hook, autopilot and CI now run both spec gates (critique and divergence), and autopilot names every red gate at once. T58 and `tests/ac/t58_divergence.sh` (15 red twins) are the evidence.

## 1.10.0 — 2026-09-27

**A spec critic before the build (t57): you are no longer the only reviewer of a plan.**

Until now the first independent reviewer the pack dispatched was the stage-10 auditor, after the code existed. A gap the human could not see — for lack of expertise, or because the brief framed the wrong problem — cost a build, a punch round and a rebuild. On every GENERATE 05b hop, a fresh subagent that did not write the spec now reads the brief and the spec first.

- **It asks "is this the right problem?" before "is the spec sound?"**, then reports at most 10 findings, most severe first, each with evidence you can check yourself — a command to run or a `path:line` to read — or marked `UNEVIDENCED`.
- **Its rows are committed verbatim, before anyone answers them**, to `docs/cascade/05b-<slice>-critique.md`. The author answers every one — `fixed <where>`, `rejected <reason>`, or `human <question>` — and `human` rows are raised at the edge.
- **Every 05b spec shows a before/after diagram and a plain benefits-and-trade-offs table**, so a non-specialist can judge the change.
- **The critic advises; it never decides.** `bash tests/critique.sh` (`CRITIQUE k/n`) scores shape, provenance and answers — never whether the critic was right. It fails on a missing, unanswered, rewritten or deleted row, rows and answers landing in one commit, an unescaped pipe, a missing diagram, more than 10 findings, or evidence that is empty or not checkable (no command, no `path:line`, not `UNEVIDENCED`). `n/a` on every other hop.
- **Three layers enforce it.** The Stop hook refuses `review spec+plan` while it is red — checked before the autopilot branch, so signed edges cannot carry a red critique past it; autopilot refuses GENERATE→EXECUTE; CI runs it. T57 and `tests/ac/t57_spec_critic.sh` are the evidence.
- **Limits, said out loud.** It catches the author editing or deleting the critic's rows after they were committed; it cannot prove what a subagent said before it was written down. Scope is 05b; stage 05 and 06–09 are follow-ups.

## 1.9.4 — 2026-09-21

**`DSHARP_JOBS=N` — score laws in parallel, without ever flipping a verdict.**

`dsharp_strength.sh` ran every law's `check:` and `break:` sequentially, so a repo whose laws are heavy builds paid the sum of all of them — hours. `DSHARP_JOBS=N` now scores up to N laws concurrently. The report is collected and printed in **declared order**, and `DSHARP k/n` and the exit code come from the collected results, so a parallel run is identical to a sequential one, only faster — speed can never turn a RED into a GREEN (I18).

- **Opt-in; default unchanged.** No `DSHARP_JOBS` (or `=1`) is the exact sequential behaviour as before — nothing changes for any repo until it sets `N>1`. `enforcement.sh` T8–T54 scores dsharp at the default and stays green.

- **`DSHARP_SERIAL="D2 D5"`** forces named laws to run alone — the escape hatch for a law that shares a daemon, a port or a build dir and would race. The pack does not fabricate isolation; hermeticity stays the law author's job.

- **`tests/ac/t56_dsharp_parallel.sh` is the red twin:** it asserts a parallel run equals the sequential one (verdicts, order and `k/n`), and `DSHARP_MUTANT=drop` proves that check can fail.

Not included, each its own change: memoization / skip-unchanged (a stale cache is a false GREEN), parallelising `enforcement.sh`, and any toolchain-specific tuning.

## 1.9.3 — 2026-09-20

**Signing is dialog-first in the docs — no terminal, no local pull on Remote/web.**

Two paths mint the same one-shot token: approving the `HUMAN SIGNATURE NEEDED` dialog (T30) and `bash tests/sign.sh` (T33). The docs led with the script, so people driving BDD from Claude Code Remote or the web — where the human has no terminal — concluded they had to clone the repo locally, run the script, and repush. Approve-to-sign already works on those clients; the round trip bought nothing.

- **The permission dialog is the headline signing path everywhere.** `envelope.md`, `hop-state.md`, `README.md`, `USAGE.md` and `INTEGRATION.md` now lead with the dialog and state plainly that it works from any Claude Code client — Claude Code Remote and the web included — with no terminal and no need to pull the repo to a local machine.

- **`bash tests/sign.sh` stays, labelled as the fallback** for a plain git client or a non–Claude-Code agent. Nothing about signing security changed: the script is untouched and `bash_guard` still denies the agent from running it. `tests/ac/t55_sign_ux_docs.sh` is the red twin — it asserts the fallback and its guard survive, so a future edit that guts them turns red.

## 1.9.2 — 2026-09-12

**A hop edge no longer reprints I1–I18.**

The edge block was ~1.2 KB of pipeline rules — byte-identical in every repo that installs this pack — repeated at the end of every hop, where it buried the two things that were actually specific to that hop: the evidence and the edge line. The reprint was also redundant: `preserve.py` already carries I1–I18 and re-injects them on compact/clear/resume, which is the case the reprint existed for, and `seam.py` carries the hop context on every prompt. Nothing enforced the reprint either — `stop_guard.py` checks only for an edge line.

- **Edges end with the evidence, the D# status, and one `STITCH NEEDED:` line.** The full invariant block is reserved for immediately after `/compact`, `/clear`, `/resume`, `/rewind` or a model change, where reprinting is a live check that preservation actually worked.

- **What is worth stating at an edge is the product's own law.** I1–I18 are how the *pipeline* runs; `D#` in `envelope.md` are the *product's* physics, and only those change per repo. `NO LAW IN FORCE` is a complete and honest answer when it is true.

## 1.9.1 — 2026-09-12

**The pack could delete its own Layer 2.**

`install.sh` decided "am I installing into myself?" with `[[ "$DST" == "$SRC" ]]` — a path comparison. A linked worktree of the pack has its own working-tree path and the same common git dir, so when `~/.config/bdd/pack` pointed at a worktree, `bdd install .` read the pack's own repo as a *product*, took the plugin-mode branch, and deleted every `.claude/hooks/*.py` out of the source they are packaged from. Every later plugin install would have shipped no Layer 2, standalone installs would have had nothing to copy, and approve-to-sign — the signature path that needs no terminal — would be dead in every clone.

- **The guard compares repositories now**, via `git rev-parse --path-format=absolute --git-common-dir` on both sides, falling back to the path when that fails. Same repo, different working tree, is no longer mistaken for a different repo.

- **`T54` locks it in**: build a pack fixture, add a linked worktree, install *from the worktree into the pack*, and assert `.claude/hooks/*.py` survives. `T54_MUTANT=pathonly` reproduces the old behaviour and turns it red.

## 1.9.0 — 2026-09-12

**`bdd disable` — stand the pipeline down without standing the bar down.**

Debugging something unrelated inside a BDD repo meant two hand edits with no memory of what they replaced: `git config --unset core.hooksPath`, and stripping the `hooks` key out of `.claude/settings.json`. The restore was a guess — `git config core.hooksPath .githooks` re-asserts the pack default and silently discards whatever the repo actually had — and a half-restored repo reported as `UNWIRED`, which reads like damage rather than like a switch someone left flipped.

- **`bdd disable [repo]` / `bdd enable [repo]`.** Disable stands down Layer 1 and Layer 2, saving the prior `core.hooksPath` and the verbatim `hooks` block under `.cascade/disabled/`. Enable restores those bytes — not the pack's idea of them — so a non-default `hooksPath` survives and a product's own keys beside `hooks` are never eaten. A repo that had no `hooksPath` comes back with none.

- **Layer 0 is never touched, and that is the whole safety argument.** The CI workflow is byte-identical across a disable and the merge gate still refuses, so work done while disabled cannot merge. `T53` proves it and `T53_MUTANT=layer0` turns it red — a disable that could reach Layer 0 would be a merge bypass with a friendly name.

- **A forgotten disable cannot look like a green pipeline.** `bdd status`, `tests/doctor.sh`, `install.sh --check` and the session seam all lead with `BDD DISABLED`; doctor reports the stood-down layers as skipped rather than RED, so a deliberate switch never reads as a fault. `install.sh --check` reports `DISABLED` (exit 0), distinct from `DRIFT` and `UNWIRED`.

- **It stays local.** `.cascade/disabled/` is gitignored, so the marker never travels — which is also what makes the protection work: any clone carrying a stripped `.claude/settings.json` fails `install.sh --check` with `UNWIRED`, and CI runs it. Enforcement could not sit in pre-commit, because disable unsets `core.hooksPath` and no git hook runs while disabled (I18: the lowest layer that *can* enforce).

## 1.8.1 — 2026-09-10

**`/doctor` — is the pipeline working, or merely installed?**

`bdd check` answers one question well: do the shipped files still match the pack — version, per-file SHA, nothing gitignored, hooks named in `settings.json`. That is the pack's *files*. A fresh clone passes every byte of it with a dead Layer 1, because `core.hooksPath` is git config and does not travel with the tree. Nothing asked whether the layers were live.

- **`bash tests/doctor.sh`, reachable as `/doctor` or `bdd doctor`.** It walks I18's layer order — Layer 0 CI, Layer 1 `core.hooksPath` and the git hooks, Layer 2 agent hooks, pack integrity, laws, hop state, the manifests, the farm — and prints one line per check plus `DOCTOR k/n`. `DOCTOR_FAST=1` defers the farm.

- **It composes; it never re-derives.** `install.sh --check`, `dsharp_strength.sh`, `reads_manifest.sh`, `stage_templates.sh` and `barbar.sh` own their verdicts and doctor quotes them. A doctor that re-scores something eventually disagrees with the merge gate, and the disagreeing number is the one people would act on.

- **Three new checks, three red twins.** `core.hooksPath` (the one that survives a clone badly and was invisible to every existing check), a CI workflow that actually runs the farm, and hop-state coherence — an open hop naming a slice whose spec does not exist, or an `AUTOPILOT:` entry nobody briefed. `DOCTOR_MUTANT=hookspath|layer0|hopstate` breaks each and the run must go red; a check without a twin is not in force. `T52`.

- **A skip is never a pass.** `k` counts green, `n` counts checks that *ran*; a check that cannot run here prints `skipped` with its reason and is excluded from `n`, so nothing can inflate the score. Branch protection is always skipped — it is a GitHub setting doctor cannot read from the tree, and a false green on the strongest control would be worse than no line at all.

- **A degraded repo is diagnosed, not crashed on.** Doctor runs *because* something may be wrong, so a missing manifest is a finding and the run continues. Three defects surfaced this way during the build itself: a linked worktree's absolute `hooksPath` read as red though it was healthy; the pack's own checkout, which has no manifest and never will, read as a broken install; and the drift check printing `RED` with an *empty reason* in a product, where `install.sh` is pack-owned and absent — it now resolves the checker through the manifest's `plugin_root`, and never reports a red without something actionable behind it.

## 1.8.0 — 2026-09-10

**The pack stopped charging every hop for the eleven stages it is not running.**

Nothing said what a stage *consumes*. The generates/executes table said what each stage produces, so the safe reading was to carry every accepted artifact into every hop, and per-hop context grew with the pile rather than with the work — a stage 08 hop dragging 01's problem statement alongside the 05 design it actually needs. The twelve stage templates had the same shape: 31 KB in one file, of which a hop uses one. Two slices, each with a validator and a red twin, because a budget written in prose is a claim nothing checks.

- **A `reads:` manifest, one line per stage.** `product-e2e-gre-pipeline.md` now says what each stage reads, and both hop output shapes cite it. Two rules govern it: `envelope.md` and `hop-state.md` are read on every hop regardless (~2.5 KB, and the D# laws bind every stage), and a stage may only name stages that precede it — a forward reference is a cycle, not a budget, because that artifact does not exist when the hop runs. `tests/reads_manifest.sh` checks every row is present, well-formed and free of forward references; `READS_MUTANT=1` injects one and must fail. The manifest is a budget, not a gate: nothing at hop time stops a hop reading more than its row, and saying otherwise would be theater.

- **One stage, one file — for the nine templates that can move.** `docs/cascade/stages/` holds them; `product-e2e-cascade.md` keeps a dispatch index and drops from 31 KB to 18.5 KB. Content moved verbatim, 432 lines out and 432 in, so `git log -M` still follows it.

- **Three templates stay in the pack, and that is a rule rather than an exception.** 00, 03 and 10 carry `<EDIT>` blocks. Relocating human-authored lines reads to `pre-commit` as an edit — correctly, since it cannot tell a move from a rewrite — so those three keep their sections in the pack. `tests/stage_templates.sh` checks the correspondence both ways: a split-out file that carries `<EDIT>` fails, and a stage kept back without `<EDIT>` fails too. An exception list would need hand-checking forever, which is how an index starts lying.

- **The parent did not reach the 4 KB the brief asked for, deliberately.** `tests/control-line.sh` asserts `Rule (I15)`, `Rule (I16)`, `Rule (I18)` and `conductor eval fails if it does` in that file, and `tests/i17_dune.sh` asserts `Rule (I17)`. Hitting a size number by relocating the strings an enforcement layer greps for is exactly I18's failure mode. The header stays.

- **`T14`'s hermetic fixture keeps the pack's new directory.** It strips the fixture to the pack's conductor docs and its allow-list predated `stages/`, so it deleted the templates and left the index dangling — the farm went red inside a READY product. One term wider; what T14 asserts is unchanged.

- **The gap this found in the signing path.** `sign_ok.py` mints a signature from an approved `Write`/`Edit` dialog, so the picker covers a human-owned edit made with those tools. An edit made by a script through Bash fires no `PostToolUse` hook, so no dialog is offered and the human first learns of it when the commit fails and tells them to run `tests/sign.sh`. Both paths work; only one is discoverable.

## 1.7.1 — 2026-09-09

**An adversarial pass over 1.7.0's own signing fix — two ways back to the ledger.**

1.7.0 sealed the signature ledger and called it the thing worse than the other six defects. Re-auditing that fix found the seal had two gaps, each of which restored the original hole in full: minting a signature without a human. Both were reproduced end to end before being fixed, and neither was visible to the suite — every test around them stayed green.

- **Fix (security): the seal did not cover a worktree.** `hop_guard` returned early on any path outside the repo root, *before* reaching the seal — and in a linked worktree `$GIT_DIR` is `<main>/.git/worktrees/<name>`, which is outside that root. So from a worktree the agent could write `<sha> docs/cascade/hop-state.md` into the ledger exactly as before 1.7.0, and `pre-commit` honoured it: verified by flipping `CURRENT_HOP` and watching the commit land with `cascade: human signature accepted` and no human anywhere. `T46` went on passing throughout because it only ever builds a plain repo, where `.git` is a directory under the root — the `T45` blind spot again, one layer up. The seal now runs before the outside-the-root return, which stays, just below it. `T50`.

- **Fix (security): one pair of quotes turned off the shell guard.** `bash_guard` ran every check over `strip_quoted()` text, so that a commit message naming a guarded command reads as prose rather than tripping the guard (the `T15` class). But blanking a quoted span blanks quoted *arguments* too, and an argument in quotes is still that argument. `printf x > ".git/cascade-human-ok"`, `cp /tmp/tok '.git/…'`, `bash "tests/sign.sh"` and `git push origin "main"` were all allowed — as was `git commit "--no-verify"`, which does not route around one guard but removes Layer 1 entirely. Path and flag checks now read the command with its quote characters removed rather than its quoted spans blanked, dropping `-m`/`--message` values first so the prose cases 1.7.0 fought for stay allowed; `echo` and `printf` joined the read-only list so naming the ledger in an `echo` is still prose, while `echo x > ledger` is still a write. `T51`.

- **Fix: the fast gate blocked every push after a branch's first.** Scoping the fast lint to changed files assigned `files=("${changed[@]}")`, and expanding an empty array under `set -u` is an error in bash 3.2 — the dialect `lint.sh` exists to police. Whenever a branch sat level with its upstream, and so on every tag push, lint died with `changed[@]: unbound variable`, the gate read that as a red farm, and `pre-push` refused. A bar that blocks correct work is one people learn to pass with `--no-verify`. Found by this release's own tag push being refused. `T48` now runs the fast lint against a repo with an empty change set and fails on the crash.

- **The limit, said out loud.** `bash_guard` reads command *strings*, so indirection still evades it — a variable (`F=…; printf x > $F`) or a script file. That was true before this release and is true after; the fix closes a deterministic one-keystroke bypass, not the category. The load-bearing defences are `hop_guard`'s seal on tool writes and Layer 0 — protected `main` plus CI — and a `--no-verify` commit still cannot reach `main` past a required check. Claiming the shell guard is complete would be the theater the pack forbids.

## 1.7.0 — 2026-09-09

**An audit of the pack, and the hole it found in the signing system.**

An end-to-end review turned up six defects, three of them introduced in the previous day's releases. Then an adversarial pass over the signing system found something worse than all six.

- **Fix (security): the signature ledger was writable by the agent.** Every defence around a signature guarded the *shell* — `bash_guard` denies `CASCADE_HUMAN=` and denies running `tests/sign.sh`. None of them sees a file write. On an `EXECUTE` hop the agent could write `<sha256> docs/cascade/envelope.md` straight into `$GIT_DIR/cascade-human-ok` with the Write tool, and `pre-commit` would honour it as the human's signature — approve-to-sign, the whole point of the pack, routed around in one call. Verified live before the fix. The git dir is now sealed against the agent on every hop: ledger, pending list, hooks and refs. Ordinary product writes are untouched. `T46`.

- **Fix: a Layer 1 guard was failing open.** `echo "$staged" | grep -qx` under `set -o pipefail` returns 141 once `grep` exits at the first match and the writer takes SIGPIPE — so on a commit with a large enough staged list, the human-ownership check on the envelope **did not run at all**. Reproduced: a commit flipping `CURRENT_HOP` walked straight through. All three pipelines into `grep -q` are gone, and scratch files clean up from an `EXIT` trap so a failing `rm` can never abort a commit whose checks passed (the T45 class). `T47`.

- **The push gate is fast again.** Sealing and testing cost time: the meta-suite went 255s → 420s, taking a push to seven minutes. A gate that slow is one people bypass with `--no-verify`, and a bar routed around protects nothing. `pre-push` now runs a 7s gate that defers only the pack's own meta-suite to CI, labels its score `(fast: … not a full farm)`, and keeps lint, the hop scorer and the merge fixtures local. `barbar merge` unsets fast mode and CI never sets it. `T48`.

- **One home for the hook helpers.** Five copies of "where does hop state live", four of the logger, three of the dedupe, two crash wrappers — the same defect consolidated in 1.2.2 (six law parsers, until a placeholder counted as a law), reintroduced by hand in the same session that shipped the fix. `seam.py` carried the proof it was copy-paste: `if "seam.py" == "preserve.py"`, a comparison that is always false, inside a dedupe key. `.claude/hooks/_common.py` is now the single definition, and all six hooks fail safely in the way their event requires — a crashing PreToolUse guard asks rather than letting the call through, and `sign_ok` says so loudly, because a silent failure there looks exactly like a signature that did not work. `T49`.

- **`bash_guard` stopped denying reads.** It matched the ledger's filename anywhere in a command, so `ls`, `cat` and even a `grep` for the name were refused — three false positives in one session. A guard that fires on harmless things is one people learn to route around. Writes are still denied, and the Write/Edit path is sealed by `T46`.

- **The punch-round cap is real.** "At most **3** punch rounds" was prose, asserted by grepping the command file for literal markdown — reformatting broke the test, ignoring the instruction did not. Four DIRTY stage-10 rounds on one slice are now refused with the remaining rows named; a CLEAN audit resets the count. An agent grinding at DIRTY rows all night looks like progress every round.

- **A push takes about 5 seconds.** The fast gate was 7s, six of them static analysis over every shell script in the pack. In fast mode it now checks only what the push actually changes — anything you are not pushing was checked when it was — while CI, `barbar merge` and a plain `bash tests/lint.sh` still cover everything. `T48` asserts the scoped version still catches a broken script. What remains is git and the network, which no hook can help with.

- **The meta-suite runs in 113s instead of 470s**, with nothing dropped. Three tests ran a full farm — which runs `enforcement.sh` — *inside* a test of `enforcement.sh`, about 70s each, to assert something the outer run was already proving; they use the fast gate now. And `T32` nested the entire suite inside itself (208s) to prove that an inherited `GIT_DIR` never reaches a throwaway repo.

- **Fix: `T32` could not fail on this machine, and never could.** It corrupted a victim repo through an inherited `GIT_DIR` and asserted the corruption did not happen — but modern git ignores `GIT_DIR` for `init`, so the assertion passed whether or not the scripts unset anything. The suite printed the reason as a footnote on every run: *"this git does not redirect init/symbolic-ref via GIT_DIR"*. It now puts a `git` shim on `PATH` and observes the environment the scripts actually hand to git, which fails for the right reason and names the leaked path.

- **Tests that asserted wording now assert behavior.** `i17_dune.sh` — the suite certifying this pack's public claims — was 0% behavioral: `T4` grepped `barbar.sh` for the string `exit 1` rather than running the farm, and `T5`/`T6`/`T7` asserted fixture files existed without ever scoring them. Five of the eight now run something; `T0`/`T1`/`T3` stay presence checks on purpose and are labelled as such. In `enforcement.sh`, the skill-binding and send-back greps became behavioral, two redundant ones were deleted, and `T43`'s eleven assertions about conversational conduct — which no script can observe — became two scored eval fixtures plus the checks that are genuinely mechanical.

## 1.6.0 — 2026-09-09

**Hop state moves out of the envelope.**

The envelope held two things with completely different lifetimes: hop state, which turns over three or four times per slice, and your laws, which change maybe twice a year. Sharing a file meant `git log docs/cascade/envelope.md` buried "we added D3" under fifty "moved to EXECUTE" — the most valuable record BDD produces, and the hardest to read.

- **`docs/cascade/hop-state.md`** now holds `CURRENT_HOP` / `CURRENT_STAGE` / `CURRENT_SLICE` and the `AUTOPILOT:` list. `envelope.md` keeps the laws, the locked decisions and the accepted artifacts. Both are human-owned; both are protected at Layer 1 and Layer 2 exactly as before — an agent flipping the hop in the new file is refused by `pre-commit` the same way, and `T44` fails if that guard is removed.

- **Nothing breaks in an existing repo.** Every reader — six scripts, five hooks, `pre-commit` — resolves hop state to `hop-state.md` when it exists and falls back to `envelope.md` when it does not. A repo installed before the split keeps working untouched, and `install.sh` deliberately **does not** create the new file where the envelope still carries `CURRENT_HOP`: doing so would silently reset a running hop to `NONE`. It prints how to split by hand, between hops, when you want to.

- To split an existing repo: move the four lines into `docs/cascade/hop-state.md` while no hop is open, and sign that commit with `bash tests/sign.sh`. Splitting the pack's own envelope needed exactly that signature — the guard refused the agent, correctly, and `T44` now proves it refuses in the new file too.

- **Fix: the git hooks broke inside a worktree.** `pre-commit` wrote its scratch file to `$ROOT/.git/…`, which is a *file* in a worktree, so every protected-line check errored with `Not a directory` before reporting. It already resolved the real git dir two lines above and simply wasn't using it. `T45`, found by this release's own commit being refused from a worktree.

## 1.5.1 — 2026-09-08

**Two more places that made you type instead of choose.**

- **`/barbar init` walks the laws one at a time.** It used to end with "copy the ones you accept into the envelope" — a block of six proposals to hand-sort, which is how a law nobody read ends up halting a run at 3am. Each candidate is now its own question: *sign it*, *sign it and build the test*, or *skip*, with the option text saying what the `check` will run and what the `break` will disable. Signing goes through the dialog as always. It closes by reporting `dsharp_strength.sh`, so you see what is actually in force rather than what you meant to sign. This is the path from `DSHARP 0/0` to a real floor, and it is now a few clicks.

- **The accept edge offers the verdict.** *Accept*, *send back* with a one-line reason, or *show me the diff first* — instead of a line of prose you answer by typing. Silence is never read as acceptance.

- **A send-back now leaves a trace, which changes I11's status.** It was the one invariant with nothing at all behind it: a send-back happened in chat, and nothing downstream knew a hop had been rejected. The reason is now written into the slice's brief and recorded in `.cascade/decisions.log`, and the fix is told to start from a clean tree rather than stack patches. Still not *enforced* — no hook can see whether you actually rewound — but it is observable, and the loop receipt (I10) already stops stacked work from reusing the old evidence. `CONTROL-LINE.md` records the new status honestly rather than upgrading it to green.

## 1.5.0 — 2026-09-08

**A halt that could have been a click.**

`/barbar auto` with an unsigned list used to print a procedure — a four-line `sed`, a commit with the stitch key, a slice name to retype that the agent already knew — for something that is not a procedure at all. It is a *decision*: which slice to build next. The agent was handing the human homework instead of asking a question.

- **The unsigned-list path now asks.** In an interactive session, `/barbar auto` reads `docs/cascade/05b-briefs.md`, offers the slices that have no work yet as options in the permission UI's own picker, and — once you choose — makes the envelope edit itself so the approval dialog carries your signature. No `sed`, no `CASCADE_HUMAN=1`, no retyping. If the current hop is a CLEAN stage 10 it says so in the question: the choice is "what next", not "something is broken".

- **Halts in general prefer a question.** When the blocker is a decision a human must make — which slice, which reading of an ambiguous brief, whether to drop an out-of-scope row — and someone is at the keyboard, the agent asks and carries on. A halt is for things a human must go and *do*. Halts that remain keep the five-field block, with `WHAT TO DO` held to the shortest real path.

- **Headless is unchanged.** With nobody at the keyboard there is nobody to ask, so an unattended run still halts with the two lines named. `T43` pins both directions.

## 1.4.2 — 2026-09-08

- **Fix: 1.4.0's I10 gate blocked stage 10.** The new "no accept without evidence" check demanded a `tests/loop.sh` receipt from *every* EXECUTE hop — but stage 10 is judged by `tests/audit.sh`, as `autopilot.py` already knew. A finished audit hop was refused for lacking evidence that stage does not produce. The check now asks each stage for its own review command, and the refusal names the right one. Found in a real repo within an hour of shipping 1.4.0.

- **Fix: running the farm dirtied the repo.** The 1.3.0 decision log wrote into two eval fixtures whose `.cascade/` was tracked, so every `tests/barbar.sh` left modified files behind — and a `git add -A` release commit swept them in. They are untracked and ignored now.

- **Fix: plugin-mode `install.sh` deleted the pack's own Layer 2.** Run inside the pack repo, it removed `.claude/hooks/*.py` and the skill source — correct in a product, where the plugin supplies them, and destructive here, where those files *are* what gets packaged. Every later release would have shipped a plugin with no `hop_guard`, no `stop_guard`, no signing dialog; standalone installs would have had nothing to copy; and the pack could no longer test itself. It now refuses when the target is the source, and still strips them in a real product. `T42`, with the destructive commit reverted before it reached any remote.

## 1.4.1 — 2026-09-08

**A number in prose is a claim, and nothing was checking it.**

- **README caught up with five releases.** It still described autopilot before the halt block, the run log and the budget existed, and pointed at "tests T1–T36" when the suite was at T41. It now covers the loop receipt (an agent cannot ask you to accept a hop it never ran), `.cascade/decisions.log`, `BDD_AUTOPILOT_MINUTES`, and links the invariant coverage map.

- **Fix: 1.4.0's invariant coverage map never landed.** The edit was anchored on a T-range that had already moved, so the replace was a silent no-op — the map and the `T41` row were reported as written and were not there. Both are in now, and the edit that added them asserts its anchor instead of trusting it.

- **`lint.sh` now fails on a stale test-range claim.** Every `T8–Tn` written in `README.md`, `CONTROL-LINE.md` or `AUDIT.md` must end at the suite's real last test, and `CONTROL-LINE.md` must carry a row for it. This is the same defect class as a stale shipped file (`T38`): documentation that reads as true. `T1–T7` is left alone — that is the separate I17 suite and is correct as written.

## 1.4.0 — 2026-09-08

**Counting the pack's own invariants, and closing the one that mattered.**

BDD declares 18 invariants (I1–I18). Fifteen were enforced by a hook, a script or a gate. Three — I10, I11, I12 — appeared in no enforcement code at all: they were prose asking the agent to behave, which is the exact thing this pack exists to replace.

- **I10 is now mechanical.** *"Execute may not ask for accept without the review command for that hop."* `autopilot.py` gated the *advance* on `tests/loop.sh`, but an interactive hop could print `STITCH NEEDED: accept execute for stage 05b` having never run it — and the human was asked to accept work with no evidence behind it. `loop.sh` now writes a receipt when it reaches n/n, naming the hop and fingerprinting the working tree; the Stop hook refuses the accept edge unless a receipt matches **this hop and this code**. A missing receipt, a receipt from another stage, or any edit made after the loop passed all fail, with the command that produces the evidence named in the refusal. A failing loop deletes the receipt. `T41`, mutation-checked.

- **I11 and I12 are documented as unenforced, with the reason.** I11 (send-back → rewind, don't stack fixes on a dirty tree) has no machine signal: a send-back happens in chat, so a hook cannot see one. I12 is half-covered — hop state, locks and plan are protected lines already, but a tangent editing a legitimately-writable file is indistinguishable from the hop's own work. Claiming otherwise would be the theater the pack forbids.

- **`CONTROL-LINE.md` gains an invariant coverage map** — every I# against the layer that enforces it and the T# that proves it, including the two entries that say "nothing" out loud.

## 1.3.1 — 2026-09-08

- **Fix: explaining a halt triggered one.** The Stop hook matched `AUTOPILOT HALT` anywhere in a reply, so documenting the halt format — in a code fence, in a changelog entry, in an answer to "what does a halt look like" — stopped a session that had no hop running and demanded an instruction block for a halt nobody issued. It happened while writing the 1.3.0 release notes. Code fences and inline code spans are now read as quotation; a halt anywhere else on a line still counts, including appended to an edge line. Same bug class as `T15`, where a commit message naming a guarded command was parsed as the command. Covered by four cases in `T40`.

## 1.3.0 — 2026-09-08

**The morning after an unattended run.**

Three ideas taken from [IronCurtain](https://github.com/provos/ironcurtain), which sandboxes untrusted agents at runtime. Its threat model is not this pack's — it distrusts the agent, BDD distrusts the code — but three of its mechanisms transfer cleanly.

- **A run log.** Git records what succeeded. It does not record what was denied, what you signed, which law went red at 3am, or why autopilot stopped — that lived in terminal scrollback and then it was gone. Every layer now appends one line to `.cascade/decisions.log`:

  ```
  2026-09-08T03:14:22Z  hop_guard   DENY    src/Ledger.kt — product path on a GENERATE hop (stage 05b)
  2026-09-08T03:19:08Z  sign_ok     SIGNED  docs/cascade/envelope.md sha=4f2a… — approved in the permission dialog
  2026-09-08T03:22:10Z  dsharp      THEATER D3 refund is idempotent — break passed, so the check cannot fail
  2026-09-08T03:22:11Z  stop_guard  HALT    AUTOPILOT HALT: D3 is THEATER
  ```

  Read it with `python3 tests/lib/decisions.py . --tail 40`; the last dozen lines are also injected at session start. It is a record, never a gate — **no verdict depends on it**, and `T40` asserts that deleting it changes nothing. It is gitignored on install, and `.cascade/` is no longer a product path, so a run can never dirty the tree it is auditing.

- **A law is checked the moment it is signed.** Approving a law in the dialog used to prove nothing: it could sit UNPROVEN or THEATER until the next `/barbar auto` halted on it. Signing the envelope now runs `dsharp_strength.sh` immediately and says `DSHARP 2/3 — signed, but not yet protecting you`, naming which law and why. Their pipeline verifies a policy before deployment; this is the same discipline, one layer up.

- **A wall-clock budget.** The hop cap (`4 × slices + 4`) counts continuations, which is a poor proxy for cost — a slice stuck on a build error can burn a night inside it. `BDD_AUTOPILOT_MINUTES=90 /barbar auto` stops at 90 minutes with committed work intact and the reason logged. Unset means no ceiling, as before.

Not taken: the sandbox and the MITM proxy. They are the right answer to their threat model, but absorbing them would make BDD a runtime with a container and a proxy to maintain. Its durability comes from being plain bash and git files with no service to keep alive. Run IronCurtain *around* BDD rather than rebuilding it inside.

## 1.2.4 — 2026-09-08

**A second machine ran with no commit gates and nothing said so.**

- **`core.hooksPath` is git config, not a file, so it never travels with the repo.** Clone a cascade repo onto another machine and `.githooks/` is right there on disk with git not calling it: no commit gate, no push gate, no error, nothing visibly different from a working repo. Session start now says `LAYER 1 IS OFF` with the one-line fix, and goes quiet once the clone is wired. `T39`.

- **Fix: friendly-format laws were invisible at session start.** `preserve.py` kept its own pipe-format parser through 1.2.2, so a repo using the `### D1` / `check:` / `break:` form began every resumed session with `Domain laws: (none declared)` — the agent starting blind to laws that were in force. It reads through `tests/lib/laws.py` now, and `hop_guard.py` takes its protected-line pattern from there too. The 1.2.2 note claiming every parser was consolidated was wrong; these two were left behind.

- **The re-injected control line stops demanding a hop edge on every reply**, matching the `AGENTS.md` fix in 1.2.2. It was the reason the ritual kept reappearing over plain questions even after the prose was corrected.

- **`/barbar init` is explicitly safe to re-run** — second machine, second pass months later. It writes one file and overwrites it, never the envelope, and now skips laws already in force instead of re-proposing them.

- **README: a mermaid diagram of who does what.** Three amber boxes are the human — approve the edge, clear a halt, sign READY — and everything else is the pack. Plus what to do on a fresh clone.

## 1.2.3 — 2026-09-08

**The plugin was shipping a stale `/barbar`.**

- **Fix: plugin-mode `/barbar auto` had been running a four-release-old command.** `commands/` and `skills/` were symlinks into `.claude/` until 1.1.1, when the plugin loader turned out not to follow links; the real files that replaced them then froze. `commands/barbar.md` fell 27 lines behind, so a plugin-mode autopilot run had **no stage-10 adversarial auditor**, no "never ask and wait" rule, and no mandatory HALT instruction block — silently, since the file still worked. It is synced, and `T38` now asserts every shipped file is a real file and byte-identical to the `.claude/` copy the repo runs.

- **`/barbar init` proposes laws in the current format.** It was still emitting `D1 | law | check | break` pipe rows, and telling humans to sign with `CASCADE_HUMAN=1` as though the approval dialog did not exist. Proposals now come as `### D1` / `check:` / `break:` blocks with a `why:` line naming the commit or code path behind each one, and the checklist leads with the dialog — approving the agent's edit *is* the signature — with `bash tests/sign.sh` and the env var as the hand-edit paths.

- **`T33` exists.** It had a changelog entry and a `CONTROL-LINE` claim since 1.1.x but no test: nothing asserted that a hand-edited file can be signed from a GUI git client, that the refusal names the signing command, that the token is one-shot, or that the agent is denied running it. All four are now checked.

## 1.2.2 — 2026-09-07

**Laws you can read, and an ending that only fires when a hop ends.**

- **A domain law is now three plain lines instead of one long pipe row.** A heading you can read, a command that must pass, a command that must fail:

  ```
  ### D1 — a user's balance MUST NOT go negative
  check:  pytest tests/inv/test_D1.py
  break:  INV_MUTANT=D1 pytest tests/inv/test_D1.py
  ```

  The old `D1 | law | check | break` form still parses, so repos already using it keep working with no edit. Both go through one reader, `tests/lib/laws.py` — previously six files each had their own regex for law syntax, which is how a placeholder line once slipped through as a real law and halted autopilot. `envelope.md` also drops its implementation notes (they moved to `USAGE.md`) for a table of the four states a law can be in — GREEN, RED, THEATER, UNPROVEN — and what to do about each.

- **Fix: the agent printed a hop-edge line over questions.** `AGENTS.md` asked for `STITCH NEEDED: … for stage N` at the end of *every* reply, so plain answers ended by closing a hop that was never open, with the literal letter `N` where a stage should be. The Stop hook always drew the right boundary — silent unless the envelope says a hop is running — and the prose now agrees with it: the ritual belongs to hop replies, and idle replies end normally. `T37` asserts both layers, so they cannot drift apart again.

- **Fix: `docs/cascade/skill-binding.md` went stale on upgrade** and turned the farm red, which blocked pushes until it was hand-edited. The installer now replaces it as a pack-owned file instead of preserving your copy.

- `CONTROL-LINE.md` gains the missing `T34`–`T36` rows alongside the new `T37`.

## 1.2.1 — 2026-09-07

- **Fix: CI failed on a plugin-mode repo.** Layer 2 (agent hooks, commands, skill) lives in the plugin, so a runner that has no plugin has nothing to test — but the tests treated absent as broken and failed `T1` and every hook test. They now skip with a reason naming the CI runner, while Layers 0 and 1 stay fully enforced. Where Layer 2 *is* installed — your machine, or any standalone install, including in CI — nothing skips and coverage is unchanged.

## 1.2.0 — 2026-09-06

**The audit joins autopilot, judged by someone who did not write the code.**

- `AUTOPILOT: 05b a, 05b b, 10 audit` — stage 10 can be signed onto the list. Its GENERATE hop dispatches an *independent* reviewer (a fresh subagent, briefed to be hostile to narrative: "if you did not open the file, it is not IMPLEMENTED") to find each FR/NFR/D#'s artifact and test; the rows go in unchanged and `tests/audit.sh` decides. Its EXECUTE hop punches DIRTY rows — real fixes only, never by editing a row or deleting a test — up to three rounds, then halts.
- **Stage 11 and merge can never be signed.** `autopilot.py` rejects a list containing them: READY is the human's signature, merge is the human's act.
- A signed initiative now costs two signatures — the list and READY — instead of two per slice (T36).

## 1.1.5 — 2026-09-06

- **Fix: a plugin-mode repo could never reach `BARBAR n/n`.** The farm's tests looked for the hooks, commands and skill inside the repo, but plugin mode keeps Layer 2 in the plugin — so `/barbar merge` was unreachable in exactly the setup the docs recommend. `install.sh` records `plugin_root` in the manifest and the tests resolve Layer 2 from it (T35).
- **Fix: a product's own `AGENTS.md` never received the cascade rules.** The installer kept an existing file, so the agent read the product's rules and not the hop law. The rules are now appended below whatever is already there (T35).
- **Version drift is announced** at session start with the exact refresh command, and `install.sh --check` names it (T34, 1.1.4).

## 1.1.4 — 2026-09-06

- **Version drift is announced.** A plugin update refreshes only the machine-wide half; a repo's `tests/`, `.githooks/` and commands come from `install.sh`. When they diverge, the session-start hook now says so and prints the exact refresh command, and `install.sh --check .` names it too. Three separate "the fix didn't work" reports traced to this (T34).

## 1.1.3 — 2026-09-06

- **Every halt is actionable.** A halt must carry `BOTTLENECK` / `WHAT TO DO` (copy-pasteable) / `IF YOU DISAGREE` / `RESUME WITH` / `DONE SO FAR`. The Stop hook sends back a halt lacking that block, so a run never ends with a reason you cannot act on (T28).
- **The loop's refusal explains itself.** An undecided law names the envelope line, the two commands to write, the signing command and the waiver alternative. A law whose commands are already named is ordinary hop work — the loop runs it and the agent writes the test (T18).

## 1.1.2 — 2026-09-06

- **Fix: a human editing by hand could not commit from an IDE.** The only signature was an environment variable, which a GUI git client cannot pass, so a hand-edited envelope was blocked in a loop. A signing command now mints the same one-shot token for the human-owned files you changed; commit from any client afterwards. The agent is denied running it (reading and linting stay allowed) and the block messages name it (T33).
- **Fix: quoted text is never a command.** A multi-line commit message mentioning a guarded command tripped the ship guard; quoted spans are blanked before command-position matching (T15).

## 1.1.1 — 2026-09-05

- **Fix: `/barbar` was unknown in plugin-mode repos.** The plugin root shipped `commands/` and `skills/` as symlinks (the loader does not follow them) and plugin-mode install removed the repo's `.claude/commands` — so such a repo had no `/barbar` at all. Both are real directories now, and plugin mode keeps the repo's commands (the plugin's own remain reachable as `/bdd:barbar`). T31 pins both.
- **Note:** `claude plugin update` refreshes only the machine-wide half. Re-run the plugin's `install.sh` in each repo to update its scripts; `install.sh --check .` reports the version mismatch.

## 1.1.0 — 2026-09-05

Seamless delivery and two bugs found by the first real user.

- **Plugin.** `claude plugin install bdd@bdd`; hooks, commands and the skill machine-wide; the agent offers the repo-side install on the first feature prompt (T31).
- **Approve-to-sign.** The permission dialog is the human signature for hop edges, laws, `<EDIT>` content and law tests; one-shot tokens pre-commit accepts once (T30).
- **First-knowledge discovery.** `/barbar init` proposes laws and audit rows; hooks nudge until a law is in force (T29).
- **Fix: a template placeholder is not a law.** Fresh installs shipped an unprovable D1 that halted autopilot at the first EXECUTE (T18).
- **Fix: a hook's GIT_DIR never reaches the farm.** The pre-push farm's throwaway repos inherited GIT_DIR and flipped a real product to `core.bare=true` and re-pointed its worktree HEAD (T32).
- Worktree-safe installer, bytecode never staged, plugin-mode install strips prior project hooks, docs rewritten for three readers.
- Versions: `VERSION`, `plugin.json` and `marketplace.json` are tied by T31 — the plugin updater compares them.

## 1.0.0 — 2026-09-02

First production-oriented release. Every control lives at the lowest layer that can enforce it (I18), and each layer is pinned by a behavioral test (T1–T22).

- **Plugin.** `claude plugin install bdd@bdd`: hooks, commands and the skill machine-wide; the agent offers the repo-side install on the first feature prompt (T31). **Approve-to-sign:** the permission dialog is the human signature for hop edges, laws, `<EDIT>` content and law tests (T30). **First-knowledge discovery:** `/barbar init` proposes laws and audit rows; hooks nudge until a law is in force (T29).
- **Layers.** CI + branch protection; git hooks (`.githooks/`) for any agent; Claude Code hooks (`.claude/hooks/`: hop_guard, bash_guard, stop_guard, preserve, seam); rules (`AGENTS.md` + shims).
- **Commands are scripts.** `tests/loop.sh` (LOOP k/n), `tests/barbar.sh` (BARBAR k/n, merge gate), `tests/dsharp_strength.sh` (DSHARP k/n), `tests/audit.sh` (AUDIT k/n). The agent never types a score.
- **Human-owned lines.** `CURRENT_HOP/STAGE/SLICE` and every D# line are rejected by pre-commit and hop_guard; humans commit hop edges with `CASCADE_HUMAN=1`, which the agent is denied.
- **Red twin.** A D# is in force only with a validator and a command that must fail; THEATER and UNPROVEN refuse merge, UNPROVEN blocks the loop.
- **Stage 10 computed.** `audit.sh` scores rows against the tree; prose verdicts are ignored. Stage 11 READY counts only inside `<EDIT>` (human-signed).