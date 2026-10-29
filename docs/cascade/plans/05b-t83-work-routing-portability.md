# Work-routing portability Implementation Plan

**Goal:** Make the accepted `bdd-work` route guidance portable across documented Agent Skills clients while defining separate, honest follow-up slices for Copilot and Aider.

**Architecture:** Keep one host-neutral route contract and provide matching skill copies only at the discovery paths each host documents. Test route behavior through common fixtures, then test discovery and invocation in each real client. Skill guidance remains advisory; git hooks and CI remain the enforcement layer.

**Tech Stack:** Markdown Agent Skills (`SKILL.md`), shell/Python acceptance scripts, the existing hop scorer and probe harness.

**Spec:** `docs/cascade/05b-t83-work-routing-portability.md`

## Global Constraints

- Keep the five route names and their precedence from accepted T82.
- Never treat a skill route as approval, permission, a D# law, or a hop transition.
- Keep probe inputs synthetic and probe artifacts sanitized.
- Claim client compatibility only for clients and versions actually exercised.
- Do not alter `docs/cascade/envelope.md`, human-owned hop fields, `<EDIT>` content, or existing `tests/inv/*` files.

---

## Current slice: `t83-work-routing-portability`

### Task 1: Pin the shared route contract

**Files:**
- Modify: `skills/bdd-work/SKILL.md`
- Modify: `.claude/skills/bdd-work/SKILL.md`
- Create: `.agents/skills/bdd-work/SKILL.md`
- Test: `tests/ac/t83_work_routing_portability.sh`

- [ ] Add failing checks that all three skill copies have identical bytes and valid required `name`/`description` metadata.
- [ ] Run the focused check and confirm it rejects a divergent copy and invalid skill metadata.
- [ ] Rewrite the common skill invocation language so it names `bdd-work` as the portable skill and treats slash syntax as a host-specific option.
- [ ] Keep routes, precedence, and hop boundaries byte-identical across shipped copies.
- [ ] Run the focused check and confirm it passes.

### Task 2: Wire repository installation to shared skill discovery

**Files:**
- Modify: `install.sh`
- Modify: `tests/ac/t83_work_routing_portability.sh`
- Modify: `tests/enforcement.sh`

- [ ] Add scratch-repo fixtures for an absent destination (created), an identical destination (no-op), and a conflicting destination (clear failure with original bytes preserved).
- [ ] Run the fixture and confirm installation currently fails the new discovery assertion.
- [ ] Update standalone install behavior to create the shared skill path only when absent; treat an identical existing file as a no-op; if contents differ, fail clearly and preserve the existing file. Never add a home-directory write.
- [ ] Verify plugin mode does not create duplicate project skill state that could shadow the plugin, unless the test proves the host needs that path.
- [ ] Run the focused acceptance check and existing T82 check.

### Task 3: Prove claimed native-skill clients

**Files:**
- Modify: `tests/ac/t83_work_routing_portability.sh`
- Modify: `evals/spike/probes.sh` and new sanitized probe artifacts, only for clients actually available
- Modify: `README.md`, `USAGE.md`, and `INTEGRATION.md`

- [ ] For each available initial target (Codex CLI, Cursor, Gemini CLI, OpenCode, Zed), verify skill discovery in a disposable repository and record the exact client/version.
- [ ] Send one synthetic read-only investigation request through the host's documented skill activation path.
- [ ] Inspect the complete available tool stream for writes or mutating commands; if the host does not expose complete tool evidence, record the result as unverified.
- [ ] Verify the final report chooses `investigation`, cites a repository source path, and leaves the disposable tree clean.
- [ ] Add a host to user-facing supported claims only when both discovery and behavior probe passed; otherwise label its status as available-format/unverified.
- [ ] Run all probe metadata checks and `git diff --check`.

## Follow-up slice proposals — separate specs and approvals required

### `t84-copilot-work-routing`

- Add `.github/skills/bdd-work/SKILL.md` (or deterministic generation from the core source) and extend install/discovery checks for VS Code/GitHub Copilot.
- Probe a named VS Code/Copilot version; no support claim before discovery and read-only route behavior pass.

### `t85-aider-work-routing`

- Document and test explicit loading of the core route instructions using Aider's `/read` or `--read` convention.
- Keep it manual and opt-in. Do not write or override `.aider.conf.yml` automatically.
- Probe a named Aider version and label this as explicit-load support, not automatic discovery.

### Deferred, no AUTOPILOT entry proposed

- Research official Windsurf and Continue skill-discovery behavior first. Generate a separate named slice only after identifying a supported project path and a safe probe.

## Definition of done for t83

- The canonical, Claude, and shared Agent Skills copies match and pass metadata validation.
- Standalone installation exposes `.agents/skills/bdd-work` without user-level writes; plugin mode remains free of conflicting project state.
- Each initial client claimed as supported has a recorded discovery plus read-only route probe for an exact version.
- Unavailable or insufficiently observable clients are labeled unverified, not passed.
- Route and cascade boundaries are covered by negative fixtures, existing T82 checks pass, and no hook, law, or hop authority is changed.

## Risks / UNKNOWNs that still block

- Which initial native-skill clients are installed and available for live probes is unknown; no client is assumed installed.
- Some clients expose skill discovery but not a complete tool event stream. Such a client cannot satisfy the read-only probe criterion without another trustworthy observation method.
- Client discovery paths and trust requirements can change. Recheck official docs and record versions at execution time.

## Ask of you

1. Accept or revise the initial Agent Skills target set: Codex CLI, Cursor, Gemini CLI, OpenCode, and Zed.
2. Confirm that Copilot and Aider should remain separate follow-up slices, and that Windsurf/Continue stay deferred pending official discovery evidence.

## Invariants this hop

- PRESERVE run: yes; source is `docs/cascade/envelope.md` and `docs/cascade/hop-state.md`.
- `/goal`: not set or run during GENERATE.
- `/model` / `/effort`: not changed.
- `/plan`: used as this hop's plan; saved in `docs/cascade/plans/` per the cascade instructions.
- I1–I18: held; no implementation, execution, autopilot, or next-stage work started.
- D# status: NO LAW IN FORCE.
- Reads: stage 05b template loaded; the envelope declares no law shards.

## Critique dispositions

| C# | DISPOSITION |
|---|---|
| C1 | human Should the t83 request be added to `docs/cascade/05b-briefs.md` as a recorded brief before this slice proceeds? |
| C2 | fixed: destination collision behavior is explicit in Task 2 and its fixtures. |
