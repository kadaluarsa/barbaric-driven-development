#!/usr/bin/env bash
# /goal helper (t77). A goal is one hop's definition of done.
#
#   bash tests/goal.sh reset      carry the replaced goal's lines to docs/cascade/regress.md (t78), then write
#                                 docs/cascade/goal.md from docs/cascade/goal.template.md for the current hop (its
#                                 GOAL_STAGE and GOAL_SLICE, no validators). Run it at the START of an EXECUTE hop,
#                                 never at an accept edge: the receipt and autopilot's check describe the goal as it was.
#   bash tests/goal.sh carry-out  move this goal's carried lines, and the previous slice's dropped ones, to the suite.
#   bash tests/goal.sh show       the slice check and the carried / standing counts, without running anything.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/cascade.sh
. "$ROOT/tests/lib/cascade.sh"
GOAL="$ROOT/docs/cascade/goal.md"
TEMPLATE="$ROOT/docs/cascade/goal.template.md"

laws() { cascade_dsharp_in_force | while IFS='|' read -r _id _law val _rest; do [[ -n "$val" ]] && printf '%s\n' "$val"; done; }
carried=0
carry() {  # carry carry|reset — run carry_out.py, print its line, keep its count
  local out
  out="$(laws | python3 -B "$ROOT/tests/lib/carry_out.py" "$ROOT" "$1" "$(cascade_slice)")" || return 1
  printf '%s\n' "$out" | grep -v '^CARRIED '
  carried="$(printf '%s\n' "$out" | sed -n 's/^CARRIED //p' | tail -n 1)"
}
# t78: the goal's own lines are read from the file, so it must be committed — what reset replaces is then in git.
carry_out_for_reset() {
  if [[ "$(count)" -gt 0 && -n "$(git -C "$ROOT" status --porcelain -- docs/cascade/goal.md 2>/dev/null)" ]]; then
    echo "goal: ${GOAL#"$ROOT"/} has uncommitted changes — commit the goal first so its lines can be carried" >&2
    return 1
  fi
  carry reset
}

count() { local n=0; [[ -f "$GOAL" ]] && n="$(tr -d '\r' < "$GOAL" | grep -cE '^VALIDATOR:[[:space:]]*[^[:space:]]')"; echo "${n:-0}"; }

case "${1:-}" in
  reset)
    [[ -f "$TEMPLATE" ]] || { echo "goal: no template at ${TEMPLATE#"$ROOT"/} — reinstall the pack (bash install.sh .)" >&2; exit 1; }
    stage="$(cascade_stage)"; slice="$(cascade_slice)"
    removed="$(count)"
    carry_out_for_reset || exit 1
    tmp="$GOAL.tmp.$$"
    awk -v st="$stage" -v sl="$slice" '
      /^GOAL_STAGE:/ && st != "" { print "GOAL_STAGE: " st; next }
      /^GOAL_SLICE:/ && sl != "" { print "GOAL_SLICE: " sl; next }
      { print }' "$TEMPLATE" > "$tmp" && mv "$tmp" "$GOAL" || { rm -f "$tmp"; exit 1; }
    plural=s; [[ "$removed" -eq 1 ]] && plural=""
    echo "goal: reset ${GOAL#"$ROOT"/} for ${stage:-<stage>} ${slice:-<slice slug>} — removed $removed validator$plural (${carried:-0} carried to docs/cascade/regress.md)"
    echo "  next: write this hop's validators; gates every hop reruns end with '# standing'; past slices' tests run from docs/cascade/regress.md"
    ;;
  carry-out)
    [[ -f "$GOAL" ]] || { echo "goal: no ${GOAL#"$ROOT"/} — nothing to carry"; exit 0; }
    carry carry || exit 1
    ;;
  show)
    [[ -f "$GOAL" ]] || { echo "goal: no ${GOAL#"$ROOT"/} — bash tests/goal.sh reset"; exit 0; }
    gs="$(tr -d '\r' < "$GOAL" | grep -E '^GOAL_SLICE:' | tail -n 1 | sed -E 's/^GOAL_SLICE:[[:space:]]*//; s/[[:space:]]+$//')"
    cs="$(cascade_slice)"
    if [[ -n "$gs" && -n "$cs" && "$gs" != "$cs" && "$gs" != "<"*">" && "$gs" != *"{{"* ]]; then
      echo "goal: ${GOAL#"$ROOT"/} is for slice $gs, this hop is $cs — the loop refuses it; bash tests/goal.sh reset"
    else
      echo "goal: slice ${gs:-<none>} (this hop: ${cs:-<none>}) — not refused for its slice"
    fi
    tsv="$(cascade_dsharp_in_force | while IFS='|' read -r _id _law val _rest; do [[ -n "$val" ]] && printf '%s\n' "$val"; done \
      | python3 -B "$ROOT/tests/lib/goal_history.py" "$ROOT" "$GOAL" "$cs" "$(cascade_envelope)" 2>/dev/null || true)"
    while IFS=$'\t' read -r kind a b c d; do
      case "${kind:-}" in
        U) echo "goal: history unreadable, carry cap not checked" ;;
        N) echo "goal: $a of $b validators were in earlier slices' goals${d:+ ($d)}, $c standing" ;;
        C) echo "goal: carry cap $a" ;;
      esac
    done <<< "$tsv"
    ;;
  *) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 64 ;;
esac
