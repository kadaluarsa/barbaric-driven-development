- multi-currency: <one paragraph>
- journal-transfers: <one paragraph>
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
- t70-stop-marker-per-stop: `stop_guard.py` judges each Stop once per `prompt_id` (`already_event`, so the plugin
  copy and the repo copy never both judge one stop). Measured in 05b t63 E0 on Claude Code 2.1.280, headless and
  in this repo's own transcript: a continuation the hook asks for (exit 2, `decision: block` or
  `additionalContext`) keeps the same `prompt_id` and sets `stop_hook_active`. So every stop after the first in a
  prompt is skipped before any check runs. The I10 evidence check never sees an accept edge printed on a
  continuation, and a signed autopilot run advances at most one edge per human prompt — the "keep going across
  repeated stops" in `continue_autopilot` is dead code after the first edge. Key the dedupe on the stop, not the
  prompt (for example `prompt_id` plus a hash of `last_assistant_message`: two installs see identical input, a
  continuation does not). Check every branch that returns early on `stop_hook_active` for the same blind spot.
  Verdicts on a first stop must not change (I18). Done when a fixture with two installs still judges one stop
  once, an accept edge on a continuation without a loop receipt is refused, a signed two-slice list advances two
  edges in one prompt, and `bash tests/enforcement.sh` stays green.
- t71-edit-scan-scope: Merging `main` into a branch locally on 2026-10-20 was refused by `.githooks/pre-commit`
  with "EDIT tag content was changed or deleted" for `CHANGELOG.md`, a file that only *mentions* the tag in
  prose. The 2.6.0 entry added one more mention, which shifted how the tags pair. The hook scans every `*.md`
  that contains the tag (`.githooks/pre-commit`, the `case "$path" in docs/*|*.md` scan). `tests/sign.sh` with no
  arguments signs only files under `docs/` and `tests/inv/`, so the human could not sign the file the hook
  demanded without naming it by path. Make both use one definition of human-owned files, and do not count a
  tag inside an inline code span or fence as a tag. Verdicts on real cascade documents must not change (I18).
  Done when a CHANGELOG-style file that mentions the tag in code spans merges cleanly, a real change inside a
  tag in a cascade doc is still refused, `sign.sh` and pre-commit name the same file set, and
  `bash tests/enforcement.sh` stays green.
- t72-gradle-twin-up-to-date: A Gradle red twin written `INV_MUTANT=<id> ./gradlew :m:test --tests …` without
  `--rerun` is scored THEATER for the wrong reason (measured in 05b t64 on Gradle 9.7.1, 8.5 and 9.1.0): the client's
  environment is not a task input, so right after the passing `check:` the twin's test task is `UP-TO-DATE`, never
  runs, and exits 0. The law looks unable to fail when it never ran. `-Dinv.mutant=…` on the command line has the
  same effect: it sets a property in the build JVM, not the test JVM. Make `dsharp_strength.sh` tell this apart:
  when a THEATER twin's own output shows its test task `UP-TO-DATE` (or `FROM-CACHE`), say so in the line and point
  to the `--rerun` shape in USAGE.md §B10, instead of a bare THEATER. The verdict itself stays THEATER (it is still
  not in force), so no law becomes GREEN by this change (I18). Done when a fixture twin without `--rerun` prints
  THEATER with the up-to-date reason, the same twin with `--rerun` is GREEN, and `bash tests/enforcement.sh` stays
  green.
- t73-t62-ac-portable-sed: `tests/ac/t62_loop_runners.sh` AC5b fails on macOS with `sed: 1: … invalid command code
  f` (seen 2026-10-20): its "plugin older" case edits a file with GNU-style `sed -i`, which BSD sed reads as a
  suffix argument. It passes on Linux CI, so the failure is the test's, not the plugin refresh's. Replace the
  in-place edit with a portable one (a python3 one-liner, or `sed -i.bak`) and keep every assertion. Done when
  `bash tests/ac/t62_loop_runners.sh` is green on macOS and Linux.
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
- t75-xcode-runner: On an iOS/macOS product every Xcode `VALIDATOR:` line and every law command is its own
  `xcodebuild test` call, and each one pays tool start, build planning and Swift package resolution, an incremental
  build check and the test host's install and launch before one test runs: typically 30–90s for a no-op call, where
  the test itself takes a second. Laws (check plus break) and loop lines multiply that, as Gradle's did before t62 and
  t64. Add an `xcode` runner behind t62's contract, which does not change: it may only report a PASS it can prove, now
  from the `.xcresult` bundle (`xcrun xcresulttool`), never from an exit code; every FAIL and every case it does not
  understand runs alone by today's code; the merge gate never uses it. The default, which keeps each line and each law in
  its own test process: `build-for-testing` once per run, then `test-without-building -only-testing:<target/class>`
  per line or law, against one simulator kept booted for the run, rebuilt whenever a source changed since the build
  (a `break:` that patches code included), so it never tests a stale binary. Not default, and only behind a signed
  decision: several lines' `-only-testing` filters in one call (their tests share one app process, so static state,
  `UserDefaults` or keychain can leak between them — t62's merged-mode risk) and `-parallel-testing-enabled`
  (cloned simulators, ordering and shared-resource races); neither is ever used for a law's `check:`. Document the
  Xcode law shape: `break: TEST_RUNNER_INV_MUTANT=<id> xcodebuild test …`, because Xcode passes only `TEST_RUNNER_`
  variables to tests, so `INV_MUTANT=<id> xcodebuild …` never reaches them and that law scores THEATER; make
  `dsharp_strength.sh` say so in the THEATER line, as t72 does for Gradle's up-to-date twin. Measure first (E0, on the
  Xcode versions it will claim): that `-only-testing` and `test-without-building` select exactly what each line alone
  selects, that `TEST_RUNNER_` mutants reach the test, and the `.xcresult` fields a verdict is read from. Verdicts
  must not change (I18). Done when, on an iOS fixture with a deliberately slow build phase, a goal of N Xcode lines
  and M laws builds once per run instead of once per call with every verdict identical to each line run alone (pass,
  failing test, compile error, a test that needs a fresh process, a source edit mid-run); a runner copy that reads
  only the exit code is a red twin that goes red; an `INV_MUTANT=` twin without the prefix is THEATER with the reason;
  E1's numbers are in the EXECUTE report; a macOS CI job runs the stress script; and `bash tests/enforcement.sh` stays
  green.
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
