# Stage 05b — t90-provenance-switch-audit — CRITIQUE

Written by a fresh read-only critic subagent with the pipeline's critic brief (spec and GENERATE-written oracle);
rows committed verbatim before any answer.

## Brief

| C# | severity | finding | evidence |
|---|---|---|---|
| C1 | high | The brief says to record "at every hop edge and every `tests/loop.sh` pass … and in a trailer on the edge commit", and to judge a switch "between its first and last loop pass". The spec records only from the Stop hook. It drops trailers (they show up under "Not chosen" and "Out of scope", but are not raised as a deviation in "Ask of you"), and `tests/loop.sh` is not on the in-scope list. Any host without the Stop hook writes nothing, so a switch to or from that host reads as one builder (`SWITCH none`). That is the case handover.sh exists for. Claude's repo-local wiring also skips run.sh, so the host is only ever the default `claude`. | `docs/cascade/05b-briefs.md:500-503`; `docs/cascade/05b-t90-provenance-switch-audit.md:67`, `:165-177`; `.claude/settings.json:39` (calls stop_guard.py directly, not via `hooks/run.sh:4`) |
| C2 | medium | The brief gates "the accept edge" of any EXECUTE hop whose builder changed. The spec limits the gate to EXECUTE 05b ("Any other hop or stage → `SWITCH n/a`"), so a model switch on an EXECUTE of stages 06–09 is still invisible. This scope cut is not listed as a deviation or put to the human in "Ask of you". | `docs/cascade/05b-t90-provenance-switch-audit.md:102`, `:124`; `docs/cascade/05b-briefs.md:502` |

## Spec

| C# | severity | finding | evidence |
|---|---|---|---|
| C3 | high | The plan lists `tests/lib/provenance.py` as "(new)", but the file already exists. It holds the shared `section`/`git`/`adding_commit` helpers that critique.py and diverge.py import. Writing it as a new file would break the t57/t58 spec gates. The spec never says these helpers must stay or that the module is being extended. | `tests/lib/provenance.py:2` ("Shared helpers for the spec-edge gates"); `tests/lib/critique.py:20` (`from provenance import adding_commit, git, section`); `grep -rln provenance tests/` → diverge.sh, diverge.py; `docs/cascade/05b-t90-provenance-switch-audit.md:74`, `:165` |
| C4 | high | On a real autopilot edge, the working-tree hop state already reads the next hop: the pre-commit hook runs autopilot.py after the change is staged, and loop.sh gets the old state through `CASCADE_HOPSTATE`. The spec never requires switch.sh or `--builders` to read the hop from `CASCADE_HOPSTATE`, and `laws.hopstate_path` ignores it. In production the gate would see `GENERATE b`, print `SWITCH n/a` and fail open. AC5 never changes `$D/$HS`, which still says EXECUTE, so it passes for the wrong reason. | `.githooks/pre-commit:221-227`; `tests/lib/autopilot.py:212-217`; `tests/lib/laws.py:234-237` vs `tests/lib/affected.py:62-69`; `tests/ac/t90_provenance_switch_audit.sh:137-138` |
| C5 | high | The review's freshness is checked only against the first switch (`--switched-at` = first line whose builder differs from the first builder). A later switch (A→B→C), or more of B's commits after the review, still passes with the old review: work after the review is never reviewed. Nothing ties the review to the HEAD it covered, and no AC tests a second switch or a commit after the review. | `docs/cascade/05b-t90-provenance-switch-audit.md:82-83`, `:96-97`; `tests/ac/t90_provenance_switch_audit.sh:116-131` |
| C6 | medium | The nudge sends the reviewer `git diff <commit at the switch>..HEAD`. The only HEAD on record is the one logged at the new builder's first Stop, and a Stop fires at the end of a turn, after that turn's commits. The diff therefore skips the new builder's first turn. The base should be the HEAD on the outgoing builder's last line, but the spec never says which line "the switch" means. | `docs/cascade/05b-t90-provenance-switch-audit.md:76-77`, `:109`; `.claude/hooks/stop_guard.py:428-440` (judge runs once per finished turn) |
| C7 | medium | "A no-switch hop is unchanged" and "the accept passes" (AC3 one-builder, AC4a) are checked only as `!= *"builder changed"*`. That also holds if the hook crashes (main() swallows it), if the I10 evidence nudge fires, or if any other nudge is sent. Nothing checks that the output is empty or matches today's behaviour. | `tests/ac/t90_provenance_switch_audit.sh:102`, `:122`; `.claude/hooks/stop_guard.py:414-425`, `:547` |
| C8 | medium | U1 covers only two different hosts. The transcript is a fallback "(its format varies)", so one host whose model resolves to `unknown` on one Stop and to a real id on the next gives `claude/unknown` plus `claude/<model>`. That forces a switch review although nobody switched, and AC1 shows `unknown` is a recorded value. Nothing normalises or ignores `unknown` within a host. | `.claude/hooks/stop_guard.py:465-466`; `docs/cascade/05b-t90-provenance-switch-audit.md:186-187`; `tests/ac/t90_provenance_switch_audit.sh:84-86` |
| C9 | low | The brief's done-when says `handover.sh` "prints the same index as preserve". AC7 checks only a `spec` substring and that some `oracle:` text appears. It never compares with preserve.py's `recall_index` output. tests/oracle.sh is not copied into the fixture, so the oracle line is never checked for real (`ok`, FAIL lines or `n/a`). The `BDD_MODEL` step of the model chain is also untested. | `docs/cascade/05b-briefs.md:507`; `tests/ac/t90_provenance_switch_audit.sh:27`, `:154`; `.claude/hooks/preserve.py:184-192` |
| C10 | low | The fixture ignores all of `.cascade/`, but install.sh treats an ignored `.cascade` as an I18 violation and ignores only named files. In a real repo `.cascade/provenance` would be an untracked file, which `affected.changed()` and the drift notice would see unless the plan's .gitignore/install.sh entry lands. The fixture cannot catch that entry being missing. | `tests/ac/t90_provenance_switch_audit.sh:33`; `install.sh:186-187`, `install.sh:204`; `tests/lib/affected.py:117` |

## Dispositions

| C# | DISPOSITION |
|---|---|
| C1 | fixed — `handover.sh --as <host>/<model>` records a `claimed` line, so a host without a Stop hook still leaves a record; the repo-local `claude` default is stated as correct for that wiring; the trailer and loop-pass recording are raised as deviations in Ask 3. |
| C2 | fixed — the gate covers EXECUTE of 05b and 06–09; the review is `docs/cascade/<stage>-<slug>-switch-review.md`; AC6 asserts a switched EXECUTE 06 is red. |
| C3 | fixed — the module is `tests/lib/builders.py` and the log `.cascade/builders`; `tests/lib/provenance.py` is listed as untouched. |
| C4 | fixed — §1: the hop is read from `CASCADE_HOPSTATE` when set (as `oracle.py`), and `hop_base` already honours it; AC5 puts the working tree on the next hop before calling autopilot, as pre-commit does. |
| C5 | fixed — §3: the review must be newer than the last switch and no product commit may follow it; AC4c (A→B→review→C) and AC4d (a commit after the review) are red. |
| C6 | fixed — §1 `switches()`: a switch's base is the HEAD on the outgoing builder's last line; the nudge names it; AC3 asserts the base sha. |
| C7 | fixed — AC3 and AC4a assert an empty hook output and no `CRASH` in `decisions.log` for the untouched cases; the twin likewise. |
| C8 | fixed — §1 folds `host/unknown` into the same host's known model; AC2b asserts one builder and `SWITCH none`. |
| C9 | fixed — AC7 compares the handover's recall lines with preserve's, copies `tests/oracle.sh` so the oracle line is real (`oracle: FAIL … no oracle manifest`), and AC1 tests `BDD_MODEL`. |
| C10 | fixed — AC8 is a labelled presence check that `install.sh` and `.gitignore` ignore `.cascade/builders`. |
