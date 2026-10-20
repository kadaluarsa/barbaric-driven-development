#!/usr/bin/env bash
# Which laws can this hop's diff break? t66.
#
# usage: tests/affected.sh [--root DIR] [--base REV] [--list | --why]
#
# Base: the commit that opened the current hop (the newest commit touching docs/cascade/hop-state.md, with the
# same CURRENT_HOP/STAGE/SLICE as the working tree). --base overrides it for reports and fixtures only; the loop
# and every gate do not pass it, and there is no environment variable that can narrow a real hop.
#
# Output: one line per in-force law with the reason it is affected, or `not affected`. The full set prints
# `AFFECTED full — <reason>` and every law affected. Exit 0 for every verdict, including full.
set -uo pipefail
# Git exports these to hooks. A script that runs `git init` in a temp dir must not be pointed at the real repo.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BASE=""
MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 ]] || { echo "affected.sh: --root needs a directory" >&2; exit 64; }
            ROOT="$2"; shift 2 ;;
    --base) [[ $# -ge 2 ]] || { echo "affected.sh: --base needs a revision" >&2; exit 64; }
            BASE="$2"; shift 2 ;;
    --list|--why) MODE="$1"; shift ;;
    -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "usage: tests/affected.sh [--root DIR] [--base REV] [--list | --why]" >&2; exit 64 ;;
  esac
done

[[ -d "$ROOT" ]] || { echo "affected.sh: no such directory: $ROOT" >&2; exit 64; }
ENVELOPE="${CASCADE_ENVELOPE:-$ROOT/docs/cascade/envelope.md}"
if [[ ! -f "$ENVELOPE" ]]; then
  echo "AFFECTED full — no envelope at $ENVELOPE"
  exit 0
fi

args=("$ROOT" "$ENVELOPE")
[[ -n "$BASE" ]] && args+=(--base "$BASE")
[[ -n "$MODE" ]] && args+=("$MODE")
python3 -B "$ROOT/tests/lib/affected.py" "${args[@]}"
rc=$?
# A crash is the full set, never an empty one. The Python already does this; this is the second lock, for the case
# where it cannot even start (a broken interpreter, a truncated file).
if [[ "$rc" -ne 0 && "$rc" -ne 64 ]]; then
  echo "AFFECTED full — the selector failed to run (exit $rc)"
  exit 0
fi
exit "$rc"
