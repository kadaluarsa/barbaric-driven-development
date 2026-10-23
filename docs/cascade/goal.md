# /goal — this hop's definition of done

> ⚙️ **MACHINE-READ FILE.** Read by `tests/loop.sh`. Every field is machine-parsed.
> 🤖 **AGENT:** Write this file at the start of every EXECUTE hop.
> 🧑 **HUMAN:** Review before approving execute.

## Current goal

```
GOAL_STAGE: 10
GOAL_SLICE: release-2.7.0
VALIDATOR: CONF_MS=1000 bash tests/stress/gradle_runner.sh
VALIDATOR: bash tests/enforcement.sh
VALIDATOR: bash tests/lint.sh

# Punch item 0 (T69S): t62's stress AC7c measures configurations per wave with tuning off; CI ran it red.
# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
```
