# Proposals — first-knowledge discovery

Drafts, not laws. Nothing here is in force until a human signs it into `docs/cascade/envelope.md`
and its red twin actually fails. Written by `/barbar init` on 2026-09-20; re-running overwrites
this file and never touches the envelope.

**Envelope state read first:** `docs/cascade/envelope.md` carries only `{{template}}` placeholders.
`DSHARP 0/0` — no law in force, nothing skipped as already-signed.

**What this repo is:** the BDD pack itself. Its product is the pipeline — CI, git hooks, agent hooks,
the scripts that compute the gates. So its physics are about the bar, not about money: a signature the
agent could mint, a gate that reads prose instead of the tree, a stand-down that reaches Layer 0.
Each candidate below was run before it was written; `status:` says what it does on this tree today.

---

## Candidate laws

### D1 — a tree that is not CLEAN 10 + human-signed READY 11 + every D# GREEN MUST NOT be allowed to merge
check:  BARBAR_ROOT=evals/fixtures/ready-product bash tests/barbar.sh gate
break:  BARBAR_ROOT=evals/fixtures/dirty-product bash tests/barbar.sh gate
why:    `tests/barbar.sh` `merge_gate()` — the one place the pack says ALLOWED. The fixtures it needs
        already exist and were scored (i17 T5, `tests/i17_dune.sh:74`). If this ever goes THEATER the
        whole pack is decoration.
status: GREEN today — check exits 0, break exits 2.

### D2 — a verdict the human did not sign MUST NOT count as READY
check:  python3 -B tests/lib/signed.py evals/fixtures/ready-product/docs/cascade/11-prr.md 'Verdict:\s*READY( WITH WAIVERS)?'
break:  python3 -B tests/lib/signed.py evals/fixtures/unsigned-ready-product/docs/cascade/11-prr.md 'Verdict:\s*READY( WITH WAIVERS)?'
why:    READY counts only inside `<EDIT>`, which the hop hooks keep agent-proof (T18, T30).
        `unsigned-ready-product` is the same verdict typed outside the tags — the exact forgery.
status: GREEN today — check exits 0, break exits 1.

### D3 — a law that cannot fail MUST NOT count as in force
check:  bash tests/dsharp_strength.sh --root evals/fixtures/ready-product
break:  bash tests/dsharp_strength.sh --root evals/fixtures/theater-product
why:    THEATER is this pack's own founding observation — a green test whose red twin also passes
        proves nothing (T18). `theater-product` declares D1 with `break: true`.
status: GREEN today — check `DSHARP 1/1` exit 0, break `DSHARP 0/1` non-zero.

### D4 — a typed verdict MUST NOT stand in for a computed one
check:  bash tests/audit.sh --root evals/fixtures/ready-product
break:  bash tests/audit.sh --root evals/fixtures/prose-clean-product
why:    Stage 10 is scored from the tree — `path:` must exist, `test:` must pass — and a CLEAN the
        agent typed is ignored (I7, T19, T6). `prose-clean-product` is a written CLEAN over a row
        with no evidence.
status: GREEN today — check `AUDIT 2/2` CLEAN exit 0, break `AUDIT 0/1` DIRTY exit 1.

### D5 — standing BDD down MUST NOT reach Layer 0
check:  bash tests/ac/t53_disable.sh
break:  BDD_DISABLE_MUTANT=layer0 bash tests/ac/t53_disable.sh     # not built yet
why:    `tests/lib/disable.py` stands down Layers 1 and 2 and records what it replaced; the CI
        workflow and branch protection are untouched, so work done while disabled still goes red and
        still cannot merge. A disable that reached Layer 0 would be a merge bypass with a friendly
        name (T53, slice `t53-bdd-disable`).
status: check passes today (AC1, AC3–AC6). The break does not exist — the mutant switch has to be
        built, on the `DOCTOR_MUTANT` pattern already in `tests/doctor.sh:20`. Until then: UNPROVEN.

### D6 — the agent MUST NOT be able to mint its own signature
check:  printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"bash tests/sign.sh"}}' "$PWD" | python3 -B .claude/hooks/bash_guard.py | grep -q '"permissionDecision": "deny"'
break:  BDD_GUARD_MUTANT=seal ... same pipeline ...                # not built yet
why:    Approve-to-sign is only real if the ledger, `tests/sign.sh`, `--no-verify` and a push to main
        are all denied to the agent — quoted or bare (T46, T50, T51). Two releases were spent closing
        holes in exactly this seal.
status: check passes today (the guard answers `deny`). The break needs a softened-guard mutant; the
        existing T46/T50/T51 evidence lives inside `tests/enforcement.sh`, which takes minutes and has
        no case selection, so it is not usable as a per-hop validator as it stands. Until then: UNPROVEN.

---

## Proposed stage-10 rows

Features that already exist, with the artifact and a test that actually runs. Every command below was
executed during discovery and exits 0 on this tree.

| ID | claim | evidence | status |
|----|-------|----------|--------|
| FR-1 | Laws are scored GREEN / RED / THEATER / UNPROVEN, and only GREEN is in force | path: tests/dsharp_strength.sh test: bash tests/dsharp_strength.sh --root evals/fixtures/ready-product | IMPLEMENTED |
| FR-2 | Stage 10 is computed from the tree, never read from prose | path: tests/audit.sh test: bash tests/audit.sh --root evals/fixtures/ready-product | IMPLEMENTED |
| FR-3 | Merge is ALLOWED or REFUSED by a script, gated on CLEAN 10 + signed READY 11 + green D# | path: tests/barbar.sh test: bash tests/i17_dune.sh | IMPLEMENTED |
| FR-4 | Git hooks reject product code on a GENERATE hop, a changed `<EDIT>`, and a push to main | path: .githooks/pre-commit test: bash tests/enforcement.sh | IMPLEMENTED |
| FR-5 | Agent hooks deny the tool call itself, and ask rather than fail open when they cannot load | path: .claude/hooks/_common.py test: bash tests/enforcement.sh | IMPLEMENTED |
| FR-6 | Approve-to-sign: the permission dialog is the human's signature, as a one-shot token | path: .claude/hooks/sign_ok.py test: bash tests/enforcement.sh | IMPLEMENTED |
| FR-7 | Autopilot advances only along a human-signed list, one signed edge at a time | path: tests/lib/autopilot.py test: bash tests/enforcement.sh | IMPLEMENTED |
| FR-8 | `bdd doctor` reports whether the pipeline works, one line per I18 layer | path: tests/doctor.sh test: bash tests/doctor.sh | IMPLEMENTED |
| FR-9 | `bdd disable` / `bdd enable` stand down Layers 1 and 2 only, restoring bytes | path: tests/lib/disable.py test: bash tests/ac/t53_disable.sh | IMPLEMENTED |
| FR-10 | Every layer appends its decisions to `.cascade/decisions.log`, which is never a gate | path: tests/lib/decisions.py test: bash tests/enforcement.sh | IMPLEMENTED |
| FR-11 | `install.sh --check` reports drift, a softened hook, a version mismatch, a gitignored `.claude/` | path: install.sh test: bash tests/enforcement.sh | IMPLEMENTED |
| FR-12 | Each stage declares a `reads:` budget, and one stage is one file | path: tests/reads_manifest.sh test: bash tests/reads_manifest.sh && bash tests/stage_templates.sh | IMPLEMENTED |

Four rows lean on `tests/enforcement.sh`, which is the honest test (throwaway repos, not greps) and
also a multi-minute one with no case selection. That is a real weakness in the evidence, not a
formatting choice — it is why D6 above cannot cite it as a validator.

## PRD skeleton

`docs/cascade/03-prd.md` is absent. If you want stage 10 scored, the twelve FR lines above are the
skeleton — copy them into `03-prd.md` as `FR-n <claim>` and the audit rows into `10-audit.md`.

---

## Note on hop state, not a proposal

`docs/cascade/hop-state.md` says `CURRENT_HOP: EXECUTE / 05b / t53-bdd-disable`, but that slice is
built, released (1.9.0) and merged (`5aa8625`). The hop looks open only because nobody closed it.
Discovery does not touch hop state — flipping it is yours.
