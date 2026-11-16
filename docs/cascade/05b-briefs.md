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
