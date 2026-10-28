# /goal — this hop's definition of done

> ⚙️ **MACHINE-READ FILE.** Read by `tests/loop.sh`. Every field is machine-parsed.
> 🤖 **AGENT:** At the start of every EXECUTE hop run `bash tests/goal.sh reset`, then write this hop's validators.
> 🧑 **HUMAN:** Review before approving execute.

A goal is **one hop's** definition of done, not a record of every slice so far. Tests that must keep passing after
their slice is accepted belong to the regression suite (`docs/cascade/regress.md` — `bash tests/goal.sh reset` moves
them there; USAGE.md §B17), or to a law (a D# in `envelope.md`) if they must hold forever.
`tests/loop.sh` counts validators that were already in earlier slices' goals on every pass, and refuses the loop above
a cap (10, or a `GOAL_CARRY_MAX` the human signs in the envelope) — see USAGE.md §B16.

## Current goal

```
GOAL_STAGE: 05b
GOAL_SLICE: t82-task-routing
VALIDATOR: bash tests/ac/t82_task_routing.sh
VALIDATOR: bash tests/lint.sh # standing
VALIDATOR: bash tests/enforcement.sh # standing
```

## Format

Only lines starting at column 0 are read. The examples below are indented, so none of them runs.

    VALIDATOR: <a command that must pass>       one per line; every one must exit 0 for LOOP n/n
    VALIDATOR: bash tests/lint.sh # standing    a gate every hop reruns (lint, the full suite): counted, never carried
    WAIVE_DSHARP: D3 <reason>                   an in-force law left out on purpose, with the reason

- `GOAL_SLICE` must be this hop's `CURRENT_SLICE`; a goal for another slice is refused.
- Every in-force D# from `envelope.md` must appear as a validator (its `check:` command, verbatim) or be waived (I13).
- Clear this file on send-back (I9): `bash tests/goal.sh reset`.
