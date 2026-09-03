---
description: /barbar — score the farm; /barbar merge — the gate; /barbar auto — run the human-signed AUTOPILOT list of slices overnight, advancing only while every law holds.
---
- Arguments exactly `merge` → run `bash tests/barbar.sh merge`, report verbatim, stop. Never push or merge yourself.
- Arguments starting with `auto` → **autopilot** (below). Any text after `auto` is a brief: append it to `docs/cascade/05b-briefs.md` (create it if missing) and commit it before starting — briefs live in git, not in chat.
- Anything else → run `bash tests/barbar.sh`, report verbatim, stop. Print the `BARBAR k/n` line the script emitted — never compose it (I18). Do not GENERATE, EXECUTE, stitch, or "fix" a red farm with product code.

## `/barbar auto` — her overnight loop, with the bar kept

Run `python3 tests/lib/autopilot.py --status .`. If it prints `off`, stop with `AUTOPILOT HALT: no signed list` and tell the human the two lines they need: a brief in `docs/cascade/05b-briefs.md` and `AUTOPILOT: 05b <slice>` in the envelope, committed with their key. Only a human signs the list. If `done`, print the invariant block and `AUTOPILOT HALT: list complete — STITCH NEEDED: accept execute for stage N, or send back.` and stop.

Otherwise it names the next signed edge. Repeat until `done` or a HALT:

1. **GENERATE the slice** (spec + plan only, into `docs/cascade/`), commit it, print the invariant block and `STITCH NEEDED: review spec+plan for stage N`.
2. **Advance**: edit `CURRENT_HOP/STAGE/SLICE` in `docs/cascade/envelope.md` to exactly what `--status` says and commit. The hooks allow only that edge; if they BLOCK, stop with `AUTOPILOT HALT: <the hook's reason>`.
3. **EXECUTE the slice**: write `goal.md` with the AC tests and every in-force D#, build, `bash tests/loop.sh` until it prints `LOOP n/n`, `git diff`, commit, print the invariant block and `STITCH NEEDED: accept execute for stage N, or send back.`
4. **Advance** again (the hooks re-run `tests/loop.sh` against this hop before allowing it).

HALT immediately — do not work around — when: `tests/loop.sh` cannot reach n/n inside the slice; a law is RED, THEATER or UNPROVEN and only a human can change it; a hook BLOCKS an edge; the slice contradicts a law (a law admits no exceptions — say so, do not implement); anything needs `CASCADE_HUMAN`. Write `AUTOPILOT HALT: <reason>` as the last line so the Stop hook lets the session end. Stages 10, 11 and merge are never yours.
