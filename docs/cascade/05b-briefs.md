- multi-currency: <one paragraph>
- journal-transfers: <one paragraph>
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
- t86-halt-notify: an overnight autopilot run ends at a halt, a budget, the cap, or `list complete` — and the human
  learns it only by opening the terminal. Add an opt-in notify command: when `BDD_NOTIFY_CMD` is set, the Stop hook
  runs it once per ending with a message of at most 100 words on stdin (the first line: `AUTOPILOT HALT` / `BUDGET` /
  `CAP` / `DONE` / `STITCH NEEDED`, then BOTTLENECK and RESUME WITH when present, the repo and slice). It runs in the
  background with a short timeout, its failure is logged to `.cascade/decisions.log` and never changes a verdict or
  blocks a stop, and the message never carries file contents, diffs or environment values. Done when a fixture halt
  calls a recording notify command once with a message under the cap, a repeated stop does not notify twice, a
  failing or hanging command neither blocks the stop nor changes its output, unset means no call, a red twin shows
  an uncapped message caught, and `bash tests/enforcement.sh` stays green.
- t91-delivery-scorecard: after a switch the only way to judge a delivery is to trust the agent's report. Compute one
  scorecard per slice from the tree, identical whichever model built it: the frozen oracle's pass (t89), the loop
  result, unanswered critic and switch-review findings, drift paths (t84), diff size, regression-suite pass, and the
  builders per hop (t90). `bash tests/scorecard.sh` prints it and exits non-zero when a required field fails; the
  accept edge shows it to the human; `/barbar merge` puts every slice's card in the PR body. A field the tree cannot
  prove prints `unknown`, never `pass`. Done when the card is identical for the same tree whatever agent runs it, an
  edited oracle, an open finding or a red regression each make it fail naming the field, a slice without t89/t90 data
  prints `unknown` for those fields, a red twin that reads the agent's report instead of the tree passes a failing
  slice, and `bash tests/enforcement.sh` stays green.
  *Superseded 2026-11-02:* merged with the route classifier into `t91-scorecard-routing` (one hop, by the human's call).
- t98-xcode-batching: [feature] requested 2026-11-07. `tests/loop.sh` runs each `xcodebuild test` line as a
  separate command. Each command builds the scheme again, and can boot a simulator again, so a product with many such
  lines pays that time once for each line. Gradle lines got this feature in t62 (USAGE.md §B9); Xcode lines did not.
  Let the loop prove more than one plain `xcodebuild test` line from one build, when the lines use the same
  project or workspace, scheme, configuration and destination. Prove each line's pass from the result bundle
  (`xcrun xcresulttool`): every test that the line's own `-only-testing:` and `-skip-testing:` options select must pass,
  and at least one test must run (t79). The runner must never print FAIL. A line that the runner does not prove, every
  failure, every line with an option that is not on an allow-list, and every Xcode version that is not verified run
  alone, as they do now. Thus the verdict of each line must be the same as the verdict when the line runs alone. Do
  not change `tests/regress.sh` and `tests/dsharp_strength.sh` in this slice. Evidence: on this machine (Xcode 27.0),
  each line pays the build and simulator boot again. Done when, on real Xcode, the batched verdict of each line is the
  same as its alone verdict in a stress test that includes failing, skipped, empty-filter and mixed-destination lines;
  when the loop needs fewer `xcodebuild` builds for a goal of same-scheme lines; and when a pack-only CI job on a
  macOS runner runs that stress test on each verified Xcode version. Out of scope: Xcode law harness (like B10),
  affected selection for Xcode, `swift test`, and Xcode versions that are not verified.
- t105-question-not-a-hop: [fix] requested 2026-11-12. `AGENTS.md` says that a question, an explanation, a status
  check or a refusal is not a hop and ends with no edge line. `.claude/hooks/stop_guard.py` does not apply this rule:
  while `CURRENT_HOP` is `GENERATE` or `EXECUTE`, each reply with no edge line gets the `NOEDGE` nudge (`Hop not
  closed (I1)`). Seen 2026-11-12 on GENERATE 05b t103-log-source (`.cascade/decisions.log` lines 3513 and 3514): the
  human asked a question that was not about the slice, and the agent answered and wrote no file. The hook demanded
  the edge line. The agent printed it, and the next stop refused that same line with `NOSPECGATE`, because no spec,
  critique or oracle existed. The two nudges contradict each other, the first one makes the agent ask for a review
  of work that does not exist, and each such `NOEDGE` line is a false entry for the pattern report (t104). Make the
  Stop hook tell an answer from an unfinished hop with evidence that a script can check, not with the words of the
  reply: for example, no tool call in this prompt wrote to the tree, the index or `docs/cascade/`. For such a reply
  the hook must not demand an edge line and must not write `NOEDGE`. No verdict becomes weaker (I18): a reply that
  changed the tree still needs its edge line, an edge line with a red spec gate is still `NOSPECGATE`, and an accept
  edge with no loop behind it is still `NOEVID`. Done when a test shows that a reply with no write during an open
  GENERATE hop and during an open EXECUTE hop passes with no nudge and no `NOEDGE` line, that a reply after a write
  with no edge line still gets the nudge, that an edge line printed on an answer with a red gate is still refused,
  that a red twin which reads the reply text instead of the write evidence lets an unfinished hop pass, and that
  `bash tests/enforcement.sh` stays green. Out of scope: the prompt hook's route classifier, and any change to
  when an edge is legal.
  Decision (human, 2026-11-16, asked in GENERATE): accepted t63 AC4's "a human prompt starts over" probe stops with
  a reply that wrote nothing, which t105 calls an answer. Change only that probe: the fixture writes a file after the
  seam.py prompt, before the stop, so it still proves the reset. Listed in the hop report.
- t108-work-in-flight: [fix] requested 2026-11-16. Source: the human, after t105. The Stop hook's `NOEDGE` nudge can
  demand an edge that the next check refuses. Seen 4 times on 2026-11-16 (t105 GENERATE and EXECUTE): a reply that
  wrote files and started `bash tests/loop.sh` or an edge commit in the background (as lesson L2 says) got `Hop not
  closed (I1)`; printing `STITCH NEEDED: accept execute` then is refused with `NOEVID` (no receipt yet), and printing
  `STITCH NEEDED: review spec+plan` while the spec critic still runs is refused with `NOSPECGATE`. The agent learns to
  ignore the nudge, and each such stop is a false `NOEDGE` event in L1's counts (since 2026-11-17). Make the Stop hook
  never demand an edge that its own later check would refuse, using evidence a script can check, not the reply's
  words: (1) while a live process holds `<git dir>/cascade-loop.lock` (`tests/loop.sh:207-219`; a lock whose holder
  is gone is broken, as there), the work is in flight: no nudge and no `NOEDGE`, a log line that `tests/patterns.sh`
  does not count; (2) with no work in flight, on GENERATE 05b with a red spec gate, or on EXECUTE with no loop
  receipt for this tree, the nudge names the unfinished step (finish the gate, or run the loop) instead of asking for
  the edge, and its log verdict is not `NOEDGE`. No verdict becomes weaker (I18): a hop with a green gate or a fresh
  receipt that ends with no edge line still gets the `NOEDGE` nudge, and `NOSPECGATE`, `NOEVID` and `NOHALTBLOCK` do
  not change. Done when a test shows that a stop while a live process holds the lock gets no nudge and no `NOEDGE`,
  that a stale lock (dead pid) gives the old verdict, that a red spec gate and a missing receipt each get the
  step-naming nudge and no `NOEDGE`, that a green gate or fresh receipt with no edge line still gets `NOEDGE`, that a
  red twin which trusts the reply's words ("waiting for the loop") lets an unfinished hop pass, and that `bash
  tests/enforcement.sh` stays green. Out of scope: background subagents (no lock a script can check), any change to
  when an edge is legal, and the cost of the gates themselves.
  Decision (human, 2026-11-16, asked in GENERATE): accepted t105 AC3, AC4 and AC6 assert "Hop not closed (I1)" and
  `NOEDGE` on fixtures with a red gate, which t108 reclassifies. Widen only those assertions to accept either nudge
  ("Hop not closed" + `NOEDGE`, or "Hop not finished" + `UNFINISHED`); a reply that wrote still never passes. Listed
  in the hop report.
