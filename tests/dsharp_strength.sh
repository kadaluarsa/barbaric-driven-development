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
#
# Cache (t65): a law's GREEN is reused, printed `GREEN  D# law  (cached)`, when tests/lib/verdict_cache.py computes the
#   same key as the stored one: the law's commands, the files and modules it declares, every file nothing declares,
#   the toolchain, the pack and the verdict-relevant environment. Only GREEN is stored, and only when the worktree did
#   not change while the laws ran; RED, THEATER and UNPROVEN always re-run. DSHARP_CACHE=on (or unset) turns it on;
#   any other value is today's path exactly. The merge gate and the nightly set DSHARP_CACHE=off: no merge
#   decision reads a remembered verdict (docs/cascade/05b-t65-verdict-cache.md).
# Nightly split (t69): `--part PLAN K --out DIR` scores only the laws tests/lib/nightly_plan.py gave to part K (cache
#   off) and writes their statuses to DIR; it prints `DSHARP PART …`, never a `DSHARP k/n`. `--join PLAN DIR…` refuses
#   (FATAL, exit 1) unless the parts hold every declared law exactly once, in its planned part, for these same laws and
#   this same plan; then it prints exactly what one run prints for those verdicts. Neither is used by the loop, the
#   farm or the merge gate. docs/cascade/05b-t69-gradle-tuning.md §5.
# usage: tests/dsharp_strength.sh [--root DIR] [--part PLAN K --out DIR | --join PLAN DIR...]
set -uo pipefail
# Git exports GIT_DIR/GIT_WORK_TREE to hooks. Inherited by a script that runs `git init` in a temp dir, they
# redirect it at the real repo (this once flipped a product to core.bare=true and re-pointed a worktree's HEAD).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MODE=full; PLAN=""; PART=""; OUT=""; JOIN_DIRS=()
usage() { echo "usage: dsharp_strength.sh [--root DIR] [--part PLAN K --out DIR | --join PLAN DIR...]" >&2; exit 64; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 ]] || usage; ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    --part) [[ $# -ge 3 && "$3" =~ ^(0|[1-9][0-9]*)$ ]] || usage; MODE=part; PLAN="$2"; PART="$3"; shift 3 ;;
    --out)  [[ $# -ge 2 ]] || usage; OUT="$2"; shift 2 ;;
    --join) [[ $# -ge 3 ]] || usage; MODE="join"; PLAN="$2"; shift 2; JOIN_DIRS=("$@"); set -- ;;
    *) usage ;;
  esac
done
[[ "$MODE" != part || -n "$OUT" ]] || usage
[[ "$MODE" == full || -f "$PLAN" ]] || { echo "FATAL     no plan file: $PLAN"; exit 1; }
ENV_FILE="${CASCADE_ENVELOPE:-$ROOT/docs/cascade/envelope.md}"
JOBS="${DSHARP_JOBS:-1}"; [[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || JOBS=1
SERIAL=" ${DSHARP_SERIAL:-} "   # space-padded so ` D2 ` matches a whole id, not a prefix
CACHE="${DSHARP_CACHE:-on}"; [[ "$CACHE" == on ]] || CACHE=off   # a value we cannot read never turns on the weaker path
[[ "$MODE" == full ]] || CACHE=off   # t69: a part or a join never reads or writes a remembered verdict
CDIR="$ROOT/.cascade/verdicts"
# One line per verdict in .cascade/decisions.log, so the morning after an unattended run says which law
# went red and when. Never fatal: a logging failure must not change a verdict. Called only from the ordered
# collection below (never from a parallel worker), so decisions.log stays deterministic and unraced.
say() { python3 -B "$HERE/lib/decisions.py" "$ROOT" dsharp "$1" "$2" 2>/dev/null || true; }
# t67: laws live in the envelope and in docs/cascade/laws/*.md (README.md is not a shard) — always this repo's
# shards, whatever CASCADE_ENVELOPE points at. No envelope and no shard is no law; a shard alone still counts.
SHARDS="$ROOT/docs/cascade/laws"
has_shard=0
for f in "$SHARDS"/*.md; do [[ -f "$f" && "$(basename "$f")" != README.md ]] && has_shard=1 && break; done
if [[ ! -f "$ENV_FILE" && "$has_shard" -eq 0 && "$MODE" == full ]]; then echo "DSHARP 0/0"; exit 0; fi
trim() { echo "${1:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Declared laws into parallel arrays, in file order, TODO/none/"" normalized to empty.
# First, get the expected count so we can detect silent parser failures.
# A duplicate id anywhere (t67) makes the laws unreadable as one set: no verdict can be given for "D7".
if [[ ! -f "$ENV_FILE" && "$has_shard" -eq 0 ]]; then
  expected_count=0; : > "$TMP/laws.err"   # t69: a part or a join of a repo with no law is still a part or a join
elif ! expected_count="$(python3 -B "$HERE/lib/laws.py" "$ENV_FILE" --count --shards "$SHARDS" 2>"$TMP/laws.err")"; then
  echo "FATAL     the laws cannot be read: $(sed -n 's/^FATAL //p' "$TMP/laws.err" | head -1)"
  exit 1
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
done < <(python3 -B "$HERE/lib/laws.py" "$ENV_FILE" --declared --shards "$SHARDS" 2>/dev/null | tee "$TMP/declared" || true)
n="${#ids[@]}"

# Mismatch check: if laws.py declares a different count than what we parsed,
# the parser may have silently failed. Fail closed (I18).
if [[ "$expected_count" -ne "$n" ]]; then
  echo "FATAL     law parser mismatch: laws.py --declared returned $n laws but --count reports $expected_count"
  exit 1
fi

# Score one law by index -> $TMP/res.<idx>: line 1 STATUS, line 2 the print line, line 3 the say detail.
# No shared mutable state between invocations, so it is safe to run several at once; each law owns its file.
# t68: a check: shared by two or more laws (a family on one test, distinct break: mutant switches) runs once, in
# the pre-pass below, before any break: runs; each law in the family takes that result. Any other check runs here.
chk_of=()
check_passes() {
  local g="${chk_of[$1]:-}" rc
  if [[ -n "$g" ]]; then rc="$(cat "$TMP/chk.$g" 2>/dev/null)"; [[ -n "$rc" && "$rc" -eq 0 ]]; return; fi   # no memo is a fail
  ( cd "$ROOT" && eval "${checks[$1]}" ) >/dev/null 2>&1
}

# The three result lines for a law and its status — the only place a verdict line is worded, so a joined run (t69)
# and a single run print the same bytes for the same verdicts.
res_for() {  # res_for <status> <index>
  local i="$2" id="${ids[$2]}" law="${laws[$2]}" val="${checks[$2]}" twin="${twins[$2]}" line detail=""
  case "$1" in
    UNPROVEN) if [[ -z "$val" ]]; then line="UNPROVEN  $id  $law  (no validator)"; detail="$id $law — no check command"
              else line="UNPROVEN  $id  $law  (no red twin)"; detail="$id $law — no break command"; fi ;;
    RED)      line="RED       $id  $law  — validator failed: $val"; detail="$id $law — check failed: $val" ;;
    THEATER)  line="THEATER   $id  $law  — red twin passed, validator cannot fail: $twin"; detail="$id $law — break passed, so the check cannot fail: $twin"
              # t75: Xcode hands only TEST_RUNNER_* variables to the tests, so a bare INV_MUTANT never reaches them.
              if [[ "$twin" == *xcodebuild* && "$twin" =~ (^|[[:space:]])INV_MUTANT= ]]; then
                line="$line  (Xcode passes only TEST_RUNNER_* variables to tests: write TEST_RUNNER_INV_MUTANT=$id — USAGE.md §B16)"
              fi ;;
    GREEN)    line="GREEN     $id  $law" ;;
  esac
  printf '%s\n' "$1"; printf '%s\n' "$line"; printf '%s\n' "$detail"
}

score_one() {
  local i="$1" val="${checks[$1]}" twin="${twins[$1]}" status
  if [[ -z "$val" || -z "$twin" ]]; then
    status=UNPROVEN
  elif ! check_passes "$i"; then
    status=RED
  elif ( cd "$ROOT" && eval "$twin" ) >/dev/null 2>&1; then
    status=THEATER
  else
    status=GREEN
  fi
  res_for "$status" "$i" > "$TMP/res.$i"
}

sha_of() { python3 -B -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1" 2>/dev/null; }
LAWS_SHA="$(sha_of "$TMP/declared")"; PLAN_SHA=""; [[ "$MODE" == full ]] || PLAN_SHA="$(sha_of "$PLAN")"
# t69: the plan must name these laws, each once, at the index this script gave it. Anything else is not this plan.
if [[ "$MODE" != full ]]; then
  planned=(); bad=""
  while IFS=$'\t' read -r pi pid pk; do
    [[ -z "$pi$pid$pk" ]] && continue
    if [[ ! "$pi" =~ ^(0|[1-9][0-9]*)$ || ! "$pk" =~ ^(0|[1-9][0-9]*)$ ]] || [[ "$pi" -ge "$n" ]]; then bad="a malformed row: $pi $pid $pk"; break; fi
    [[ "$pid" == "${ids[$pi]}" ]] || { bad="row $pi names $pid, but law $pi is ${ids[$pi]}"; break; }
    [[ -z "${planned[$pi]:-}" ]] || { bad="law ${ids[$pi]} is planned twice"; break; }
    planned[$pi]="$pk"
  done < "$PLAN"
  if [[ -z "$bad" ]]; then for ((i = 0; i < n; i++)); do [[ -n "${planned[$i]:-}" ]] || { bad="law ${ids[$i]} is in no part"; break; }; done; fi
  [[ -z "$bad" ]] || { echo "FATAL     plan: $bad"; exit 1; }
fi

if [[ "$MODE" == part ]]; then
  # Laws another part owns are marked done before anything runs, so the cache, the harness, the shared-check pre-pass
  # and the scorer all pass them by, exactly as they pass by a law already proven.
  for ((i = 0; i < n; i++)); do [[ "${planned[$i]}" == "$PART" ]] || printf 'SKIP\n\n\n' > "$TMP/res.$i"; done
elif [[ "$MODE" == join ]]; then
  bad=""; parts_seen=" "
  for d in "${JOIN_DIRS[@]}"; do
    m_laws="$(sed -n 's/^laws //p' "$d/manifest" 2>/dev/null)"; m_plan="$(sed -n 's/^plan //p' "$d/manifest" 2>/dev/null)"
    m_part="$(sed -n 's/^part //p' "$d/manifest" 2>/dev/null)"
    if [[ ! -f "$d/manifest" ]]; then bad="$d has no manifest"
    elif [[ "$m_laws" != "$LAWS_SHA" ]]; then bad="$d scored other laws than these"
    elif [[ "$m_plan" != "$PLAN_SHA" ]]; then bad="$d was scored from another plan"
    elif [[ ! "$m_part" =~ ^(0|[1-9][0-9]*)$ ]]; then bad="$d names no part"
    elif [[ "$parts_seen" == *" $m_part "* ]]; then bad="part $m_part is given twice"
    fi
    [[ -n "$bad" ]] && break
    parts_seen="$parts_seen$m_part "
  done
  if [[ -z "$bad" ]]; then
    for pk in $(printf '%s\n' "${planned[@]:-}" | sort -un); do
      [[ "$parts_seen" == *" $pk "* ]] || { bad="part $pk has no results"; break; }
    done
  fi
  if [[ -z "$bad" ]]; then
    for ((i = 0; i < n; i++)); do
      found=0; st=""
      for d in "${JOIN_DIRS[@]}"; do
        [[ -f "$d/res.$i" ]] || continue
        found=$((found + 1)); st="$(head -1 "$d/res.$i")"
        [[ "$(sed -n 's/^part //p' "$d/manifest")" == "${planned[$i]}" ]] || bad="law ${ids[$i]} has a result outside its part ${planned[$i]}"
      done
      [[ -n "$bad" ]] && break
      [[ "$found" -eq 1 ]] || { bad="law ${ids[$i]} has $found results, not one"; break; }
      case "$st" in
        GREEN|RED|THEATER) [[ -n "${checks[$i]}" && -n "${twins[$i]}" ]] || bad="law ${ids[$i]} cannot be $st: it has no check or no break" ;;
        UNPROVEN) [[ -z "${checks[$i]}" || -z "${twins[$i]}" ]] || bad="law ${ids[$i]} cannot be UNPROVEN: it has both commands" ;;
        *) bad="law ${ids[$i]} has an unknown status: $st" ;;
      esac
      [[ -n "$bad" ]] && break
      res_for "$st" "$i" > "$TMP/res.$i"
    done
  fi
  [[ -z "$bad" ]] || { echo "FATAL     join: $bad"; exit 1; }
fi

# t65: a law whose key matches its stored GREEN is scored from the cache; every other law runs below, as before.
# Inert with no declared law (DSHARP 0/0 stays byte-identical). Any doubt about a key is a miss (`CACHE off — why`).
keys=(); cached=(); f1=""; cache_note=""; hits=0
if [[ "$CACHE" == on && "$n" -gt 0 && -f "$HERE/lib/verdict_cache.py" ]]; then
  while IFS=$'\t' read -r kt ki kk kh; do
    case "$kt" in
      F) f1="$ki" ;;
      OFF) cache_note="CACHE     off — $ki" ;;
      K) [[ "$ki" =~ ^[0-9]+$ && "$ki" -lt "$n" ]] || continue
         keys[$ki]="$kk"
         if [[ "$kh" == hit ]]; then
           cached[$ki]=1; hits=$((hits + 1))
           { printf 'GREEN\n'; printf 'GREEN     %s  %s  (cached)\n' "${ids[$ki]}" "${laws[$ki]}"; printf '\n'; } > "$TMP/res.$ki"
         fi ;;
    esac
  done < <(for ((i = 0; i < n; i++)); do
             [[ -n "${checks[$i]}" && -n "${twins[$i]}" ]] || continue
             printf 'L\t%s\t%s\t%s\t%s\t%s\n' "$i" "${ids[$i]}" "${checks[$i]}" "${twins[$i]}" "${paths[$i]}"
           done | python3 -B "$HERE/lib/verdict_cache.py" keys "$ROOT" "$ENV_FILE" "$CDIR" 2>/dev/null || echo "OFF	the key script failed")
  [[ -z "$f1" && -z "$cache_note" ]] && cache_note="CACHE     off — no worktree fingerprint"
fi

# t64: Gradle laws tests/lib/law_harness.py can prove GREEN from one build instead of two per law. It prints only
# GREEN, and only when the human signed and committed `- DSHARP_GRADLE_HARNESS: on`; every other law is scored
# below by its own two commands, exactly as before, so a RED or a THEATER is always that path's verdict.
# DSHARP_HARNESS=off skips it (the merge gate always sets it).
if [[ "${DSHARP_HARNESS:-}" != off && "$MODE" != join && -f "$HERE/lib/law_harness.py" && "$n" -gt 0 ]]; then
  while IFS=$'\t' read -r hi hv; do
    [[ "$hv" == GREEN && "$hi" =~ ^[0-9]+$ && "$hi" -lt "$n" ]] || continue
    { printf 'GREEN\n'; printf 'GREEN     %s  %s\n' "${ids[$hi]}" "${laws[$hi]}"; printf '\n'; } > "$TMP/res.$hi"
  done < <(for ((i = 0; i < n; i++)); do [[ -f "$TMP/res.$i" ]] && continue   # a cached GREEN needs no build (t65)
             printf 'L\t%s\t%s\t%s\t%s\n' "$i" "${ids[$i]}" "${checks[$i]}" "${twins[$i]}"; done \
             | python3 -B "$HERE/lib/law_harness.py" "$ROOT" "$ENV_FILE" "$ROOT/.cascade/laws" 2>/dev/null)
fi

# t75: Xcode laws tests/lib/xcode_harness.py can prove GREEN from one build per build key. Same contract as t64's: it
# prints only GREEN, only when `- DSHARP_XCODE_HARNESS: on` is signed and committed; every other law is scored below by
# its own two commands. DSHARP_HARNESS=off (the merge gate) skips it too.
if [[ "${DSHARP_HARNESS:-}" != off && "$MODE" != join && -f "$HERE/lib/xcode_harness.py" && "$n" -gt 0 ]]; then
  while IFS=$'\t' read -r hi hv; do
    [[ "$hv" == GREEN && "$hi" =~ ^[0-9]+$ && "$hi" -lt "$n" ]] || continue
    { printf 'GREEN\n'; printf 'GREEN     %s  %s\n' "${ids[$hi]}" "${laws[$hi]}"; printf '\n'; } > "$TMP/res.$hi"
  done < <(for ((i = 0; i < n; i++)); do [[ -f "$TMP/res.$i" ]] && continue
             [[ "${checks[$i]}" == xcodebuild\ * ]] || continue   # nothing to start for a repo with no Xcode law
             printf 'L\t%s\t%s\t%s\t%s\n' "$i" "${ids[$i]}" "${checks[$i]}" "${twins[$i]}"; done \
             | python3 -B "$HERE/lib/xcode_harness.py" "$ROOT" "$ENV_FILE" "$ROOT/.cascade/laws" 2>/dev/null)
fi

# The shared-check pre-pass (t68): in this process, sequentially, in declared order — before any break: can change the
# tree, and outside DSHARP_JOBS/DSHARP_SERIAL. Only laws still to be scored here (not cached, not harness-proven).
while IFS=$'\t' read -r kind a b; do
  case "$kind" in
    M) chk_of[$a]="$b" ;;
    G) ( cd "$ROOT" && eval "${checks[$b]}" ) </dev/null >/dev/null 2>&1; echo "$?" > "$TMP/chk.$a" ;;   # not this loop's stdin
  esac
done < <(for ((i = 0; i < n; i++)); do
           [[ -f "$TMP/res.$i" || -z "${checks[$i]}" || -z "${twins[$i]}" ]] && continue
           printf '%s\t%s\n' "$i" "${checks[$i]}"
         done | python3 -B -c '
import sys
groups = {}
for line in sys.stdin:
    i, cmd = line.rstrip("\n").split("\t", 1)
    groups.setdefault(cmd, []).append(i)
g = 0
for cmd, members in groups.items():
    if len(members) < 2:
        continue
    print(f"G\t{g}\t{members[0]}")
    for i in members:
        print(f"M\t{i}\t{g}")
    g += 1
')

if [[ "$JOBS" -le 1 ]]; then
  for ((i = 0; i < n; i++)); do [[ -f "$TMP/res.$i" ]] || score_one "$i"; done
else
  # Partition only where it is used: serial laws (share a daemon/port/dir) never race; the rest go to the pool.
  par=(); ser=()
  for ((i = 0; i < n; i++)); do
    [[ -f "$TMP/res.$i" ]] && continue   # already proven by the law harness (t64)
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
k=0; m=0
for ((i = 0; i < n; i++)); do
  [[ "$drop_last" -eq 1 && "$i" -eq $((n - 1)) ]] && continue
  { IFS= read -r status; IFS= read -r line; IFS= read -r detail; } < "$TMP/res.$i"
  [[ "$status" == SKIP ]] && continue   # t69: another part's law
  m=$((m + 1))
  echo "$line"
  case "$status" in
    GREEN) k=$((k + 1)) ;;
    UNPROVEN|RED|THEATER) say "$status" "$detail" ;;
  esac
done
# t69: a part writes its statuses and stops here — the join prints RETIRED lines, metadata and the one DSHARP k/n.
if [[ "$MODE" == part ]]; then
  mkdir -p "$OUT" || { echo "FATAL     cannot write $OUT"; exit 1; }
  rm -f "$OUT"/res.* "$OUT/manifest"
  for ((i = 0; i < n; i++)); do
    IFS= read -r status < "$TMP/res.$i"
    [[ "$status" == SKIP ]] || printf '%s\n' "$status" > "$OUT/res.$i"
  done
  printf 'laws %s\nplan %s\npart %s\n' "$LAWS_SHA" "$PLAN_SHA" "$PART" > "$OUT/manifest"
  echo "DSHARP PART $PART: $k/$m — not a verdict; join the parts"
  [[ "$k" -eq "$m" ]]; exit
fi
# t65: store each GREEN this run proved itself — never a cached one, never another verdict — once the collector has
# every result, and only if the worktree is the one the keys were computed on (verdict_cache.py store checks).
if [[ "$CACHE" == on && "$n" -gt 0 && -f "$HERE/lib/verdict_cache.py" ]]; then
  if [[ -n "$f1" ]]; then
    nostore="$(for ((i = 0; i < n; i++)); do
                 [[ -n "${keys[$i]:-}" && -z "${cached[$i]:-}" && -f "$TMP/res.$i" ]] || continue
                 IFS= read -r status < "$TMP/res.$i"
                 [[ "$status" == GREEN ]] && printf 'S\t%s\t%s\n' "${ids[$i]}" "${keys[$i]}"
               done | python3 -B "$HERE/lib/verdict_cache.py" store "$ROOT" "$CDIR" "$f1" 2>/dev/null \
                 || echo "NOSTORE	the store script failed")"
    [[ -n "$nostore" ]] && echo "CACHE     not stored — ${nostore#*	}"
  fi
  if [[ -n "$cache_note" ]]; then echo "$cache_note"; else echo "CACHE     $hits hit, $((n - hits)) run"; fi
fi
# t68: a validly retired law is not scored and not in k/n; say so, with its reason. An invalid retired: line leaves
# the law in force (it was scored above) — name why.
while IFS='|' read -r rid rlaw rdate rwhy; do
  [[ -n "$rid" ]] || continue
  if [[ "$rdate" == INVALID ]]; then echo "WARNING   $rid  retired: — $rwhy; the law stays in force"
  else echo "RETIRED   $rid  $rlaw  — $rwhy ($rdate)"; fi
done < <(python3 -B "$HERE/lib/laws.py" "$ENV_FILE" --retired --shards "$SHARDS" 2>/dev/null || true)
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

[[ "$validation_fail" -gt 0 ]] && echo "METADATA  $validation_fail GREEN law(s) have invalid metadata — fix reason:/path: in docs/cascade/envelope.md or the law's shard (docs/cascade/laws/)"
[[ "$k" -eq "$n" && "$validation_fail" -eq 0 ]]
