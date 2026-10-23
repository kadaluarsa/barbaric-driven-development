#!/usr/bin/env bash
# Did any law leave force inside an open hop while it was not GREEN? (t68, I18) — the merge gate's backstop to the
# pre-commit guard, re-proved from git so `git commit --no-verify` does not get around it.
#
# usage: tests/retirements.sh [--root DIR] [--base REV]
#   --base  where to start (default: the merge base with the repo's default branch — origin/HEAD, else main, master
#           or trunk). No base, or a shallow clone that cannot reach it, is a refusal, never "clean": nothing checked
#           must not read as nothing found.
#
# For every commit that changes the envelope or a law shard: a law declared at the parent and not after (retired, or
# its block deleted), in a commit whose parent or own hop state has CURRENT_HOP GENERATE or EXECUTE, must have been
# GREEN on the parent's tree (check passes, break fails). Prints `RETIREMENT REFUSED …` per law; exit 1 if any.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BASE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    *) echo "usage: tests/retirements.sh [--root DIR] [--base REV]" >&2; exit 64 ;;
  esac
done
# A tree that is not its own git repository (a copied fixture, or a subdirectory of another repo) has no history in
# which a law could have left force; say so instead of reading another repo's history with this tree's paths.
top="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$top" || "$(cd "$top" && pwd -P)" != "$(cd "$ROOT" && pwd -P)" ]]; then
  echo "RETIREMENTS clean: $ROOT is not its own git repository — no history to check"
  exit 0
fi
if [[ "$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null)" == true ]]; then
  echo "RETIREMENT REFUSED  a shallow clone cannot show which laws left force — fetch full history (fetch-depth: 0)"
  exit 1
fi
if [[ -z "$BASE" ]]; then
  for b in "$(git -C "$ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" main master trunk origin/main origin/master; do
    [[ -n "$b" ]] || continue
    BASE="$(git -C "$ROOT" merge-base HEAD "$b" 2>/dev/null)" && [[ -n "$BASE" ]] && break
    BASE=""
  done
fi
if [[ -z "$BASE" ]]; then
  echo "RETIREMENT REFUSED  no base to compare against (no main/master/trunk or origin/HEAD) — pass --base REV"
  exit 1
fi
python3 -B "$HERE/lib/retirement_guard.py" history "$ROOT" "$BASE"
