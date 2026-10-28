# Stage 05b — t82-task-routing — CRITIQUE

Written by a fresh read-only critic. Rows below are verbatim.

## Brief

NO FINDINGS

## Spec

| C# | severity | finding | evidence |
|---|---|---|---|
| C1 | medium | The plan does not specify how the real-agent probe will be scored. It asks the transcript to show the route and evidence action, but the existing probe harness scores with text matches; recording a transcript alone would not establish that the agent followed the route. | `docs/cascade/05b-t82-task-routing.md:64`, `docs/cascade/05b-t82-task-routing.md:126`; `evals/spike/probes.sh:47-50` |

## Dispositions

| C# | DISPOSITION |
|---|---|
| C1 | fixed — P8 now has explicit pass conditions for the route label, source-path evidence, absence of mutating tool calls, and a clean product tree; the result is scoped to the recorded model and version. |
