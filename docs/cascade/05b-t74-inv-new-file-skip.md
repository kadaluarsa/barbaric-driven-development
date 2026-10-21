# Stage 05b — t74-inv-new-file-skip — SPEC

## User story IDs from the PRD

BDD's product is the cascade itself; the stories this slice serves:

- **S-IN1** — As an agent adding the red twin for a new D# (a mutant patch, a fixture, a table of its own), I can
  commit a new file under `tests/inv/` whatever its name, as AGENTS.md rule 5 promises ("you may add a test for a
  **new** D# id").
- **S-IN2** — As a human, when the hook refuses a commit it says why. It never exits 1 in silence.
- **S-IN3** — As the operator, the policy on existing `tests/inv/` files is unchanged: changing, deleting or
  extending one is a human-signed law edit, and a new `test_D<N>…` file for a declared law that names a different
  test is still refused.

## The problem, stated as cost

`.githooks/pre-commit` runs under `set -euo pipefail` (`.githooks/pre-commit:6`). Its tests/inv reuse check
extracts a law id from every **added** `tests/inv/` file:

```
id="$(basename "$f" | grep -oE '^test_D[0-9]+' | sed 's/^test_//')"     # .githooks/pre-commit:76
[[ -n "$id" ]] || continue
```

For a file not named `test_D…` (`tests/inv/mutants/D49.patch`), grep matches nothing, the pipeline fails, the
assignment's status is non-zero, and `set -e` ends the hook with exit 1 before the `continue` that was meant to skip
it. No message is printed. Reported from a downstream repo on 2026-10-21 and reproduced on `6703437`:

| Commit | Today |
|---|---|
| adds `tests/inv/test_D99.sh` (new id) | lands |
| adds `tests/inv/mutants/D99.patch` | **exit 1, no output, nothing committed** |
| appends a row to an existing `tests/inv/twins.tsv` | BLOCKED with "existing D# tests are human-owned (I13)" — by design |

The third row is not a bug: an existing file under `tests/inv/` is a law's test surface (AGENTS rule 5, I13). But
AGENTS.md does not tell an agent how to add a twin without touching a shared file, so the downstream agent hit the
silent exit, then the designed block, and handed the row to a human.

`.claude/hooks/hop_guard.py`'s copy of the check is already safe: its `re.match(r"test_(D\d+)", …)` returns None and
the check is skipped (`hop_guard.py:214-224`).

## Before vs after

Before:

```mermaid
flowchart TD
  A[commit adds tests/inv/mutants/D49.patch] --> B[pre-commit: id = basename \| grep test_D \| sed]
  B --> C{grep matches?}
  C -->|no| D[pipeline fails under set -e<br/>hook exits 1, prints nothing]
  C -->|yes| E[declared law names another test? BLOCKED with a message]
```

After:

```mermaid
flowchart TD
  A[commit adds tests/inv/mutants/D49.patch] --> B[pre-commit: id = basename \| grep test_D \| sed \|\| true]
  B --> C{id found?}
  C -->|no| F[not a law test name: skipped, commit continues]
  C -->|yes| E[declared law names another test? BLOCKED with a message — unchanged]
  G[change to an existing tests/inv file] --> H[BLOCKED with a message — unchanged]
  I[AGENTS.md rule 5] --> J[add a new law's twin as a new file under tests/inv/;<br/>an existing shared file is the human's]
```

## Benefits and trade-offs

| | Today | After t74 |
|---|---|---|
| New non-`test_D` file under `tests/inv/` | silent exit 1 | commits |
| New `test_D<N>_x` for a declared law naming another test | BLOCKED with a message | unchanged |
| Change to an existing `tests/inv/` file | BLOCKED with a message | unchanged |
| How to add a new law's twin | not documented | AGENTS.md rule 5: a new file; a shared table is the human's |
| Not chosen: let agents append rows for undeclared ids to an existing table (`twins.tsv`) | — | it relaxes a Layer 1 guard for a file format the pack does not define (I18: never weaken a layer); a new file per twin needs no exception |

## What the slice adds — and the line it must not cross

1. `.githooks/pre-commit:76` — `id="$(basename "$f" | grep -oE '^test_D[0-9]+' | sed 's/^test_//' || true)"`,
   the same `|| true` pattern as the `law=` line below it, with a comment saying why.
2. AGENTS.md rule 5, one sentence: the red twin for a **new** D# goes in a **new** file under `tests/inv/` (any name:
   a mutant patch, a fixture, its own table); adding to or changing an existing file there — a shared twins table
   included — is a law edit the human signs, and the hook names the file when it refuses.
3. `tests/enforcement.sh` T74 with the AC below.

Must not touch: what counts as an existing law test, the `MDR` filter on existing files, `hop_guard.py`'s check
(already safe), `tests/sign.sh`, any law's meaning.

## Acceptance criteria

`tests/enforcement.sh` T74 builds a scratch repo with the hook wired (`core.hooksPath .githooks`) and one declared
law `D1` whose `check:` names `tests/inv/test_D1.sh`:

- **AC1** — adding `tests/inv/mutants/D99.patch` commits (exit 0).
- **AC2** — adding `tests/inv/test_D99.sh` (an undeclared id) commits; adding `tests/inv/test_D1_vip.sh` (a declared
  law that names another test) is BLOCKED with "reuses declared D1" on stderr.
- **AC3** — changing the existing `tests/inv/test_D1.sh`, and appending a row to an existing `tests/inv/twins.tsv`,
  are each BLOCKED with "existing D# tests are human-owned".
- **AC4** — red twin: a copy of the hook without the `|| true` makes AC1 exit 1 with empty stderr — the silent
  failure, observed.
- **AC5** — AGENTS.md rule 5 contains the new-file sentence (presence check, like T0's).

Gate: `bash tests/enforcement.sh` (T74), `bash tests/lint.sh`.

## Laws

`bash tests/dsharp_strength.sh` prints `DSHARP 0/0`: NO LAW IN FORCE in this repo. The slice changes how the hook
skips a file it never meant to judge; no law and no existing-file policy changes.

# Stage 05b — PLAN

## Goal

EXECUTE makes `.githooks/pre-commit`'s id extraction set -e safe, says in AGENTS.md rule 5 how an agent adds a new
law's red twin, and adds T74 (AC1–AC5, one red twin).

## In scope this execute

- [ ] `.githooks/pre-commit:76` — `|| true` with a one-line reason.
- [ ] `AGENTS.md` rule 5 — the new-file sentence.
- [ ] `tests/enforcement.sh` T74; `CONTROL-LINE.md` T74 row and T-range; `CHANGELOG.md` entry (downstream repos
      re-run `install.sh`).
- [ ] `docs/cascade/goal.md` for the EXECUTE hop.

## Out of scope this execute

- Allowing appends to an existing shared file (rejected above).
- Word-splitting in the `for f in $(git diff …)` loop over added files (a path with a space): a separate defect,
  noted for a brief.
- t71's EDIT-tag pairing, t73's portable sed, the autopilot `CASCADE_ENVELOPE` leak.

## Definition of done

- `bash tests/enforcement.sh` exits 0 with T74, and T74's red twin is shown to go red.
- `bash tests/lint.sh` is clean (T-ranges updated).

## Risks / UNKNOWNs that still block

- **U1 — downstream copies.** Installed repos run their own `.githooks/pre-commit`; they get the fix only by
  re-running `install.sh` (or a plugin refresh when idle and clean). CHANGELOG says so.

## Ask of you

1. **Option (b) of the report, not (a):** an existing `tests/inv/` file stays human-owned, a shared twins table
   included; the agent adds a new file instead. *Default taken.*

## Invariants this hop

- PRESERVE run: no
- /goal set to: n/a — GENERATE; EXECUTE's goal is T74 + lint
- /model /effort: as set by the session
- /plan: skipped — this document is the plan
- INVARIANTS I1–I18: held
- Skills: none invoked; brainstorming skipped (brief signed; the one choice is Ask 1)
- reads: AGENTS.md, hop-state.md, envelope.md, 05b-briefs.md (t74), .githooks/pre-commit, hop_guard.py,
  tests/enforcement.sh (T25), the downstream bug report
