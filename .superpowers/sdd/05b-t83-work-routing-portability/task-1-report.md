# Task 1 — Pin the shared route contract

## Scope

Completed Task 1 from the accepted [t83 implementation plan](../../../docs/cascade/plans/05b-t83-work-routing-portability.md) and [task brief](task-1-brief.md). Changes are limited to the focused acceptance check, the three `bdd-work` skill copies, and this report. Task 2 (`install.sh`) and Task 3 were not started.

## TDD evidence

- **RED:** Added `tests/ac/t83_work_routing_portability.sh` before changing the skills. `bash tests/ac/t83_work_routing_portability.sh` exited 1 with `FAIL: missing skill copy: .agents/skills/bdd-work/SKILL.md`, as expected for the unimplemented shared discovery path.
- **GREEN:** After creating the shared copy and aligning the other two copies, the same command exited 0: `PASS: three skill copies match; required metadata is valid; negative fixtures reject divergence and invalid metadata`.
- The acceptance check includes negative fixtures that append divergent content to one copy and invalidate its `name` metadata; each is rejected by the corresponding parity or metadata assertion.
- `git diff --check` passed.

## Implementation

- Updated the heading to identify the portable skill as `bdd-work`.
- Clarified that hosts invoke or load `bdd-work` through their documented mechanism, and `/bdd-work` syntax applies only where the host supports it.
- Created `.agents/skills/bdd-work/SKILL.md` and kept it byte-identical to `skills/bdd-work/SKILL.md` and `.claude/skills/bdd-work/SKILL.md`.
- The acceptance check verifies all three files exist, match byte-for-byte, and contain required `name: bdd-work` and non-empty `description` metadata.

## Self-review and limitations

Reviewed the final diff: routes, precedence, evidence guidance, and cascade boundaries are unchanged; only the invocation heading and introductory wording changed. No installer behavior, user-level files, law files, existing `tests/inv/*` files, or human-owned cascade content were changed by this task. Existing dirty edits to `docs/cascade/goal.md`, `docs/cascade/hop-state.md`, and `docs/cascade/regress.md` were left out of the Task 1 commit.

Only the focused acceptance check and whitespace validation were run for this task. Client discovery/runtime probes and install fixtures belong to Task 2 or Task 3 and are not claimed here.
