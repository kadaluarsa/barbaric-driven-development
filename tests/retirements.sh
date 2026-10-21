#!/usr/bin/env bash
# Did any law leave force inside an open hop while it was not GREEN? (t68, I18) — the merge gate's backstop to the
# pre-commit guard, re-proved from git so `git commit --no-verify` does not get around it.
#
# usage: tests/retirements.sh [--root DIR] [--base REV]
#   --base  where to start (default: the merge base with main, else origin/main, else the whole history)
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
if [[ -z "$BASE" ]]; then
  BASE="$(git -C "$ROOT" merge-base HEAD main 2>/dev/null || git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null || true)"
fi
python3 -B "$HERE/lib/retirement_guard.py" history "$ROOT" "$BASE"
