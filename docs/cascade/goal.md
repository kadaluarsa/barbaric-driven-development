# /goal — this hop's definition of done

> ⚙️ **MACHINE-READ FILE.** Read by `tests/loop.sh`. Every field is machine-parsed.
> 🤖 **AGENT:** Write this file at the start of every EXECUTE hop.
> 🧑 **HUMAN:** Review before approving execute.

## Current goal

```
GOAL_STAGE: 05b
GOAL_SLICE: t66-affected-laws
VALIDATOR: bash tests/ac/t66_affected_laws.sh
VALIDATOR: bash tests/stress/affected.sh
VALIDATOR: bash tests/ac/t56_dsharp_parallel.sh
VALIDATOR: bash tests/ac/t64_law_harness.sh
VALIDATOR: bash tests/enforcement.sh
VALIDATOR: bash tests/lint.sh

# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
```
