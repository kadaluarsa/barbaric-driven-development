#!/usr/bin/env bash
# D# strength — a law is in force only when it can fail.
#   GREEN    validator exit 0, red twin exit non-zero
#   RED      validator failed                         (law broken)
#   THEATER  red twin passed                          (validator cannot fail — worthless green)
#   UNPROVEN no validator or no red twin              (declared, not in force)
# Prints one line per D# and `DSHARP k/n`; exit 0 only if every declared D# is GREEN.
#
# Speed (t56): DSHARP_JOBS=N scores up to N laws concurrently. Default 1 = sequential, unchanged.
#   The report is COLLECTED and printed in DECLARED order, and k/n and the exit code come from the
#   collected results — so a parallel run is identical to a sequential one, only faster (I18: speed must
#   never flip a verdict). The merge gate and enforcement.sh run at the default (sequential) on purpose:
#   the authoritative verdict stays race-free; parallelism is an opt-in dev speedup. A law that shares a
#   daemon/port/build dir is NOT hermetic and must not race — list its id in DSHARP_SERIAL (space-
#   separated) to keep it sequential. The pack does not fabricate isolation; hermeticity is the law
#   author's job, DSHARP_SERIAL is the honest escape hatch.
# usage: tests/dsharp_strength.sh [--root DIR]
set -uo pipefail
# Git exports GIT_DIR/GIT_WORK_TREE to hooks. Inherited by a script that runs `git init` in a temp dir, they
# redirect it at the real repo (this once flipped a product to core.bare=true and re-pointed a worktree's HEAD).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$(cd "$2" && pwd)"; shift 2 ;; *) echo "usage: dsharp_strength.sh [--root DIR]" >&2; exit 64 ;; esac; done
ENV_FILE="${CASCADE_ENVELOPE:-$ROOT/docs/cascade/envelope.md}"
JOBS="${DSHARP_JOBS:-1}"; [[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || JOBS=1
SERIAL=" ${DSHARP_SERIAL:-} "   # space-padded so ` D2 ` matches a whole id, not a prefix
# One line per verdict in .cascade/decisions.log, so the morning after an unattended run says which law
# went red and when. Never fatal: a logging failure must not change a verdict. Called only from the ordered
# collection below (never from a parallel worker), so decisions.log stays deterministic and unraced.
say() { python3 -B "$HERE/lib/decisions.py" "$ROOT" dsharp "$1" "$2" 2>/dev/null || true; }
[[ -f "$ENV_FILE" ]] || { echo "DSHARP 0/0"; exit 0; }
trim() { echo "${1:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Declared laws into parallel arrays, in file order, TODO/none/"" normalized to empty.
# First, get the expected count so we can detect silent parser failures.
expected_count=0
if [[ -f "$ENV_FILE" ]]; then
  expected_count="$(python3 -B "$HERE/lib/laws.py" "$ENV_FILE" --count 2>/dev/null || echo 0)"
fi
ids=(); laws=(); checks=(); twins=(); reasons=(); paths=(); tiers=()
while IFS='|' read -r id law val twin reason path tier; do
  id="$(echo "$id" | tr -d '[:space:]')"; [[ -z "$id" ]] && continue
  law="$(trim "$law")"; val="$(trim "$val")"; twin="$(trim "$twin")"
  reason="$(trim "${reason:-}")"; path="$(trim "${path:-}")"; tier="$(trim "${tier:-}")"
  case "$val"  in TODO|none|"") val="" ;; esac
  case "$twin" in TODO|none|"") twin="" ;; esac
  ids+=("$id"); laws+=("$law"); checks+=("$val"); twins+=("$twin")
  reasons+=("$reason"); paths+=("$path"); tiers+=("$tier")
done < <(python3 -B "$HERE/lib/laws.py" "$ENV_FILE" --declared || true)
n="${#ids[@]}"

# Mismatch check: if laws.py declares a different count than what we parsed,
# the parser may have silently failed. Fail closed (I18).
if [[ "$expected_count" -ne "$n" ]]; then
  echo "FATAL     law parser mismatch: laws.py --declared returned $n laws but --count reports $expected_count"
  exit 1
fi

# Score one law by index -> $TMP/res.<idx>: line 1 STATUS, line 2 the print line, line 3 the say detail.
# No shared mutable state between invocations, so it is safe to run several at once; each law owns its file.
score_one() {
  local i="$1" id="${ids[$1]}" law="${laws[$1]}" val="${checks[$1]}" twin="${twins[$1]}"
  local status line detail=""
  if [[ -z "$val" ]]; then
    status=UNPROVEN; line="UNPROVEN  $id  $law  (no validator)"; detail="$id $law — no check command"
  elif [[ -z "$twin" ]]; then
    status=UNPROVEN; line="UNPROVEN  $id  $law  (no red twin)"; detail="$id $law — no break command"
  elif ! ( cd "$ROOT" && eval "$val" ) >/dev/null 2>&1; then
    status=RED; line="RED       $id  $law  — validator failed: $val"; detail="$id $law — check failed: $val"
  elif ( cd "$ROOT" && eval "$twin" ) >/dev/null 2>&1; then
    status=THEATER; line="THEATER   $id  $law  — red twin passed, validator cannot fail: $twin"; detail="$id $law — break passed, so the check cannot fail: $twin"
  else
    status=GREEN; line="GREEN     $id  $law"
  fi
  { printf '%s\n' "$status"; printf '%s\n' "$line"; printf '%s\n' "$detail"; } > "$TMP/res.$i"
}

if [[ "$JOBS" -le 1 ]]; then
  for ((i = 0; i < n; i++)); do score_one "$i"; done
else
  # Partition only where it is used: serial laws (share a daemon/port/dir) never race; the rest go to the pool.
  par=(); ser=()
  for ((i = 0; i < n; i++)); do
    if [[ "$SERIAL" == *" ${ids[$i]} "* ]]; then ser+=("$i"); else par+=("$i"); fi
  done
  if [[ "${BASH_VERSINFO[0]}" -gt 4 || ( "${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -ge 3 ) ]]; then
    # bash 4.3+: drain whichever job finishes first — no head-of-line stall behind one slow law.
    running=0
    for i in "${par[@]:-}"; do
      [[ -z "$i" ]] && continue
      score_one "$i" &
      running=$((running + 1))
      if [[ "$running" -ge "$JOBS" ]]; then wait -n 2>/dev/null || true; running=$((running - 1)); fi
    done
  else
    # bash 3.2 (macOS default) has no `wait -n`: wait the oldest. Still bounded, just coarser.
    pids=()
    for i in "${par[@]:-}"; do
      [[ -z "$i" ]] && continue
      score_one "$i" &
      pids+=("$!")
      if [[ "${#pids[@]}" -ge "$JOBS" ]]; then wait "${pids[0]}" 2>/dev/null || true; pids=("${pids[@]:1}"); fi
    done
  fi
  wait
  for i in "${ser[@]:-}"; do [[ -z "$i" ]] && continue; score_one "$i"; done
fi

# Collect in DECLARED order: the report and k/n are deterministic, independent of completion order.
# Each result file is read once (three lines, one open) — no per-law sed forks in the hot path.
# DSHARP_MUTANT=drop reproduces a broken parallel collector (a lost verdict) so the t56 red twin can fail.
drop_last=0; [[ "${DSHARP_MUTANT:-}" == "drop" && "$JOBS" -gt 1 ]] && drop_last=1
k=0
for ((i = 0; i < n; i++)); do
  [[ "$drop_last" -eq 1 && "$i" -eq $((n - 1)) ]] && continue
  { IFS= read -r status; IFS= read -r line; IFS= read -r detail; } < "$TMP/res.$i"
  echo "$line"
  case "$status" in
    GREEN) k=$((k + 1)) ;;
    UNPROVEN|RED|THEATER) say "$status" "$detail" ;;
  esac
done
echo "DSHARP $k/$n"

# ---- Mutation type registry (must match docs/cascade/mutation-types.md) ----
VALID_MUTATION_TYPES="REMOVED_GUARD INVERTED_CONDITION WRONG_CONSTANT SKIPPED_STEP BYPASSED_AUTH WRONG_STATE REMOVED_ENCRYPTION ALLOWED_OVERFLOW"

# ---- Metadata validation: check every GREEN law's reason, path, tier ----
validation_fail=0
for ((i = 0; i < n; i++)); do
  { IFS= read -r status; IFS= read -r line; IFS= read -r detail; } < "$TMP/res.$i" 2>/dev/null || continue
  [[ "$status" != "GREEN" ]] && continue

  id="${ids[$i]}"; law="${laws[$i]}"
  reason="${reasons[$i]}"; path="${paths[$i]}"; tier="${tiers[$i]}"

  # Skip validation for laws with no metadata at all (backward compat)
  [[ -z "$reason" && -z "$path" && -z "$tier" ]] && continue

  # Strict mode: if ANY metadata field is present, ALL required fields must be present.
  if [[ -z "$reason" ]]; then
    echo "WARNING   $id  reason: is required when metadata is present — add a mutation type from docs/cascade/mutation-types.md"
    validation_fail=$((validation_fail + 1))
  fi
  if [[ -z "$path" ]]; then
    echo "WARNING   $id  path: is required when metadata is present — point at the file the mutant changes"
    validation_fail=$((validation_fail + 1))
  fi

  # Validate what IS present (even if the other field is missing)
  # Validate mutation type
  if [[ -n "$reason" ]]; then
    # Extract type before " — " or " - " (em-dash or hyphen with spaces)
    if [[ "$reason" == *" — "* ]]; then
      mtype="${reason%% — *}"
    elif [[ "$reason" == *" - "* ]]; then
      mtype="${reason%% - *}"
    else
      mtype="$reason"
    fi
    mtype="$(trim "$mtype")"
    found=0
    for t in $VALID_MUTATION_TYPES; do [[ "$t" == "$mtype" ]] && found=1 && break; done
    if [[ "$found" -eq 0 ]]; then
      echo "WARNING   $id  reason: \"$mtype\" is not a registered mutation type (see docs/cascade/mutation-types.md)"
      validation_fail=$((validation_fail + 1))
    fi
  fi

  # Validate path: file exists
  if [[ -n "$path" ]]; then
    # Split file and optional symbol (file.py:function)
    filepart="${path%%:*}"
    symbol="${path#*:}"
    [[ "$symbol" == "$filepart" ]] && symbol=""  # no colon -> no symbol
    absfile="$ROOT/$filepart"
    if [[ ! -f "$absfile" ]]; then
      echo "WARNING   $id  path: \"$filepart\" — file not found in repo"
      validation_fail=$((validation_fail + 1))
    elif [[ -n "$symbol" ]]; then
      # Symbol check: grep for def/class/val/fun matching the symbol name
      if ! grep -qE "(def |class |fun |val |var |object )\b${symbol}\b" "$absfile" 2>/dev/null; then
        echo "WARNING   $id  path: \"$filepart:$symbol\" — symbol \"$symbol\" not found in file"
        validation_fail=$((validation_fail + 1))
      fi
    fi
  fi
done

[[ "$validation_fail" -gt 0 ]] && echo "METADATA  $validation_fail GREEN law(s) have invalid metadata — fix reason:/path: in docs/cascade/envelope.md"
[[ "$k" -eq "$n" && "$validation_fail" -eq 0 ]]
