# Stage 06 — Codex CLI hook compatibility — SPEC + PLAN

Status: GENERATE proposal for `codex-compatibility`; not an implementation or a Codex runtime test.

## Authority and scope

The current hop is `GENERATE`, stage `06`, slice `codex-compatibility`. The host reports `codex-cli 0.165.0`. The accepted stage 05b spec says Codex support is out of scope for `t82-task-routing`; this is a separate slice and does not change that accepted artifact. NO LAW IN FORCE. No new D# is proposed.

Goal: make the BDD plugin discoverable and usable as a Codex CLI plugin, and remove hook errors while preserving the repo's approval, deny, logging, and hop-boundary behavior. Claude Code behavior must remain compatible. This slice does not claim compatibility with all Codex releases or hosts; the target is CLI 0.165.0.

Observed source facts:

- `codex --version` returns `codex-cli 0.165.0` in the current environment.
- The repository has `.claude-plugin/plugin.json` and `hooks/hooks.json`, but no `.codex-plugin/plugin.json`.
- `hooks/hooks.json` registers PreToolUse, PostToolUse, Stop, SessionStart, and UserPromptSubmit handlers.
- `hop_guard.py`, `bash_guard.py`, and `_common.py` return `permissionDecision: "ask"` for important guard and signature paths.
- Current Codex hook documentation explicitly says `permissionDecision: "ask"` is unsupported; Codex reports the hook as failed and continues the tool call. This directly explains at least one class of the reported hook errors and is a security-relevant fail-open behavior.
- Codex plugin documentation says plugin hooks are discovered from `hooks/hooks.json` when the selected compatibility manifest does not override them, and plugin hooks are skipped until the user reviews and trusts the current hook definition.

These are source and documentation findings. The reported session's complete hook error log has not been captured, so other errors remain possible and the exact runtime behavior must be checked in EXECUTE.

## Proposed behavior

1. Package metadata exposes the existing skill directory and hook bundle to Codex through a compatibility manifest, leaving the Claude manifest and plugin surface intact.
2. Hook commands use Codex's documented plugin root environment while remaining runnable in Claude Code. The runner continues resolving the same BDD hook implementations.
3. Hook input handling accepts Codex 0.165.0 event fields and tool names for all currently registered events. Codex `apply_patch` must receive the existing write/edit policy checks.
4. Hook output is host-aware. It emits only response fields supported by the active host and event. No path emits the unsupported `permissionDecision: "ask"` value to Codex.
5. A policy denial remains a supported hard deny. A human-signature request must never be converted into an allow or silently treated as an ordinary denial that appears to approve the change. If Codex cannot provide a human approval prompt for a hook, the safe fallback is to deny the mutation with a clear instruction for a human to use the documented signing path. Any more convenient approval mapping must be demonstrated to preserve a real human decision under default and bypass permission modes.
6. Codex hook installation, trust review, and an untrusted project layer are documented as separate from the BDD repo-side git enforcement. Hooks that are skipped or untrusted must not be described as active enforcement.

## Data inventory

| Data | Purpose and storage | Access | Retention and deletion |
|---|---|---|---|
| Hook event JSON (`cwd`, session/event identifiers, prompts, tool input/output) | Local hook process stdin; used to locate the repository and apply the existing policy | Local Codex process and the invoked hook; Codex transcript handling is governed by Codex | This slice should not add transcript capture or persist event payloads. Existing BDD decision logging stores policy decisions, not raw payloads. Codex transcript retention/deletion remains controlled by Codex and is not changed here. |
| Repository paths and cascade state | Read from the active repo; used for hop/law checks | Local hook process and repository readers | No new storage. Existing git-dir marker and decision-log behavior remains. Git history is not removed by this slice. |
| Plugin hook definitions and scripts | Packaged under plugin root and loaded by Codex after trust review | Plugin users and local Codex runtime | Versioned in the repository. Users can review and revoke hook trust through Codex. Existing Git history remains. |

Possible sensitive data in hook event JSON includes prompts, source code, file paths, and command arguments. The plugin must not persist raw event JSON or claim a comprehensive secrets scan. No new provider transmission is introduced by this slice.

## Threat model — STRIDE-lite

| Boundary / threat | Risk | Required control or evidence |
|---|---|---|
| Plugin package → Codex discovery (spoofing/tampering) | Missing or malformed compatibility metadata can prevent intended hooks from loading or select an unintended configuration. | Add and validate the Codex compatibility manifest; verify the loaded source with Codex's `/hooks` UI and inspect hook trust state. |
| Codex PreToolUse → BDD policy (elevation) | Unsupported `ask` output is reported as an error and the tool call continues, bypassing the intended BDD decision. | Remove unsupported outputs from Codex paths; prove denied operations do not run and every human-signature operation either receives a real human decision or is denied. |
| Codex event schema → shared hook logic (tampering/elevation) | Tool-name, input, matcher, or output differences can skip checks or cause invalid output. | Cover `apply_patch`, `Bash`, Codex event fields, and each registered output shape with focused compatibility fixtures and a real CLI probe. |
| User trust/config → plugin hooks (elevation) | Codex can skip non-managed plugin hooks until their definitions are reviewed and trusted; a project-local layer can also be untrusted. | Document the review/trust step. State clearly that hook enforcement is inactive until Codex reports the hook definition as trusted; retain git/CI gates as enforcement layers. |
| Hook process → local files/transcript (information disclosure) | Raw prompts or tool payloads may contain secrets or private code. | Do not add raw event/transcript storage. Keep any diagnostics redacted and bounded; test that normal hook operation does not write payloads into repo or plugin data. |
| Multiple matching hook sources (denial of service / confusing behavior) | User, project, and plugin layers may all load matching hooks and race or duplicate decisions. | Preserve idempotency for duplicate calls; inspect actual loaded hook sources and avoid relying on hook execution order. Keep individual handlers bounded by existing timeout policy. |

## Controls and privacy

- **Authentication / authorization:** no user identity or account system is added. Codex's trust review controls whether plugin hooks run; BDD's git hooks, CI, and human signature remain the durable controls for repository changes.
- **Human-signature path:** Codex PreToolUse does not support the current `ask` response. EXECUTE must choose and prove a safe Codex path before changing the hook adapter. If a Codex-native permission prompt cannot be reliably enlisted for a protected write, Codex must deny and direct a human to sign through the established path. Never infer human approval from the absence of a hook error.
- **Session and secrets:** do not read Codex transcript files or add credentials. Use synthetic prompts and paths in probes. Do not log raw tool arguments or prompts.
- **Supply chain:** Codex hook definitions are user-reviewable and trust is tied to the current definition; changes require renewed review. Repository release metadata and the Claude distribution must remain coherent.
- **Rate limits / resource use:** keep existing hook timeouts and avoid new network calls. No model probe is needed for ordinary hook behavior; any live probe uses a bounded local fixture.
- **Compliance:** none locked. Residual risk: local prompt/tool data is handled by Codex according to its own data controls; this repo cannot set Codex transcript retention.

## Abuse and residual risk

An agent or user could exploit an invalid hook response or an untrusted/disabled plugin hook to make a forbidden operation proceed. The primary mitigation is a valid Codex output contract plus independent git/CI enforcement. A local hook cannot prove that every Codex tool path is intercepted, so runtime coverage is bounded to documented hook-supported tool paths and the tested CLI version. Changes to hook definitions require user trust review, which can temporarily leave hooks inactive.

No new accepted-risk owner/expiry is proposed from incomplete evidence. The exact errors in the user's session, installed plugin source, and trust status remain UNKNOWN until an EXECUTE probe. No security claim should be broadened beyond the local CLI/version and hook paths exercised.

## Security and privacy exit gate

- [x] The proposed design adds no persistent PII fields; hook event payloads remain transient and are not newly captured. Codex transcript access/deletion stays with Codex.
- [x] The human control path is specified: Codex hook trust is reviewed by the local user, and protected writes require a verifiable human signature or are denied.
- [x] No accepted risks are proposed in this spec. The remaining unknowns are unresolved and must not be treated as accepted risks; if EXECUTE cannot resolve them, record an owner and expiry with the human before acceptance.
- [x] Threats describe this plugin's Codex packaging, hook protocol, trust, and local event data.

## Acceptance criteria

- **AC1 — Discovery:** Codex CLI 0.165.0 discovers the BDD plugin and its skill/hook resources from the compatibility manifest without breaking the Claude plugin manifest.
- **AC2 — No hook errors:** each registered hook event runs with a valid Codex 0.165.0 input/output contract and produces no reported hook error on its normal, no-op, deny, and human-signature paths.
- **AC3 — No fail-open guard:** unsupported `ask` output is absent from Codex hook responses; a protected tool operation cannot proceed because a guard emitted an invalid result.
- **AC4 — Signature integrity:** human-owned edits are never approved by automation. The Codex path either presents a verifiable human decision or denies with clear instructions for the human signing path, including in bypass-permissions mode.
- **AC5 — Event coverage:** `Bash` and Codex `apply_patch` events reach the intended BDD guards; `SessionStart`, `UserPromptSubmit`, `PostToolUse`, and `Stop` outputs are accepted by Codex.
- **AC6 — Trust clarity:** documented steps identify Codex hook review/trust and project trust requirements; the test report distinguishes an untrusted/skipped hook from a passing hook.
- **AC7 — Claude preservation:** existing Claude hook wiring and output semantics remain valid; no change weakens existing BDD or D# gates.
- **AC8 — Privacy:** no raw prompt, tool input/output, or Codex transcript is newly persisted or transmitted.

## Test and review strategy for EXECUTE

1. Add compatibility fixtures for Codex hook event payloads and validate every response against the documented 0.165.0 event contract. Include unsupported-output counterexamples, especially `permissionDecision: "ask"`.
2. Exercise the policy adapter on synthetic `Bash` and `apply_patch` events. Assert that safe operations pass, forbidden operations deny before execution, and human-signature writes are never auto-approved.
3. Add manifest/discovery checks for `.codex-plugin/plugin.json`, the default `hooks/hooks.json` discovery, skill paths, and unchanged Claude metadata.
4. Run a real local Codex CLI 0.165.0 probe in a disposable repository with synthetic content. Inspect `/hooks` for source, matchers, trust, and errors; exercise startup, prompt, tool, edit, and stop events. Preserve only redacted result metadata, not transcript or raw tool payloads.
5. Run existing focused plugin/hook enforcement checks and the repo's required stage goal validators. Do not modify existing `tests/inv/*` files; any new D# work is out of scope.

The real CLI probe is needed because a fixture can prove output shape but not actual Codex plugin discovery, trust state, or runtime behavior. No claim about other CLI versions follows from that probe.

## Plan

### Files expected to change in EXECUTE

- `.codex-plugin/plugin.json` — Codex compatibility metadata pointing at the existing skills. Do not declare a competing inline hooks value unless required; default discovery of `hooks/hooks.json` should remain the source.
- `hooks/hooks.json` and `hooks/run.sh` — Codex command paths/environment integration, while retaining Claude compatibility.
- `.claude/hooks/*.py` — only the smallest shared hook-input/output adapter changes needed for Codex; preserve valid Claude responses.
- `tests/ac/` — new compatibility acceptance test for manifest, event payloads, host-specific outputs, and fail-closed signature semantics.
- `tests/enforcement.sh` — register the new acceptance check if required by current suite conventions.
- `README.md` and `USAGE.md` — install/trust instructions and tested-version scope.
- `VERSION` and `CHANGELOG.md` — only if the repository's release convention requires a versioned distribution update.

### Execute sequence

1. Confirm Codex 0.165.0's actual loaded hook sources and capture the user's error class from a synthetic isolated repo; do not capture real prompts or private command inputs.
2. Add failing compatibility fixtures for the Codex event shapes, manifest discovery, host-aware responses, and human-signature fail-closed behavior.
3. Implement the Codex manifest and the narrowest shared adapter that passes the fixtures while preserving Claude outputs.
4. Run the real CLI probe in a disposable repo; inspect trust state and verify each event without weakening permissions or bypassing human-signature requirements.
5. Update installation/trust docs and release metadata according to current repository convention.
6. Run slice acceptance checks plus existing hook/enforcement regressions; inspect the final diff and verify no human-owned cascade fields, laws, or existing invariant tests changed.

### Definition of done

AC1–AC8 pass with recorded commands and outcomes. The Codex runtime probe uses CLI 0.165.0, synthetic data, a disposable repo, and reviewed/trusted hook definitions. No human-owned state changes or D# changes occur. Any remaining unsupported event path or platform limitation is named in the report.

## Generate-hop report

- Hop: `GENERATE 06 codex-compatibility`.
- Laws in force: none; the envelope D1 is an unsigned template.
- Product code: none.
- Root cause confirmed from source and current Codex documentation: Codex reports `permissionDecision: "ask"` as unsupported and continues the tool call. A Codex compatibility manifest is also absent.
- Runtime observation: not yet performed; the exact hook errors in the user's session and the current trust state remain unknown.
- External reference: [Codex hooks](https://developers.openai.com/codex/hooks), [Codex plugin packaging](https://developers.openai.com/plugins/build/plugins).
