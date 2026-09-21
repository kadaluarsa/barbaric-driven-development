# Stage 05b — t56-dsharp-parallel — SPEC

## User story IDs from the PRD

- **S-PF1** — As someone with many independent, hermetic laws, I run `DSHARP_JOBS=4 bash tests/dsharp_strength.sh`
  and it scores laws concurrently, finishing faster, with the **same `DSHARP k/n` and the same per-law
  verdicts** as a sequential run.
- **S-PF2** — As a maintainer, the **default is unchanged**: with no `DSHARP_JOBS` (or `=1`), output is
  byte-for-byte what it is today. No existing repo's verdict, ordering, or exit code changes unless it
  opts in.
- **S-PF3** — As someone whose laws share a daemon/port/build dir, I am never silently raced into a false
  verdict: a law can be marked `serial` and always runs alone, and the slice's red twin proves a parallel
  run equals the sequential run.

## The problem, stated exactly

`dsharp_strength.sh` scores laws in a sequential `while` loop — for each declared D# it runs `check:`
then `break:`. Wall time is the **sum** of every law's runtime, and on a repo whose laws are heavy
(e.g. gradle builds) that is hours. The commands are independent, so the wall time is reducible by
running them concurrently.

But this is the **verification tool**, so speed must never buy a wrong answer (I17/I18). The failure to
prevent is a **race that flips a verdict** — most dangerously a `RED` law reported `GREEN` because two
jobs shared a daemon, a port, a build dir, or a temp file. A faster farm that can lie is worse than a
slow one that cannot.

## What the slice adds — and the line it must not cross

An **opt-in, deterministic, bounded** parallel mode for `dsharp_strength.sh`, verdict-identical to
sequential.

- **`DSHARP_JOBS=N`** (env; default `1`). `1` = today's exact sequential path. `N>1` runs up to N laws'
  scoring concurrently via a bounded worker pool.
- **Deterministic output.** Each law's verdict line is captured and printed in **declared order**
  regardless of N, and `DSHARP k/n` and the exit code are computed from the collected results — so the
  report and the verdict are identical to sequential, only faster.
- **`serial` opt-out.** A law that cannot be isolated is marked `serial` on its D# line; such laws never
  run concurrently (run in a final sequential pass). The pack **does not fabricate isolation** — it does
  not silently give each job a clean worktree (that would change *what* is tested: dsharp scores the
  working tree, uncommitted changes included, and a HEAD-only checkout would miss them). Hermeticity is
  the law author's responsibility; `serial` is the safe escape hatch, documented.

### The load-bearing constraint — the red twin

**A parallel run MUST produce the identical `DSHARP k/n` and the identical set of per-law verdicts as the
sequential run.** `tests/ac/t56_dsharp_parallel.sh` runs a fixture set of laws at `DSHARP_JOBS=1` and at
`DSHARP_JOBS=4` and asserts equality of both the score and every per-law verdict. `T56_MUTANT=race`
reproduces a broken collector (a law dropped, duplicated, or misordered under concurrency) and MUST turn
it red. This AC is the slice, not a footnote.

### Language-agnostic by construction

The pool runs **arbitrary command strings** — it makes no gradle/JVM assumption. The fixture laws use
plain shell (`sleep`, `true`/`false`, a file write), never gradle, so the test proves the mechanism, not
a toolchain.

## Acceptance criteria

- **AC1** — Default path unchanged: with `DSHARP_JOBS` unset or `1`, the output (lines, order, `DSHARP
  k/n`) and exit code are byte-for-byte identical to the pre-change script on the same envelope.
- **AC2 — THE RED TWIN.** On a ≥3-law fixture, `DSHARP_JOBS=4` yields the **same `k/n` and the same
  per-law verdicts** as `DSHARP_JOBS=1`. `T56_MUTANT=race` (drop/dupe/misorder a result) turns it red.
- **AC3** — Output order is the declared order for any `N` (deterministic report, not first-to-finish).
- **AC4** — A law marked `serial` is never run concurrently, even at `DSHARP_JOBS=8`.
- **AC5** — Language-agnostic: the fixture laws are plain shell; no gradle/JVM in the test path.
- **AC6** — Exit code semantics unchanged: `0` iff every declared law is GREEN, at any `N`.
- **AC7** — Concurrency is bounded: at most `N` law jobs run at once (no fork bomb on a 40-law repo).

## Laws

`NO D# IN FORCE`. This slice proposes none: it is tooling/performance, not product physics. AC2 is an
enforcement/regression test (a `tests/ac/` script, optionally mirrored as a `T#` in
`tests/enforcement.sh`), **not** a domain law, and it is a *new* test — it neither changes nor adds under
any existing `tests/inv/*` (I13).

## PLAN

1. **Refactor for a unit of work.** Extract "score one law" from the loop into a function that, given
   `id|law|val|twin`, emits a structured result (id, verdict token, full line) to a per-law temp file —
   no shared mutable state between invocations.
2. **Bounded pool.** Add a worker pool gated on `DSHARP_JOBS` (background jobs + a `wait`-throttle, or
   `xargs -P`), capped at N. `DSHARP_JOBS<=1` takes the existing sequential path unchanged (AC1).
3. **Deterministic collect.** After the pool drains, read results in declared order, print the verdict
   lines, sum `k/n`, set the exit code — identical shape to today (AC2/AC3/AC6).
4. **`serial` marker.** Parse an optional `serial` flag on the D# line (via `tests/lib/laws.py`); route
   those laws to a final sequential pass (AC4).
5. **Red twin.** `tests/ac/t56_dsharp_parallel.sh`: fixture envelope of plain-shell laws; assert
   `jobs=1` == `jobs=4` for score and per-law verdicts; `T56_MUTANT=race` proves it can fail (AC2/AC5).
6. **Docs.** `USAGE.md` / `INTEGRATION.md`: document `DSHARP_JOBS`, the determinism guarantee, the
   hermeticity requirement, and `serial`.
7. **Version.** `VERSION` bump (+ `plugin.json`/`marketplace.json` to match, per T31) and a `CHANGELOG`
   entry.
8. **Verify.** `bash tests/loop.sh` clean (goal.md validators: the t56 AC script + `enforcement.sh`);
   re-read the diff adversarially.

**Not in this slice** (each its own hop):
- **Memoization / skip-unchanged** (cache a GREEN verdict by tree-hash) — higher risk (a stale cache is a
  false GREEN) and needs per-law input scoping; separate slice.
- **Parallelizing `enforcement.sh` / the farm stages** — those throwaway-repo cases are hermetic by
  construction and a cleaner parallel target, but a different slice.
- **Auto-isolating non-hermetic laws** (per-job worktrees/caches) — the pack offers `serial`, it does not
  fabricate isolation or change what the working tree under test contains.
- **Gradle-specific tuning** (daemon, `GRADLE_USER_HOME`, narrow tests) — that is the law author's config,
  not the pack's code.

## Decision for the human (flag at the edge)

Default is `DSHARP_JOBS=1` (opt-in), so **nothing changes for anyone until they set it** — that is the
safe default and the reason this can land without a law change. If you would rather it default to
`nproc`, say so on review; I would still keep `serial` and the parallel==sequential red twin, but the
blast radius of a bug would be everyone instead of opt-in users. My recommendation: ship opt-in.
