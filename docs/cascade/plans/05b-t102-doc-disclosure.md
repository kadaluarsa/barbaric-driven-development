# Stage 05b — t102-doc-disclosure — PLAN

**Spec:** [`../05b-t102-doc-disclosure.md`](../05b-t102-doc-disclosure.md). This plan runs only after the EXECUTE edge is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t102_doc_disclosure.sh`,
`bash tests/lint.sh # standing`, `bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

Measured on 2026-11-12 with the manifest of spec item 4: see the spec's "Benefits and trade-offs"; the largest class,
`GENERATE 05b`, stays under half of 103,554 bytes. AC2 recomputes it.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset`. Write the goal for slice `t102-doc-disclosure`. |
| T2 | — | AC1, AC3 | Write `tests/lib/doc_parts.py`: parse the manifest block, resolve `#heading` parts (skip fenced lines) and `@label` parts (inside the conductor's code block), `parts()`, `check()`, `measure()` (spec items 3, 6–11). |
| T3 | T2 | AC1–AC3 | Write `tests/doc_parts.sh` as a thin wrapper (no option, `--hop/--stage`, `--check`, `--measure`). |
| T4 | T2 | AC1, AC2, AC4 | Add the section `## Doc parts — what a hop reads (t102)` with the manifest (spec items 1, 4, 5) before `## Loop constitution`. Add lines only. Run `--check` and `--measure`. |
| T5 | T2 | AC5 | In `.claude/hooks/seam.py`, add the `DOC PARTS THIS HOP` line after the law-shard line (items 12–13). Import `doc_parts` from `tests/lib` in a `try`; any error adds no line. |
| T6 | — | AC4 | Change `AGENTS.md` read items 3 and 5 (items 14–16). Change no other line. |
| T7 | — | AC6, AC7, AC9 | Write `tests/lib/briefs.py` (`blocks`, `closed`, `archive`, `find`) and `tests/briefs.sh` (`archive`, `find`) (items 17–22). In `tests/goal.sh reset`, call the archive after the reset; a refusal prints one line and does not fail (item 21a). |
| T8 | T7 | AC7 | Make `recall.brief`, `diverge.tag` and `oracle.bugfix_tagged` use `briefs.find` (item 23). Add the item-24 lines to the pipeline doc and both `barbar.md` copies. Keep each reader's output format. Do not change `tests/doctor.sh` (item 23a). |
| T9 | T7 | — | Append the two `Absorbed by` lines (item 19a). Commit T7–T8, then run `bash tests/briefs.sh archive` on this repo and commit the move as its own commit. Check `git diff --stat`: the two brief files only. |
| T10 | T3, T7 | — | `install.sh`: confirm the new files ship with `tests/` (item 25). USAGE.md §B21, CHANGELOG `## 3.5.4`, `VERSION`, the three manifests, `README.md` (item 27). |
| T11 | T1–T10 | all | Run `bash tests/ac/t85_recall_index.sh`, `bash tests/ac/t58_*.sh` (diverge) and `bash tests/doctor.sh`. Report the results; change none of these tests. Run `bash tests/loop.sh` in the background. Report the result. Stop at the edge. |

## Order and risk

- T4 edits the pipeline doc that four tests grep. Add lines only; AC4 checks this against `5b26e2c`.
- T5 runs on every prompt. The import must be fast and must never raise into the hook. AC5 checks the fallback.
- T9 moves every closed brief in one commit (35 with a spec today, plus the two absorbed ones). Run it after the reader changes (T8) are committed, so no reader looks at a
  missing brief between commits.
- The diverge and recall tests build their own brief files; they must stay green without an archive file.
- Do not change the oracle. A wrong oracle is a send-back to GENERATE.
