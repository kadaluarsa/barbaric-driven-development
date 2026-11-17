# Stage 05b — t106-lessons — PLAN

**Spec:** [`../05b-t106-lessons.md`](../05b-t106-lessons.md). This plan runs only after the EXECUTE edge is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t106_lessons.sh`,
`bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset`. Write the goal for slice `t106-lessons`. |
| T2 | — | AC6, AC7 | The signature (item 4): add `LESSON\s` to `PROTECTED` in `tests/lib/laws.py` and to the fallback regexes in `.claude/hooks/hop_guard.py`; treat `docs/cascade/lessons.md` as a law shard in `hop_guard.py` (`is_shard`) and in `.githooks/pre-commit` (the `guarded_files` list and `is_shard`). Then run `bash tests/enforcement.sh` for the hooks' existing checks. |
| T3 | — | AC3 | In `tests/patterns.sh`: hops as real edges with their class (item 6), from the `hop-state.md` version at each commit (one `git log -p` or one `git show` per commit). t104's `in M hops` uses them. |
| T4 | T3 | AC1, AC4 | Read `docs/cascade/lessons.md` when it exists; parse lesson lines (items 1–3); report malformed lines with the fault word. |
| T5 | T3, T4 | AC3 | Keep every event per group with no `--since` filter next to the groups t104 prints (item 8). Compute in-scope before/after hops (item 7), rates (item 9), marks (item 10). Print the lesson block before the `PATTERNS:` line (items 11–12). |
| T6 | T4 | AC2, AC5 | `--propose` in the argument parser and the usage line; drafts and `PROPOSALS:` (item 13); nothing written (item 14). |
| T7 | T3–T6 | AC8 | Run `bash tests/ac/t104_pattern_report.sh`: t104's output must not change on its fixture. |
| T8 | — | AC8 | `USAGE.md` `### B24` and the §B23 hop note; `CHANGELOG.md` `## 3.5.7`; `VERSION`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json` and `README.md` to 3.5.7 (item 15). Update the header comment of `tests/patterns.sh`. |
| T9 | T1–T8 | all | Run `bash tests/loop.sh` in the background. Report the result and `bash tests/patterns.sh --propose --min 1` on this repository. Stop at the edge. |

## Order and risk

- T2 changes enforcement: a new guarded file. It makes a layer stricter, never weaker (I18). `tests/enforcement.sh`
  must stay green; the T40-style checks of the envelope and law shards share the same code path.
- T3 changes how t104 counts hops on a real repository: fewer hops (no AUTOPILOT-only or NONE commits). The t104
  oracle's fixture opens a new slice at each commit, so its counts do not change (checked at GENERATE).
- `lessons.md` is not created in this repository by this slice. The first lesson is a human signature, after the
  slice is accepted.
- Do not change the oracle. A wrong oracle is a send-back to GENERATE.
