# /goal — this hop's definition of done

> ⚙️ **MACHINE-READ FILE.** Read by `tests/loop.sh`. Every field is machine-parsed.
> 🤖 **AGENT:** Write this file at the start of every EXECUTE hop.
> 🧑 **HUMAN:** Review before approving execute.

## Current goal

```
GOAL_STAGE: 05b
GOAL_SLICE: t75-xcode-runner
VALIDATOR: bash tests/ac/t75_xcode_runner.sh
VALIDATOR: bash tests/ac/t69_gradle_tuning.sh
VALIDATOR: bash tests/ac/t68_law_retirement.sh
VALIDATOR: bash tests/ac/t65_verdict_cache.sh
VALIDATOR: bash tests/ac/t64_law_harness.sh
VALIDATOR: bash tests/enforcement.sh
VALIDATOR: bash tests/lint.sh

# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
```
