#!/usr/bin/env bash
# AC tests for 05b t58-enforcement-cache. enforcement.sh gains a skip-unchanged cache keyed on a total
# tree fingerprint, stored in $GIT_DIR. AC2 is the RED TWIN: a changed tree MUST re-run (fingerprint
# mismatch), and ENF_CACHE_MUTANT=stale — which serves a cached green regardless of the fingerprint —
# MUST be caught, proving the invalidation has teeth. ENF_CACHE_PROBE prints the gate's decision without
# running the ~53s body, so these checks are fast and deterministic.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1
. "$ROOT/tests/lib/cascade.sh"
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }

GITDIR="$(git -C "$ROOT" rev-parse --git-dir)"; [[ "$GITDIR" == /* ]] || GITDIR="$ROOT/$GITDIR"
CACHE="$GITDIR/cascade-enforcement-ok"
SHA="$(cascade_worktree_sha "$ROOT")"

# Never disturb the developer's real cache: save it and restore on exit.
SAVED="$(mktemp)"; had=0; [[ -f "$CACHE" ]] && { cp "$CACHE" "$SAVED"; had=1; }
restore() { if [[ "$had" -eq 1 ]]; then cp "$SAVED" "$CACHE"; else rm -f "$CACHE"; fi; rm -f "$SAVED"; }
trap restore EXIT

probe() { env "$@" ENF_CACHE_PROBE=1 bash tests/enforcement.sh 2>/dev/null; }

# AC1 — matching fingerprint → hit (unchanged tree served from cache)
printf '%s\n' "$SHA" > "$CACHE"
[[ "$(probe)" == "CACHE: hit" ]] && ok=1 || ok=0
t AC1 "$ok" "unchanged tree (fingerprint match) is served from cache"

# AC2 — mismatched fingerprint → miss (a changed tree re-runs)
printf 'not-the-real-sha\n' > "$CACHE"
[[ "$(probe)" == "CACHE: miss" ]] && ok=1 || ok=0
t AC2 "$ok" "changed tree (fingerprint mismatch) forces a full re-run"

# AC2 RED TWIN — the mutant serves stale where the real gate re-runs → the fingerprint check has teeth
[[ "$(probe ENF_CACHE_MUTANT=stale)" == "CACHE: hit" ]] && ok=1 || ok=0
t AC2 "$ok" "RED TWIN: ENF_CACHE_MUTANT=stale serves a stale cache on a mismatch (invalidation matters)"

# AC4 — no cache present (fresh clone / CI) → miss → full suite
rm -f "$CACHE"
[[ "$(probe)" == "CACHE: miss" ]] && ok=1 || ok=0
t AC4 "$ok" "no cache present (fresh clone / CI) runs the full suite"

# AC5 — opt-out forces a full run even on a match
printf '%s\n' "$SHA" > "$CACHE"
[[ "$(probe ENFORCEMENT_NO_CACHE=1)" == "CACHE: miss" ]] && ok=1 || ok=0
t AC5 "$ok" "ENFORCEMENT_NO_CACHE=1 forces a full run on an unchanged tree"

# AC3 — a failing run clears the cache, so a red suite can never later be served green. Force a real
#        full run (bypass the hit) with a case forced red, then assert the cache is gone. (~one full run.)
printf '%s\n' "$SHA" > "$CACHE"
ENFORCEMENT_NO_CACHE=1 T54_MUTANT=pathonly bash tests/enforcement.sh >/dev/null 2>&1
[[ ! -f "$CACHE" ]] && ok=1 || ok=0
t AC3 "$ok" "a failing run clears the cache (a red suite is never served green)"

echo
[[ "$fail" -eq 0 ]] && echo "t58 AC: all green" || echo "t58 AC: FAILURES above"
exit "$fail"
