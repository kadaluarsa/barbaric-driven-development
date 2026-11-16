# Archived briefs (t102) — closed slices, verbatim
- stage-reads-manifest: Every hop currently carries context for stages it is not running. A stage 08
  hop re-reads 01's problem statement and 02's JTBD in full, though it needs only the invariants and
  the stage 05 technical design — so per-hop context grows with the accepted-artifact pile rather than
  with the work. Give each stage in `product-e2e-gre-pipeline.md` an explicit `reads:` line naming the
  prior artifacts that stage actually consumes, and teach the GENERATE and EXECUTE hop shapes to load
  exactly that list and nothing else. The 22-hop floor is the method and stays; what goes is each hop
  paying for stages it is not on. Done when every stage 00–11 carries a `reads:` line, the hop shapes
  cite it, and a test asserts no stage's manifest names an artifact from a stage that has not been
  accepted yet.
- t52-environment-independent: `T52` asserts `DOCTOR n/n` in the pack's own checkout, which is a fact
  about the machine running it rather than about the code. CI checks out a fresh clone, `core.hooksPath`
  is unset there — it is git config and does not travel with a tree — so doctor correctly reports Layer 1
  dead, and T52 fails. It passed locally only because this machine had `core.hooksPath` set from an
  earlier install, and it could never have passed in CI. The failure is real but it is the test's, not
  doctor's: a test that depends on ambient configuration asserts nothing about the thing it names, and
  the fix is not to make doctor lenient about a genuinely dead layer. Replace the ambient-health
  assertion with a constructed positive control — a scratch repo with `core.hooksPath` set, where that
  check must be green — keeping every behavioural assertion T52 already makes (the three red twins, a
  skip never counted as green, branch protection never claimed as checked, a bare repo diagnosed rather
  than crashed on, one command file byte-identical in both trees). Done when `bash tests/enforcement.sh`
  passes both with `core.hooksPath` set and with it unset, proving the test no longer reads the
  environment it runs in.
- bdd-doctor: `bdd check` (`install.sh --check`) answers one question — do the shipped files still match
  the pack: version, per-file SHA, nothing gitignored, hooks wired. That is the pack's *files* being
  intact, which is not the same as the pack *working*. Nothing today asks whether the laws are in force,
  whether the hop state is coherent (a hop open on a slice whose spec doc does not exist, an `AUTOPILOT:`
  entry naming a slice nobody briefed), whether `core.hooksPath` actually points at `.githooks`, whether
  Layer 0 exists at all, or whether the farm still runs end to end. A repo can pass `bdd check` with
  every byte correct and still have a dead pipeline. Add `/bdd doctor` — `tests/doctor.sh`, plus a
  `doctor` case in the `bdd` launcher and a command file — that runs the checks in I18's layer order
  (Layer 0 CI, Layer 1 git hooks + `core.hooksPath`, Layer 2 agent hooks, pack integrity via
  `install.sh --check`, laws via `dsharp_strength.sh`, hop-state coherence, the `reads:`/`stages`
  manifests, then the farm) and prints one line per layer plus `DOCTOR k/n`, exiting non-zero unless
  k=n. It composes existing scripts wherever one exists and never re-implements their verdicts; the new
  checking is the hop-state coherence and the Layer 0/`hooksPath` probes. Done when `bash
  tests/doctor.sh` prints `DOCTOR n/n` in this repo, a red twin proves each new check can fail
  (`DOCTOR_MUTANT=<check>` breaks one and the run must go red), `bdd doctor` and the command file reach
  it, and a fresh `install.sh` into a scratch repo yields a tree where doctor runs and names its own
  gaps rather than crashing.
- stage-template-split: `product-e2e-cascade.md` holds all twelve stages' spec templates in one 31 KB
  file, and a hop uses exactly one of them. Split the templates into `docs/cascade/stages/NN-<name>.md`
  and reduce the parent file to a dispatch index that points at the stage in play. Done when the parent
  is under 4 KB, every stage template lives in its own file, and a test asserts the index names every
  file present and no file is orphaned.
- invariant-card: Invariants I1–I18 are the part of `product-e2e-gre-pipeline.md` actually consulted
  mid-hop, but they sit inside a 32 KB document that must be loaded whole to reach them. Extract them
  to a standalone `docs/cascade/invariants.md` card of roughly 1 KB, leave a pointer behind, and have
  the hop shapes cite the card. Done when the card exists, the pipeline doc references rather than
  restates I1–I18, and `tests/loop.sh` reads the card.
  Absorbed by t102-doc-disclosure (2026-11-12).
- t53-bdd-disable: There is no way to stand the pipeline down. Debugging something unrelated inside a
  BDD repo means hand-unsetting `core.hooksPath` and hand-stripping the `hooks` key out of
  `.claude/settings.json`, then remembering to put both back — and a half-restored repo reports as
  `UNWIRED` drift, which reads like damage rather than like a switch someone left flipped. Add
  `bdd disable [repo]` and `bdd enable [repo]`: disable stands down Layer 1 (git hooks) and Layer 2
  (agent hooks), stashing the exact prior state under `.cascade/disabled/` so enable restores it
  byte-for-byte; it never touches Layer 0, so CI stays red and the merge gate still refuses. Every
  status surface — `bdd status`, `bdd doctor`, `install.sh --check`, the `seam.py` prompt banner —
  leads with `BDD DISABLED` so a forgotten disable cannot masquerade as a green pipeline. Done when
  disable/enable round-trip `core.hooksPath` and `.claude/settings.json` exactly, `.cascade/disabled/`
  is gitignored so a disable can never be committed, `install.sh --check` distinguishes DISABLED from
  DRIFT, and a red twin proves Layer 0 survives: with the repo disabled, the CI workflow is unchanged
  and `bash tests/barbar.sh merge` still REFUSES.
- t57-spec-critic: The human is the only critic of a spec+plan before it is built, and a human who lacks
  the expertise misses exactly the gaps that matter; the first independent reviewer (the stage-10
  auditor) arrives after the code exists, when a gap costs a rebuild instead of an edit. On every
  GENERATE hop of 05 / 05b, after the spec+plan are drafted, dispatch a fresh subagent with no memory of
  writing them. It first challenges the **brief** (is this the right problem; does it conflict with the
  envelope), then the spec+plan, and writes `docs/cascade/<stage>-<slice>-critique.md`: at most 10 rows,
  severity-ranked, `| C# | severity | finding | evidence | DISPOSITION |`, kept verbatim. Evidence is a
  runnable command or a quoted `path:` line; a row with neither is marked `UNEVIDENCED` so the human sees
  which findings rest on the critic's word. The author fills every DISPOSITION: `fixed <where>`,
  `rejected <reason>`, or `human <question>` (raised at the edge). Every spec also carries a
  `## Before vs after` section with a mermaid diagram and a plain-language `## Benefits and trade-offs`
  table, so a non-specialist can judge the change; the critic checks the diagram matches the plan. The
  critic is advisory — it never passes or fails a spec; `tests/critique.sh` checks only that the critique
  exists, its rows keep their shape, every row is dispositioned, and the two spec sections are present.
  The stop hook and the autopilot GENERATE→EXECUTE edge refuse while it is red. Done when `bash
  tests/critique.sh` passes on a critiqued slice, a red twin (`CRITIQUE_MUTANT=missing|undispositioned|rewritten|nodiagram`)
  makes each case go red, the GENERATE edge is refused without a green critique, and stages 01–04 / 11
  are untouched.
- t58-divergence: The design is the agent's first idea — stage 05 asks for one stack and one rejected
  alternative — so the human never sees options they did not know to ask for. Opt-in per slice: a brief
  tagged `[diverge]` makes its GENERATE hop dispatch N subagents (default 3, `DIVERGE_N`) before the
  spec, one always the boring baseline (so "prefer boring technology" survives as the default to beat),
  the others each under a different forbidden pattern or single priority. Each writes one entry in
  `docs/cascade/05b-<slice>-candidates.md` with `approach`, `constraint`, `gives up`, `regret when`,
  `failure modes` and `falsifier` (a cheap command or experiment that would prove it wrong); the t57
  critic ranks them, advisory only. The human signs the pick as a `CHOSEN: <C#> — <reason>` line inside
  `<EDIT>`; autopilot always stops for that choice with a halt naming the candidates and their
  falsifiers. `tests/diverge.sh` checks ≥N candidates, every field filled, distinct `constraint`s, and
  no two `approach` texts near-duplicate (token-overlap threshold) — it guarantees distinct text, not
  real novelty, and the spec says so. Done when `bash tests/diverge.sh` passes on a tagged slice, a red
  twin (`DIVERGE_MUTANT=clone|missing-falsifier|no-baseline`) makes each case go red, an untagged slice
  runs GENERATE exactly as today with `bash tests/enforcement.sh` green, and autopilot stops rather than
  chooses on a `[diverge]` slice.
- t59-scale-hardening: A stress test on a synthetic ten-year repo (60,060 tracked files, 10,000 spec docs,
  150 laws, 3,000 audit rows) showed the per-action layers stay flat (hooks under 100ms, a 10-file commit
  195ms), but three things grow with the repo, and two of them turn a check off without saying so.
  `cascade_worktree_sha` forks one `git hash-object` per file: 235s at 60k files, so `loop.sh` took 217s
  with a single `true` validator. The Stop hook runs that same fingerprint under a 120s timeout and
  treats a timeout as "cannot verify, let it through" (`stop_guard.py:229–234`), so past roughly 30k files
  the I10 "tree changed after the loop passed" check silently stops running; the stage-10 branch does the
  same under 900s around a full `audit.sh` (`stop_guard.py:203–208`). `sign.sh` forks one `grep` per doc
  to find `<EDIT>` blocks: 38s per signature, where one `git grep` takes 61ms. And autopilot accepts a
  slice's spec doc by substring match (`tests/lib/autopilot.py:83`), so after years of slugs an old
  `05b-login-rate-limit.md` satisfies a new slice `login`. Make the fingerprint cost scale with what
  changed, not with the size of the repo (git's own index and stat cache); make a check that cannot
  finish say so and refuse, never pass; find `<EDIT>` files in one process; match the spec doc exactly.
  Verdicts must not change on any tree the current code can check in time (I18). Done when the
  fingerprint stays under 1s on the 60k-file fixture and still changes on a one-byte edit, a timed-out
  Stop-hook check refuses the edge with a message naming the cause and the command to run by hand,
  `sign.sh` finds the same `<EDIT>` files as today, a slug that is only a substring of an older spec
  name no longer counts as its spec, and `bash tests/enforcement.sh` stays green.
- t62-loop-runners: `tests/loop.sh` runs every `VALIDATOR:` line as its own opaque process, one after
  another (`tests/loop.sh:107-115`), and throws the output away. On a Gradle product every line is a
  separate `./gradlew` build, so each one pays client startup plus configuration of the whole build
  (every module, every plugin, AGP on Android) before a single test runs, and every loop pass repeats
  that N times; a failing line prints only `FAIL <cmd>`, so the agent re-runs the build by hand to see
  why. The pack treats a build tool as a process spawner when the build tool already owns a task graph,
  a scheduler and an input-keyed cache. Split *what to verify and the verdict* (the pack) from *how to
  run it* (a runner): a runner takes the hop's whole validator list and returns one verdict per line.
  The `shell` runner is today's behaviour and stays the default for anything it does not recognise. A
  `gradle` runner recognises plain Gradle lines in an **unchanged** `goal.md`, runs them as one
  `--continue` build, and scores each line from Gradle's own task outcomes and test results; any line or
  outcome it cannot attribute with certainty is re-run alone, today's way, so a faster loop can never
  report a verdict the sequential loop would not. Letting tests from different lines share one test JVM
  (faster, but a real verdict risk) is not the default: only a human-signed decision turns it on, and never
  for a law's `check:` line. In plugin mode, the first session after a plugin update refreshes the repo's
  pack-owned files itself when the cascade is idle, the tree is clean and no pack file was edited, and
  otherwise names the one command to run. Every line gets a log under `.cascade/loop/`, its time,
  and on FAIL the failing tests or the log's tail. Upgrading needs no edit to `goal.md`, the envelope or
  any law; `LOOP k/n`, the `PASS`/`FAIL` lines, the receipt and the merge gate keep their contracts.
  Done when, on a Gradle fixture with a deliberately slow configuration phase, N validators cost one
  configuration per wave of non-clashing lines instead of one per line (one in total with signed merging); a verdict matrix (pass, fail, shared task, compile error, no matching
  tests, mixed shell and Gradle lines) is identical to the sequential loop line by line; an old repo's
  `goal.md` runs unchanged after `install.sh`; and `bash tests/enforcement.sh` stays green.
- t63-quiet-stop-guard: Every nudge from `stop_guard.py` reaches Claude by exiting 2 with stderr, which
  Claude Code also renders to the human as a red "Stop hook error". The guard is working, but the label
  reads as a crash, and two messages are wrong besides: the I1 nudge tells the agent to print "the
  invariant block", which AGENTS.md forbids at a hop edge, and the autopilot branch and the final I1 check
  match the edge strings against raw text, so an explanation that quotes them in a code span is mistaken
  for a closed hop and starts a signed autopilot run nobody asked for (`halting()` already strips code
  spans; the other checks do not). Send the agent-facing nudges (I1 edge missing, autopilot continue,
  halt missing its block, I10 no evidence, spec gate red) through the quiet channel the hooks API
  provides for Stop, `hookSpecificOutput.additionalContext` on exit 0, instead of stderr on exit 2, and
  keep the human-facing stops (wall-clock budget, continuation cap, punch cap) visible. The quiet channel
  does not set `stop_hook_active` on the next stop, so the "fires at most once per stop" bound must come
  from the guard's own per-prompt marker, not the event field. Match every edge string with code spans
  and fences stripped, and drop "invariant block" from the I1 text. Verdicts must not change (I18): every
  case that blocks today still sends the agent back, and every case that passes still passes. Done when
  `bash tests/enforcement.sh` asserts the new channel for each nudge, a quoted edge in a code span no
  longer counts as a hop ending, a guard that nudges twice for the same prompt is a red twin, and a live
  session shows no "Stop hook error" for a missing edge line.
- t64-law-harness-jvm: On a Gradle product every D# costs two builds: `tests/dsharp_strength.sh` runs a
  law's `check:` and then its `break:` as separate commands, so N laws are 2N `./gradlew` invocations,
  each paying JVM start, configuration and compilation before one assertion runs. At a thousand laws
  that is hours per farm run, and `DSHARP_JOBS` does not help because concurrent builds in one project
  queue on Gradle's own locks. Ship a JVM law harness: red twins become runtime switches
  (`-Dinv.mutant=D7`, read only in test wiring, the Gradle form of the template's `INV_MUTANT=D1`), and
  a JUnit 5 extension runs each law test twice inside one test task, once plain (must pass) and once
  with its mutant on (must fail), writing both outcomes to JUnit XML. `dsharp_strength.sh` gains a
  `gradle` scoring mode that runs one build per module and reads the XML into the same per-law GREEN /
  RED / THEATER / UNPROVEN verdicts. A law whose `break:` is not a mutant switch keeps the old two-
  command path. Builds on t62's Gradle runner and must not land before it. Verdicts must not change
  (I18). Done when a fixture with many laws in two modules scores in one build per module with a
  `DSHARP k/n` and per-law lines identical to the sequential run, a mutant switch that leaks into the
  plain run is a red twin that goes red, and `bash tests/enforcement.sh` stays green.
- t65-verdict-cache: Every farm run re-proves every law even when nothing it depends on has changed, and
  a red twin's verdict only moves when its test or the code it guards moves. Cache each law's verdict
  under a key made of its `check:` and `break:` text, the content hashes of the inputs it depends on (its
  `path:` file and, on Gradle, the source sets of its module and the modules that module depends on), the
  toolchain version (`gradle --version`, JDK) and the pack version; a hit reuses the verdict and prints it
  marked `cached`, a miss runs the law. On Gradle, also turn on the build cache for law runs
  (`--build-cache`, with an optional remote cache URL signed in the envelope's locked decisions) so an
  unchanged module's test task comes back FROM-CACHE. Only GREEN verdicts are cached; RED, THEATER and
  UNPROVEN always re-run. The merge gate may opt out with `DSHARP_CACHE=off`, and CI's nightly run always
  does. A cache that cannot compute a key misses, never hits (I18). Done when a second run on an
  unchanged tree scores every law from cache with the same `DSHARP k/n`, a one-byte edit to a guarded
  file re-runs exactly the laws that depend on it, a forged cache entry whose key does not match is a red
  twin that is ignored, and `bash tests/enforcement.sh` stays green.
- t66-affected-laws: `tests/loop.sh` requires every in-force D# `check:` in `/goal` on every EXECUTE hop
  (I13, `tests/loop.sh:81-93`), so a hop that edits one module still pays for every law in every module,
  and the cost grows with the age of the repo instead of the size of the change. Add affected-law
  selection: map each law to the files and Gradle modules it guards (from `path:`, plus the module's
  project dependencies read once from Gradle), and on a hop run only the laws whose map intersects the
  diff against the hop's base. Selection fails closed: the full set runs when the diff touches build
  logic (`build.gradle*`, `settings.gradle*`, `gradle/libs.versions.toml`, `buildSrc/`, convention
  plugins), a module marked shared, any file no law maps, or when the map cannot be built. The schedule:
  each hop runs affected checks; the merge gate runs every check plus affected twins; the nightly CI job
  runs everything. Laws not run are printed as `not affected`, never as passing, and an omitted law is
  still a FAIL (I13). Done when a fixture hop that edits one module runs only that module's laws and its
  dependents', every fail-closed trigger runs the full set, a constructed diff whose affected law is not
  selected is a red twin that goes red, and `bash tests/enforcement.sh` stays green.
- t67-envelope-shards: The agent reads all of `docs/cascade/envelope.md` at the start of every hop
  (AGENTS.md, read-list item 2), so per-hop context grows with the number of laws ever written: at a
  couple of thousand D# lines that is a large token cost before any work starts, and a human reviewing
  one law scrolls past all the others. Let laws live in per-module shards, `docs/cascade/laws/<module>.md`,
  in the same D# format, with `envelope.md` keeping locked decisions, accepted artifacts and an index of
  shards. `tests/lib/laws.py` reads the envelope plus every shard (ids must stay unique across all of
  them; a duplicate is FATAL), hooks guard shard D# lines exactly as they guard envelope ones, and the hop
  read-list loads only the shards the slice's spec names, plus any shard t66 marks affected. An envelope
  with no shards behaves exactly as today. Done when a repo split into shards gives the same `DSHARP k/n`,
  per-law verdicts and `laws.py --count` as the unsplit one, a duplicate id across shards and an
  unsigned shard D# edit are both red twins, `install.sh` ships the shard layout as optional, and
  `bash tests/enforcement.sh` stays green.
- t68-law-retirement: Laws only accumulate. Nothing records that a law was superseded or that the
  behaviour it guards was removed, so after years the set carries dead laws whose checks still cost
  builds, near-duplicates that guard the same thing twice, and laws nobody can explain. Add a human-
  signed retirement: a D# line may carry `retired: <date> — superseded by D# | removed — <reason>`, signed
  like any other D# change; a retired law is not scored and not required in `/goal`, is listed by
  `dsharp_strength.sh` as `RETIRED` with its reason, and stays in git history. Add law grouping: several
  D# ids may name one shared test class with distinct mutant switches, so one test task proves a family.
  Add `bash tests/laws_report.sh`, which flags candidates for a human to review (laws whose `path:` no
  longer exists, laws with identical `check:` commands, laws with no change to their guarded files in a
  configurable number of years) and never retires anything itself. Retirement may never be used to drop
  a RED law to make a gate pass: a law that is RED at the time of signing cannot be retired in the same
  hop (I18). Done when a retired law drops out of scoring and `/goal` with a `RETIRED` line, retiring a
  currently RED law is refused, the report finds each seeded candidate in a fixture, and
  `bash tests/enforcement.sh` stays green.
- t69-gradle-tuning: After t62, t64 and t65 cut how many Gradle builds run, each remaining build is still
  slower than it needs to be. Have the Gradle runner pass the settings that make repeat builds cheap,
  and nothing that changes a test result: configuration cache (`--configuration-cache`, falling back
  per build with a logged reason when a project is not compatible), a daemon kept warm across lines
  and laws within one run, `--offline` when the dependency cache is already populated, and
  `maxParallelForks` sized to the machine for law test tasks instead of separate concurrent builds.
  Split the nightly full run across CI runners by module (a job matrix over t66's module map), each
  shard scoring its own laws and a final job joining them into one `DSHARP k/n`. Any flag a product's
  build rejects is dropped for that product with a logged reason, never forced. This is the last slice
  of the scale work: bump the pack to the next minor version above what is on main when it lands, with
  a CHANGELOG entry covering t63–t69 and measured before/after numbers on the t62 fixture. Verdicts must
  not change (I18). Done when the fixture's full farm run is measurably faster with identical verdicts,
  a project that rejects the configuration cache still scores correctly, the split nightly job's joined
  score equals a single-machine run, the version and manifests are bumped, and
  `bash tests/enforcement.sh` stays green.
- t74-inv-new-file-skip: `.githooks/pre-commit` exits 1 with no message when a commit adds any file under
  `tests/inv/` that is not named `test_D<N>…` (reported from a downstream repo on 2026-10-21 for a red-twin mutant,
  `tests/inv/mutants/D49.patch`; reproduced on `6703437`). The id-extraction line in the tests/inv reuse check,
  `id="$(basename "$f" | grep -oE '^test_D[0-9]+' | sed 's/^test_//')"`, runs under `set -euo pipefail`: grep's
  no-match fails the pipeline and the hook dies before the intended `[[ -n "$id" ]] || continue` skip. Make it set -e
  safe (`|| true`, as the `law=` line below it already is), and check `hop_guard.py`'s twin of the same check for the
  same skip. Then say in AGENTS.md rule 5 how an agent adds the red twin for a new D#: as a new file under
  `tests/inv/` — new files are allowed — while editing an existing shared file there (a twins table, say) stays a
  human-signed law edit, which the hook already names when it blocks. The policy on existing files does not change
  (I18). Done when a commit adding `tests/inv/mutants/D99.patch` lands, a new `tests/inv/test_D<N>_x` for a declared
  law that names a different test is still blocked with its message, a change to an existing `tests/inv/` file is
  still blocked, a red twin that restores the unguarded line makes the hook exit 1 silently again, and
  `bash tests/enforcement.sh` stays green. Downstream repos pick it up by re-running `install.sh`.
- t76-gradle-task-copies: t62's exact mode batches only lines that do not clash, and two lines clash when they run the
  same test task with different `--tests` filters — which is how most goals are written. Measured downstream on
  2026-10-23 (dream-camera, worktree recording-audio-integrity, pack 2.7.0): 49 of 59 validators run
  `:composeApp:testDebugUnitTest` with different filters, so every wave held one line, no batched build ran, and the 49
  lines cost one full Gradle configuration each (40–200s per line, ~26 min of a ~27 min loop) — silently, with nothing
  saying why. Batch such lines the way t64 proves laws: in one build, register a copy of the test task per line
  (`bddLoopTest_<i>`, the line's own filter as command-line include patterns, its own report dir), so each line still
  runs in its own test JVM, with no shared JVM as in signed merge. Reuse t64's fidelity checks fail-closed (a copy
  that cannot faithfully reproduce the original makes that line run alone), run copies one after another in goal
  order, and prove a line PASS only when its copy succeeded, ran at least one test its own patterns select, and every
  task its own run would include succeeded; every other line, every FAIL included, runs alone as today. Not on by
  default where t62's waves already batch; never for a line equal to an in-force law's `check:` unless its verdict
  comes from its own copy. And say why lines ran alone: the `loop:` summary names the reason when a Gradle segment
  made no batched build (one task, N different filters; an unverified Gradle; the configuration cache off), so a
  45-minute loop is never silent about its cause. Verdicts must not change (I18). Done when, on a fixture of N lines
  on one test task with different filters, the loop makes one configuration instead of N with every verdict equal to
  the line run alone (pass, failing test, no-match filter, a test that needs a doFirst the copy cannot reproduce, a
  compile error); a copy without the fidelity checks is a red twin that passes a line its own run fails; the summary
  names the reason on a goal that cannot batch; E1 reports a dream-camera-shaped fixture (many filters, one task,
  KMP-scale configuration) before and after; and `bash tests/enforcement.sh` stays green.
- t77-goal-hygiene: `goal.md` is meant to be one hop's definition of done — its header says "Write this file at the start
  of every EXECUTE hop", I9 says "/goal is this hop's DoD only … /goal clear before STOP", and the conductor's step 5
  says "/goal clear any leftover" — but nothing enforces it, so goals grow. Measured downstream on 2026-10-23
  (dream-camera, worktree recording-audio-integrity, pack 2.7.0): `goal.md` carried "Previous slice" sections for
  every earlier slice, 59 validators where this slice needed a handful, and the loop spent ~27 minutes re-proving past
  slices on every pass. Old slices' tests belong in the project's CI suite, and real invariants in laws (which t66
  already requires per hop), not in every hop's goal. Make the rule mechanical without hiding anything: `loop.sh`
  refuses a goal written for another slice (`GOAL_SLICE` set and not the current slice), and prints a notice naming
  how many validators were already in an earlier slice's goal (from git history; an in-force law's `check:` exempt),
  so growth is visible every pass; a `tests/goal.sh reset` helper writes a clean goal for the current hop; AGENTS.md and
  the conductor say to reset at the accept edge and where old tests go instead. Nothing rewrites an existing goal, and
  the notice never refuses a carried-over line. Release it as 2.8.0 (VERSION, both manifests, CHANGELOG). Verdicts
  must not change (I18) beyond the one new refusal. Done when a goal for another slice is refused with the command to
  fix it, a carried-over line is counted and named in the notice (and a law's check is not), `goal.sh reset` writes a
  goal `loop.sh` accepts, an installed repo's goal without `GOAL_SLICE` behaves as today, 2.8.0 is in all three
  version files with a CHANGELOG entry, and `bash tests/enforcement.sh` stays green.
- t78-carry-out: t77 counts validators carried from earlier slices' goals and refuses the loop above a cap of 10, and
  tells the owner to "move them to the project's CI or a law" — but the pack gives them nowhere to go. The easy way
  under the cap is to delete lines, so a slice's tests stop running at hop edges and maybe anywhere: shorter loops
  bought with lost coverage, the opposite of "tests are law". Measured downstream on 2026-10-24 (dream-camera, worktree
  cinematic-natural-blur): 63 validators, 3 merged-slice sections, refused by 2.8.0 on its first loop. Give carried
  lines a destination that keeps them running where it counts: `bash tests/goal.sh carry-out` moves every carried line
  (t77's rule, `tests/lib/goal_history.py`; standing lines and law checks stay) from `goal.md` into
  `docs/cascade/regress.md` as column-0 `REGRESS:` lines with the slice each came from, and prints how many it moved; a
  `tests/regress.sh` runs them and prints `REGRESS k/n`; the merge gate (`bash tests/barbar.sh merge`) and the nightly
  require n/n, the hop loop does not run them. A regression line may be added freely, but removing or changing an
  existing one is the human's to sign, as for `tests/inv/` (pre-commit names the file and the line) — otherwise the
  suite is just a quieter place to delete tests. The loop's notice also names lines that were in the previous slice's
  goal and are now in neither the goal, `regress.md` nor a law ("dropped"), so a deletion is visible on the next pass;
  never a refusal. `install.sh` ships `regress.sh` and seeds an empty `regress.md`. Release with t77 as 3.0.0 (the
  two new refusals are breaking; 2.8.0 is not tagged on its own) unless the human names another version. Verdicts must
  not change (I18): a goal with nothing carried and an empty `regress.md` loops exactly as 2.8.0's. Done when carry-out
  moves exactly the carried lines (a standing line and a law check stay) and the loop is no longer refused for them;
  `regress.sh` runs each line and fails on any failure; the merge gate refuses with a failing regression line and
  passes with all green; removing or editing a committed `REGRESS:` line is BLOCKED unsigned and lands signed; a
  dropped line is named in the notice; E1 reports a dream-camera-shaped goal before and after carry-out (loop
  wall-clock, lines per pass); and `bash tests/enforcement.sh` stays green.
- t79-zero-test-guard: a validator passes when its command exits 0, whether or not it ran a test. A test filter that
  matches nothing — a misspelled class in `--tests` on a task where an empty filter is allowed, `xcodebuild test
  -only-testing:` naming a class that does not exist — can exit 0 having executed zero tests, and the loop, the
  regression suite and a law's check all print PASS. The agent does not lie; the script does. (Found reviewing t77/t78
  for blind spots, 2026-10-25: the one hole the pack can close outright.) For the runners the pack already parses —
  Gradle test tasks (the JUnit XML the run wrote under each module's `build/test-results/`, newer than the run's start)
  and `xcodebuild test` (its `Executed N tests` summary, or the `.xcresult` when one is named) — a validator line that
  executed **zero** tests is a FAIL with the reason `ran no tests` in `loop.sh`, `regress.sh` and the merge gate's
  regression run; a skipped-only run counts as zero. Lines the pack cannot read (plain shell, other runners) are
  unchanged and counted as `not inspected` in the loop's summary line, never as passed-with-tests. A law's check that
  runs zero tests is already THEATER when its red twin also passes; this slice makes a zero-test check RED instead, and
  says so. Verdicts change only from PASS to FAIL, and only for zero executed tests (I18). Done when a misspelled Gradle
  filter on a lenient task and a misspelled `-only-testing:` class each FAIL with `ran no tests`, a line that runs one
  test passes, a skipped-only run fails, a plain shell line is unchanged and counted `not inspected`, the t62 batched
  runner proves a line only when its own tests executed, red twins show a guard that accepts zero goes green, and
  `bash tests/enforcement.sh` stays green.
- t80-carry-matching: t77's carried count and t78's carry-out and dropped notice match validator lines exactly after
  collapsing whitespace, so a reworded line slips through: reorder `--tests` filters, add `-q`, fold one slice's filter
  into another slice's line, and the line is neither carried nor (if it came from an older slice than the previous
  one) named as dropped. Narrow it, knowing it cannot be closed: for Gradle lines compare (wrapper, tasks, the set of
  `--tests` filters, the set of other flags) ignoring order and quiet/log flags; for `xcodebuild` lines the scheme,
  destination and the set of `-only-testing:` targets; a line whose filter set contains a carried line's filters
  carries it (a fold); every other line keeps today's exact rule. The notice says `matched by filters` when a match was
  not exact, so a human can see the rule at work. Never a refusal beyond t77's cap, which simply counts more honestly.
  Done when reordered filters, an added `-q`, and a fold each count as carried (and are carried out and not dropped), a
  genuinely different filter does not, a plain shell line keeps the exact rule, red twins show the exact-only matcher
  missing each case, and `bash tests/enforcement.sh` stays green.
  *Added 2026-10-25 by the human ("elaborate in readme regarding the stage code"):* the README explains the codes on
  every screen — the stage numbers and `05b`, a slice id like `t80`, GENERATE / EXECUTE, `D#`, `LOOP k/n`,
  `REGRESS k/n`, `STITCH NEEDED`, `AUTOPILOT HALT`.
- t81-autopilot-edge-envelope: autopilot's EXECUTE→next edge runs `tests/loop.sh` with `CASCADE_ENVELOPE` set to a
  temporary copy of the pre-edge hop state (`tests/lib/autopilot.py:111-116`), and every validator inherits it. The
  enforcement suite — a `# standing` line in every goal since t77 — does not unset it (`grep -c CASCADE_ENVELOPE
  tests/enforcement.sh` → 0), so its throwaway fixtures read that file instead of their own envelopes and fail. On
  2026-10-25 the edge EXECUTE t79 → GENERATE t80 was refused ("tests/loop.sh is not n/n") while the same tree was
  LOOP 3/3 outside the hook (`ce7c4fe`); the t78 → t79 edge needed a human signature for the same reason (and a
  30-minute timeout against a ~25-minute loop). Make the edge check honest: the loop reads the pre-edge hop state
  without exporting it to validators (or validators run with it unset), and the check reports which validator failed
  instead of a bare "not n/n". Also fix t62's AC5b, which uses `sed -i 's/…/'` without a suffix and fails on macOS.
  Verdicts must not change (I18). Done when an autopilot EXECUTE→GENERATE edge on this repo's own goal (enforcement
  standing) is accepted when the loop is n/n and refused, naming the validator, when it is not; t62's AC5b passes on
  macOS; and `bash tests/enforcement.sh` stays green.
  *Corrected 2026-10-25 at GENERATE (critic C1):* the cause is deeper than validators inheriting the variable —
  `CASCADE_ENVELOPE` points every **law** reader at the hop-state copy, so envelope laws vanish and the edge check
  fails open (measured). Fixing it makes the check stricter: edges the fail-open accepted are refused. "Verdicts must
  not change" holds for every verdict except that one, which changes on purpose.
- t82-task-routing: BDD already makes the hop, laws, and human edge authoritative, but it sends investigations,
  bug fixes, features, refactors, and verification through the same general craft instructions. Add an optional
  `/bdd-work` entry point for Claude Code that selects a small, evidence-oriented workflow for the request inside
  the current BDD hop. It must preserve the signed slice, obey GENERATE/EXECUTE limits, refuse requests to alter
  human-owned state or bypass laws, and handle non-trivial requests at NONE without starting a hop. Keep it a
  router, not a clone of pstack's full playbook set or a second cascade. Done when plugin and standalone installs
  expose it, route cases and negative boundary cases are scored in the existing eval machinery, and a real-agent
  probe covers routing behavior without weakening an existing gate.
- t84-progress-watchdog: autopilot stops a run only on wall-clock (`BDD_AUTOPILOT_MINUTES`), a hop-count cap
  (`4 * entries + 4`, `.claude/hooks/stop_guard.py:164`) and the edge loop's time limit (t81). None of them asks
  whether the work is moving: an EXECUTE hop can re-run `tests/loop.sh` all night at the same `LOOP k/n` with the same
  failing validators, or keep editing files its plan never named, and the run continues until the cap. Add a
  deterministic watchdog, read from the tree and the loop's own output, never a model's judgement: `tests/loop.sh`
  appends one line per pass (slice, `k/n`, the failing validator set, the tree fingerprint) to a local history; under
  a signed autopilot list the Stop hook ends the run for a human, naming the evidence, when the last N passes of this
  slice (default 3, an env var changes it) show no rise in `k` and the same failing set, or the same fingerprint (no
  edit between passes). Scope drift — hop-diff paths outside the plan's "In scope this execute" list — is reported to
  the human at the edge, not a halt. No verdict loosens; a human-driven hop is never stopped by it. Done when an
  autopilot fixture stuck at `LOOP 1/2` is stopped after N passes with the failing validator named, one that rises
  each pass is not, a drift fixture names the out-of-plan path, red twins show a watchdog that ignores the failing
  set (or the fingerprint) letting the stuck run continue, and `bash tests/enforcement.sh` stays green.
- t85-recall-index: after compaction, resume or clear, `.claude/hooks/preserve.py` re-injects the invariants, the
  hop, the laws and the last 12 decisions — but not where this slice's work lives. The agent then rereads broadly or
  reconstructs from chat residue, which the control line forbids. Inject a short recall index instead of more text:
  the slice's brief line (first 200 characters and its `05b-briefs.md` line number), the spec, plan-section, critique
  and candidates paths that exist, the last loop pass (`k/n` and its failing validators, from t84's history when
  present) and the last `AUTOPILOT HALT` / `BUDGET` / `CAP` line with its timestamp — each as a path or id the agent
  follows on demand (inline the pointer, spill the content). Capped at about 25 lines; silent at NONE as today. Done
  when a compact on a GENERATE and on an EXECUTE fixture injects exactly the files that exist (no dead path), the
  cap holds on a long history, a red twin shows a stale path injected when the file is gone, and
  `bash tests/enforcement.sh` stays green.
  *Corrected 2026-11-02 at GENERATE (critic C2):* t84's history keeps the first failing validator and a hash of the
  set, not every one, so the index names the first and points at `.cascade/loop/` for the rest.
- t87-autopilot-list-retire: a signed `AUTOPILOT:` list outlives its run. `tests/lib/autopilot.py` treats a current
  slice that is not on the list like no hop at all (`status()` `:193`, `decide()` `:118`: `idx < 0 or hop in ("",
  "NONE")`), so while an off-list hop is open it answers `next GENERATE <first entry>` and the Stop hook pushes the
  agent toward that edge after every stop — measured 2026-11-02: 12+ `CONTINUE … next GENERATE 05b t78-carry-out`
  lines while t84 and t85 ran by hand, a finished list (t78–t80) still signed. At NONE the same stale list is a valid
  start, so `/barbar auto` would rebuild accepted slices. Fix both: an open hop whose slice is not on the list is
  `off` for status (no continuation, no nudge) and its edges are refused by autopilot (a human takes them, as today
  for any off-list edge); and when the last entry's EXECUTE is accepted, the agent proposes emptying the
  `AUTOPILOT:` line in the same edge (the human approves it — the line stays human-owned, never cleared by a hook).
  Done when a fixture with an off-list open hop and a signed list gets `off` and no continuation, the same list at
  NONE still starts entry 1, the done-edge proposal is made, a red twin with today's `idx < 0` rule continues the
  off-list hop, and `bash tests/enforcement.sh` stays green.
  *Corrected 2026-11-02 at GENERATE (critic C1):* "the same list at NONE still starts entry 1" holds for a fresh list;
  a list whose entry 1 was already accepted (per the hop state's git history) is `stale` and refused, naming the
  accepted and remaining entries — that is the brief's own cost ("would rebuild accepted slices"); status says `off-list`.
- t88-briefs-archive: `docs/cascade/05b-briefs.md` holds every brief since the first slice (455 lines, 35 entries on
  2026-11-02), and GENERATE, the spec critic, `/barbar auto` and the prompt hook read it. Move each accepted slice's
  brief, verbatim and with its dated notes, to `docs/cascade/05b-briefs-archive.md`, so the live file holds only
  briefs not yet built. A slice counts as accepted when its `### <slug>` section exists in `docs/cascade/regress.md`
  (written by `goal.sh reset` after its accept) — a rule a script can check, not a judgement. Every reader that finds a
  brief by slug (`.claude/hooks/seam.py`, `tests/lib/diverge.py`, `tests/lib/recall.py`, `tests/doctor.sh`,
  `commands/barbar.md` and its `.claude` copy, the critic brief in `product-e2e-gre-pipeline.md`, USAGE.md) looks in the
  live file first, then the archive, so a send-back or a re-critique of an archived slice still finds its brief. The
  move is done by a command (`bash tests/briefs.sh archive`), run at the start of a GENERATE hop like `goal.sh
  reset`, never by hand-editing; it refuses a dirty briefs file and moves nothing it cannot match exactly. Done when
  the command moves exactly the accepted briefs (byte-identical text in the archive), every reader finds an archived
  brief, a `[diverge]` tag still resolves from the archive, a red twin that reads only the live file fails to find
  an archived slice's brief, and `bash tests/enforcement.sh` stays green.
  Absorbed by t102-doc-disclosure (2026-11-12).
- t89-frozen-oracle: the agent that builds a slice also writes the tests that judge it. t84, t85 and t87's acceptance
  files were all written during EXECUTE by the builder, red twins included — and models are switched mid-work
  because of usage limits, so the grader changes with the builder and a weaker model can pass an easier exam it wrote
  itself. Make the oracle fixed before the build: on a GENERATE 05b hop the spec writer also writes the slice's
  acceptance tests (`tests/` is GENERATE-writable; a product that keeps tests elsewhere lists the path in
  `docs/cascade/generate-writable.txt`) and names them in a committed manifest `docs/cascade/05b-<slug>.oracle` —
  one path and content hash per line — which the critic reviews with the spec. The human's GENERATE→EXECUTE
  signature freezes it: during EXECUTE the oracle files are read-only (`hop_guard` asks, pre-commit blocks without the
  key, as for `tests/inv/`), `tests/loop.sh` refuses the hop when an oracle file's hash differs from the manifest or
  an oracle file is not a goal validator, and changing the oracle means sending the slice back to GENERATE. The
  builder may add further tests; they never replace the oracle. Done when an EXECUTE fixture cannot edit or delete an
  oracle file in session or at commit, a changed hash or a missing oracle validator is `LOOP REFUSED` naming the
  file, a send-back to GENERATE can change it again, red twins show a loop without the hash check passing an edited
  oracle and a hook without the guard allowing the edit, and `bash tests/enforcement.sh` stays green.
- t90-provenance-switch-audit: when a model or agent is switched mid-slice nothing records it — commit trailers name a
  model only if the agent writes one, and hops and edges record no builder — so nobody can tell which part of a
  delivery a weaker model built. Record, at every hop edge and every `tests/loop.sh` pass, the host (`claude` /
  `codex` / other, from `BDD_HOOK_HOST`), the model when the host reports it, and the session, in
  `.cascade/provenance` and in a trailer on the edge commit. When the builder of an EXECUTE hop changes between its
  first and last loop pass, the accept edge requires a fresh full loop on the final tree plus an independent
  fresh-context review of the diff since the switch (t57's critique format, rows answered) before it can be asked
  for. Add `bash tests/handover.sh`, which any agent runs first (AGENTS.md says so): it prints t85's recall index and
  the hop state, so handover does not depend on Claude Code's SessionStart hook. Done when edges and passes record
  host, model and session, a fixture that switches model mid-EXECUTE is refused accept until the switch review is
  committed and answered, a no-switch hop is unchanged, `handover.sh` prints the same index as preserve, a red twin
  without switch detection accepts the switched hop, and `bash tests/enforcement.sh` stays green.
- t91-scorecard-routing: two halves in one slice, by the human's call to save a hop. (1) **Scorecard.** After a model
  switch the only way to judge a delivery is to trust the agent's report. `bash tests/scorecard.sh [slug]` computes one
  card per slice from the tree, identical whichever model runs it — oracle (t89, frozen and unchanged), loop (last pass
  for the slice, t84), review (open critic or switch-review rows, t90), drift (t84), diff (files and lines since the
  hop opened), regression (`tests/regress.sh`), builders (t90) — each `pass`, `fail <why>` or `unknown`; a field the
  tree cannot prove is `unknown`, never `pass`; it exits non-zero when a required field (oracle, loop, review,
  regression) fails; the accept edge shows it to the human. (2) **Routing.** `bdd-work` (t82) is used only when the model
  chooses to load it — never across t84–t90 in this repo. `tests/lib/route.py` classifies a prompt deterministically
  (investigation, bug-fix, feature, refactor, verification, or `ambiguous`) and the UserPromptSubmit seam injects one
  `ROUTE …` line with the route's evidence chain and first steps (to copy into the todo list verbatim, pstack's trick),
  hop-aware; on a 05b slice whose brief routes bug-fix, the GENERATE oracle gate also requires an oracle command that
  fails on the unfixed tree. Done when the card is identical for the same tree whoever runs it and fails naming the
  field on an edited oracle, an open review row or a red regression; a labeled prompt set passes an accuracy bar with
  ambiguity reported; the ROUTE line appears on hop prompts and not on plain questions at NONE; a bug-fix oracle that
  passes on the unfixed tree is refused at the spec edge; red twins cover a card that trusts the agent's report, an
  always-`feature` classifier, and a gate that skips the failing-test rule; and `bash tests/enforcement.sh` stays green.
- t93-adaptive-effort-routing: draft requested 2026-11-04. Extend workflow advice with deterministic effort
  recommendations from phase, complexity, uncertainty, risk and explicit task/failure evidence. Keep plan at
  medium by default, allow low only for bounded known work, and preserve high floors for risky work. Resolve
  provider/model/platform capabilities and cache-transition guidance from explicit profiles; unsupported and
  unknown remain visible. Preserve user overrides and report recommendation separately from application.
  This slice is offline advice plus a portable JSON CLI, not a host/API settings controller. Spec and plan:
  `docs/cascade/05b-t93-adaptive-effort-routing.md` and `docs/cascade/plans/05b-t93-adaptive-effort-routing.md`.
  Not accepted or active; t91 remains the human-owned current hop until signed otherwise.
- t96-install-repairs: [bug-fix] requested 2026-11-05. A stress test of tag 3.5.0 found that a clean install cannot reach
  a merge. Fix these faults and release 3.5.1. (1) In an installed repo, `tests/enforcement.sh` fails T52 and T74 in both
  install modes, and T53 and T54 in plugin mode, because each check needs a pack-only file or fixture. The farm then
  stays at `BARBAR 40/41`, `doctor` stays red, CI fails and `barbar merge` refuses. Make these checks SKIP in a product
  repo, as T93 does, and do not weaken them in the pack. (2) `install.sh` copies the pack's open hop into a new repo. Seed
  `NONE / 00 / empty`, and keep the existing hop state of a repo that has one. (3) `bash_guard.py` denies `--no-verify` but
  allows `git commit -n` and `git -c core.hooksPath=/dev/null commit`. Deny both. (4) CI does not detect softened shipped
  files. Make CI run the drift check. (5) A no-plugin upgrade from 3.0.2 stops at `CONFLICT` on an untouched
  `.agents/skills/bdd-work/SKILL.md`. Replace the file when it matches an earlier pack copy, and keep the conflict for a
  real user edit. (6) The workflow takes about 614 s against `timeout-minutes: 10`; give it enough time. (7) The farm leaves
  untracked `evals/fixtures/*/.cascade/` files; stop this. (8) `.codex-plugin/plugin.json` says 3.4.0; correct it. `tests/ac/codex_compatibility.sh`
  detects this, and `docs/cascade/regress.md:37` runs it, so `main` is at `REGRESS 13/14`; also run it through T96. (9) `hop_guard.py` lets the agent write its own hook files and
  `settings.json`; require a human signature. Evidence is the 3.5.0 stress run of 2026-11-05. Done when the replayed CI
  steps exit 0 in a fresh clone of each install mode, `bash tests/barbar.sh` scores n/n there, and each fault has a test
  that fails on tag 3.5.0. Out of scope: the unreleased 3.6.0 work on `feat/specplan-refinement`.
- t97-self-check-gate: [bug-fix] requested 2026-11-07. The `self-check` job in `.github/workflows/pack-self-check.yml` has
  not given a verdict since 2026-10-23, and CI cancels it after 5 minutes on `main` and on PRs. Fix these faults. (1) The job
  runs `bash tests/barbar.sh merge`, which runs the full farm first, against `timeout-minutes: 5`. The `eval` job, which
  also runs the farm, takes 23 minutes on CI. Run `bash tests/barbar.sh gate` instead, because `eval` already runs the farm.
  (2) `gate` alone takes 440 s on this machine, and most of the gate's work is the regression suite, which takes 5 minutes
  on CI. So 5 minutes is too low for `gate` also; give the job enough time. (3) The job accepts any non-zero exit, so a crash
  or a failing farm counts as a refusal. Make the job pass only when the gate prints its refusal for the pack's real reason:
  stage 10 is not CLEAN and stage 11 is not READY. Evidence is CI run 42314826062 at a39735c and the run at 970744e, both
  cancelled after about 5 minutes. Done when the job finishes inside its limit on CI, passes on the pack, and fails when
  the gate crashes or allows. The test must fail on the unfixed workflow. The workflow is pack-only (`install.sh` does not
  copy it), so a product gets no change. Out of scope: the farm's run time, and the gate's rules.
- t99-gate-timeout: [bug-fix] requested 2026-11-09. The autopilot gate has three time limits that do not agree.
  `tests/lib/autopilot.py:29` sets `LOOP_MINUTES = 60` (`BDD_AUTOPILOT_LOOP_MINUTES` changes it), but
  `.claude/hooks/hop_guard.py:129` stops `autopilot.py` after 1300 s, and `hooks/hooks.json` sets no `timeout` for the
  `hop_guard` hook, so the Claude Code default applies. When the 1300 s limit stops the gate, `autopilot_ok` catches the
  exception and returns `(False, "")`: the human sees a refusal with no reason. Thus a loop that takes more than about
  22 minutes always sends the EXECUTE→next edge back to a human, with no reason given. Fix these faults. (1) Make one limit
  control the gate: `hop_guard.py` and the hook `timeout` must come from `loop_minutes()` plus a margin, so the gate's own
  limit is always the first to stop. (2) When a limit stops the gate, the refusal must name the limit and the variable
  that changes it. Evidence is a product user's report of 2026-11-09: loops of 17 to 66 minutes, and every EXECUTE→next edge
  went back to a human. Done when a test with a slow stub loop shows that the gate's own message
  (`did not finish in N minutes`) reaches the refusal, and when the same test shows that a loop shorter than
  `BDD_AUTOPILOT_LOOP_MINUTES` but longer than 1300 s is allowed. The test must fail on the unfixed code. Out of scope:
  whether the gate may accept an existing `.cascade/loop-receipt` instead of running the loop again (that is a human
  decision), and the loop's run time.
- t100-isolated-gradle-merge: [feature] requested 2026-11-09. In exact mode (USAGE.md §B9), Gradle lines that use one test
  task with different `--tests` filters each get their own wave. A goal of 25 such lines therefore needs 25 builds, and
  batching saves nothing. A product user measured about 40 s per build, almost all of it Gradle start and configuration,
  so about 17 minutes for each loop pass. Merged mode unions the filters into one build, but it needs a signed
  `LOOP_GRADLE_MERGE: on`, because test classes from different lines then share one test JVM, and it never merges a D#
  `check:` line. Add an isolated merge: union the filters of one test task into one build, and use
  `gradle_runner.init.gradle` to give that merged test task `forkEvery = 1`, so each test class runs in its own JVM. Prove
  each line's pass from the JUnit XML, as merged mode does now: the line's own patterns surely selected at least one test
  (t79), and they could not have selected any failing test. The runner must never print FAIL. Every line that it does
  not prove, every failure, and every case it does not understand run alone, as they do now. Thus a line's verdict is
  the same as when it runs alone, and isolated merge can be the default. It can also take a D# `check:` line. Lines that
  set their own fork options, and builds where the init script cannot set `forkEvery`, run alone. `tests/barbar.sh merge`
  and `tests/dsharp_strength.sh` do not change. Evidence: on the user's goal of 29 validators, 28 lines ran alone. Done when,
  on real Gradle (8.5 and the newest verified version), a stress test that includes order-dependent, static-state,
  failing, empty-filter and D# lines gives each line the same verdict in isolated merge as alone; when a goal of
  same-task filtered lines needs one build in place of one per line; and when `BDD_LOOP_RUNNER=shell` still turns
  batching off. Out of scope: `LOOP_GRADLE_MERGE` (it stays as it is), the law harness (B10), and Xcode lines (t98).
  Decision 2026-11-09 (human, at GENERATE): build per-line copies, not `forkEvery = 1`. `forkEvery = 1` gives each
  test class its own JVM, so a line whose own classes fail together alone would pass. One Gradle build registers a
  faithful Test-task copy per line with the line's own filter (t64's law-harness way), run in sequence. A copy that
  is not faithful, and every line not proven, runs alone.
  Dropped 2026-11-09 (human, at GENERATE, after spec critique C1): t76's E0b gate already failed this design on AGP
  (`AndroidUnitTest` copies need AGP-private state), so the reporting user's `testDebugUnitTest` gains nothing. No
  product code. The spec, oracle and critique stay as the record. For that user today: a signed `LOOP_GRADLE_MERGE: on`.
- t101-goal-verdict-cache: [feature] requested 2026-11-09. `tests/loop.sh` runs every goal line again on each pass,
  also after an edit that only changes `docs/`. The t65 verdict cache (USAGE.md §B12) reuses a law's GREEN when no input
  that the law declares changed, but goal validator lines do not get that cache. A product user lost about 83 minutes in
  one day to two loop passes that followed a docs-only commit. Reuse a goal line's PASS when its key did not change. Build
  the key with t65's code: the line's own command; for a plain Gradle line, every file of its module and of the modules it
  depends on (t66's map), every build-logic file and the toolchain; for an `xcodebuild` line, the paths that a signed
  `- LOOP_CACHE_PATHS:` line in the envelope names for it; every non-doc file that no module declares; the pack version and
  the relevant environment. Every other line has no key and always runs. Cache only PASS; never cache FAIL. Print a cached
  line as `PASS (cached)`, and count it in `k`. The accept receipt keeps the fingerprint of the whole tree, and
  `tests/barbar.sh merge`, `tests/audit.sh` and `tests/regress.sh` never read this cache. `BDD_LOOP_CACHE=off` turns it off.
  Done when a test shows that a docs-only commit runs no Gradle line again, that an edit in a module runs again the lines
  of that module and of the modules that depend on it, that a build-logic edit runs every Gradle line again, that a
  changed toolchain or pack version runs every line again, and that a FAIL is never reused. Out of scope: affected
  selection for goal lines, and running lines at the same time.
  Decision 2026-11-09 (human, at GENERATE, spec critique C1): the autopilot gate (`hop_guard`, `pre-commit`) never
  reads or writes this cache; each EXECUTE→next edge stays a full run. `LOOP_CACHE_PATHS` may key any non-Gradle line.
  Decision 2026-11-10 (human, at EXECUTE): the cache's key builds add Gradle calls that t62, t69 and enforcement T62
  count exactly. Those fixtures set `BDD_LOOP_CACHE=off` (they test the runner), and t69 AC9's allowlist gets
  `goal_cache.py`, as t91/t93/t96 did.
- t102-doc-disclosure: [feature] requested 2026-11-12. Source: the talk "Learning While You Sleep" (AI Native DevCon
  London 2026): long instruction files lose effect ("context blurred"), and progressive disclosure keeps them short.
  t67 applies this to laws, but not to the pack's own docs. Before an agent starts work, `AGENTS.md` tells it to read
  `docs/cascade/product-e2e-gre-pipeline.md` (40 KB) and `CONTROL-LINE.md` (38 KB), about 22k tokens. The file
  `docs/cascade/05b-briefs.md` (68 KB) holds every brief and only grows. Give each of the two docs an index: one line
  for each invariant or rule, with a pointer to its full text. Make the agent read the index and the parts for its
  stage only. Move each brief of an accepted or dropped slice to an archive file, and keep the open slices in
  `05b-briefs.md`. `tests/doctor.sh`, `tests/lib/recall.py` and the prompt hook must find a brief in either file.
  Keep every rule text exact; this slice moves text, it does not change a rule. Done when a test shows that the
  required reads before work drop by at least half (bytes, measured by a script), that each I1–I18 and each rule in
  the index points to text that exists, that `tests/doctor.sh` and the recall index find an archived brief, and
  that preserve after a compact still injects what it injects today. Out of scope: rewriting rule text, the law
  shards (t67), and `USAGE.md`.
  Decision 2026-11-12 (human, at EXECUTE): t69 AC9's install allowlist gets `doc_parts` and `briefs` (`.py` and `.sh`),
  as t91/t93/t96/t101 did; the spec had listed `tests/ac/*` as unchanged.
- t103-log-source: [feature] requested 2026-11-12. Source: the same talk: analyse tool calls and metadata, and select
  which transcripts an analysis sees. `.cascade/decisions.log` has 3,426 lines; 2,766 are `bash_guard`, and most of
  them are acceptance-test fixtures that fire in bursts in the same second, not real agent actions. A report over
  this log learns from fixtures. Give each new line a source field `src=test|agent|human`, set by the writer
  (`tests/lib/decisions.py`), and make the test suites write `src=test` (or write to a separate log that the hooks
  do not read). Existing lines with no field stay valid and read as `src=unknown`. Readers (`tests/lib/recall.py`,
  `.claude/hooks/preserve.py`, the watchdog) keep their current results. Done when a test shows that a guard denial
  from an acceptance test is recorded as `src=test`, that a denial from a real hook call is `src=agent`, that a
  signature is `src=human`, that an old line with no field parses, and that recall and preserve output does not
  change for a log with no test lines. Out of scope: deleting or rewriting old lines, and any pattern report (t104).
- t104-pattern-report: [feature] requested 2026-11-12. Source: the same talk: in-band memory sees one session only,
  so repeated mistakes across sessions stay hidden; a proposal must carry example evidence and a prevalence count.
  Depends on t103. Add `bash tests/patterns.sh [--since DATE] [--min N]`, a read-only report in the style of
  `tests/laws_report.sh`. It groups `src=agent` and `src=human` events from `decisions.log` and the cascade commits
  (guard denials, `NOEDGE` stops, halts, watchdog stops, send-backs) by kind and reason. For each group it prints
  `seen N times in M hops`, up to three evidence lines (log line or commit hash that a script can check), and no
  group below `--min` (default 3). It uses no LLM, never edits a file, never signs, and no gate reads it. Done when a
  test shows that a fixture log with known repeats prints the expected groups and counts, that `src=test` lines
  never count, that a group below `--min` is not printed, that each evidence line resolves to a real log line or
  commit, and that the script exits 0 and writes nothing. Out of scope: LLM analysis ("dreaming"), proposals that
  edit laws or docs, and a signed focus or ignore list.
- t106-lessons: [feature] requested 2026-11-13. Source: the human asked for focus and learning over time without token
  overhead ("smarter but still efficient … not just nonsense token overhead"). t104 shows patterns; nothing turns one
  into a change, and nothing measures whether a change worked. Add `docs/cascade/lessons.md`: each lesson is one line
  inside `<EDIT>` (human-signed by the existing pre-commit `<EDIT>` scan), keyed to a t104 group (actor, verdict,
  reason prefix), with a scope (hop class) and one imperative sentence of at most 160 characters. Add to
  `tests/patterns.sh`: `--propose` prints a draft lesson line for each group at or above `--min` that no lesson
  covers (stdout only; the human signs it in through the dialog), and a `LESSONS` block that gives, for each lesson,
  its group's rate per hop before and after the lesson's `since:` date, and marks it `SETTLED` when no event occurred
  in the last 5 hops after it, or `NOT WORKING` when the after rate is not lower. Read-only as t104. Done when a test
  shows the format is parsed, that `--propose` skips covered groups, that the before/after rates and the two marks are
  right on a fixture, that a malformed lesson line is reported and not used, and that `<EDIT>` protection refuses an
  unsigned lesson commit. Out of scope: injecting lessons into prompts (t107), an LLM, editing lessons automatically.
- t107-lesson-recall: [feature] requested 2026-11-13. Depends on t106. The prompt hook (`.claude/hooks/seam.py`)
  prints a `LESSONS THIS HOP:` line with the signed lessons whose scope matches the current hop class, most frequent
  group first, at most 3 lessons and 400 characters, and never a `SETTLED` lesson: a lesson leaves the prompt when it
  has done its work, so the memory cost falls as the agent improves. No line when none matches. A context budget test
  measures the seam's output on each hop class in a scratch repository and fails above a signed budget (default: the
  3.5.6 size plus 400 bytes), so no later slice can grow per-prompt context without a human signing it. Done when a
  test shows the matching, the order, the two caps, that a settled lesson is not printed, that no lesson prints
  nothing, and that the budget test goes red when a fixture adds 1 KB to the seam. Out of scope: lesson content in
  the recall index, embeddings or semantic matching.
  Human decisions (2026-11-14, asked in session at GENERATE): (1) t106's AC8 release check is relaxed from exactly
  3.5.7 to 3.5.7 or later, as for t104, and t107 ships as 3.5.8; (2) the per-prompt budget is law D1 in a
  pack-only shard `docs/cascade/laws/context.md`, its check `tests/inv/D1_context_budget.sh` (critique C1).
  Human decision (2026-11-16, asked in session at EXECUTE): t67 AC4's pack-repo dsharp comparison runs on a copy of
  the pack with its law shards removed, so the pack's own D1 shard stays outside AC4's "with no shards".
  Same decision (2026-11-16) for t65 AC7 and AC11: their "DSHARP 0/0" pack repo is a copy with the law shards
  removed; any other accepted test that uses the pack as a no-law repo gets the same change, listed in the report.
