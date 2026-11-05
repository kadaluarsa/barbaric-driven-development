# Switch review — 05b t93-adaptive-effort-routing

Fresh independent read-only audit on 2026-11-05 of `git diff e299626..970744e`, with the spec, plan and frozen
oracle. The recorded chain is `codex/gpt-6 → claude/claude-opus-5-5`. The incoming session built no t93 code. It
fast-forwarded `main`, created `feat/specplan-refinement` and drafted a brief outside this range.

The earlier review of `e299626..07984d1` remains in git history at `e21bbc8`. It was removed in `d5880ea` because
`tests/lib/builders.py` dates a review by the commit that added its file.

The rows and verdict below are the reviewer's, verbatim.

## Review

| R# | severity | finding | evidence |
|---|---|---|---|
| R1 | info | The range changes no frozen oracle file, oracle manifest, hop state, envelope, law shard, `tests/inv` file or EDIT block. | `shasum -a 256` of both pinned files matches `05b-t93-adaptive-effort-routing.oracle:2-3`; `git diff --stat e299626..HEAD` over those paths is empty; `git diff e299626..HEAD` has no added or removed EDIT tag lines |
| R2 | info | The edits to `tests/enforcement.sh` and `tests/ac/t69_gradle_tuning.sh` weaken nothing. | `enforcement.sh` only adds the T93 block, which fails on a red AC or edge test, and updates the T8–T93 labels; `t69_gradle_tuning.sh:365` adds exactly `effort` to the two `-x` allowlists, as the plan's table says |
| R3 | info | The `effort.py` hunks enforce the existing schema without changing policy, and the seven USAGE examples produce the documented results. | `tests/lib/effort.py:139,190-196,209,249,264,273`; `python3 -B tests/ac/t93_effort_input_edges.py` gave 5 tests OK; I ran the seven example contexts through the CLI and got low, medium, high, high/investigate, medium/investigate, high/investigate (repeat), medium |
| R4 | major | t93 was merged to main and released as 3.5.0 while the hop is still open, with no t93 entry or READY/CLEAN record in the envelope, and the acceptance record says it authorizes no release or merge. | `hop-state.md` has `CURRENT_HOP: EXECUTE`; `grep -n 't93' envelope.md` and `grep -n 'READY' envelope.md` are empty; acceptance doc: "No release, merge, new slice or stage is authorized"; AGENTS.md rule 6; b6ca853, 40027e7 and 970744e postdate 6a5a9e3 |
| R5 | minor | The 3.5.0 release missed the Codex manifest, which is still 3.4.0 although every recent release bumped it, and no test catches the mismatch. | `.codex-plugin/plugin.json:3` is 3.4.0 while `VERSION` and `.claude-plugin/plugin.json` are 3.5.0; `git log -p` shows it moved 3.1.0 to 3.4.0 with each release; `tests/ac/codex_compatibility.sh:10-11` only checks that the file exists |
| R6 | minor | The plan is stale against HEAD on the changelog entry, the version bump and the `advisory()` interface. | `plans/05b-t93-adaptive-effort-routing.md:74-75` says the entry is marked unreleased but `CHANGELOG.md:3` is `## 3.5.0`; `:67` excludes a bump from the slice; `:93,121` define and consume `effort.advisory`, but `grep advisory tests/lib/effort.py` is empty and the seam uses `effort_line` (`seam.py:93`) |
| R7 | minor | The earlier switch review says its rows are "preserved verbatim", but e21bbc8 later renamed the reviewer's C# ids to R# without saying so in the record. | `git show e21bbc8` rewrites all rows from C1-C4 to R1-R4; `05b-t93-adaptive-effort-routing-switch-review.md:7` keeps the verbatim claim; the finding text is unchanged |
| R8 | minor | The CLI ignores unknown arguments, so a mistyped `--profile=p.json` would return a no-profile decision with exit 0 rather than the input error the spec implies, and it accepts a bare `https://` source URL. | Ran `effort.py --context c.json --bogus`: exit 0 with a decision; `effort.py:419-424` only looks for exact flags (the `--profile=` case is from reading this code, not a run); a profile with `source_url` `https://` exited 0 (`effort.py:246`) |
| R9 | minor | The seam passes the raw stage line to the strict schema, so an annotated stage gets `EFFORT unavailable` even though `hop_class` tolerates that form. | `seam.py:137` uses `stage.split()[0]`; `seam.py:113-114,122-123` pass the stage whole and return the notice on nonzero exit; CLI with stage `05b x` exited 2; the prompt is not blocked |
| R10 | info | The switch gate is correctly red until a review of the new switch is committed, and the other scorecard fields pass. | `bash tests/switch.sh`: `switch review is older than the switch`, `work after the review: 2 commits`, `SWITCH red`; `bash tests/scorecard.sh`: oracle, loop (LOOP 6/6) and drift pass, review fails, builders `codex/gpt-6 → claude/claude-opus-5-5`, `SCORECARD fail` |

Verdict: The t93 code and docs in the reviewed range are fit for the human's acceptance decision, with no blocker and no weakened gate, but R4 is the human's to resolve because the merge and release preceded the signed close, and R5 needs a one-line fix; I ran only `tests/ac/t93_effort_input_edges.py`, `tests/oracle.sh` (it printed n/a on EXECUTE, so I compared hashes by hand), `tests/switch.sh`, `tests/scorecard.sh`, `builders.py --switches` and direct CLI probes, leaving the tree unchanged apart from the existing `05b-briefs.md` edit; not checked: a fresh run of the t93 oracle, t69, t91, t67 or `tests/enforcement.sh` (LOOP 6/6 is the scorecard's receipt, not my run), `tests/barbar.sh merge`, any stage 10 or 11 record outside the envelope, whether the human separately authorized the release, GitHub branch protection, and the external provider doc links.

## Dispositions

| R# | DISPOSITION |
|---|---|
| R1 | rejected — informational; no change requested. The preservation evidence is accepted. |
| R2 | rejected — informational; no change requested. The gate evidence is accepted. |
| R3 | rejected — informational; no change requested. The policy evidence is accepted. |
| R4 | human — confirmed against the acceptance record and the envelope. The merge, the release and the hop close are the human's to resolve; the agent changes none of them. |
| R5 | human — confirmed: `.codex-plugin/plugin.json` says 3.4.0 and `VERSION` says 3.5.0. Release packaging is outside this accepted delivery; the human decides on a follow-up. |
| R6 | human — the accepted plan is left as written; the human decides whether to annotate it. |
| R7 | fixed `docs/cascade/05b-t93-adaptive-effort-routing-switch-review.md` — the claim is gone with the removed record, and this record keeps the reviewer's ids. |
| R8 | human — confirmed in `tests/lib/effort.py`: flags are matched exactly and others are ignored. Building a fix after acceptance needs a new slice or a send-back. |
| R9 | human — the advisory falls back to a notice and blocks no prompt. Building a fix after acceptance needs a new slice or a send-back. |
| R10 | rejected — informational; the gate is expected to pass after this commit, and `tests/switch.sh` decides. |

NO LAW IN FORCE. This record signs no hop edge, law, release or human acceptance.
