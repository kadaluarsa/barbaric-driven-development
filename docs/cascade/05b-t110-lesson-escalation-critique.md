# Stage 05b — t110-lesson-escalation — spec critique

Rows below are the critic's, verbatim (a fresh read-only subagent, 2026-11-24).

## Brief

| C# | severity | finding | evidence |
|---|---|---|---|
| C1 | medium | The rule `a >= 2` ignores the before-rate. A lesson can print `WORKING` on its `LESSON` line and then `ESCALATE … a prompt line is not enough` on the next line. The oracle pins this result. Take the real L1: its before-rate is 0.31/hop. If the lesson cut that rate by a third, it would still log about 2 events in 10 hops and escalate. The brief asks for "at least 2 events", so the brief causes this, not only the spec. The human should decide whether a WORKING lesson may escalate. | `tests/ac/t110_lesson_escalation.sh:150` `(9, 2, 1, 3, "WORKING", True)`. Run `bash <clone>/tests/patterns.sh --root . --propose` and it prints `LESSON L1  stop_guard NOEDGE  before: 14 in 45 hops (0.31/hop)` |
| C2 | low | The spec adds two conditions the brief does not state: no ESCALATE when the mark is SETTLED, and `hb > 0` in the rate branch. The human decision recorded under the brief covers only the module and the T69 change. These two additions need the human's sign-off too. SETTLED needs only 5 clean hops, and at this repo's base rates 5 clean hops are weak evidence. So the SETTLED exclusion can hide a lesson that is still failing. | `docs/cascade/05b-briefs.md:127` ("at least 2 events in its after-window") vs spec item 1. The weak-evidence point is in the user memory `lesson-experiment-2026-11-16.md` ("SETTLED after 5 hops is weak evidence") |

## Spec

| C# | severity | finding | evidence |
|---|---|---|---|
| C3 | medium | The "After" diagram and the first row of the case table show ESCALATE only after a `NOT WORKING` mark. The rule and the oracle also escalate lessons marked WORKING and NEW. The diagram's condition box also leaves out the SETTLED/NO MATCH exclusion and `hb > 0`. So the diagram does not match spec item 1 or the oracle. | `docs/cascade/05b-t110-lesson-escalation.md:49` `M[tests/patterns.sh: LESSON L1 ... NOT WORKING]` and `:59` (Before = `NOT WORKING`). Oracle cases at `tests/ac/t110_lesson_escalation.sh:145,150`: `(0, 2, 0, 3, "NEW", True)` and `(9, 2, 1, 3, "WORKING", True)` |
| C4 | low | Item 5 makes a full run exit non-zero when the module is missing. The script's stated exit contract still says "Exit 0; 64 on a bad argument". Item 9 updates the header but the prototype patch leaves that line as it is, so the header becomes wrong. | `tests/patterns.sh:33` `# Exit 0; 64 on a bad argument.`. `docs/cascade/prototypes/t110/patterns.patch` has no hunk for that line |
| C5 | low | The AC4 static check cannot fail on several real violations of item 4. It does not catch `.write_text(`, `pathlib`, `os.open` via `import os`, `__import__` or `exec(`. Nothing tests the "standard library only" half of item 4. | `tests/ac/t110_lesson_escalation.sh:158` (`\.write\(` does not match `.write_text(`) |
| C6 | low | Item 8 says the git dir is unchanged after any run, but the AC2 snapshot skips `.git`. The snapshot also runs `git status`, which can rewrite the index by itself. | `tests/ac/t110_lesson_escalation.sh:111` `find . -path ./.git -prune …` |
| C7 | low | Item 11 asks for a README release line and a CHANGELOG entry that names the T69 allowlist change. AC5 checks neither, so the oracle cannot see if either is missing. | `tests/ac/t110_lesson_escalation.sh:175` checks only `^## $v `, and the script never reads README |
| C8 | low | The plan does not move the closed brief to `docs/cascade/05b-briefs-archive.md`. The last EXECUTE (t109) did this step. | `git show --stat ba9c62f` lists `docs/cascade/05b-briefs-archive.md \| 23 ++` and `docs/cascade/05b-briefs.md \| 23 --` |
| C9 | low | The mutants line measures only `tests/lib/escalate.py`, and all 18 of its mutants die. The code that connects the rule to the report gets no mutants: the `$HERE/lib` argument, where the import sits, and the two print loops. They live in the heredoc or in a quoted line, as are the lines of the T69 regex. Only the exact-output asserts in AC1–AC3 guard this code, and no mutation run measures how strong those asserts are. | Simulated EXECUTE in a temp clone (hop-state set to EXECUTE and committed, prototype applied, AC5 stubbed): `bash tests/mutants.sh` gave `MUTANTS 18/18 killed`, every mutant in `tests/lib/escalate.py`. The oracle fails AC1–AC5 on the current tree and passes AC1–AC4 on the reference build |

## Dispositions

| C# | DISPOSITION |
|---|---|
| C1 | rejected the rule is the brief's ("at least 2 events in its after-window"): a lesson whose rate fell but whose event still happens twice is the case the brief names; the mismatch is a trade-off row in the spec, and the human can drop any draft |
| C2 | fixed spec Problem and item 1: the SETTLED exclusion and the `mark` input are gone (the brief's rule, word for word; AC1 L8 now escalates); `hb > 0` and `a > 0` stay with their reason stated (no before-rate with no before hop; with no event the rate branch would mark a lesson that never failed) |
| C3 | fixed spec Before vs after: the After diagram's mark is "any mark" and its condition box is item 1; the case table names every mark, the rate row and the SETTLED row |
| C4 | fixed prototype patterns.patch: the header's exit line names exit 1 when tests/lib/escalate.py is missing (never with --recall); spec items 5 and 9 |
| C5 | fixed oracle AC4: the static check adds `.write`, `os.`, `pathlib`, `exec(`, `eval(`, `__import__`, `importlib`, and a check that the only import is `from __future__ import annotations`; spec item 4 |
| C6 | fixed oracle AC2: the snapshot covers every file under the fixture, its git dir too, except `.git/index`, and runs no `git status`; a clean `git status` is checked after |
| C7 | fixed oracle AC5: the CHANGELOG section must name `escalate` and T69, and README.md must name the release |
| C8 | fixed plan T5: `bash tests/briefs.sh archive` moves the closed t109 brief |
| C9 | rejected by design (human decision 2026-11-24): the rule and the text are in the module so mutants measure them; the heredoc glue is guarded by the exact-output asserts of AC1–AC3; the limit is a trade-off row in the spec. Simulated EXECUTE after the fixes: `MUTANTS 15/15 killed` in 37 s |
