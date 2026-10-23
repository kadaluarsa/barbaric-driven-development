# 10 Feature Audit — release-2.7.0 (branch t60-quiet-stop-guard vs main 2.6.0)

## Method

- **Baseline.** This repo is the pack; its product is the cascade itself. It has no accepted 01–09 documents
  (`docs/cascade/03-prd.md` does not exist, and the envelope's `Accepted artifacts` block holds only its template
  line). The accepted baseline is the human-closed 05b slices: their briefs (`docs/cascade/05b-briefs.md`), specs
  (`docs/cascade/05b-<slice>.md`) and close commits. Main is 2.6.0 (t62); this branch adds t63, t64, t66, t65,
  t67, t74, t68 and t69 (`git diff --stat origin/main..HEAD`: 90 files).
- **Laws.** `bash tests/dsharp_strength.sh`: `DSHARP 0/0` — no D# is declared, so there are no D# rows.
- **Opened.** Each slice's spec and its acceptance script under `tests/ac/`, `tests/enforcement.sh`, `tests/lint.sh`,
  `tests/ac/t62_loop_runners.sh`, `VERSION` and the plugin manifests. Every `test:` below is run by
  `bash tests/audit.sh`, not by this document. A status written here is advisory.
- **Run during this hop.** `bash tests/ac/t62_loop_runners.sh </dev/null` (2026-10-23, macOS): AC1–AC5 PASS,
  AC5b FAIL (`sed: … invalid command code f`). Without `</dev/null` the run hangs (see T62).

## Inventory

| ID | Spec claim (quote, short) | Evidence (paths, tests, commands) | Primary status | Also-violates | Send back to stage | Notes |
|---|---|---|---|---|---|---|
| T63 | "Send the agent-facing nudges … through additionalContext on exit 0" | path: .claude/hooks/stop_guard.py test: bash tests/ac/t63_quiet_stop_guard.sh | IMPLEMENTED | — | — | closed 3ed54a9 |
| T64 | "a JUnit 5 extension runs each law test twice inside one test task" (one law build) | path: tests/lib/law_harness.py path: tests/lib/law_harness.init.gradle test: bash tests/ac/t64_law_harness.sh | IMPLEMENTED | — | — | closed 09df86b |
| T65 | "Cache each law's verdict under a key …; only GREEN verdicts are cached" | path: tests/lib/verdict_cache.py test: bash tests/ac/t65_verdict_cache.sh | IMPLEMENTED | — | — | closed bffedc9 |
| T66 | "on a hop run only the laws whose map intersects the diff"; fails closed | path: tests/lib/affected.py path: tests/affected.sh test: bash tests/ac/t66_affected_laws.sh | IMPLEMENTED | — | — | closed 129c5d3 |
| T67 | "Let laws live in per-module shards, docs/cascade/laws/<module>.md" | path: tests/lib/laws.py test: bash tests/ac/t67_envelope_shards.sh | IMPLEMENTED | — | — | closed 492a953 |
| T74 | "a new non-test_D tests/inv file" no longer dies silently; rule explicit | path: .githooks/pre-commit test: bash tests/enforcement.sh | IMPLEMENTED | — | — | closed 537c0c0; T74 lives in enforcement.sh |
| T68 | "a human-signed retirement …; retiring a currently RED law is refused" | path: tests/lib/retirement_guard.py path: tests/retirements.sh path: tests/laws_report.sh test: bash tests/ac/t68_law_retirement.sh | IMPLEMENTED | — | — | closed 8d5b269 |
| T69 | "pass the settings that make repeat builds cheap, and nothing that changes a test result"; nightly split; release | path: tests/lib/gradle_tuning.py path: tests/lib/nightly_plan.py path: .github/workflows/nightly.yml test: bash tests/ac/t69_gradle_tuning.sh | IMPLEMENTED | — | — | closed 896441b. Farm row flat in E1, accepted by the human (critique C2) |
| R270 | "bump the pack to the next minor version above what is on main" (t69 brief) | path: VERSION path: .claude-plugin/plugin.json path: .claude-plugin/marketplace.json test: grep -qx 2.7.0 VERSION && grep -q '"version": "2.7.0"' .claude-plugin/plugin.json && grep -q '"version": "2.7.0"' .claude-plugin/marketplace.json | IMPLEMENTED | — | — | origin/main VERSION is 2.6.0 |
| I18 | "Enforcement is layered … Never weaken a layer" — every layer exercised, T8–T74 | path: tests/enforcement.sh path: tests/lint.sh test: bash tests/enforcement.sh && bash tests/lint.sh | IMPLEMENTED | — | — | |
| T62 | t62 AC: "the verdict matrix … identical to the sequential loop"; its AC script is the proof | path: tests/ac/t62_loop_runners.sh — expected: the AC script exits 0; actual: AC5b fails on macOS (`sed -i` is GNU-only, briefed t73), and with stdin left open the lying-runner red twin hangs forever: it reads stdin at import, and `tests/lib/affected.py` has imported `gradle_runner` since 219baef (t66) | DRIFTED | — | 05b | Shipped in 2.6.0, not this branch's delta; the hang is new since t66. Fix with t73 (portable sed) plus `</dev/null` for the lying runner, or a runner stub that does not read at import |

## Scoreboard

- 05b slices on this branch (t63–t69, t74): 8 IMPLEMENTED / 0 DRIFTED / 0 VIOLATED / 0 REFINED / 0 MISSING
- Release and enforcement (R270, I18): 2 IMPLEMENTED
- Already on main (T62): 1 DRIFTED
- D#: none declared

## Blocking (must be empty for PRR READY)

- **T62 — DRIFTED — send back 05b** — the t62 acceptance script is not green on macOS and hangs on an open stdin.
  Proposed fix: run 05b t73 (portable `sed`), adding `</dev/null` to the lying-runner twin (or making the twin not
  read stdin at import).

## Refinements awaiting you

None.

## Drift map

- **Baseline gap.** No accepted 01–09 documents; this audit's baseline is the accepted 05b slices. Whether that is
  the right baseline for the pack is a human call.
- **T62** — the t62 spec says its AC script proves the runner; on macOS the script is red (AC5b) or hangs. CI on
  Linux runs `pack-self-check.yml`; this audit did not observe a CI run.

## Punch list (for execute 10)

1. T62: give the lying-runner twin in `tests/ac/t62_loop_runners.sh` a closed stdin (`</dev/null`) so it cannot hang
   the suite (send-back 05b; smallest fix).
2. T62: make AC5b's file edit portable (`sed -i` differs between GNU and BSD) — brief t73.

## Audit verdict

DIRTY — T62 is DRIFTED. The script's verdict below (`bash tests/audit.sh`) is the one that counts.

## Exit gate

- [x] Every accepted slice on this branch has a row (t63–t69, t74), plus the release and enforcement rows
- [x] Every status other than MISSING has a path or test
- [x] No IMPLEMENTED row lacks evidence (each names `path:` and `test:`; the script re-runs them)
- [x] Punch list maps to send-back stages (05b)
- [x] Verdict is explicit
