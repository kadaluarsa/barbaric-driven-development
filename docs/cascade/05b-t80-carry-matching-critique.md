# Stage 05b — t80-carry-matching — CRITIQUE

Written by a fresh read-only critic subagent with the pipeline's critic brief; rows committed verbatim
before any answer.

## Brief

| C# | severity | finding | evidence |
|---|---|---|---|
| C1 | high | The problem may not exist in the one real product cited. In dream-camera, 62 of 63 goal lines already match exactly, and filter matching would add 0 carried lines and 0 fewer dropped lines. The spec's figure ("12 of 51 Gradle lines … strict subset of another line's") compares lines inside a single goal version. It does not measure the across-slice carried/dropped mismatch this slice changes, so it does not show a cost. | `python3 -B /private/tmp/claude-503/-Users-justlogout-Projects-personal-barbaric-driven-development/754d7a5e-b5e7-49a2-b949-39f15d828281/scratchpad/e1.py` → `exact carried 62 matched by filters 0 total 63` / `dropped exact 0 dropped with covers 0`; `docs/cascade/05b-t80-carry-matching.md:27-30` |
| C2 | medium | The brief's "fold" ("fold one slice's filter into another slice's line") is the mixed case. Its Done says folds are "carried out", but t78 carry-out deletes a carried line from the hop's goal, which would take this slice's new tests out of its own loop. The spec redefines fold as "old filters only" and calls the mixed case "Ask 1 … *Default taken*". This is a departure from the brief's Done criterion and should be raised as one, not filed as a defaulted ask. | `docs/cascade/05b-briefs.md:386-387,392-393`; `tests/lib/carry_out.py:98-104`; `docs/cascade/05b-t80-carry-matching.md:65,187-188` |
| C3 | medium | Scope creep. The README "Reading the codes" item (S-CM4, AC8, and a plan item) is not in the t80 brief. Its only source is a chat quote. AGENTS rule 8 says chat residue is not a decision, so this unrelated work rides inside a matching slice. | `docs/cascade/05b-briefs.md:384-395` (no README); `docs/cascade/05b-t80-carry-matching.md:12-14,200` |

## Spec

| C# | severity | finding | evidence |
|---|---|---|---|
| C4 | high | The claim "never changes a verdict … Only counts and the notice change" is false. The carried count feeds t77's cap, which prints `LOOP REFUSED` and exits 3. A goal that runs today can be refused after t80. No AC covers a filter-matched line pushing the count over the cap, and E1 does not measure how close any product is to the cap. | `tests/loop.sh:179-186`; `docs/cascade/05b-t80-carry-matching.md:76-77,116,199` |
| C5 | high | `line_match.py` would be a third Gradle/xcodebuild parser, and weaker than the existing ones. `gradle_runner.parse` already ties each `--tests` to the task before it, treats `app:test` and `:app:test` as one task, rejects shell operators (`&&`, `\|`, `;`), and knows which flags take a value (`-x`, `--console`). `test_count.gradle_tasks` also handles `--tests=`. The spec's flat set of tasks plus flat set of filters over-matches: `:a:test --tests X :b:test --tests Y` equals the version with the filters swapped; `-x :m:lint` puts `:m:lint` into the task set; a line chaining two `./gradlew` calls with `&&` gets a shape. | `tests/lib/gradle_runner.py:73-120`; `tests/lib/test_count.py:46-62`; `docs/cascade/05b-t80-carry-matching.md:81-86` |
| C6 | medium | The red twins only test under-matching (`same`/`covers` always False). Nothing tests over-matching: a matcher that ignores the base, carries the mixed line (AC3), or checks `covers` in the wrong direction. Over-matching is the risky direction, because it hides a test that no longer runs ("not dropped") and inflates the cap count. | `docs/cascade/05b-t80-carry-matching.md:139` |
| C7 | medium | The AC harness contradicts §1. If fixture lines are "`echo`-prefixed Gradle/Xcode shapes", their first word is `echo`, so they have no shape and fall back to exact matching. AC1–AC6 cannot then pass unless the parser strips `echo`, which would be a hack that exists only for the test. | `docs/cascade/05b-t80-carry-matching.md:81,86,122-123` |
| C8 | medium | Carried and dropped use different rules. Carried uses "⊆ union of older lines"; dropped and already-there use a single line's `covers`. A split (older `{X,Y}` becomes current `{X}` and `{Y}`) is counted as carried, yet the older line is also reported dropped, and carry-out appends it to the suite a second time. No AC covers splits. | `docs/cascade/05b-t80-carry-matching.md:54-55,92-93,99-101` |
| C9 | low | The output protocol for the new count is not specified. `goal_history.py`'s `N` row is read with `read -r kind a b c d`, so a sixth tab column would be folded into `origins`. The plan does not say where `m` goes, or that the docstring's row list changes. | `tests/loop.sh:171-174`; `tests/goal.sh:68-70`; `tests/lib/goal_history.py:17-18` |
| C10 | low | The "After" diagram does not match the plan. Node F shows "carried" (a question about the current line) and "not dropped" (a question about the older line) as mutually exclusive branches of one decision, though one pair can satisfy both. It also leaves out §1's non-empty-filters condition, the carry-out `already there` path, `test-without-building`, and Xcode's project/workspace in the base. | `docs/cascade/05b-t80-carry-matching.md:51-56` vs `:84-88,99-101` |

## Dispositions

| C# | DISPOSITION |
|---|---|
| C1 | human — re-run by the author, confirmed: across dream-camera's 100 earlier goal versions, filter matching changes 0 of 63 lines. Build the matcher anyway as prevention (Plan B), or descope t80 to the README's "Reading the codes" plus a measurement note (Plan A, recommended)? Spec v2 Ask 0. |
| C2 | human — the brief's "fold" is the mixed case, and carrying it out would move this slice's new tests out of its own loop. If Plan B: keep a mixed line as this slice's (not carried, its old lines not dropped), or follow the brief and carry it out? Spec v2 Ask 1, raised as a departure rather than a default. |
| C3 | fixed — the README item is now recorded in the brief (`05b-briefs.md`, under t80, "Added 2026-10-25 by the human") instead of resting on a chat quote. |
| C4 | fixed — the line and the benefits table say t80 (Plan B) can change a verdict through t77's cap; AC6c asserts a reworded set of 11 carried lines is refused; E1 reports each product's distance to the cap. |
| C5 | fixed — §1: no new parser; Gradle lines go through `gradle_runner.parse` (per-task filters, `app:test` = `:app:test`, value flags, shell operators rejected), Xcode lines through `test_count.py`'s tokeniser; a shape keeps a per-task map of filters. |
| C6 | fixed — the red twins now include over-matching: a matcher ignoring the base, one flattening the per-task map, one with the union reversed; each shown red. |
| C7 | fixed — the AC fixture uses real `./gradlew` / `xcodebuild` shapes run by stubs (writing one executed case so t79's guard passes); no `echo` prefix. |
| C8 | fixed — §3: carried and dropped both use the union rule (each task's filters ⊆ the union across lines), so a split is neither dropped nor carried out twice; AC6b covers it. |
| C9 | fixed — §2: the count is a new `M\t<m>` row; the `N` row and its readers are unchanged. |
| C10 | fixed — the after-diagram now asks the carried question and the dropped question separately, with the non-empty-filters condition and the `already there` path. |
