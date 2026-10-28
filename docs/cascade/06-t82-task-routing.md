# Stage 06 — Security, Privacy, Compliance — t82-task-routing

Status: GENERATE proposal; not an executed security review or a release approval.

## Authority and scope

The committed envelope accepts `docs/cascade/05b-t82-task-routing.md` and records no locked decisions. This document derives its design facts from that accepted spec. Implementation claims must be checked during EXECUTE. NO LAW IN FORCE: the envelope's D1 is a template, not a product law. No new D# is proposed.

Scope: the optional `/bdd-work` router, plugin/standalone distribution, routing fixtures, and P8 evidence. The router selects craft guidance, not permissions. Existing cascade gates remain authoritative. No product code, gate changes, autonomous transitions, or stages 07–09 belong to this hop.

## Data inventory

The accepted spec defines no new application database or account system. That does not establish that agent sessions or recorded probes contain no personal data.

| Data | Purpose and storage | Access | Retention and deletion |
|---|---|---|---|
| Requests and repository context | Select a route; read by the agent from the request, hop state, spec, and applicable laws | Agent host and anyone authorized for its session; provider processing UNKNOWN | Host/provider retention UNKNOWN; proposed use of synthetic probe requests only; operator must identify session deletion/export controls before sensitive use |
| Route cards and source-path evidence | Explain the next permitted action; agent output and possibly captured reports | Session viewers; repository readers if published | Proposed retention only with reviewed evidence; local removal does not remove provider copies or Git history |
| P8 transcript, tool stream, model/version and result | Prove one recorded investigation was read-only; captured probe artifacts | Probe operator and repository readers for committed artifacts | Proposed retention of sanitized synthetic evidence while that version's claim is maintained; raw sensitive output must not be committed |
| Skill text and routing fixtures | Distribution and conformance checks; plugin and standalone trees and eval files | Repository and installed-plugin users | Versioned with the pack; removal in a new commit does not erase historical copies |

Potential special categories: credentials, personal identifiers, private source, and usernames in paths can enter through context or tool output. Payment, health, children, and location data are not required by the accepted design; absence from actual artifacts is unverified. No secrets are needed to classify a route.

## Threat model — STRIDE-lite

| ID / boundary | Threat | Required control or review evidence |
|---|---|---|
| S06-1: request/context → route → action | Spoofing/elevation: a request or repository instruction claims human approval, asks to weaken a law, or disguises a change as investigation | Router defers to committed hop/spec and existing human approval; inspect negative fixtures and their scoring, not just successful examples |
| S06-2: route recommendation → cascade state | Tampering/elevation: GENERATE writes code, EXECUTE expands scope, or NONE starts a hop | Map the accepted AC3–AC6 cases to fixtures; confirm the router cannot treat its route card as authority; existing mechanical gates must remain unchanged |
| S06-3: source skill → installed skill | Tampering: plugin and standalone copies diverge or installation selects different instructions | Compare the copies and inspect T82 discovery/install coverage; equality is not provenance or authenticity proof |
| S06-4: agent run → evidence → reviewer | Repudiation/tampering: a fixture pass is presented as real-agent proof, mutations are omitted, or a historical result is generalized to all models | Record command, revision, model/version, exit status, tool stream and tree checks; separate fixture coverage from the limited P8 observation |
| S06-5: context/tool output → stored or published transcript | Information disclosure: private code, credentials or personal paths are copied into evidence | Synthetic inputs and pre-publication review; resolve retention/access questions; a route label is not a data-loss prevention control |
| S06-6: ambiguous request → repeated routing/probes | Denial of service: repeated interpretation or agent runs consume time and provider budget | Keep one named slice and one approved probe scope; inspect existing timeout/budget behavior before claiming a bound; no new retry runner in this slice |

## Controls

- **Authorization and admin paths (S06-1/2):** no new authn/session/admin service is specified. The human owns hop state, laws and approvals; the router introduces no break-glass path. Existing signing and gate mechanisms are dependencies to inspect, not guarantees supplied by this skill. Never use the human key or bypass a hook to finish this review.
- **Supply chain (S06-3):** verify plugin and standalone parity and discovery from the accepted revision. Package provenance and distribution permissions are UNKNOWN from the accepted spec; byte equality alone cannot prove a trusted publisher.
- **Evidence and security events (S06-4):** preserve test verdicts and refusal reasons in the review report. Do not add full production prompts as security logs. Missing tooling or a skipped probe is a gap, not PASS.
- **Secrets, encryption and tenancy (S06-5):** the router adds no secret store, transport, tenancy boundary or encryption implementation. Host/provider protections are UNKNOWN; do not claim the skill supplies them. Use a disposable synthetic repository for any newly approved model probe.
- **Resource limits (S06-6):** no new service rate limiter is proposed. Runtime limits and provider costs must be reported from observed runner behavior before rerunning a probe.

These are review requirements and proposals, not newly signed laws or verified implementation findings.

## Privacy

Proposed access/export flow: the operator identifies relevant local reports, Git artifacts and agent/provider sessions; verifies the requester's authority; then supplies only their data through approved channels. Provider export capabilities remain UNKNOWN.

Proposed deletion flow: remove local raw captures and generated copies, identify committed history and remote copies, and request provider-side deletion where supported. Do not rewrite shared Git history automatically. A credential discovered in evidence requires rotation as well as removal. The operator must confirm retention and deletion obligations before sensitive captures are allowed.

Subprocessors, tracking, consent and lawful basis are UNKNOWN in the accepted inputs. No additional analytics or collection is proposed. This review does not conclude that no privacy regime applies.

## Abuse, residual risk and decisions

An adversarial user may ask the router to impersonate approval, disguise writes as verification, or advertise one passing model run as universal protection. Existing boundaries and targeted evidence address those claims; prompt conformance remains weaker than a mechanical gate.

No risks have been accepted by the human in this stage. The following are proposed risk decisions, not assertions of acceptance:

| Risk | Proposed accountable owner | Proposed expiry / disposition |
|---|---|---|
| R1: prose routing can fail on untested models or prompts | Pack maintainer; human must confirm owner | Re-review at the next model/skill change and before stage 11; never claim universal enforcement |
| R2: transcript retention, access and provider deletion are unspecified | Probe operator; human must confirm owner | Block sensitive/real-user probe data until resolved; synthetic-only evidence proposed for this review |
| R3: distribution authenticity is outside the router's parity test | Pack maintainer; human must confirm owner | Resolve or explicitly accept before stage 11; do not describe parity as a supply-chain security guarantee |

## Compliance mapping

None locked — residual risk: deployment-specific privacy and compliance obligations are not identified by the accepted inputs. This is a scope statement, not legal clearance. No external compliance regime is invented or assessed here.

## EXECUTE acceptance criteria

- **SEC1:** Every S06 threat has a source/test reference or an explicitly unresolved finding in the execute report.
- **SEC2:** Existing T82 route/discovery checks and the standing enforcement suite have recorded actual results; no fixture result is described as model-behavior proof.
- **SEC3:** P8 evidence is assessed for provenance, read-only behavior, model/version limits and possible sensitive content; missing evidence is named. A fresh external model run requires agreed data handling and scope first.
- **SEC4:** Privacy unknowns and R1–R3 have a human disposition, confirmed owner and expiry where accepted; otherwise the security exit gate remains open.
- **SEC5:** Diff and security review show no product/gate/invariant-test changes or human-owned field edits by the agent. Any required remediation returns to an approved build slice.

## Exit gate — not yet satisfied

- [ ] Every identified PII field has confirmed retention and deletion.
- [ ] Existing admin/signing paths are inspected; no router bypass is introduced.
- [ ] The human explicitly accepts named risks with owner/expiry, or confirms no accepted risks after disposition.
- [x] Threats address this router and its evidence/distribution boundaries.

## Plan for a separately approved EXECUTE 06

Use the executing-plans skill within the cascade; no delegation, automatic commits or transitions are implied. This plan produces review evidence, not product functionality.

### 1. Establish the review baseline

- [ ] Confirm the committed EXECUTE 06 state and acceptance of this spec.
- [ ] Run `bash tests/goal.sh reset`; stop on refusal rather than carrying the old goal forward.
- [ ] Run `bash tests/affected.sh --shards` and read only the applicable law shards it names.
- [ ] Set this hop's goal to `bash tests/ac/t82_task_routing.sh`, `bash tests/enforcement.sh` as standing coverage, and any required in-force law checks. Keep the goal slice `t82-task-routing`.

### 2. Inspect the threat boundaries

- [ ] Read `skills/bdd-work/SKILL.md`, `.claude/skills/bdd-work/SKILL.md`, `install.sh`, `tests/ac/t82_task_routing.sh`, `tests/score_hops.py` and the t82 fixtures under `evals/hops/`.
- [ ] Inspect the existing gate/signing paths implicated by S06-1/2 without modifying them; distinguish local hooks, agent-specific controls and CI coverage.
- [ ] Review P8's definitions, stored transcript and result via `evals/spike/probes.sh` and `evals/probes/`; record the exact evidence paths and model/version. Do not launch the external probe merely to inspect its evidence.
- [ ] Map S06-1 through S06-6 to observed controls, coverage limits and findings. Do not copy discovered sensitive values into the report.

### 3. Validate and report

- [ ] Run `bash tests/loop.sh` for the approved goal; retain actual command results. No loop runs during GENERATE.
- [ ] Create `docs/cascade/06-t82-task-routing-execute.md` containing SEC1–SEC5 results, the threat/evidence matrix, data-handling gaps and risk decisions still requiring the human.
- [ ] Inspect `git diff` and perform the stage-required security review before requesting acceptance. Passing tests do not close unresolved privacy or risk decisions.
- [ ] Stop at the stage 06 edge. Do not start stage 07 or silently implement a remediation.

### File boundary

This GENERATE hop creates only this spec+plan. EXECUTE may write its report and hop-local goal; the prescribed goal reset may carry prior validators to `regress.md` through the existing script. Existing regression lines, human-owned envelope/hop fields, product code and `tests/inv/*` remain untouched by direct edits.

## Generate-hop report

Scope is `GENERATE 06 t82-task-routing`. NO LAW IN FORCE. No implementation or security validation has been performed by this document. Brainstorming/writing-plans are adapted to the cascade: one combined spec+plan under `docs/cascade/`, no separate process, automatic commit, implementation handoff or next-stage work. Human review is the next action.
