---
description: /barbar — score the farm; /barbar merge — the merge gate; /barbar auto — run the signed AUTOPILOT list; /barbar init — first-knowledge discovery
template: 
- Arguments exactly `merge` → run `bash tests/barbar.sh merge`, report verbatim, stop. Never push or merge yourself.
- Arguments exactly `init` → scan the repo and propose laws and audit rows for the human to sign. Never write `docs/cascade/envelope.md` or `10-audit.md` yourself.
- Arguments starting with `auto` → run `python3 tests/lib/autopilot.py --status .` and follow the autopilot protocol.
- Anything else → run `bash tests/barbar.sh`, report verbatim, stop. Print the `BARBAR k/n` line the script emitted — never compose it. Do not GENERATE, EXECUTE, stitch, or "fix" a red farm with product code.
