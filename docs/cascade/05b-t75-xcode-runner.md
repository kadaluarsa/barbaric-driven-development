# Stage 05b — t75-xcode-runner — SPEC

## User story IDs from the PRD

BDD's product is the cascade itself; the stories this slice serves:

- **S-XR1** — As an iOS/macOS product owner, consecutive `xcodebuild test` lines in `/goal` share one build instead of
  building on every call. Each line still runs in its own test process, so a line's verdict is what it would be alone.
- **S-XR2** — As a law author on Xcode, I can sign `DSHARP_XCODE_HARNESS: on` and my laws are proven from one build
  per scheme and destination, not two builds per law. A RED or THEATER verdict is still the law's own two commands'.
- **S-XR3** — As a law author, a red twin written `INV_MUTANT=<id> xcodebuild …` tells me why it can never fail:
  Xcode passes only `TEST_RUNNER_`-prefixed variables to tests.
- **S-XR4** — As the operator, a hung `xcodebuild` in the fast path costs a bounded amount of time and never becomes a
  verdict. (A line run alone can still hang, as today: U3.)

## The problem, stated as cost

Every Xcode line in `/goal`, and both commands of every Xcode law, is a separate `xcodebuild test` call. Each call
pays tool start, build planning, package resolution and an incremental build check before one test runs. Measured
this hop (E0) on Xcode 27.0, an iOS 26.5 simulator, and a Swift-package fixture whose build has a 5s phase standing in
for a real app's script phases and planning:

| Call | Cost |
|---|---|
| `xcodebuild test -only-testing:WalletTests/BalanceTests/testDebit`, nothing changed | **8s, every call** |
| `build-for-testing` once | 8s |
| then `test-without-building -only-testing:…` | **2–3s per call** |
| the same `test` call on a trivial package with no slow phase | 2–3s |

So in this fixture the build check is the cost: a goal of N Xcode lines and M laws pays it N + 2M times today, and
`test-without-building` pays it once. What E0 did **not** measure (C1): a fixture with a host app, where every call —
`test-without-building` included — also installs and launches the app. The brief's "30–90s per call" is not measured
here and is not claimed. The first EXECUTE task (E0b) measures an app-hosted fixture; if the build check there is not
the larger part of a call, the slice stops at E0b with a report instead of building a runner that saves little.

E0 also measured four hazards that decide the design:

| Hazard (E0) | What happened | Consequence |
|---|---|---|
| Shared process | `-only-testing:A -only-testing:B` in one call ran both classes in **one process** (one pid); a class that passes alone **failed** after another class set static state | Merging lines into one test run changes verdicts. The reverse — fails alone, passes merged — is a false PASS nobody re-checks (C5). No merged mode in this slice |
| Stale binary | After a source edit, `test-without-building` ran the **old** binary: a false pass one way, and, after the edit was reverted, a false failure the other | The shared build must be keyed to the sources and rebuilt when they change |
| Mutant reach | `INV_MUTANT=D1 xcodebuild …` did **not** reach the test (rc 0); `TEST_RUNNER_INV_MUTANT=D1` did (rc 65) | An unprefixed twin always passes: the law is THEATER, and should say why |
| Hang | After its tests failed, `xcodebuild test` **did not exit for 9+ minutes** and had to be killed | The fast path needs a wall-clock bound, and a timeout proves nothing |

The `.xcresult` bundle holds what a verdict needs: `xcrun xcresulttool get test-results tests` lists each test case
with its `nodeIdentifier` (`BalanceTests/testDebit()`), `result` (`Passed`, `Failed`, …) and failure messages (E0).

No locked decision or signed law conflicts with the brief (both `<EDIT>` blocks hold placeholders; `DSHARP 0/0`).

## Before vs after

Before:

```mermaid
flowchart TD
  L[loop.sh] --> G{plain Gradle lines?}
  G -->|yes| GR[gradle_runner: batched build]
  G -->|no| A[every other line alone, verbatim:<br/>each xcodebuild test builds again]
  D[dsharp_strength.sh] --> H[law_harness: Gradle laws only]
  D --> T[every Xcode law: check and break,<br/>two xcodebuild test calls, two builds]
  T --> TH[INV_MUTANT twin never reaches the test:<br/>THEATER, with no reason given]
```

After:

```mermaid
flowchart TD
  L[loop.sh] --> R{segment of runner lines?}
  R -->|Gradle| GR[gradle_runner, unchanged]
  R -->|xcodebuild test, same build key, 2+ lines| X[xcode_runner]
  R -->|anything else| A[alone, verbatim, as today]
  X --> V{Xcode version verified?}
  V -->|no| A
  V -->|yes| K{a build for this key and this<br/>source fingerprint already in this run?}
  K -->|yes| W
  K -->|no| B[build-for-testing, fingerprint recorded]
  B --> S{fingerprint unchanged by the build itself?}
  S -->|no: the build writes into the tree| SA[key marked self-modifying:<br/>its lines run alone for the rest of the run]
  SA --> A
  S -->|yes| W[test-without-building with the line's own<br/>-only-testing: its own test process]
  W --> F2{fingerprint unchanged since the build?}
  F2 -->|no| A
  W --> P{.xcresult proves the line passed,<br/>within the time bound?}
  P -->|yes| PASS[PASS]
  P -->|no, or timeout, or not understood| A
  D[dsharp_strength.sh] --> XH{DSHARP_XCODE_HARNESS: on signed<br/>and the law has the Xcode shape?}
  XH -->|yes| XB[one build per key; per law: check run,<br/>then TEST_RUNNER_INV_MUTANT run]
  XB --> XG{.xcresult: check passed, mutant failed on<br/>failing tests only, same cases?}
  XG -->|yes| GREEN[GREEN]
  XG -->|no| T[the law's own two commands, as today]
  XH -->|no| T
  T --> TH[unprefixed INV_MUTANT twin: THEATER<br/>plus the reason and the fix]
  MG[merge gate] --> T
```

## Benefits and trade-offs

| | Today | After t75 |
|---|---|---|
| N Xcode lines, nothing changed | N builds (8s each in E0) | 1 build per key per run + N test runs (8s + 2–3s each in E0, no host app; E0b measures one) |
| The runner's first build | — | a cold build into its own `.cascade/xcode/` DerivedData (gitignored), not the IDE's (C6) |
| A line's verdict | its own call | identical: own process, same build key, fresh binary, PASS only from `.xcresult` |
| Every FAIL | its own call | still its own call: the runner never reports a FAIL |
| M Xcode laws | 2M builds | signed: one build per key + 2M test runs; unsigned: as today |
| Unprefixed `INV_MUTANT` twin | THEATER, unexplained | THEATER with the reason and `TEST_RUNNER_INV_MUTANT` |
| A hung `xcodebuild` in the fast path | n/a | killed after `BDD_XCODE_TIMEOUT` (default 600s), proves nothing, the line runs alone — where it can hang again, as today (C8, U3): the bound adds up to 600s to such a line, it does not cure it |
| A build that writes into the tree | n/a | detected once (the fingerprint moves during the build); that key's lines run alone for the run, logged (C4) |
| An Xcode version not verified | every line alone | every line alone (C7) |
| Escape hatch | — | `BDD_LOOP_RUNNER=shell` (all runners), `DSHARP_HARNESS=off` (all harnesses) |
| Not chosen: merging lines at all (the brief allowed it signed) | — | E0: classes share one process. Fail-alone/pass-merged is a false PASS nothing re-checks (C5); left to a later slice that can prove it safe |
| Not chosen: parallel testing (`-parallel-testing-enabled`) | — | cloned simulators, ordering and shared-resource races; out of scope |
| Not chosen: trusting `test-without-building`'s exit code | — | a hang, a crash and a stale binary all produce misleading exit codes; only `.xcresult` proves |
| Cost | — | a second runner, macOS CI time, and the build key + fingerprint bookkeeping |

## What the slice adds — and the line it must not cross

The line: **the runner and the harness may only report what they prove from a `.xcresult` produced by a build of the
current sources.** Everything else runs the user's own command, verbatim. The merge gate never uses either.

### 1. Which lines (`tests/lib/xcode_runner.py: parse`)

A line is taken when it is a plain `xcodebuild` call with:

- exactly one action, `test`;
- exactly one `-scheme`, at most one of `-workspace`/`-project`, exactly one `-destination` whose value names one
  device (`id=…`, or `platform=…,name=…`; `generic/…` and repeated `-destination` are refused);
- only these options otherwise: `-configuration`, `-testPlan`, `-sdk`, `-derivedDataPath` (refused: the runner owns
  its own), `-only-testing:X` and `-skip-testing:X` (repeatable), `-quiet`, and `KEY=VALUE` build settings;
- no shell syntax (the t62 rule) and no `-resultBundlePath` (the runner writes its own).

Anything else runs alone. The **build key** is the line minus its action and its `-only-/-skip-testing` selectors.
A runner segment, as in t62, is the longest run of consecutive taken lines; a segment never reaches past a line the
runner does not take, so a shell line always runs between two segments, never inside one (C3).

**Verified Xcode only (C7).** `xcodebuild -version` is read once per run; `VERIFIED = ("27.0", "27.1")` (≥ and <) in
`xcode_runner.py`, widened only by a stress run on the new version, as t62's Gradle range is. Any other version, or no
readable version, runs every line alone.

### 2. How a line is proven (`xcode_runner.py`)

For each build key in the segment:

1. **Once per key per run (C2).** `.cascade/xcode/<key hash>/built` records the fingerprint (`cascade_worktree_sha`,
   t59; `.cascade/` is gitignored, so the runner's own files never move it) of the last successful build in this loop
   run. If it equals the current fingerprint, the build is reused — a later segment after a shell line that changed
   nothing pays no build. Otherwise: `xcodebuild <build key> build-for-testing -derivedDataPath
   .cascade/xcode/<key hash>`, with the fingerprint taken before it starts. A failed build proves nothing: its lines run
   alone.
2. **A build that moves the tree (C4).** If the fingerprint right after a successful build differs from the one taken
   before it (a build phase bumped a version, ran a formatter, wrote `Package.resolved`), the key is marked
   self-modifying in `.cascade/xcode/<key hash>/unstable` with the changed paths, and every line of that key runs alone
   for the rest of the run. There is never a second build attempt in a run for that key.
3. Per line, in goal order: `xcodebuild <build key> test-without-building <line's selectors> -resultBundlePath
   .cascade/xcode/<key hash>/<line>.xcresult`, bounded by `BDD_XCODE_TIMEOUT` (default 600s; on timeout the process
   group is killed; E0b checks that this also ends the simulator-side test process). If the fingerprint changed during
   the line's run (a test wrote into the tree), that line is not proven and the next line of the key rebuilds first.
4. A line is **PASS** only when all of these hold: the call exited 0 within the bound; the `.xcresult` exists and
   `xcresulttool get test-results tests` parses; at least one `Test Case` node ran; no node has `result` `Failed`; and
   every test case that ran is one the line's own selectors select (no foreign class, so no shared process with
   another line's tests). Anything else — including a result the runner does not recognise — proves nothing, and the
   line runs alone through today's code path.

The runner speaks t62's protocol to `loop.sh` (`<i>\tPASS\t<summary>`, `E`, t69's `T`/`M`), with one addition: its `S`
line carries a third field, `xcode`, so the `loop:` summary says "xcode build(s)" for them (C10). A Gradle runner's `S`
line, and so the Gradle wording, is unchanged. It never prints FAIL.

**The simulator (C2).** The runner does not boot, shut down or erase simulators. `xcodebuild` boots the destination when
it needs to and leaves it booted (E0: a fresh device's first call 12s, the next 10s; a long-booted one 2–3s), which is
what a line run alone does too.

**No merged mode (C5).** Every line gets its own `test-without-building` and its own process. The brief allowed a
signed merge; it is left out because a test that fails alone can pass merged (another class sets the state it needs),
a false PASS nothing re-checks. A later slice may add it with a proof rule for that direction.

### 3. `loop.sh`

Generalise the runner hook from Gradle only to a table: a line matching `^(\./gradlew|gradle) ` starts a Gradle
segment (unchanged), a line matching `^xcodebuild ` starts an Xcode segment. One segment is one runner; a segment never
mixes tools. With no Xcode line, `loop.sh` output is byte-identical to `d89438e` (AC9).

### 4. The law harness (`tests/lib/xcode_harness.py`, signed)

On only when `- DSHARP_XCODE_HARNESS: on` is signed and committed (t64's rule) and `DSHARP_HARNESS` is not `off` (the
merge gate always sets it). A law is eligible when its `check:` is a line §1 takes with at least one `-only-testing`
selector, and its `break:` is exactly `TEST_RUNNER_INV_MUTANT=<id> <check>`. A `break:` that patches code (`git apply
tests/inv/mutants/D7.patch && …`) is not eligible and keeps its own two commands (C2), as on t64. Per build key: one `build-for-testing`.
Per law, sequentially: the check run, then the mutant run with `TEST_RUNNER_INV_MUTANT=<id>` in the environment, each
its own `test-without-building` with its own `.xcresult`. **GREEN** only when (t64's §4 conditions): the check run
passed with at least one test case; the mutant run failed, its `.xcresult` shows only test-case failures (no build,
launch or crash failure); both ran the same test cases; every case that failed in the mutant passed in the check; and
the fingerprint did not change across the two. It prints only GREEN; every other law is scored by its own two
commands, exactly as today. Laws are never run concurrently.

### 5. The THEATER reason (`dsharp_strength.sh`)

When a THEATER law's `break:` contains `INV_MUTANT=` before `xcodebuild` without the `TEST_RUNNER_` prefix, its line
gains `  (Xcode passes only TEST_RUNNER_* variables to tests: write TEST_RUNNER_INV_MUTANT=<id> — USAGE.md §B16)`.
The verdict stays THEATER (I18).

### 6. Docs and CI

USAGE.md §B16 (Xcode products: what is batched, the verified range, the law shape, the timeout and what it does not
fix); CONTROL-LINE.md T75; CHANGELOG under `## Unreleased`.

- **Gitignore (C6).** `install.sh` adds `.cascade/xcode/` to the product's ignore list (beside `.cascade/loop/`,
  `.cascade/gradle/`, `.cascade/verdicts/`), and the pack's own `.gitignore` gets it too.
- **Lint (C10).** `tests/lint.sh`'s envelope-only decision list gains `DSHARP_XCODE_HARNESS`.
- **CI (C9).** A new workflow, `.github/workflows/xcode-self-check.yml`, so `pack-self-check.yml` is untouched: on
  `pull_request` with `paths:` the Xcode files (`tests/lib/xcode_*`, `tests/stress/xcode_runner.sh`, `tests/loop.sh`,
  `tests/dsharp_strength.sh`), and on a nightly `schedule`. It selects a pinned Xcode (`xcode-select`) and fails loudly
  if that version is not on the image; the stress script asserts that the runner batched (one build for its four
  lines), so a version outside the range cannot pass by running everything alone.

## What the slice must not touch

- t62's Gradle runner and its contract; t64–t69's rules; the merge gate's conditions (it already sets
  `DSHARP_HARNESS=off` and never runs the loop).
- Any user command: lines run alone and every law's own `check:`/`break:` stay verbatim.
- The alone path's lack of a timeout (U3).

## Acceptance criteria

`tests/ac/t75_xcode_runner.sh` uses an `xcodebuild` stub that plays recorded behaviour (selection, process sharing,
`.xcresult` JSON, exit codes, a hang), as `gradlew-stub.py` does for Gradle; `tests/stress/xcode_runner.sh` makes the
same claims on real Xcode.

- **AC1 — which lines.** Taken: the §1 shape. Alone: two actions, `build`, `clean`, a second `-destination`,
  `generic/platform=iOS`, `-derivedDataPath`, `-resultBundlePath`, shell syntax, and every line when the stub reports an
  unverified Xcode version (C7). A single line, or a segment whose lines all have different build keys, makes no batched
  build. A segment stops at the first line the runner does not take.
- **AC2 — the verdict matrix.** Every line's verdict equals the line run alone, for: all pass; a failing test; a
  compile error; a selector that matches nothing; a test that crashes the host; a class that fails only after another
  class ran in its process (E0's case); a hang.
- **AC3 — the fingerprint (C3, C4).** Goal `X1, X2, shell-edit, X3, X4` (one build key): segment one builds once;
  the shell line edits a source; segment two rebuilds before X3 instead of reusing; with a shell line that edits
  nothing, segment two reuses the build (one build in the run). A stub build phase that writes a tracked file marks the
  key self-modifying: one build attempt, every line of the key alone, the reason logged. The stub counts builds.
  **Red twin:** a runner copy that reuses a build without comparing fingerprints reports PASS for X3 against the stale
  binary, where X3 alone fails (E0's stale-binary case).
- **AC4 — proof only from `.xcresult`.** **Red twin:** a runner copy that reads only the exit code reports PASS for a
  call whose `.xcresult` has a `Failed` test (or is missing).
- **AC5 — never merged (C5).** Two lines of one key always run as two `test-without-building` calls; a goal whose
  envelope signs `LOOP_XCODE_MERGE: on` behaves the same (no such switch exists).
- **AC6 — the harness.** Unsigned: every Xcode law runs its own two commands. Signed: eligible laws are GREEN from one
  build per key; RED, THEATER, a launch failure in the mutant, and a mutant that ran other cases are each left to the
  two commands with that verdict. `DSHARP_HARNESS=off` (the merge gate) uses neither. **Red twin:** a harness that
  trusts the mutant's exit code alone proves a RED law GREEN.
- **AC7 — THEATER reason.** An `INV_MUTANT=D1 xcodebuild …` twin prints THEATER with the reason; the same law with
  `TEST_RUNNER_INV_MUTANT` is GREEN.
- **AC8 — the bound.** A stubbed hang is killed after `BDD_XCODE_TIMEOUT`, proves nothing, and the line runs alone.
- **AC9 — parity.** With no `xcodebuild` line and no Xcode law, `loop.sh` and `dsharp_strength.sh` output equals
  `d89438e` byte for byte; with `BDD_LOOP_RUNNER=shell` too. With Xcode lines, the `loop:` line says "xcode build(s)"
  (C10). `install.sh` ignores `.cascade/xcode/`, and after a stress run `git status` is clean (C6).
- **E1 — measured (stress).** On the E0 fixture with a 5s build phase **and** E0b's app-hosted fixture: 4 lines and 6
  laws, before/after, first and unchanged pass, with identical verdicts; in the EXECUTE report and the CHANGELOG,
  including a row that did not improve.

Gate: `bash tests/ac/t75_xcode_runner.sh`, `bash tests/enforcement.sh` (T75), the t56–t69 tests, lint; the stress
script on macOS CI.

## Laws

`bash tests/dsharp_strength.sh` prints `DSHARP 0/0`: NO LAW IN FORCE in this repo. The slice changes how Xcode lines
and laws are run, never what they mean; nothing it adds reaches the merge gate.

## E0b — the gate, measured at the start of EXECUTE (2026-10-23)

An app-hosted fixture generated with xcodegen (an iOS app target, a unit-test bundle hosted in it, an optional
pre-build script phase), Xcode 27.0, iOS 26.5 simulator, three calls each, nothing changed between calls:

| Fixture | `xcodebuild test -only-testing:…` | `test-without-building -only-testing:…` | Saved per call |
|---|---|---|---|
| App-hosted, no script phase | 3s (9s on the first, cold call) | 2–3s | ~0–1s |
| App-hosted, a 5s script phase | 8s | 2–3s | ~5s |

Installing and launching the host app costs about 2s per call in both paths. What `test-without-building` saves is the
project's own per-build work — script phases, build-tool plugins, code generation, package checks — and nothing else.
The gate ("if the build check is not the larger part of a call, stop") **fails for a plain app and passes for one
with per-build phases**; this fixture cannot say which a real product is. EXECUTE stopped here, with no product code,
for the human to decide: measure the real app (two commands, below) and proceed only if its per-call saving is worth a
runner, or send the slice back.

    time xcodebuild test -scheme <S> -destination <D> -only-testing:<Target/Class>             # run twice, take the 2nd
    xcodebuild build-for-testing -scheme <S> -destination <D>
    time xcodebuild test-without-building -scheme <S> -destination <D> -only-testing:<Target/Class>

# Stage 05b — PLAN

## Goal

EXECUTE adds `tests/lib/xcode_runner.py` (parse, build key, fingerprint, `.xcresult` proof, bound), a runner table in
`loop.sh`, the signed `xcode_harness.py`, the THEATER reason, an `xcodebuild` stub, the AC and stress scripts, T75,
docs and a macOS CI job.

## In scope this execute

- [ ] E0b on real Xcode, before code — **a gate (C1):** an app-hosted fixture (a host app plus unit tests), timed
      per-call `test` vs `test-without-building`; if the build check is not the larger part of a call there, stop
      and report. Also: a selector that matches nothing (exit code and `.xcresult`); a test that crashes the host;
      whether `build-for-testing` fails on a compile error in a test target the line does not select while `test
      -only-testing` alone passes (if so, those lines run alone: safe, slower); the `.xcresult` shape for a launch
      failure; `-quiet`'s effect; whether `test-without-building` also hangs after failures, and whether killing its
      process group ends the simulator-side test process (C8).
- [ ] `tests/lib/xcode_runner.py`, `tests/lib/xcode_harness.py` (new).
- [ ] `tests/loop.sh` — the runner table.
- [ ] `tests/dsharp_strength.sh` — the Xcode harness call (as t64's) and the THEATER reason.
- [ ] `tests/ac/fixtures/xcodebuild-stub.py` and an `xcrun` stub for `xcresulttool` and `-version` (C9);
      `tests/ac/t75_xcode_runner.sh` (AC1–AC9, three red twins); `tests/stress/xcode_runner.sh` (AC2, AC3 and E1 on real
      Xcode); `tests/enforcement.sh` T75.
- [ ] `install.sh` and `.gitignore` (`.cascade/xcode/`), `tests/lint.sh` (`DSHARP_XCODE_HARNESS`), `tests/loop.sh`
      summary wording (C6, C10).
- [ ] `USAGE.md` §B16, `CONTROL-LINE.md` T75, `CHANGELOG.md` (Unreleased), `.github/workflows/xcode-self-check.yml`.
- [ ] `docs/cascade/goal.md` for the EXECUTE hop.

## Out of scope this execute

- Merging lines into one test run (C5); `-parallel-testing-enabled`; UI tests' extra device state; a timeout on the alone path; t65 cache keys for Xcode
  (path-based keys already apply); a nightly split for non-Gradle laws (a separate brief).
- A version bump (t69 shipped 2.7.0; t75 lands under `## Unreleased`).

## Definition of done

- `bash tests/ac/t75_xcode_runner.sh` exits 0 and the three red twins are shown to go red.
- `bash tests/stress/xcode_runner.sh` passes on this machine's Xcode and in the macOS CI job, with E1's table.
- `bash tests/enforcement.sh` exits 0 with T75; t56–t69 stay green; AC9 parity is byte-identical.

## Risks / UNKNOWNs that still block

- **A1 — the binary is the sources.** A PASS rests on: same build key, same source fingerprint, and the test
  process launched from that build. A build that reads untracked state outside the repo (a remote package that moved
  on, a system tool upgraded mid-run) could differ; FAIL is always re-run alone.
- **U1 — stub fidelity.** The AC stub replays E0's recorded behaviour; the stress script on real Xcode is the check
  that the stub is honest, as t62's was.
- **U2 — macOS CI cost.** macOS runners cost more minutes than Linux and need a simulator runtime; the separate
  workflow runs on PRs that touch the Xcode files, and nightly (Ask 4).
- **U3 — the alone path can still hang (C8).** E0's 9-minute hang came after failed tests, and a line run alone can
  hit it again after the fast path timed out: the bound adds up to `BDD_XCODE_TIMEOUT` to such a line, it does not
  cure it. Bounding the alone path changes today's behaviour for every tool; it is left out and named here, and is a
  candidate brief.
- **U4 — Xcode versions.** Verified on what E0b and CI measure (27.0 here); other versions run every line alone, as
  t62 does for unverified Gradle.

## Ask of you

1. **The loop runner is on by default** for Xcode lines (one build per key, each line in its own process), as t62's
   exact mode is for Gradle. *Default taken.*
2. **The law harness needs your signature** (`DSHARP_XCODE_HARNESS: on`), as t64's does. *Default taken.*
3. **No merged mode in t75** (C5) — the brief allowed it signed; it is dropped because its failure is a false PASS
   nothing re-checks. *Default taken.*
4. **A separate macOS workflow** (`xcode-self-check.yml`) on PRs that touch the Xcode files, and nightly, with a pinned
   Xcode. *Default taken.*
5. **Verified Xcode range starts at what E0b and CI measure** (27.0 here); other versions run alone. *Default taken.*

## Invariants this hop

- PRESERVE run: no
- /goal set to: n/a — GENERATE; EXECUTE's goal is AC1–AC9 + T75 + the t56–t69 tests + lint
- /model /effort: as set by the session
- /plan: skipped — this document is the plan
- INVARIANTS I1–I18: held; no unsigned setting can change a verdict
- Skills: none invoked; brainstorming skipped (brief signed into 05b-briefs.md; gaps are Asks 1–5)
- E0: measured this hop in a scratch Swift package (Xcode 27.0, iOS 26.5 simulator); no product code written
- critique: C1–C10 answered in `05b-t75-xcode-runner-critique.md` (spec v2)
- reads: AGENTS.md, hop-state.md, envelope.md, 05b-briefs.md (t75), loop.sh, dsharp_strength.sh, gradle_runner.py,
  law_harness.py, gradle_tuning.py, cascade.sh, the t62 and t64 specs
