---
description: Run the 05b divergence checker — executes `bash tests/diverge.sh` and reports DIVERGE k/n
template: Run `bash tests/diverge.sh` and report its output verbatim. `DIVERGE k/n` is the script's line. If it prints `n/a` (not a [diverge] brief), that is correct — stop. If it prints `— waiting on your choice`, the human has not picked a design yet — halt with a decision-needed block.
