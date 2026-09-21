# Stage 05b — t58-enforcement-cache — SPEC

## User story IDs from the PRD

- **S-EC1** — As someone running the farm repeatedly while working on a product, I don't pay the full
  `enforcement.sh` cost (~53s here) on every run when the pack it tests hasn't changed — an unchanged
  tree is served from cache in well under a second.
- **S-EC2** — As a maintainer, the cache can never hide a regression: a changed tree always re-runs, a
  failing run is never cached green, and CI / a fresh clone always runs the full suite.

## The problem, stated exactly

`tests/enforcement.sh` is the pack's meta-suite (T8–T54). It tests the pack's *own* hooks and scripts by
building throwaway repos — it is **product-independent** (gradle-free), so it costs ~53s (measured on a
4-core box; tmpfs made no difference — it is CPU/interpreter-bound, not I/O-bound) whether you run it on
this pack or on a JVM product. That cost is paid **in full on every `barbar.sh` run**, even when nothing
the suite tests has changed since the last green run.

The 47 cases are an inline monolith sharing global `ok`/`fail`/`$TMP` — **not** callable functions — so
parallelising them means rewriting the pack's most safety-critical file for a ~35s save on a sub-minute,
non-bottleneck suite. That trade is refused (I18: never destabilise the enforcement core for speed).

The safe win is **not re-running work whose inputs are unchanged.**

## What the slice adds — and the line it must not cross

A skip-unchanged cache around the whole suite, keyed on a total tree fingerprint.

- A **top gate**: compute the tree fingerprint (every tracked + untracked file's content hash, the same
  shape as `cascade_worktree_sha`, inlined). If it matches the fingerprint recorded by the last GREEN run
  and the cache is not opted out, print `PASS: I18 T8–T54 enforced (cached — tree unchanged since last
  green)` and exit 0, doing zero work.
- On a full run that goes **green**, record the fingerprint. On a run that **fails**, clear the cache.

### The load-bearing constraints — quality is preserved by construction

1. **The cache is in `$GIT_DIR`, never the worktree.** It is not committed, so a **fresh clone and CI
   have no cache and always run the full suite** — the authoritative gate never trusts a cache. This is
   the same seal the signature ledger uses.
2. **The fingerprint is the whole tree.** *Any* tracked-or-untracked file change (a hook, a test, a
   doc — anything) changes the fingerprint and forces a full re-run. It **over-invalidates** (re-runs
   more than strictly necessary) and never under-invalidates — the safe direction.
3. **Only a green run writes the cache; a failing run clears it.** A red suite can never be served as
   green.
4. **Opt-out:** `ENFORCEMENT_NO_CACHE=1` forces a full run even on an unchanged tree.

The one honest edge: a tree that is byte-identical but whose result would differ for a reason *outside
the files* (an environment/toolchain change) could be served stale. Constraint 1 is the backstop — CI
always runs full — and constraint 4 is the manual override. Documented, not hidden.

### The red twin

`tests/ac/t58_enforcement_cache.sh`. After a green run populates the cache, **touching any tracked file
must force a full re-run** (cache miss). `ENF_CACHE_MUTANT=stale` makes the gate serve a cached green
*regardless* of the fingerprint — reproducing the "a change was missed" bug — and the test MUST catch it
(the mutant serves stale where the real gate re-runs). This proves the invalidation has teeth.

## Acceptance criteria

- **AC1** — Second run on an unchanged tree is served from cache: prints the `(cached …)` marker, exits 0,
  and is fast (does not build fixtures).
- **AC2 — THE RED TWIN.** After a green run, modifying any tracked file forces a full re-run (no cache
  hit). `ENF_CACHE_MUTANT=stale` serves the stale cache and the test detects the divergence — so a real
  regression could not slip through the cache.
- **AC3** — A failing suite never leaves a green cache: after a fail, the next run re-runs in full.
- **AC4** — Fresh-clone / CI safety: with no cache present the suite runs in full; the cache never travels
  (it lives in `$GIT_DIR`, outside the worktree and every fixture copy).
- **AC5** — `ENFORCEMENT_NO_CACHE=1` forces a full run on an unchanged tree.
- **AC6** — Cache-miss (full-run) output is byte-for-byte today's output; the 47 cases are untouched.
- **AC7** — `VERSION` bumped (1.9.4 → 1.9.5), `plugin.json` + `marketplace.json` matched (T31), CHANGELOG.

## Laws

`NO D# IN FORCE`. This slice proposes none: it is farm plumbing/performance, not product physics. AC2 is
an enforcement/regression test (`tests/ac/`), a *new* test — it neither changes nor adds under any
existing `tests/inv/*` (I13).

## PLAN

1. `tests/enforcement.sh`: add a `_enf_sha` helper (inlined tree fingerprint), a top gate that serves a
   cached green (honouring `ENFORCEMENT_NO_CACHE` and `ENF_CACHE_MUTANT=stale`), and cache write on green
   / clear on fail. Cache path: `$(git rev-parse --git-dir)/cascade-enforcement-ok`. The 47 case bodies
   are not touched.
2. `tests/ac/t58_enforcement_cache.sh`: AC1–AC6 with the `ENF_CACHE_MUTANT=stale` red twin, on a throwaway
   git fixture so it never pollutes this repo's real cache.
3. Docs: `INTEGRATION.md` (+ a line in `USAGE.md` troubleshooting) — the cache, `ENFORCEMENT_NO_CACHE`,
   and "CI / a fresh clone always runs the full suite."
4. `VERSION` 1.9.4 → 1.9.5; `plugin.json` + `marketplace.json`; `CHANGELOG`.
5. `docs/cascade/goal.md` validators: the t58 AC script + `enforcement.sh` (which, first run in the hop,
   is a cache miss → full run → proves AC6).

**Not in this slice** (each its own hop): parallelising the enforcement cases (measured poor ROI, high
risk); parallelising the farm's top-level steps; per-repo default-parallel dsharp (t57); gradle tuning.
