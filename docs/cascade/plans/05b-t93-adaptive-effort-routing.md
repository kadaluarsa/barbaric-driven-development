# Stage 05b — t93-adaptive-effort-routing — draft PLAN

**Goal:** Add explainable, provider-neutral effort recommendations with explicit capability and cache-transition
guidance, while preserving the existing workflow classifier and human-owned cascade edges.

**Spec:** [`../05b-t93-adaptive-effort-routing.md`](../05b-t93-adaptive-effort-routing.md).

**Architecture:** One pure standard-library Python policy module, one thin shell CLI and one bounded advisory
line in the existing seam. Inputs explicitly carry state and capabilities; the pack makes no model calls or
configuration writes. No new state store, daemon, SDK, inference dependency or provider credential.

**Execution:** Inline in one approved EXECUTE hop, using the existing test-first and verification workflows.
No permission to execute is granted by this plan. Do not launch parallel implementation agents by default.

## Global constraints

- `classify(prompt)` and its existing CLI/eval behavior remain unchanged.
- Provider/model ids and prices are not hardcoded into policy.
- Internal effort levels are low/medium/high; provider levels are mapped, not assumed equivalent.
- Output is deterministic; application_status is always not_applied.
- Same-task retention never lowers a computed quality floor; cache concerns never lower that floor.
- No host-global configuration edits, automatic model/session changes or collection of raw prompt/log data.
- The current t91 frozen tests, manifest, human-owned hop fields and EDIT blocks remain untouched.
- New acceptance files are written and pinned during the future signed GENERATE hop, then read-only on EXECUTE.

## GENERATE completion prerequisites

- [ ] Human resolves the previous hop and signs GENERATE 05b t93-adaptive-effort-routing. Do not edit hop state
      on the human's behalf or use a temporary envelope to impersonate this transition.
- [ ] Write `tests/ac/t93_adaptive_effort_routing.sh` and `tests/ac/data/t93_effort_cases.json` to implement
      AC1–AC9 exactly. Use the existing shell fixture pattern in `tests/ac/t91_scorecard_routing.sh`:
      isolated repos, real CLI/hook/install invocations, assertions against outputs and exit codes.
- [ ] Data rows include a unique case id, context, optional profile, expected target/action/compatibility/
      transition and expected reason/warning subsets. Freeze cases before writing the policy. No percentage-only
      bar: every case passes, and each named red twin fails the intended behavior assertion.
- [ ] Oracle run command is exactly `bash tests/ac/t93_adaptive_effort_routing.sh`. Pin with:

```bash
bash tests/oracle.sh --write --run "bash tests/ac/t93_adaptive_effort_routing.sh" \
  tests/ac/t93_adaptive_effort_routing.sh tests/ac/data/t93_effort_cases.json
```

- [ ] Dispatch a fresh read-only spec critic per the pipeline, including both pinned files, existing seam,
      route classifier, installer and parity test. Commit findings verbatim, answer them, update spec/tests
      while GENERATE, and re-pin when needed. Run `bash tests/critique.sh`, `bash tests/oracle.sh` and lint.
- [ ] Stop for the GENERATE review. No implementation in this checklist.

## In scope this execute

Only after the human accepts the spec, plan and frozen oracle:

| Path | Responsibility |
|---|---|
| `tests/lib/effort.py` (new) | Validated context/profile types, pure policy, transition resolver and JSON CLI. |
| `tests/effort.sh` (new) | Existing wrapper pattern; Python entry point, no model calls. |
| `.claude/hooks/seam.py` | Append one bounded advisory line; preserve routing/empty/idle behavior. |
| `tests/enforcement.sh`, `CONTROL-LINE.md` | Register T93 and document only proven behavior. |
| `tests/ac/t69_gradle_tuning.sh` | Add exactly the new wrapper/helper paths to the installer parity allowlist. |
| `skills/bdd-work/SKILL.md`, `.claude/skills/bdd-work/SKILL.md`, `.agents/skills/bdd-work/SKILL.md` | Identical concise effort guidance; advice never grants cascade authority. |
| `USAGE.md`, `CHANGELOG.md` | CLI/schema examples, host limitations, source dates, cache semantics, manual checks. |
| `docs/cascade/goal.md`, `docs/cascade/regress.md` | Reset previous goal through script, then install this hop's validators and preserve carried tests. |

No `install.sh` change is planned: it already copies `tests/*.sh` and `tests/lib`. Verify the actual install
rather than adding another copy path. No release version bump is part of this proposed slice; release packaging
is a human decision outside this plan.

## Task 1 — policy and portable decision contract

Files: new `tests/lib/effort.py`, `tests/effort.sh`; frozen test/data files are consumers, never edited on EXECUTE.

Interfaces defined in this task:

```python
def parse_context(value: dict) -> EffortContext:
    """Reject malformed/unknown fields with ValueError; no side effects."""

def parse_profile(value: dict) -> CapabilityProfile:
    """Validate exact identity, source/date, enums and complete low/medium/high mapping."""

def recommend(context: EffortContext, profile: CapabilityProfile | None) -> EffortDecision:
    """Apply spec precedence; serialize via dataclasses.asdict with sorted JSON keys."""

def advisory(prompt: str, route: str, hop: str, stage: str) -> str:
    """Use conservative context only; return one bounded EFFORT line or empty for whitespace."""

def main(argv: list[str] | None = None) -> int:
    """--context FILE [--profile FILE]; <=64 KiB each; exit 0 or input error 2."""
```

- [ ] At EXECUTE start, run `bash tests/goal.sh reset`; set exactly the five validators in the spec. Check
      `bash tests/oracle.sh --loop` before editing product files.
- [ ] Run the frozen t93 command on the unimplemented tree; confirm it fails for the missing behavior,
      not invalid fixture setup. Preserve that failing output as task evidence.
- [ ] Define frozen dataclasses/enums matching the spec, with required fields, bounded identifiers and explicit
      unknowns. Validate nested JSON before evaluating policy; never interpret arbitrary strings as commands.
- [ ] Implement defaults, floors, state matching, escalation and overrides in the numbered precedence order.
      Keep capability resolution separate from the quality-target calculation inside the same focused module.
- [ ] Resolve compatibility and transition using the full truth table. Equal current/desired remains unchanged;
      absent profile/current and unsupported mappings remain explicit. Always return not_applied.
- [ ] Wrap the module using `tests/scorecard.sh`'s root-resolution pattern. The wrapper must work from another
      cwd and preserve Python's exit status. There is no eval, command interpolation or host setting mutation.
- [ ] Run frozen t93 policy/CLI cases; inspect exact failures. Do not weaken tests to fit the implementation.
      Full command may still fail the not-yet-built hook/install assertions until Task 2.

## Task 2 — seam and installation integration

Files: `.claude/hooks/seam.py`, bdd-work's three copies, `tests/ac/t69_gradle_tuning.sh`.

Consumes `effort.advisory(prompt, route, hop, stage) -> str` from Task 1. Existing `route_lines()` remains the
workflow entry point and retains its existing signature.

- [ ] Call advisory only where a nonempty prompt already receives ROUTE. Pass no invented complexity, profile,
      override, risk or history. Ambiguous routed prompts may receive conservative medium advice without changing
      their existing ROUTE text. Idle ambiguous/question cases stay silent.
- [ ] Honor `BDD_EFFORT=off`; add a bounded unavailable notice on helper/import failure while allowing the prompt.
      Append the line after existing ROUTE/STEPS/hint content, preserving the original lines byte-for-byte.
- [ ] Update bdd-work guidance identically in the three copies: effort is advisory, user override remains explicit,
      the portable CLI accepts structured context, host application is not claimed, cascade still owns edges.
- [ ] Extend only the t69 installer allowlist with `tests/lib/effort.py` and `tests/effort.sh`. Preserve its
      baseline and every existing comparison; verify install idempotence with the frozen t93 fixture.
- [ ] Run `bash tests/ac/t93_adaptive_effort_routing.sh`, then t91 and t67 commands from the spec. Confirm red
      twins fail their designated behavior checks and empty prompts still preserve baseline seam output.

## Task 3 — enforcement, operator docs and verification

Files: `tests/enforcement.sh`, `CONTROL-LINE.md`, `USAGE.md`, `CHANGELOG.md`, goal/regression documents as above.

- [ ] Add T93 using the same presence/exit-code pattern as T91. A product without the pack acceptance file may
      skip its meta-test; a present test that fails must fail enforcement. No softened existing gate.
- [ ] Add the spec's seven example decisions to USAGE, full JSON schema, example invocation and profile format.
      Show how an operator supplies an exact model id and source/date rather than recommending a baked-in winner.
      Include OpenAI, Anthropic, Gemini level/budget examples, with unknown cache effect unless documented for
      the exact platform/model/mode. Example values do not become runtime capability defaults.
- [ ] Explain that observed current effort must come from the host; a previous recommendation is insufficient.
      Unsupported/unknown profile results do not prove the task or host failed; application remains not_applied.
- [ ] State measurement requirements for future cost claims. No invented savings, fixed prices, throughput
      promises or GPU KV-memory estimates. Mark metrics unavailable in this offline slice.
- [ ] Run `bash tests/lint.sh`, the three named acceptance commands, then `bash tests/loop.sh`. No loop on GENERATE.
      Review the diff before asking for acceptance; run switch review if provenance requires it.
- [ ] Record the scorecard, drift and open findings truthfully. Commit only this slice; stop at the human edge.

## Out of scope this execute

- Applying host/API settings, editing global settings or selecting/changing a foundation model automatically.
- Provider SDKs, new credentials, a remote model registry, live telemetry, price estimation or cache benchmarks.
- Changing existing route precedence, patching t91 scorecard bugs, or fixing the stale switch-review gate.
- Automatic task identity inference, history scraping, a persistent policy store or autonomous retry orchestration.
- Stage progression, merging, release version selection or changes to existing laws and their tests.

## Definition of done

Frozen t93 oracle unchanged and all AC1–AC9 pass, including red twins. Existing t91/t67 checks, enforcement
and lint pass. CLI remains offline and side-effect-free; installation is idempotent. Human review can see
recommended effort, reasons, capability uncertainty and cache-transition guidance without any false applied claim.

## Risks / UNKNOWNs

- Host/API adapters do not exist in the current architecture; recommendation-only must be an explicit accepted MVP.
- Capability claims supplied by callers may be wrong or stale. The evaluator validates schema, not provider truth.
- Structured task/evidence inputs can be mistaken. They affect advice only and grant no gate or execution authority.
- No actual cache/cost reduction has been measured; a later adapter/eval slice must establish that benefit.
- Current human hop state is still t91 EXECUTE. Oracle tests/pinning and the formal GENERATE critique remain
  blocked until a human-signed transition. This draft is not a claim that those gates passed.
