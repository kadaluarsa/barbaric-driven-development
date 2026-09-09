# Stage 05b — t52-environment-independent — SPEC

## The failure

CI is red on 1.8.1:

```
FAIL  T52  doctor goes red per dead layer (hooksPath, Layer 0 CI, hop state), …
```

Reproduced locally by making the pack look like CI — a fresh clone, no ambient git config:

```
hooksPath in fresh clone: ''
  L1  hooksPath  RED — core.hooksPath is unset — .githooks never runs …
DOCTOR 7/8
```

## Whose bug it is

**Doctor is right and the test is wrong.** A fresh checkout genuinely has no Layer 1: `core.hooksPath`
is git config, it does not travel with a tree, and reporting that as red is the single most valuable
thing doctor does. If doctor were quiet about it, the command would be pointless.

T52 asserted:

```
[[ "$rc52" -eq 0 ]] && echo "$out52" | grep -qE '^DOCTOR [0-9]+/[0-9]+$' || {
  ok=0; echo "  doctor is not clean in the pack itself: …"; }
```

"Doctor is clean in the pack itself" is a fact about the **machine**, not the code. This machine had
`core.hooksPath` set by an earlier install, so it passed here; a CI runner clones fresh, so it could
never pass there. The test read its environment and called that a property of the thing it names —
the same defect class as a prose claim nothing checks, which is what `lint.sh`'s stale-T-range guard
exists to catch.

**The wrong fix is to make doctor lenient** — treat an unset `hooksPath` as a skip, or exempt CI. That
would delete the check's whole reason to exist to turn a bar green, which is I18's forbidden move. The
layer really is dead in a fresh clone; the test simply must not assume it is alive.

## What the slice changes

One assertion in `tests/enforcement.sh`. The ambient-health check is replaced by a **constructed
positive control**: a scratch repo where `core.hooksPath` *is* set, in which that check must be green.
Paired with the existing `DOCTOR_MUTANT=hookspath` twin, T52 then proves both directions — green when
the layer is alive, red when it is not — without reading the environment either time.

Everything else T52 asserts stays exactly as it is:

- the three red twins (`hookspath`, `layer0`, `hopstate`)
- a skipped check is never counted as green
- branch protection is never claimed as checked
- a bare repo is diagnosed, not crashed on
- `commands/doctor.md` and `.claude/commands/doctor.md` byte-identical

The score line is still checked for shape (`^DOCTOR [0-9]+/[0-9]+$`), just not for a particular value.

## Files likely touched

- `tests/enforcement.sh` — the T52 block only
- `CHANGELOG.md` — the fix entry

Not touched: `tests/doctor.sh` (it is correct), the command files, `install.sh`, any other T.

## Tests that must pass

- `bash tests/enforcement.sh` with `core.hooksPath` **set** → `PASS: I18 T8–T52`
- `bash tests/enforcement.sh` with `core.hooksPath` **unset** → `PASS: I18 T8–T52`

Passing both is the proof: the same code, two environments, one verdict. Today the second is red.

- `bash tests/lint.sh` green.
- `bash tests/doctor.sh` unchanged in behaviour — still `DOCTOR 8/8` on a machine with hooks wired,
  still red on a fresh clone. That red is correct and stays.

## What the agent must not touch

- `tests/doctor.sh`. Softening a check to make CI green is the defect this pack exists to prevent (I18).
- Any T other than T52.
- `<EDIT>` blocks, `envelope.md`, human-owned `hop-state.md` lines, `evals/`.

## D# IDs this slice can break

None. No law is in force (`DSHARP 0/0`).

---

# Stage 05b — PLAN

## Goal

Execute rewrites T52's environment-dependent assertion as a constructed positive control, so the suite
gives the same verdict on a developer machine and on a fresh CI clone.

## In scope this execute

- [ ] Replace the "clean in the pack" assertion with a scratch repo whose `core.hooksPath` is set, in
      which doctor's `hooksPath` line must be green → `tests/enforcement.sh`
- [ ] Keep every other T52 assertion unchanged
- [ ] CHANGELOG entry

## Out of scope this execute

- Any change to `tests/doctor.sh`.
- Auditing the other 44 tests for the same environment-dependence. Worth doing; not this hop.
- The version bump. Cut it once CI is actually green, not before.

## Definition of done

1. `bash tests/enforcement.sh` exits 0 with `core.hooksPath` set.
2. `bash tests/enforcement.sh` exits 0 with `core.hooksPath` unset (a `git -c core.hooksPath= …`
   style run, or a scratch clone) — the case that is red today.
3. `git diff` touches only the T52 block and `CHANGELOG.md`.
4. `bash tests/lint.sh` green; `bash tests/doctor.sh` behaviour unchanged.

## Risks / UNKNOWNs that still block

- **Other tests may share the defect.** T52 is the one CI caught; nothing proves it is the only test
  reading ambient config. DoD 2 would surface a second offender by failing, and if it does, that is a
  finding to report at the edge rather than quietly widen this slice into.
- **The positive control must construct a real repo**, not stub the check. A control that fakes its
  way to green is the theater the pack forbids.

## Ask of you

None blocking. One thing to know: **1.8.1 is shipped and its CI is red.** The fix is a test change, so
the shipped `/doctor` behaves identically before and after — but the tag currently points at a commit
whose suite fails on a clean checkout. Whether that warrants 1.8.2 or an amended 1.8.1 is yours; the
plan cuts nothing until CI is green.

## Invariants this hop

- PRESERVE run: no
- /goal set to: the four DoD items above
- /model /effort: Opus 5, default
- /plan: used — this is the plan
- reads: manifest for this stage — loaded as written; also read `tests/enforcement.sh` T52 and the CI
  workflows as impact surface
- Skills skipped (I14): `brainstorming`, `writing-plans` — denied on this hop class; `systematic-debugging`
  was followed in substance (reproduced the CI environment locally before proposing a fix).
- INVARIANTS I1–I18: held. One hop, GENERATE only, spec + plan, no product code, no EXECUTE.
