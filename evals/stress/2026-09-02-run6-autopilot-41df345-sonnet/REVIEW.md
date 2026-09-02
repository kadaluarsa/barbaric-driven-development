# Run 6 — first autopilot run: 1/4, and two real findings

`/barbar auto` did nothing: 3 turns, plain `bash tests/barbar.sh`, report worded like the *skill*. Two causes, both now fixed with tests:

1. **A skill named `barbar` shadowed the `/barbar` command.** With both installed, the skill (no `auto` mode) won. Renamed to `cascade-farm` (`eb23cc5`); the command is the only user-facing `/barbar`.
2. **`stop_guard` was blind in headless mode.** It parsed the transcript file for the last assistant text and found nothing (`last_len=0`), so it never blocked a stop — not for a missing edge line, not for pending autopilot edges. The Stop event carries `last_assistant_message`; the hook now reads it (T28). This also retracts the earlier claim that the Stop hook "fired live in P3": that match came from the agent `cat`-ing the hook's source. Harness detection now ignores tool results.

Instrumented ground truth (marker files on hook entry, headless `claude -p --dangerously-skip-permissions`): `seam`, `stop_guard`, `bash_guard` all run. Layer 2 is real headless; the Stop path simply had a parsing bug.

The trap passed under autopilot (off-list slice, human-flipped: the agent stopped, no product write).
