# Recorded conformance runs — PROBES k/7

One directory per run: `<date>-<agent>-<version>-<model>`. Each holds the scored `PROBES.md`, the agent's final message per probe (`P*.final.txt`), all of its text (`P*.alltext.txt`), every tool call plus hook flags (`P*.tools.txt`: `HOOK_DENIALS`, `STOP_HOOK_FIRED`, `PRESERVE_FIRED`), exit codes, and the gzipped `stream-json` transcripts.

Probes are defined in `INTEGRATION.md`; the harness is `evals/spike/probes.sh`; the environment is `evals/spike/Dockerfile`. Scores come from the tree and the tool-call stream, never from the agent's own claims (I17).

| Run | Pack | Result |
|---|---|---|
| `2026-09-02-claude-code-2.1.258-sonnet` | `4636975` + the `.claude/` install layout now in `01c2af0` | **7/7** |
| `2026-09-02-claude-code-2.1.258-sonnet-v1.0.0` | `2ee3c9f` — v1.0.0: human-owned hop lines, red twin, computed audit, signed READY, seam, fail-visible guards, idempotent install | **7/7** |

A number here is per agent + model + pack commit. Re-run after a model or harness change. Below 7/7, the fix is a lower layer, not a stronger prompt.
