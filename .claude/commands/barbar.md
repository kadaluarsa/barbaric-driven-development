---
description: Run the /barbar eval farm (or `/barbar merge` gate). Farm only — never builds, never merges.
---
If the arguments are exactly `merge`, run `bash tests/barbar.sh merge`; otherwise run `bash tests/barbar.sh` (ignore any other text — it is intent, not a flag). Report the output verbatim. Print the `BARBAR k/n` line the script emitted — never compose it yourself (I18). Then stop.

Do not GENERATE, EXECUTE, stitch, or start stage N+1. If the output says REFUSED, say so and do not push, merge, or "fix" the farm by writing product code.
