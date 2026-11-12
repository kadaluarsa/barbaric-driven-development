# Stage 05b — t103-log-source — SPEC

## Problem and scope

`.cascade/decisions.log` records one line for each decision a layer makes (`tests/lib/decisions.py`). On 2026-11-12 it
held 3,497 lines: 2,872 `bash_guard`, 300 `dsharp`, 203 `stop_guard`, 61 `sign_ok`, 61 `hop_guard`, 53 `loop`. 1,796
lines arrived in bursts of five or more in the same second. Most bursts are acceptance-test fixtures, not agent
actions. The cause: `tests/enforcement.sh:38` runs each hook as `python3 -B "$L2/.claude/hooks/$1"` with no `cwd` in
the event, so `repo_root(os.getcwd())` resolves to the real checkout, and every denial the suite provokes
(`git push origin main`, `gh pr merge`, the signature-ledger probes) is written to the real log.

A report over this log learns from fixtures (the talk "Learning While You Sleep", AI Native DevCon London 2026: look
at tool calls and metadata, and choose which transcripts an analysis sees). t104 needs to tell real events from test
events. This slice adds a source field to each new line and tags the test runs.

This slice:

1. Appends `src=<test|agent|human>` to each new line, after the detail.
2. Sets the source from `BDD_LOG_SRC` when it is `test`, `agent` or `human`; else from the actor.
3. Tags test runs: `tests/enforcement.sh`, `tests/regress.sh` and `tests/barbar.sh` export `BDD_LOG_SRC=test`, and
   `tests/loop.sh` runs each goal line with `BDD_LOG_SRC=test`.
4. Makes the display readers (`decisions.tail`, the recall index's halt line, `tests/handover.sh`) strip the field and
   hide `src=test` lines.

Out of scope: rewriting or deleting old lines; the pattern report (t104); log rotation (unchanged: 2,000 lines kept
above 2 MB); the hooks' decisions themselves.

## Approaches considered

| Approach | Decision | Reason |
|---|---|---|
| Run the enforcement hooks from a scratch `cwd` so they never reach the real log | Rejected | It changes what T1–T101 test: several checks rely on the real checkout as the hook's root. It also leaves every other test path untagged. |
| A separate log file for tests (`.cascade/decisions.test.log`) | Rejected | The writer cannot know it runs in a test without the same signal, and two files split one timeline. A field in one file keeps the order. |
| A source column after the verdict (`ts actor verdict src detail`) | Rejected | `recall.halt` and other readers split by position; a new column shifts the detail and changes what `preserve.py` prints. |
| A trailing `src=<x>` field, set from `BDD_LOG_SRC` or the actor, stripped by display readers | **Chosen** | Positional readers (`bits[1]`, `bits[2]`) and the T40 greps (`hop_guard.*DENY.*src/x.kt`) keep working. Old lines stay valid. |

## Before vs after

Before:

```mermaid
flowchart LR
  E["tests/enforcement.sh hook() — cwd = real checkout"] --> R["record()"]
  A["agent's hook calls"] --> R
  H["human: sign_ok, SENDBACK"] --> R
  R --> L["decisions.log — one stream, no source"]
  L --> P["preserve tail, recall halt, handover — fixtures mixed in"]
```

After:

```mermaid
flowchart LR
  E["enforcement / regress / barbar export BDD_LOG_SRC=test; loop runs goal lines with it"] --> R["record()"]
  A["agent's hook calls (no env)"] --> R
  H["actor sign_ok or human"] --> R
  R --> L["decisions.log — '… src=test', '… src=agent', '… src=human'"]
  L --> P["preserve tail, recall halt, handover: field stripped, src=test hidden"]
  L --> T["t104 pattern report: counts src=agent and src=human only"]
```

## Benefits and trade-offs

| Item | Benefit | Cost or limit |
|---|---|---|
| Source field | t104 can count real events only. | Old lines read as `src=unknown`; the report must decide what to do with them. |
| Trailing position | No reader that splits by position changes; old and new lines parse the same way. | The field adds about 10 bytes per line. |
| Tagged suites | The enforcement suite, the regression suite, the farm and every goal line write `src=test`. | An acceptance test run by hand, outside those four, writes `src=agent`. USAGE.md says to export `BDD_LOG_SRC=test` for that. |
| Hidden test lines | The tail after a compact shows the last 12 real decisions, not fixture denials. | A human who wants the test lines reads the file. |
| Env override | A wrapper can tag its own runs. | Any process can set `BDD_LOG_SRC=human`. The log is a record, never a gate (`decisions.py` docstring), so no verdict depends on the field. |

## Decision contract

### The writer (`tests/lib/decisions.py`)

1. `record(root, actor, verdict, detail)` writes `{ts}  {actor:<11} {verdict:<7} {detail}  src={src}` — the line it
   writes today, then two spaces, then `src=` and the source. The detail is cut to 400 characters before the field is
   added, as today.
2. The source is the value of `BDD_LOG_SRC` when it is exactly `test`, `agent` or `human`. Otherwise it is `human` when
   the actor is `sign_ok` or `human`, and `agent` for every other actor.
3. `record` never raises, as today.
4. A new helper `source(line) -> str` returns the field's value, or `unknown` for a line with no field. A new helper
   `display(line) -> str` returns the line with a trailing `  src=<x>` removed.
5. `tail(root, n)` returns the last `n` lines that are not `src=test`, each through `display()`. The scan reads at most
   the last 2,000 lines, so `n` real lines may be fewer than `n` when the tail is all tests.
6. `decisions.py <root> --tail [n]` prints `tail()`. A new `decisions.py <root> --tail-all [n]` prints the last `n`
   raw lines, test lines and fields included.

### The readers

7. `tests/lib/recall.py` `halt()` skips `src=test` lines and prints the line through `display()`. Its positional test
   (`bits[2] in HALTS`) does not change.
8. `tests/handover.sh` prints `python3 -B tests/lib/decisions.py "$ROOT" --tail 5` in place of `tail -5` on the file.
9. `.claude/hooks/preserve.py` and `.claude/hooks/_common.py` do not change: they read through `decisions.tail`.

### Tagging test runs

10. `tests/enforcement.sh`, `tests/regress.sh` and `tests/barbar.sh` each `export BDD_LOG_SRC=test` near their top.
11. `tests/loop.sh` runs each goal line with `BDD_LOG_SRC=test` in that line's environment only (`tests/loop.sh:323`
    subshell, and the Gradle runner's child environment). The loop's own `loop PASS` record keeps the caller's source:
    an agent's loop writes `src=agent`.
12. A git hook, an agent hook and `tests/dsharp_strength.sh` set nothing: in an agent session they write `src=agent`,
    and inside a tagged suite they inherit `src=test`.

### Docs and release

13. USAGE.md gets `### B22. Where a log line came from (t103)`. `CHANGELOG.md` gets `## 3.5.5`. `VERSION`, the three
    manifests and `README.md` say 3.5.5.
14. The `decisions.py` docstring documents the field and `BDD_LOG_SRC`.

### Files that may change on EXECUTE

- `tests/lib/decisions.py`, `tests/lib/recall.py`, `tests/handover.sh`
- `tests/enforcement.sh`, `tests/regress.sh`, `tests/barbar.sh`, `tests/loop.sh` (items 10–11 only)
- `USAGE.md`, `CHANGELOG.md`, `VERSION`, `README.md`, the three plugin manifests
- `docs/cascade/goal.md`, `docs/cascade/regress.md`, `docs/cascade/05b-briefs.md`,
  `docs/cascade/05b-briefs-archive.md` (by `tests/goal.sh` only)

### Files that must not change on EXECUTE

- `.claude/hooks/*.py`, `.githooks/*`, `tests/dsharp_strength.sh`
- `tests/ac/*` other than the oracle, `tests/inv/*`, `docs/cascade/envelope.md`, `docs/cascade/hop-state.md`
- `.cascade/decisions.log` (no rewrite of old lines)

## Acceptance criteria and the frozen oracle

The oracle is `tests/ac/t103_log_source.sh`. It uses scratch git repos and needs `git` and `python3` only.

| AC | Requirement | How the oracle proves it |
|---|---|---|
| AC1 | The writer adds the field (items 1–3). | `record` with `BDD_LOG_SRC=test` ends `  src=test`; actor `sign_ok` and actor `human` end `src=human`; actor `hop_guard` ends `src=agent`; `BDD_LOG_SRC=bogus` gives `src=agent`; the text before the field equals the line the code at `0a3d5ce` writes for the same call (timestamp masked). |
| AC2 | A real hook call is tagged (items 2, 12). | `bash_guard.py` fed `git push origin main` in a scratch repo writes a `DENY` line ending `src=agent`; with `BDD_LOG_SRC=test` in its environment, `src=test`. |
| AC3 | Old lines still read (items 4, 7). | A log of `0a3d5ce`-format lines: `source()` is `unknown`, `display()` returns each line unchanged, `tail()` returns them all, and `recall.halt` finds an old `HALT` line. |
| AC4 | Display output does not change for a log with no test lines (items 5, 8, 9). | For the same decisions, `preserve.py` (compact, on GENERATE) and `tests/handover.sh` print the same "Last decisions" lines with the new code and a new-format log as `0a3d5ce`'s code with an old-format log. |
| AC5 | Test lines are hidden from display (items 5, 7). | With `src=test` lines after the real ones (a test `HALT` included), `tail()`, `preserve.py`'s tail and `recall.halt` show only the real lines; `--tail-all` shows all of them. |
| AC6 | The loop tags goal lines, not itself (item 11). | A scratch repo on EXECUTE with a goal line that calls `decisions.py … t103probe` runs `tests/loop.sh` to `LOOP 1/1`: the probe line ends `src=test`, and the loop's `loop PASS` line ends `src=agent`. |
| AC7 | The suites export the tag (item 10). | `tests/enforcement.sh`, `tests/regress.sh` and `tests/barbar.sh` each hold a line `export BDD_LOG_SRC=test` before their first test; a scratch `regress.md` with one line that calls `decisions.py` writes `src=test` through `tests/regress.sh`. |

On the unfixed code, AC1, AC2, AC3, AC5, AC6 and AC7 fail: no line has a field, and `source()` and `display()` do not
exist (AC3 fails at that call; its old-line halt check is the guard). AC4 passes there: it is a guard that the fixed
code must not break.

## Laws and boundaries

- `NO LAW IN FORCE`: this repo declares no D#.
- No gate reads the log or the field (`decisions.py`: "No gate reads it").

## Evidence limits

- The counts are from this repo on 2026-11-12. The cause of the bursts is inferred from `tests/enforcement.sh:38` and
  the matching detail texts; this slice does not re-run the suite to attribute each old line.
- `BDD_LOG_SRC` is not authenticated. The field is a label for reports, not evidence.
