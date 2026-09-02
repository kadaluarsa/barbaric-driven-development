# Changelog

## 1.0.0 — 2026-09-02

First production-oriented release. Every control lives at the lowest layer that can enforce it (I18), and each layer is pinned by a behavioral test (T1–T22).

- **Layers.** CI + branch protection; git hooks (`.githooks/`) for any agent; Claude Code hooks (`.claude/hooks/`: hop_guard, bash_guard, stop_guard, preserve, seam); rules (`AGENTS.md` + shims).
- **Commands are scripts.** `tests/loop.sh` (LOOP k/n), `tests/barbar.sh` (BARBAR k/n, merge gate), `tests/dsharp_strength.sh` (DSHARP k/n), `tests/audit.sh` (AUDIT k/n). The agent never types a score.
- **Human-owned lines.** `CURRENT_HOP/STAGE/SLICE` and every D# line are rejected by pre-commit and hop_guard; humans commit hop edges with `CASCADE_HUMAN=1`, which the agent is denied.
- **Red twin.** A D# is in force only with a validator and a command that must fail; THEATER and UNPROVEN refuse merge, UNPROVEN blocks the loop.
- **Stage 10 computed.** `audit.sh` scores rows against the tree; prose verdicts are ignored. Stage 11 READY counts only inside `<EDIT>` (human-signed).
- **Fail visibly.** A crashing guard returns `ask`, never allow. `install.sh --check` reports drift. Idempotent install: a re-run replaces pack-owned paths, nests nothing, drops stale files (T23).
- **Measured.** `evals/spike/`: fresh container, Phase 1 from zero, then a real agent through seven probes — recorded in `evals/probes/` — Phase 1 22/22, PROBES 7/7 on `2ee3c9f`.
