#!/usr/bin/env bash
# The regression suite (t78): every column-0 `REGRESS: <command>` line in docs/cascade/regress.md, run alone.
# An accepted slice's tests land here (bash tests/goal.sh reset / carry-out) and keep running before every merge,
# without re-running in every later hop's loop. REGRESS k/n is machine output; exit 0 iff k = n.
#
# usage: tests/regress.sh [--root DIR] [--gate] [--ci]
#   --gate  the committed suite, plus every line the merge base had that HEAD dropped, minus lines the human retired
#           (REGRESS_RETIRED in the envelope). A working copy that differs from HEAD or a shallow clone is refused.
#           The merge gate (tests/barbar.sh) runs this.
#   --ci    --gate, but a line ending in the shell comment `# gate-only` is skipped and counted as skipped — never
#           as passed; the merge gate still runs it. CI (control-line.yml) runs this.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MODE=work; CI=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    --gate) MODE=gate; shift ;;
    --ci)   MODE=gate; CI=1; shift ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "usage: tests/regress.sh [--root DIR] [--gate] [--ci]" >&2; exit 64 ;;
  esac
done

lines=(); why=""
while IFS=$'\t' read -r kind rest; do
  case "${kind:-}" in
    L) lines+=("$rest") ;;
    REFUSE) why="$rest" ;;
  esac
done < <(python3 -B "$HERE/lib/regress_lines.py" suite "$ROOT" "$MODE" 2>/dev/null || echo "REFUSE	tests/lib/regress_lines.py failed")
if [[ -n "$why" ]]; then
  echo "REGRESS REFUSED: $why"
  exit 3
fi

LOGDIR="$ROOT/.cascade/regress"
rm -rf "$LOGDIR" 2>/dev/null || true
mkdir -p "$LOGDIR" 2>/dev/null || LOGDIR=""
detail() {  # the same 25-line detail as loop.sh
  [[ -n "$LOGDIR" && -s "$1" ]] || return 0
  { grep -E ' > .* FAILED$' "$1" | head -10; tail -n 14 "$1"; } | cut -c1-200 | sed 's/^/      | /'
  echo "      log: ${1#"$ROOT"/}"
}

# t79: a recognised test runner that exits 0 having executed no test is a FAIL (tests/lib/test_count.py).
test_re='^(\./gradlew|gradlew|gradle|xcodebuild)[[:space:]]'
has_test_lines=0; uninsp=0
for l in "${lines[@]:-}"; do [[ "$l" =~ $test_re ]] && has_test_lines=1; done
k=0; n=0; skipped=0; i=-1
for l in "${lines[@]:-}"; do
  [[ -z "$l" ]] && continue
  i=$((i + 1))
  if [[ "$CI" -eq 1 && "$l" =~ [[:space:]]#[[:space:]]*gate-only[[:space:]]*$ ]]; then
    echo "SKIP  gate-only  $l"; skipped=$((skipped + 1)); continue
  fi
  n=$((n + 1))
  log=/dev/null; [[ -n "$LOGDIR" ]] && log="$LOGDIR/$i.log"
  t0="$(python3 -c 'import time; print(time.time())')"
  if ( cd "$ROOT" && eval "$l" ) >"$log" 2>&1; then
    zt="uninspected"
    [[ "$l" =~ $test_re ]] && zt="$(python3 -B "$HERE/lib/test_count.py" "$ROOT" "$t0" "$log" "$l" 2>/dev/null || echo 'uninspected the reader failed')"
    case "$zt" in
      none*) echo "FAIL  $l"; echo "      | ran no tests (${zt#none })"; detail "$log" ;;
      *) [[ "$zt" == uninspected* ]] && uninsp=$((uninsp + 1)); k=$((k + 1)); echo "PASS  $l" ;;
    esac
  else
    echo "FAIL  $l"; detail "$log"
  fi
done

note=""; [[ "$has_test_lines" -eq 1 && "$uninsp" -gt 0 ]] && note=" ($uninsp not inspected)"
if [[ "$skipped" -gt 0 ]]; then echo "REGRESS $k/$n ($skipped gate-only, not run here)$note"; else echo "REGRESS $k/$n$note"; fi
[[ "$k" -eq "$n" ]]
