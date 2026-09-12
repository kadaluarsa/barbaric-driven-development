# Stage 05b — t53-bdd-disable — SPEC

## User story IDs from the PRD

- **S-DS1** — As someone debugging something unrelated inside a BDD repo, I stand the pipeline down
  with one command and bring it back with one command, without hand-editing two files.
- **S-DS2** — As that same person three days later, I cannot mistake a disabled repo for a healthy
  one: every status surface says so before it says anything else.
- **S-DS3** — As a maintainer, a disabled repo still cannot merge. Standing down the local layers
  never stands down the gate.

## The problem, stated exactly

Disabling BDD today is two manual edits with no memory of what they replaced:

| Layer | Turn off | Turn back on | Remembers prior state |
|---|---|---|---|
| L1 git hooks | `git config --unset core.hooksPath` | `git config core.hooksPath .githooks` | **no** — the restore is a guess |
| L2 agent hooks | strip `hooks` from `.claude/settings.json` | `git checkout .claude/settings.json` | only if the file was committed clean |
| L0 CI + protection | — | — | not locally disableable (correct) |

Three failures follow from that:

1. **The restore is a guess.** `git config core.hooksPath .githooks` re-asserts the pack's default. If
   the repo had a different value, or none, that value is gone.
2. **A half-restore reads as damage.** `install.sh --check` reports `UNWIRED .claude/settings.json —
   Layer 2 is off`. That is the drift detector describing a deliberate switch as corruption, so the
   operator learns to ignore an `UNWIRED` line — which is the line that matters when it is real.
3. **A disable is silent and forgettable.** Nothing on any status surface says the pipeline is down.
   A repo can sit disabled for a week while `bdd check` reports no drift in every shipped file.

## What the slice adds

`bdd disable [repo]` and `bdd enable [repo]` — two new cases in `install-global.sh`, backed by
`tests/lib/disable.py` so the logic is testable without the launcher.

```
$ bdd disable
BDD DISABLED — barbaric-driven-development 1.8.1

  L1  hooksPath     core.hooksPath was .githooks -> unset
  L1  git hooks     stood down (files untouched)
  L2  agent hooks   5 hooks stripped from .claude/settings.json
  L0  CI            UNTOUCHED — CI still runs the farm, merge gate still refuses

  state saved to .cascade/disabled/ (gitignored)
  re-enable with: bdd enable
```

### What it stands down

- **Layer 1** — reads the current `core.hooksPath`, records it, then unsets it.
- **Layer 2** — lifts the `hooks` key out of `.claude/settings.json` and writes it verbatim to
  `.cascade/disabled/settings.hooks.json`. `enable` puts back exactly those bytes; it never
  regenerates the block from the pack, because regenerating silently discards local hook entries the
  product added.

### What it must never touch — the load-bearing constraint

**Layer 0 stays live.** `.github/workflows/control-line.yml` and branch protection are untouched, so
work done while disabled still goes red in CI and still cannot merge. Without that, `bdd disable`
is a merge bypass — precisely the I18 violation the pack exists to catch. This is the slice's red
twin, not a footnote.

### Loudness

A forgotten disable must be impossible to miss, so `BDD DISABLED` leads the output of every surface
that reports health:

| Surface | Behavior when disabled |
|---|---|
| `bdd status` | `BDD DISABLED (since <commit>)` before the autopilot line |
| `bash tests/doctor.sh` | first line `BDD DISABLED`; L1/L2 lines read `stood down`, not RED; score excludes them the way a `skipped` line does |
| `install.sh --check` | `DISABLED` — distinct from `DRIFT` and from `UNWIRED`, exit 0 |
| `.claude/hooks/seam.py` | prompt banner leads `BDD DISABLED — no hop seam in force` |

`.cascade/disabled/` is gitignored, so a disable is local and can never be committed into someone
else's clone.

## Acceptance criteria

- **AC1** — `bdd disable` then `bdd enable` restores `core.hooksPath` and `.claude/settings.json`
  byte-for-byte, including a repo whose `hooksPath` was unset or non-default before disable.
- **AC2** — With the repo disabled: `.github/workflows/control-line.yml` is unchanged and
  `bash tests/barbar.sh merge` still REFUSES. **This is the red twin.**
- **AC3** — `install.sh --check` on a disabled repo prints `DISABLED`, exits 0, and prints neither
  `UNWIRED` nor `DRIFT`.
- **AC4** — `bdd status`, `tests/doctor.sh` and the `seam.py` banner each lead with `BDD DISABLED`.
- **AC5** — `.cascade/disabled/` is gitignored; `git status --short` is clean after a disable.
- **AC6** — `bdd enable` on a repo that was never disabled exits 0 and says so; `bdd disable` twice
  is idempotent and does not overwrite the saved state with the already-stripped state.

## Laws

`NO D# IN FORCE`. This slice proposes none: disable/enable is enforcement plumbing, not product
physics, and AC2 is an enforcement test (a T# in `tests/enforcement.sh`), not a domain law.

## PLAN

1. `tests/lib/disable.py` — `save/strip/restore` for the two layers plus `is_disabled()`; the
   launcher and the status surfaces both call it rather than re-implementing the check.
2. `install-global.sh` — `disable)` and `enable)` cases calling it; refresh the usage header.
3. Loudness: `is_disabled()` branch in `tests/doctor.sh`, `install.sh --check`, and
   `.claude/hooks/seam.py`; `bdd status` gets the prefix.
4. `.gitignore` — `.cascade/disabled/`.
5. `tests/enforcement.sh` — `T23` for AC2 (disabled repo, Layer 0 intact, merge still refuses) and a
   round-trip test for AC1. T23 must fail if disable is made to touch the workflow.
6. Docs: `USAGE.md` and `INTEGRATION.md` gain the command and the "Layer 0 is never disabled" note.

**Not in this slice:** disabling the plugin machine-wide (that is Claude Code's plugin UI, not the
pack's to edit), and any change to Layer 0 or branch protection.
