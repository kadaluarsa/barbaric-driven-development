---
description: Run this hop's /loop — `bash tests/loop.sh` — and report LOOP k/n. Legal only inside an approved EXECUTE of 05b / 06–09 / 10 punch.
---
Run `bash tests/loop.sh $ARGUMENTS` and report its output verbatim. `LOOP k/n` is the script's line — never type it yourself (I18). If it prints LOOP REFUSED (GENERATE hop, stage 01–04/11, or no goal), stop and say so; do not work around it.

If k < n, fix the failing validator or add the omitted in-force D# to `docs/cascade/goal.md` (with its real validator command), then run it again. Never delete a test or waive a D# without a written `WAIVE_DSHARP:` reason approved by the human. Stop at the hop edge.
