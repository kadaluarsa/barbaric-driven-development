# Stage 05b — t104-pattern-report — spec critique

Fresh read-only subagent, no memory of writing the spec. Rows verbatim.

## Brief

| C# | severity | finding | evidence |
|---|---|---|---|
| C1 | high | The brief asks for events grouped "from `decisions.log` and the cascade commits (… send-backs)". The spec reads git only to assign hops and never takes events from commits. In production, nothing writes a `human SENDBACK` line: the only writer is a test in enforcement.sh. Real send-backs exist only as commit subjects. So the spec's `src=human` event branch has no real data. AC1's `human SENDBACK seen 3 times in 2 hops` tests a fixture-only path, and the send-back kind that the brief names will never appear on a real repository. The spec does not list this narrowing as a scope decision. | `grep -rn 'SENDBACK' tests/lib/*.py tests/*.sh .claude/hooks/*.py .githooks/*` (only `tests/enforcement.sh:893`); `git log --format=%s -- docs/cascade/hop-state.md \| grep -i 'send back'` (real send-backs are commits) |
| C2 | medium | Right problem, but it has no data yet. Of 3,619 log lines, 66 carry `src=`. 60 of those are `src=test`, which leaves 6 agent lines and 0 human lines. On this repository the report prints 0 groups at `--min 3`. The spec's figure "51 lines have the field … it becomes useful as new lines arrive" is out of date and overstates the data: almost all of those lines are test lines that are excluded anyway. AC8 ("runs on this repository") only proves that the script exits 0. | `grep 'src=' .cascade/decisions.log \| awk '{print $2,$3,$NF}' \| sort \| uniq -c`; spec "Only 51 lines have the `src=` field" and "Today the report has little data (51 lines with the field)" |
| C3 | low | `NOEDGE` is one of the brief's named kinds and is the biggest real group. Brief t105 (the next slice) says `stop_guard` fires `NOEDGE` wrongly on questions and status replies. If t104 runs first, its top pattern is mostly a known false positive of the guard, not an agent mistake. Neither the brief nor the spec says so. | `docs/cascade/05b-briefs.md` t105 entry (~line 134): "each reply with no edge line gets the `NOEDGE` nudge" |

## Spec

| C# | severity | finding | evidence |
|---|---|---|---|
| C4 | medium | The t69 allowlist decision blocks the slice; it is not optional. The plan's goal includes `bash tests/enforcement.sh # standing`, and enforcement.sh runs t69. Its AC9 fails on any new shipped `tests/*.sh`, so LOOP cannot go green until the allowlist changes. Yet plan T4 says "without a decision, stop at the edge and ask", and T6 runs the loop after that. The alternative in spec item 12 ("keep the script out of `install.sh`") needs an `install.sh` change, because install.sh copies every `tests/*.sh`. The plan does not list that change. The decision belongs at this GENERATE edge. | `tests/enforcement.sh:1714`; `install.sh:98` `for f in "$SRC"/tests/*.sh …`; `tests/ac/t69_gradle_tuning.sh:368` allowlist regex; plan T4/T6 |
| C5 | medium | Hop assignment is weakly tested. In the fixture, every commit changes `hop-state.md`, so code that treats every commit as a hop (`git log` without `-- docs/cascade/hop-state.md`) passes AC1 and AC4. No event falls before the first hop commit, so the hop `-` path in item 7 is never exercised. | `tests/ac/t104_pattern_report.sh:27-33` (only commits are `hop()`); earliest fixture event `2026-01-01T05:00:00Z` comes after H1 (line 39) |
| C6 | medium | Normalization turns every run of digits into `N`, so different law ids merge into one group. All `dsharp RED D3 — …` and `D49 — …` lines become `DN — …`, which hides which law keeps going red. That is the reason that matters, and it is the second-largest verdict (300 lines). The trade-off table only says "two reasons that differ only in a number … join one group" and does not cover D# ids. Nothing tests it. | `tests/lib/decisions.py:8` (`dsharp RED D3 — break passed …`); spec item 6; `awk '{print $2,$3}' .cascade/decisions.log \| sort \| uniq -c` (300 `dsharp RED`) |
| C7 | low | The read-only check (item 2) is weak. AC6 skips everything under `.git/` and only snapshots `$R`, so writes into `.git/`, `$TMPDIR` or `~/.cache` pass. AC7's regex misses `"wb"`, `"ab"`, `pathlib.write_text`, shell `>`/`>>`, `tee` and `mkdir` outside `$R`. | `tests/ac/t104_pattern_report.sh:177` (skips `.git`); `:205` `open\([^)]*['\"][wax]\+?['\"]` |
| C8 | low | `--since` and the "not counted" numbers are unspecified. Item 9 does not say whether `<t>` and `<u>` count only lines on or after `--since` or every line. AC5 checks only ` from 3 event(s);`, so either behavior passes. | spec items 1, 9; `tests/ac/t104_pattern_report.sh:168` |
| C9 | low | AC8 only checks that `VERSION` equals the manifests. On today's tree they all say 3.5.5 and match, so the 3.5.6 release, the CHANGELOG `## 3.5.6` entry and README in item 11 go unchecked. The plan also names those files by description ("the three manifests", "CHANGELOG"), not by path. On the accept edge, stop_guard's drift check will flag them, as it did for t102. | `tests/ac/t104_pattern_report.sh:217-227`; `cat VERSION` → 3.5.5; `.cascade/decisions.log:2806` (DRIFT … `VERSION, tests/ac/t69_gradle_tuning.sh`) |
| C10 | low | Item 7 assigns events to hops by committer time (`%ct`). A rebase or cherry-pick of the hop-state commits on the feature branch rewrites committer times and moves events into other hops. The plan's risk list covers only shallow clones. The before/after diagram matches the plan: git hop-state log plus the log in, the report out. | spec item 7 `git log --format='%H %ct'`; plan "Order and risk" (shallow clone only) |

## Dispositions

| C# | DISPOSITION |
|---|---|
| C1 | fixed spec Problem and items 5a, 7, 8: send-back commits (`^(cascade: )?send back\b`) are `git SENDBACK` events with commit evidence; oracle AC1, AC4 and AC5 test a send-back commit |
| C2 | fixed spec Problem and Benefits: the counts are now 66 lines with `src=` (60 test, 6 agent, 0 human), and the spec says the report has almost no log data today; commit events give it real data now |
| C3 | fixed spec Benefits row `NOEDGE events`: until t105 is built, part of that group is a false positive of the guard |
| C4 | human — extend the T69 allowlist with `patterns` (recommended), or add an `install.sh` exception that does not ship the script? Spec item 12 and plan now ask for the decision at this GENERATE edge, before EXECUTE |
| C5 | fixed oracle fixture: a send-back commit that does not change hop-state.md sits inside hop 1, and an event comes before the first hop; AC4 checks hop H1 and hop `-` |
| C6 | fixed spec item 6: a law id (`D` and digits) is kept; oracle AC1 has separate `D3` and `D49` groups |
| C7 | fixed oracle AC6 (snapshots `.git` except its index, and checks that an empty HOME and TMPDIR stay empty) and AC7 (b modes, write_text, write_bytes, makedirs, mkdir, tee, redirect to a variable path) |
| C8 | fixed spec item 9: `<t>` and `<u>` describe the whole file, with no regard to `--since`; oracle AC5 checks the full last line |
| C9 | fixed oracle AC8 (VERSION 3.5.6, the three manifests, `## 3.5.6` in CHANGELOG.md, 3.5.6 in README.md); plan T3 names each file by path |
| C10 | fixed spec item 7: hops use the author time (`%at`); the oracle's second hop commit has a committer time one month late |
