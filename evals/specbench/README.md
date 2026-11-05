# Spec-wording benchmark

This benchmark tests a hypothesis. It has no result yet, and the pack claims no gain.

| Arm | The agent receives |
|---|---|
| A | The original request. |
| B | The request in controlled language. |
| C | The request in controlled language, with an execution contract. |

## Run protocol

The human starts each paid run. No script here calls a model.

1. Use the same model, tools and repo for each arm.
2. Write hidden tests for each row in `tasks.tsv`. The agent must not see them.
3. Run each task in each arm two times or more. `evals/spike` can host the agent in a container.
4. Write one JSON object for each run.
5. Run `bash tests/specbench.sh score FILE`.

`unneeded_lines` counts changed lines outside the scope of the task's reference solution.

Each object holds `task`, `arm`, `run`, `hidden_pass`, `unneeded_lines`, `repairs`, `tokens`, `seconds` and `tool_calls`.

`bash tests/specbench.sh --dry-run` scores `fixture.jsonl`. Its numbers are placeholders, not measurements.

This directory is pack-only and does not install.
