#!/usr/bin/env bash
# /loop — GRE execute loop, as a script.
#
# LOOP k/n is machine output, not something an agent types. Fails closed:
#   * illegal on a GENERATE hop (I15)
#   * an in-force D# missing from /goal is FAIL, not skip (I13)
#   * exit non-zero unless k = n
#
# usage: tests/loop.sh [--goal docs/cascade/goal.md] [--list]
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/cascade.sh
. "$ROOT/tests/lib/cascade.sh"

GOAL="$ROOT/docs/cascade/goal.md"
LIST_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --goal) GOAL="$2"; shift 2 ;;
    --list) LIST_ONLY=1; shift ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "usage: tests/loop.sh [--goal FILE] [--list]" >&2; exit 64 ;;
  esac
done

hop="$(cascade_hop)"
stage="$(cascade_stage)"

if [[ "$hop" == "GENERATE" ]]; then
  echo "LOOP REFUSED: /loop is illegal on a GENERATE hop (I15)." >&2
  echo "  GENERATE stops at spec + plan. Get 'approved, execute stage $stage' first." >&2
  exit 3
fi
if [[ "$hop" == "NONE" ]]; then
  echo "LOOP REFUSED: no CURRENT_HOP in $(cascade_envelope)." >&2
  exit 3
fi
case "$stage" in
  01|02|03|04|11)
    echo "LOOP REFUSED: /loop is illegal on stage $stage (I15). Build hops are 05b / 06-09 / 10 punch." >&2
    exit 3 ;;
esac
if [[ ! -f "$GOAL" ]]; then
  echo "LOOP REFUSED: no /goal file at $GOAL. Set this hop's DoD first (I9)." >&2
  exit 3
fi

validators=(); waivers=()
while IFS= read -r line; do [[ -n "$line" ]] && validators+=("$line"); done \
  < <(tr -d '\r' < "$GOAL" | grep -E '^VALIDATOR:' | sed -E 's/^VALIDATOR:[[:space:]]*//; s/[[:space:]]+$//')
while IFS= read -r line; do [[ -n "$line" ]] && waivers+=("$line"); done \
  < <(tr -d '\r' < "$GOAL" | grep -E '^WAIVE_DSHARP:' | sed -E 's/^WAIVE_DSHARP:[[:space:]]*//; s/[[:space:]]+$//')

k=0; n=0
declare -a omitted=()

# A declared D# that cannot be proven (no validator, or no red twin) blocks the hop (I13). STOP and ask; never code around it.
unproven=()
while IFS='|' read -r id law why; do
  [[ -z "${id:-}" ]] && continue
  waived=0; for w in "${waivers[@]:-}"; do [[ "$w" == "$id "* || "$w" == "$id" ]] && waived=1 && break; done
  [[ "$waived" -eq 1 ]] && { echo "WAIVED  $id  $law  ($why; waiver recorded in $(basename "$GOAL"))"; continue; }
  unproven+=("$id  $law  ($why)")
done < <(cascade_dsharp_unproven)
if [[ ${#unproven[@]} -gt 0 && "$LIST_ONLY" -eq 0 ]]; then
  echo "LOOP REFUSED: declared D# not in force — each needs a validator AND a red twin (I13):" >&2
  printf '  %s\n' "${unproven[@]}" >&2
  echo "  Ask the human to complete the law in docs/cascade/envelope.md, or record WAIVE_DSHARP: <D#> <reason> in $(basename "$GOAL")." >&2
  exit 3
fi

# I13: every in-force D# must appear in /goal, or carry a written waiver.
while IFS='|' read -r id law val _twin; do
  [[ -z "${id:-}" ]] && continue
  found=0
  for v in "${validators[@]:-}"; do [[ "$v" == "$val" ]] && found=1 && break; done
  if [[ "$found" -eq 0 ]]; then
    for w in "${waivers[@]:-}"; do [[ "$w" == "$id "* || "$w" == "$id" ]] && found=2 && break; done
  fi
  case "$found" in
    0) omitted+=("$id  $law") ;;
    2) echo "WAIVED  $id  $law  (waiver recorded in $(basename "$GOAL"))" ;;
  esac
done < <(cascade_dsharp_in_force)

if [[ "$LIST_ONLY" -eq 1 ]]; then
  printf 'stage %s, hop %s\n' "$stage" "$hop"
  printf 'validator: %s\n' "${validators[@]:-<none>}"
  [[ ${#omitted[@]} -gt 0 ]] && printf 'OMITTED D#: %s\n' "${omitted[@]}"
  exit 0
fi

if [[ ${#validators[@]} -eq 0 && ${#omitted[@]} -eq 0 ]]; then
  echo "LOOP REFUSED: /goal has no VALIDATOR lines. A hop with no bar is not a hop (I9)." >&2
  exit 3
fi

for v in "${validators[@]:-}"; do
  [[ -z "$v" ]] && continue
  n=$((n + 1))
  if ( cd "$ROOT" && eval "$v" ) >/dev/null 2>&1; then
    k=$((k + 1)); echo "PASS  $v"
  else
    echo "FAIL  $v"
  fi
done

# An omitted in-force D# is a FAIL entry, never a skipped one.
for o in "${omitted[@]:-}"; do
  [[ -z "$o" ]] && continue
  n=$((n + 1))
  echo "FAIL  in-force D# omitted from /goal: $o"
done

echo
echo "LOOP $k/$n"
if [[ "$k" -eq "$n" && "$n" -gt 0 ]]; then
  echo "Hop edge. STITCH NEEDED: accept execute for stage $stage, or send back."
  exit 0
fi
echo "not n/n — do not ask for accept."
exit 1
