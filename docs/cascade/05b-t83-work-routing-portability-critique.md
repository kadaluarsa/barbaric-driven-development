# Stage 05b — t83-work-routing-portability — CRITIQUE

## Brief

| C# | severity | finding | evidence |
|---|---|---|---|
| C1 | medium | No `t83-work-routing-portability` brief appears in `05b-briefs.md`; the closest entry is the earlier `t82-task-routing` brief. The spec therefore lacks a matching recorded brief for this slice. | `rg -n 't83-work-routing-portability\|work-routing-portability\|bdd-work' docs/cascade/05b-briefs.md` returns only the `t82-task-routing` entry at `docs/cascade/05b-briefs.md:414` |

## Spec

| C# | severity | finding | evidence |
|---|---|---|---|
| C2 | medium | The plan requires installation to avoid overwriting unrelated files, but does not define what to do when `.agents/skills/bdd-work/SKILL.md` already exists with different contents. That leaves the installer’s behavior and acceptance result ambiguous for a common collision. | `docs/cascade/plans/05b-t83-work-routing-portability.md:44-47` |
