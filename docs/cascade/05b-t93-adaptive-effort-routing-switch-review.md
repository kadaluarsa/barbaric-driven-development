# Switch review — 05b t93-adaptive-effort-routing

Fresh independent read-only audit on 2026-11-04, after implementation commit `07984d1`.
The outgoing builder base reported by `builders.py --switches` is `e299626`; the recorded chain is
`codex/gpt-6 → claude/unknown`. The reviewer did not write the implementation, change provenance,
or run the full suite. It reviewed `e299626..07984d1` and the existing t93 core for context.

The rows and verdict below are preserved verbatim from that reviewer.

## Review

| R# | severity | finding | evidence |
|---|---|---|---|
| R1 | info | Schema fixes preserve policy while returning bounded input errors for malformed enum values and requiring canonical calendar dates. | `tests/lib/effort.py` adds string guards before set membership and compares parsed dates with their canonical representation. Independently ran `python3 -B tests/ac/t93_effort_input_edges.py`: all 5 tests passed. |
| R2 | info | The file-size fix bounds memory consumption before JSON parsing without relaxing the 64 KiB limit. | `load()` reads at most 65,537 bytes and rejects the overflow byte. The supplemental counted-stream test verifies consumption stays within that bound. |
| R3 | info | Existing gates and frozen acceptance artifacts remain preserved in the reviewed diff. | `git diff e299626..07984d1` shows no changes to the frozen t93 test/data/manifest, hop state, envelope, law shards, invariant tests or git hooks. T69 adds exactly `effort.py` and `effort.sh` to its existing parity allowlist; T93 enforcement propagates either acceptance or supplemental-test failure. |
| R4 | info | Integration and documentation stay within the accepted advisory MVP and explain its operational limits. | The existing policy keeps risk floors, same-task retention, explicit capability mappings and `application_status="not_applied"`. USAGE B19 documents the structured schema, transitions, operator-supplied capability claims and missing telemetry; no dependency, credential, model-selection or host-setting mechanism is introduced by this diff. |

Verdict: **Approve the reviewed change for the current hop’s human acceptance.** No blocking correctness, security or preserved-gate defect found in `e299626..07984d1`. Reviewed relevant existing t93 core for context; independently ran only the supplemental input tests. The reported full-loop result was supplied by the coordinator and was not rerun during this audit.

## Dispositions

| R# | DISPOSITION |
|---|---|
| R1 | fixed `tests/lib/effort.py` — explicit string guards and canonical dates are covered by supplemental regressions, reproduced red before the fixes and green afterward. |
| R2 | fixed `tests/lib/effort.py` — the bounded read rejects overflow without allocating the whole input stream; the counted-stream regression passes. |
| R3 | rejected — no further change requested by this informational observation; preservation evidence accepted. The oracle and every human-owned gate remain unchanged. |
| R4 | rejected — no further change requested by this informational observation; scope and documentation evidence accepted. Host application remains outside the accepted MVP. |

## Verification evidence

Before this review record was added, the coordinator ran `bash tests/loop.sh`: all six validators passed
(frozen t93 acceptance including five red twins; supplemental input regressions; t91; t67; full enforcement
through T93; lint). The receipt's run took 1,049 seconds. USAGE examples also passed: default medium, explicit
billing risk high, observed-setting warning, application_status not_applied and byte-identical output from
another cwd. `git diff --cached --check` passed before the implementation commit.

The scorecard then passed oracle, loop and drift but refused review because this switch record was missing.
This record closes that finding only after commit. The final loop and scorecard must be computed afterward
against the resulting tree; their verdicts are machine output, not supplied by this report.

NO LAW IN FORCE. No release version, hop edge, law or human acceptance is signed by this review.
