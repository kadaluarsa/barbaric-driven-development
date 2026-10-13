---
description: Run this hop's /goal loop — executes `bash tests/loop.sh` and reports LOOP k/n
template: Run exactly `bash tests/loop.sh` (no arguments) and report its output verbatim. `LOOP k/n` is the script's line — never type it yourself. If it prints LOOP REFUSED (GENERATE hop, stage 01–04/11, no goal, or an UNPROVEN D#), stop and say so; do not work around it.

If k < n, fix the failing validator or add the omitted in-force D# to `docs/cascade/goal.md` (with its real validator command), then run it again. Never delete a test or waive a D# without a written `WAIVE_DSHARP:` reason approved by the human. Stop at the hop edge.
