# Stage 05b — t55-sign-ux-docs — SPEC

## User story IDs from the PRD

- **S-SX1** — As someone driving BDD from Claude Code Remote or the web, I sign a hop edge, a law, or
  an `AUTOPILOT:` list by approving the **HUMAN SIGNATURE NEEDED** dialog — without opening a terminal
  and without pulling the repo to a local machine to run a script and repush.
- **S-SX2** — As a first-time reader, the first signing instruction I meet in any doc is the dialog.
  `bash tests/sign.sh` appears only afterward, plainly labelled as the fallback for hand-editing from a
  plain git client or a non–Claude-Code agent.
- **S-SX3** — As a maintainer, nothing about signing *security* changed: the terminal fallback still
  exists and the agent still cannot run it.

## The problem, stated exactly

Two signing paths mint the identical one-shot token:

| Path | Who | Where it works | Agent can run it? |
|---|---|---|---|
| Approve the permission dialog (T30) | human clicks | anywhere Claude Code surfaces prompts — **incl. Remote/web** | no (can't click) |
| `bash tests/sign.sh` (T33) | human types | a terminal | no (`bash_guard` denies it) |

The docs lead with the terminal path. `docs/cascade/envelope.md:5` and `docs/cascade/hop-state.md:8`
both read "…in the permission dialog, or by editing this file and running `bash tests/sign.sh`", and
`README`/`USAGE`/`INTEGRATION` reinforce the script. On Claude Code Remote/web there is **no terminal
for the human**, so readers conclude they must clone locally, run the script, and repush — a round trip
that buys nothing, because approve-to-sign already produces the same token and works on those clients.

**This is a documentation-ordering bug, not a missing capability.** The fix is to re-order the guidance,
not to add or remove machinery.

## What the slice adds — and the line it must not cross

Docs-only re-ordering plus a version bump. Every place that explains *how to sign* leads with the
dialog and demotes `bash tests/sign.sh` to a clearly-labelled fallback, and the two most-read surfaces
gain an explicit "on Remote/web, approve the dialog — do not pull locally" line.

### The load-bearing constraint — the red twin

`tests/sign.sh` and the `bash_guard.py` rule that denies the agent from running it (or `bdd sign`) are
**unchanged**. The terminal fallback is the only signing path for a human on a plain git client or a
non–Claude-Code agent; removing it is a real capability loss, and because it lives in the I18
enforcement layer it would need its own hop with a red twin proving the agent still cannot self-sign.
**That deletion is explicitly out of scope here.** AC3 is the guard that keeps this a docs change: if a
future edit guts the fallback, AC3 goes red.

> Note on the original request: the ask was to "remove the fallback bash sign requirement." This slice
> removes the fallback's **primacy in the docs** (the implied requirement), not the fallback itself.

### Surfaces touched (docs + version only)

| File | Change | Human-owned? |
|---|---|---|
| `docs/cascade/envelope.md` | dialog-first wording on the sign line | yes → dialog-signed in EXECUTE |
| `docs/cascade/hop-state.md` | dialog-first wording on the sign line | yes → dialog-signed in EXECUTE |
| `README.md` | dialog-first; "one click, from anywhere incl. Remote/web" | no |
| `USAGE.md` | dialog-first; explicit Remote/web "don't pull locally" note; fallback labelled | no |
| `INTEGRATION.md` | dialog-first; fallback labelled as the non–Claude-Code path | no |
| `VERSION` | `1.9.2` → `1.9.3` | no |
| `CHANGELOG.md` | one entry for the slice | no |

## Acceptance criteria

- **AC1** — In every doc above, the line explaining how to sign presents the **dialog first**;
  `bash tests/sign.sh` appears only after it, labelled as the hand-edit / non–Claude-Code fallback.
- **AC2** — `USAGE.md` and `INTEGRATION.md` each state, in words, that on Claude Code Remote/web the
  human signs by approving the dialog and does **not** need to pull the repo locally.
- **AC3 — THE RED TWIN.** `tests/sign.sh` still exists, and `.claude/hooks/bash_guard.py` still denies
  an agent command that runs `tests/sign.sh` / `bdd sign`. A check asserts the denial still fires; if
  the fallback or its guard is removed, the check fails. *(This is the invariant, not a footnote.)*
- **AC4** — `VERSION` reads `1.9.3` and `CHANGELOG.md` has the matching entry.
- **AC5** — `git diff --name-only` for the slice touches only the files in the table above plus the
  AC3 check under `tests/`. No product/runtime behaviour changes: no hook logic, no `tests/sign.sh`,
  no enforcement path is modified.

## Laws

`NO D# IN FORCE`. This slice proposes none: it is documentation plus a version bump and changes no
product physics or domain invariant. AC3 is an enforcement/regression check (a `T#` in
`tests/enforcement.sh` or a small standalone check), **not** a domain law, and it is a *new* check — it
neither changes nor adds under any existing `tests/inv/*` (I13).

## PLAN

1. **Docs, human-owned** — reword the sign line in `docs/cascade/envelope.md` and
   `docs/cascade/hop-state.md`: dialog first, `bash tests/sign.sh` as the labelled fallback. Each edit
   raises the signature dialog in EXECUTE (that *is* the mechanism this slice documents).
2. **Docs, agent-writable** — same re-ordering in `README.md`, `USAGE.md`, `INTEGRATION.md`; add the
   explicit Remote/web "approve the dialog, don't pull locally" sentence to `USAGE.md` and
   `INTEGRATION.md`.
3. **AC3 check** — add a `T#` to `tests/enforcement.sh` asserting `bash_guard` still denies
   `bash tests/sign.sh` and that `tests/sign.sh` exists. New id; nothing under an existing D#.
4. **Version** — `VERSION` → `1.9.3`; add a `CHANGELOG.md` entry.
5. **Verify** — `bash tests/loop.sh` clean for this hop; re-read the diff adversarially (docs + VERSION
   + one new test only).

**Not in this slice:** deleting or weakening `tests/sign.sh` or its `bash_guard` rule (I18 — a separate,
red-twinned hop); any change to Layer 0/1/2 enforcement behaviour; a new signing channel for
headless / `bypassPermissions` sessions (a genuine feature — its own slice, its own spec).
