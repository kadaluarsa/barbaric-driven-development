# /goal — this hop's definition of done

> ⚙️ **MACHINE-READ FILE.** Read by `tests/loop.sh`. Every field is machine-parsed.
> 🤖 **AGENT:** Write this file at the start of every EXECUTE hop.
> 🧑 **HUMAN:** Review before approving execute.

## Format

Indented here so `tests/loop.sh`, which reads every line that starts with `VALIDATOR:`, never takes this example
for the goal. Write the real lines unindented, under "Current goal".

```
  GOAL_STAGE: <stage ID>
  GOAL_SLICE: <slice slug>
  VALIDATOR: <command that must pass>
  VALIDATOR: <command that must pass>
  ...
  # WAIVE_DSHARP: D<N> <reason for one-hop waiver>
```

## Rules

| # | Rule | Enforced by |
|---|---|---|
| 1 | Every in-force D# from `envelope.md` must have a `VALIDATOR:` line here | `tests/loop.sh` — omitted D# is a FAIL entry |
| 2 | Or carry a `WAIVE_DSHARP:` line with a reason | `tests/loop.sh` — accepted for one hop only |
| 3 | Clear this file on send-back (I9) | `tests/loop.sh` — refuses stale goal |

## Current goal

```
GOAL_STAGE: 05b
GOAL_SLICE: t64-law-harness-jvm
VALIDATOR: bash tests/ac/t64_law_harness.sh
VALIDATOR: bash tests/stress/law_harness.sh "$(ls -d ~/.gradle/wrapper/dists/gradle-8.5-bin/*/gradle-8.5 | head -1)/bin/gradle" "$(ls -d ~/.gradle/wrapper/dists/gradle-9.1.0-bin/*/gradle-9.1.0 2>/dev/null | head -1)/bin/gradle"
VALIDATOR: bash tests/ac/t56_dsharp_parallel.sh
VALIDATOR: bash tests/ac/t63_quiet_stop_guard.sh
VALIDATOR: bash tests/enforcement.sh
VALIDATOR: bash tests/lint.sh

# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
```

## 🤖 AGENT: How to write /goal

1. Read `envelope.md` — list every D# that is in force (GREEN status).
2. Read this hop's spec — list every AC test the slice must pass.
3. Write `VALIDATOR:` lines for each.
4. If a D# cannot be tested this hop, add `WAIVE_DSHARP: D<N> <reason>`.
5. Run `bash tests/loop.sh` to confirm the goal is valid.

## 🧑 HUMAN: How to review /goal

- Every D# you signed is listed? ✅
- Every AC test for this slice is listed? ✅
- No `WAIVE_DSHARP:` without a reason you agree with? ✅
