# Stage 06 — t82-task-routing — EXECUTE security review

Baseline: `ecc8601061fd2ec59e3c2f0d4686fcd3e992b16e`. Scope: the accepted `06-t82-task-routing.md` review plan only. NO LAW IN FORCE. No external model probe was launched, product code changed, or human-owned field edited.

## Verdict

Security exit gate OPEN. The recorded P8 run supports a limited read-only observation, not general mutation detection or universal model conformance. SEC4 remains unresolved: approval of the review plan did not itself assign risk owners or accept risks.

## Findings

### F1 — Important: P8 can miss mutating tool calls

`evals/spike/probes.sh:36` truncates each tool call to 200 characters. At line 117, a blacklist checks only selected tool names and shell command prefixes. Redirection, other interpreters, compound commands and mutations beyond the truncation boundary can escape it. The final `git status --porcelain` check at line 118 cannot detect writes outside the repository, ignored files, or mutations subsequently restored.

A non-executing reproduction fed the literal string `Bash: printf changed > /tmp/probe-side-effect` to the exact blacklist regex. Grep exited 1: the mutation-shaped call was missed. No side-effect command was executed. Consequently P8's automated PASS is not proof that arbitrary tool activity was read-only. The actual stored full calls were reviewed separately and contain only reads.

Remediation proposal for a separately approved build slice: inspect complete structured tool inputs, fail closed on unsupported operations, test redirection/compound/truncated-call counterexamples, and constrain the probe filesystem rather than treating a clean final tree as full mutation evidence.

### F2 — Important: P8 does not require successful agent completion

`evals/spike/probes.sh:25` records the process exit code, but the P8 verdict at lines 115–119 never reads it or requires a successful result event. A failed/timed-out run that already emitted the expected words can satisfy those predicates. The stored run has exit code 0 and a successful result, so this finding does not invalidate that specific completion.

Proposed remediation: require process success and a successful terminal result; add failure/timeout counterexamples in a separate build slice.

### F3 — Important: evidence retention/access remain unspecified

The committed raw stream includes session/request identifiers, environment paths, tool output, model usage and cost metadata. This is broader than a route label. No data retention deadline, provider deletion mechanism or accountable operator is established by the accepted inputs. No credential absence guarantee is made; this was not a comprehensive secrets audit. Raw values are not reproduced here.

Human decision required: confirm approved evidence audience, retention/deletion policy and owner; resolve provider handling before any sensitive probe. Keep future inputs synthetic until then. Existing Git history and provider copies are not erased by deleting a working-tree file.

### F4 — Coverage limitation: fixtures and parity are not runtime security proof

`tests/score_hops.py:88` compares literal expected/actual route and action fields. T82 exercises that scorer, skill parity, README presence and a real standalone installation; it does not run adversarial prompts against an agent. Plugin skill existence/parity is not an end-to-end plugin invocation or publisher-authenticity check. Keep these claims separate from the recorded P8 observation.

### F5 — Evidence metadata defect: stop-hook flag is reset

`evals/spike/probes.sh:39` may set `stop_fired=True`, but line 43 resets it to false immediately before writing the tools summary. Therefore the recorded `STOP_HOOK_FIRED=no` cannot prove no stop hook fired. This flag does not enter P8's verdict; do not generalize it as evidence of hook execution. Refer any correction to a separate build slice.

## Threat-to-evidence matrix

| Threat | Reviewed evidence | Result / limitation |
|---|---|---|
| S06-1: spoofed approval | `skills/bdd-work/SKILL.md` cascade boundaries; t82 human-state-change and law-conflict fixtures; `.githooks/pre-commit:55` and `:200`; `.claude/hooks/hop_guard.py:32` | Router denies authority in prose; pre-commit protects human state and recognizes human signatures; Claude hook asks interactively and denies headless signing. The human key is an intentional trusted operator path, not available to this agent |
| S06-2: hop/scope escalation | t82 generate-spec-only, execute-accepted-plan, none-propose-edge and reject-scope-expansion fixtures; `.githooks/pre-commit:29`; `.github/workflows/control-line.yml:14` | Fixture expectations match boundaries; git hook gates GENERATE product writes; CI declares enforcement/farm checks. Branch protection and current remote CI verdict were not verified; Claude-specific hooks do not establish enforcement in every agent host |
| S06-3: distribution tampering | Byte comparison of both bdd-work skill files; `tests/ac/t82_task_routing.sh:26`; `install.sh:129` | Copies match; standalone install test checks placed content. Publisher provenance and real plugin invocation remain outside this proof |
| S06-4: evidence overclaim | `tests/score_hops.py:88`; raw P8 stream and result; F1/F2/F4/F5 | Fixture scorer and one model observation are distinct; probe checker has gaps that require explicit disposition |
| S06-5: transcript disclosure | Stored P8 stream top-level metadata and tool calls; F3 | Metadata is retained in Git; access/retention/deletion unresolved |
| S06-6: repeated-run/resource cost | `evals/spike/probes.sh:24` | Runner specifies `timeout 900` and `--max-turns 30`; no monetary cap is specified there. Stored run reports 8 turns, 29,531 ms and USD 0.1478858. These are historical telemetry, not guarantees for future runs |

## Recorded P8 evidence

Directory: `evals/probes/2026-10-28-claude-code-2.1.258-sonnet-t82/`, introduced by `90e6220`.

- `PROBES.md` reports PASS and a clean final product tree. The original sandbox tree was not independently recovered in this review.
- `P8.stream.jsonl` identifies Claude Code 2.1.258 and model `claude-sonnet-5`, with `bypassPermissions` mode and a successful terminal result. This describes the recorded run, not the current agent.
- The seven full structured tool calls are Bash reads: `cat`, `ls`, and a `sed -n`/`grep` pipeline. No mutating call appears in those seven records. No fresh agent run was needed to inspect them.
- `P8.final.txt` selects Investigation and cites repository paths. `P8.rc` is 0. `P8.tools.txt` is a derived/truncated view, not the primary evidence for complete command inspection.
- The stored report provides provenance within this Git tree, not cryptographic attestation of the original environment. No universal model, prompt, plugin or host claim follows.

## Validation

- `bash tests/goal.sh reset`: exited 0; removed three previous validators, carried zero lines. `regress.md` was unchanged.
- `bash tests/affected.sh --shards`: exited 0 with no shard names.
- `cmp skills/bdd-work/SKILL.md .claude/skills/bdd-work/SKILL.md`: exited 0.
- `bash tests/loop.sh`: exited 0. Both `bash tests/ac/t82_task_routing.sh` and `bash tests/enforcement.sh # standing` reported PASS; the script reported two lines run alone in 844 seconds. Logs are in `.cascade/loop/`, with the captured console output at `/tmp/bdd-stage06-loop.log` (local evidence, not committed artifacts).
- `git diff --check`: passed. Final scope inspection shows only this new report and `docs/cascade/goal.md`; no product or human-owned state changes.

## Acceptance criteria and risk disposition

| Criterion | Status |
|---|---|
| SEC1 | Reviewed: all six threats mapped to evidence and explicit limitations |
| SEC2 | PASS: focused T82 and standing enforcement validation completed successfully |
| SEC3 | Reviewed: stored provenance, full calls, model/version and metadata inspected; F1–F5 qualify claims |
| SEC4 | OPEN: R1–R3 owners/expiry/disposition and privacy unknowns still require human decisions |
| SEC5 | Reviewed: only the report and hop-local goal changed; inline security review recorded F1–F5, with no product remediation attempted |

R1 (prompt conformance), R2 (transcript handling) and R3 (distribution authenticity) remain proposed risks, not accepted risks. F1/F2/F5 also need remediation or explicit disposition; this review does not authorize code changes. No stage 07, READY or merge is authorized.

## Review method and scope

Inline source/diff security review; no dedicated `/security-review` command was available in this session, so no tool execution under that name is claimed. Executing-plans and verification guidance were used within cascade constraints; delegation, worktree creation, automatic commits and finishing-a-development-branch were omitted because this approved hop is a bounded review with a human edge, not an implementation/merge workflow.
