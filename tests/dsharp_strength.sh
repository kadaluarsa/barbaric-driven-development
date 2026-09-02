#!/usr/bin/env bash
# D# strength — a law is in force only when it can fail.
#   GREEN    validator exit 0, red twin exit non-zero
#   RED      validator failed                         (law broken)
#   THEATER  red twin passed                          (validator cannot fail — worthless green)
#   UNPROVEN no validator or no red twin              (declared, not in force)
# Prints one line per D# and `DSHARP k/n`; exit 0 only if every declared D# is GREEN.
# usage: tests/dsharp_strength.sh [--root DIR]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$(cd "$2" && pwd)"; shift 2 ;; *) echo "usage: dsharp_strength.sh [--root DIR]" >&2; exit 64 ;; esac; done
ENV_FILE="$ROOT/docs/cascade/envelope.md"
k=0; n=0
[[ -f "$ENV_FILE" ]] || { echo "DSHARP 0/0"; exit 0; }
trim() { echo "${1:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }
while IFS='|' read -r id law val twin _; do
  id="$(echo "$id" | tr -d '[:space:]')"; law="$(trim "$law")"; val="$(trim "$val")"; twin="$(trim "$twin")"
  case "$val"  in TODO|none|"") val="" ;; esac
  case "$twin" in TODO|none|"") twin="" ;; esac
  n=$((n + 1))
  if [[ -z "$val" ]];  then echo "UNPROVEN  $id  $law  (no validator)"; continue; fi
  if [[ -z "$twin" ]]; then echo "UNPROVEN  $id  $law  (no red twin)"; continue; fi
  if ! ( cd "$ROOT" && eval "$val" ) >/dev/null 2>&1; then echo "RED       $id  $law  — validator failed: $val"; continue; fi
  if ( cd "$ROOT" && eval "$twin" ) >/dev/null 2>&1; then echo "THEATER   $id  $law  — red twin passed, validator cannot fail: $twin"; continue; fi
  echo "GREEN     $id  $law"; k=$((k + 1))
done < <(tr -d '\r' < "$ENV_FILE" | grep -E '^D[0-9]+[[:space:]]*\|' || true)
echo "DSHARP $k/$n"
[[ "$k" -eq "$n" ]]
