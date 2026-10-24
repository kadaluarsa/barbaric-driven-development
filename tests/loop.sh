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
# Git exports GIT_DIR/GIT_WORK_TREE to hooks. Inherited by a script that runs `git init` in a temp dir, they
# redirect it at the real repo (this once flipped a product to core.bare=true and re-pointed a worktree's HEAD).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
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

# t77: a goal is one hop's definition of done. One written for another slice proves the wrong slice: refuse it. The
# last GOAL_SLICE line at column 0 decides; absent or a <placeholder>, the goal is not refused for its slice.
goal_slice="$(tr -d '\r' < "$GOAL" | grep -E '^GOAL_SLICE:' | tail -n 1 | sed -E 's/^GOAL_SLICE:[[:space:]]*//; s/[[:space:]]+$//')"
cur_slice="$(cascade_slice)"
if [[ "$LIST_ONLY" -eq 0 && -n "$goal_slice" && -n "$cur_slice" && "$goal_slice" != "$cur_slice" \
      && "$goal_slice" != "<"*">" && "$goal_slice" != *"{{"* ]]; then
  echo "LOOP REFUSED: ${GOAL#"$ROOT"/} is for slice $goal_slice, this hop is $cur_slice" >&2
  echo "  BOTTLENECK:  a goal is one hop's definition of done" >&2
  echo "  WHAT TO DO:  bash tests/goal.sh reset, then write this hop's validators" >&2
  exit 3
fi

# t67: laws read from the envelope and every shard as one set. A duplicate id makes them unreadable, and then no
# requirement can be computed — refuse rather than read "no rows" as "no law in force" (I13).
laws_err="$(cascade_laws_error)"
if [[ -n "$laws_err" ]]; then
  echo "LOOP REFUSED: the laws cannot be read — ${laws_err#FATAL }" >&2
  echo "  BOTTLENECK:  two laws share an id across docs/cascade/envelope.md and docs/cascade/laws/*.md." >&2
  echo "  WHAT TO DO:  give one of them a new id (a human-signed D# change), then: bash tests/sign.sh && git commit" >&2
  exit 3
fi

validators=(); waivers=()
while IFS= read -r line; do [[ -n "$line" ]] && validators+=("$line"); done \
  < <(tr -d '\r' < "$GOAL" | grep -E '^VALIDATOR:' | sed -E 's/^VALIDATOR:[[:space:]]*//; s/[[:space:]]+$//')
while IFS= read -r line; do [[ -n "$line" ]] && waivers+=("$line"); done \
  < <(tr -d '\r' < "$GOAL" | grep -E '^WAIVE_DSHARP:' | sed -E 's/^WAIVE_DSHARP:[[:space:]]*//; s/[[:space:]]+$//')

k=0; n=0
declare -a omitted=() not_affected=()

# A declared D# that cannot be proven (no validator, or no red twin) blocks the hop (I13). STOP and ask; never code around it.
unproven=()
while IFS='|' read -r id law why; do
  [[ -z "${id:-}" ]] && continue
  waived=0; for w in "${waivers[@]:-}"; do [[ "$w" == "$id "* || "$w" == "$id" ]] && waived=1 && break; done
  [[ "$waived" -eq 1 ]] && { echo "WAIVED  $id  $law  ($why; waiver recorded in $(basename "$GOAL"))"; continue; }
  unproven+=("$id  $law  ($why)")
done < <(cascade_dsharp_unproven)
if [[ ${#unproven[@]} -gt 0 && "$LIST_ONLY" -eq 0 ]]; then
  echo "LOOP REFUSED: a declared D# is not in force — its validator/twin are undecided (TODO or placeholder), which is a human decision, not work (I13):" >&2
  printf '  %s\n' "${unproven[@]}" >&2
  echo "" >&2
  echo "  BOTTLENECK:  that D# line (in docs/cascade/envelope.md or its shard in docs/cascade/laws/) has no runnable validator and red twin." >&2
  echo "  WHAT TO DO:  name both commands on the line (docs/cascade/proposals.md has candidates), then:" >&2
  echo "                 bash tests/sign.sh && git commit -am 'law: complete the D# line'" >&2
  echo "               Once named, writing the test files is ordinary hop work — the loop will run them." >&2
  echo "  OR DEFER:    add  WAIVE_DSHARP: <D#> <reason>  to $(basename "$GOAL"), then sign and commit." >&2
  echo "  RESUME WITH: /barbar auto      (or: bdd auto)" >&2
  exit 3
fi

# t66: which in-force laws this hop's diff can break. A narrow answer removes a *requirement* only; an affected
# law omitted from /goal is still a FAIL, and a validator listed anyway still runs. Any doubt is the full set,
# which is exactly the pre-t66 behavior. The selector reads the same envelope the law rows come from and the
# commit that opened this hop; it reads no base from the environment.
affected_mode="full"; affected_reason="selector unavailable"; affected_ids=""; not_affected_ids=""
if [[ -f "$ROOT/tests/lib/affected.py" ]]; then
  affected_tsv="$(python3 -B "$ROOT/tests/lib/affected.py" "$ROOT" "$(cascade_envelope)" --tsv 2>/dev/null || true)"
  if [[ -n "$affected_tsv" ]]; then
    affected_mode="narrow"; affected_reason=""
    while IFS=$'\t' read -r kind a b c; do
      case "${kind:-}" in
        M) affected_mode="${a:-full}"; affected_reason="${c:-}" ;;
        L) [[ -z "${a:-}" ]] && continue
           if [[ "${b:-}" == "affected" ]]; then affected_ids="$affected_ids|$a|"
           else not_affected_ids="$not_affected_ids|$a|"; fi ;;
      esac
    done <<< "$affected_tsv"
  fi
fi

# A law absent from the selector's rows is required (fail closed): only an explicit `not` hides a requirement.
law_not_affected() {
  [[ "$affected_mode" == "narrow" ]] || return 1
  [[ "$not_affected_ids" == *"|$1|"* ]] || return 1
  [[ "$affected_ids" != *"|$1|"* ]]
}

# I13: every in-force D# must appear in /goal, or carry a written waiver. An omitted one is a FAIL entry, never a skip.
while IFS='|' read -r id law val _twin _reason _path _tier; do
  [[ -z "${id:-}" ]] && continue
  found=0
  for v in "${validators[@]:-}"; do [[ "$v" == "$val" ]] && found=1 && break; done
  if [[ "$found" -eq 0 ]]; then
    for w in "${waivers[@]:-}"; do [[ "$w" == "$id "* || "$w" == "$id" ]] && found=2 && break; done
  fi
  case "$found" in
    0) if law_not_affected "$id"; then not_affected+=("$id  $law"); else omitted+=("$id  $law"); fi ;;
    2) echo "WAIVED  $id  $law  (waiver recorded in $(basename "$GOAL"))" ;;
  esac
done < <(cascade_dsharp_in_force)

if [[ "$LIST_ONLY" -eq 1 ]]; then
  printf 'stage %s, hop %s\n' "$stage" "$hop"
  printf 'validator: %s\n' "${validators[@]:-<none>}"
  if [[ "$affected_mode" == "narrow" ]]; then
    ids=""; for a in ${affected_ids//|/ }; do ids="$ids $a"; done
    printf 'affected:%s\n' "${ids:- <none>}"
    [[ ${#not_affected[@]} -gt 0 ]] && printf 'not affected: %s\n' "$(printf '%s\n' "${not_affected[@]}" | cut -d' ' -f1 | tr '\n' ' ')"
  else
    printf 'affected: full — %s\n' "$affected_reason"
  fi
  [[ ${#omitted[@]} -gt 0 ]] && printf 'OMITTED D#: %s\n' "${omitted[@]}"
  exit 0
fi

if [[ ${#validators[@]} -eq 0 && ${#omitted[@]} -eq 0 ]]; then
  echo "LOOP REFUSED: /goal has no VALIDATOR lines. A hop with no bar is not a hop (I9)." >&2
  exit 3
fi

# t77: validators carried over from earlier slices' goals. Counted and named on every pass (never a verdict), and
# refused above a cap — 10, or a GOAL_CARRY_MAX the human signed and committed. Standing gates (`# standing`) and
# law checks never count. History that cannot be read checks no cap and says so.
goal_note=""
if [[ -f "$ROOT/tests/lib/goal_history.py" ]]; then
  carry_tsv="$(cascade_dsharp_in_force | while IFS='|' read -r _id _law val _rest; do [[ -n "$val" ]] && printf '%s\n' "$val"; done \
    | python3 -B "$ROOT/tests/lib/goal_history.py" "$ROOT" "$GOAL" "$cur_slice" "$(cascade_envelope)" 2>/dev/null || true)"
  carried=0; total=0; standing=0; origins=""; carry_cap=""
  while IFS=$'\t' read -r kind a b c d; do
    case "${kind:-}" in
      U) goal_note="goal: history unreadable, carry cap not checked" ;;
      N) carried="${a:-0}"; total="${b:-0}"; standing="${c:-0}"; origins="${d:-}" ;;
      C) carry_cap="${a:-}" ;;
    esac
  done <<< "$carry_tsv"
  if [[ "$carried" =~ ^[0-9]+$ && "$carried" -gt 0 ]]; then
    goal_note="goal: $carried of $total validators were in earlier slices' goals ($origins), $standing standing — move the $carried to the project's CI or a law (USAGE.md §B16)"
    if [[ "$carry_cap" =~ ^[0-9]+$ && "$carried" -gt "$carry_cap" ]]; then
      echo "LOOP REFUSED: $carried validators were in earlier slices' goals ($origins), the cap is $carry_cap" >&2
      echo "  BOTTLENECK:  a goal is one hop's definition of done; past slices' tests belong to the project's CI or a law" >&2
      echo "  WHAT TO DO:  move $((carried - carry_cap)) or more to CI or a law (USAGE.md §B16), or the human signs a higher" >&2
      echo "               GOAL_CARRY_MAX in docs/cascade/envelope.md (a <EDIT> line, committed)" >&2
      exit 3
    fi
  fi
fi

# Two loops in one repo (autopilot's re-run from a commit, a human in another terminal) would share .cascade/loop
# and Gradle's outcome file. They take turns. A loop that a validator starts itself inherits BDD_LOOP_LOCKED and
# does not wait on its parent; a lock whose holder is gone is broken.
gitdir="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null || true)"
if [[ -z "${BDD_LOOP_LOCKED:-}" && "$gitdir" == /* && -d "$gitdir" ]]; then
  LOCK="$gitdir/cascade-loop.lock"
  until mkdir "$LOCK" 2>/dev/null; do
    holder="$(cat "$LOCK/pid" 2>/dev/null || true)"
    if { [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; } \
       || { [[ -z "$holder" ]] && [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ]]; }; then
      rm -rf "$LOCK"; continue
    fi
    sleep 1
  done
  echo $$ > "$LOCK/pid"
  trap 'rm -rf "$LOCK"' EXIT
  export BDD_LOOP_LOCKED=1
fi

# Each line's output goes to its own log, reset every pass. .cascade/ is outside the receipt's fingerprint and
# install.sh gitignores the log directories. If the directory cannot be made, output is discarded as before t62.
LOGDIR="$ROOT/.cascade/loop"
rm -rf "$LOGDIR" 2>/dev/null || true
mkdir -p "$LOGDIR" 2>/dev/null || LOGDIR=""

# loop_detail <log> — what a FAIL needs to be fixed without re-running it: Gradle's failed-test lines, then
# the log's tail. At most 25 lines of 200 characters, so a huge log cannot flood the agent's context.
loop_detail() {
  [[ -n "$LOGDIR" && -s "$1" ]] || return 0
  { grep -E ' > .* FAILED$' "$1" | head -10; tail -n 14 "$1"; } | cut -c1-200 | sed 's/^/      | /'
  echo "      log: ${1#"$ROOT"/}"
}

# t62: consecutive plain Gradle lines can be proven to pass from a shared build (tests/lib/gradle_runner.py), run
# at their place in the goal so every line still sees what the lines before it did. The runner only ever reports
# PASS; any line it does not prove — every failure included — runs alone below, exactly as before.
# BDD_LOOP_RUNNER=shell turns it off. Nothing an environment variable says can loosen a verdict: merging test
# filters across lines takes a human-signed, committed envelope line, which the runner reads itself.
proven=(); runner_builds=0; runner_secs=0; seg_end=-1; use_runner=0; laws_in=""
tuning_seen=""; daemon_note=""   # t69: what the runner's builds were tuned with, and any daemon it had to start
gradle_re='^(\./gradlew|gradle) '
if [[ "${BDD_LOOP_RUNNER:-auto}" != shell && -n "$LOGDIR" && ${#validators[@]} -gt 1 ]] \
   && [[ "$(printf '%s\n' "${validators[@]}" | grep -cE "$gradle_re")" -gt 1 ]]; then
  use_runner=1
  laws_in="$(cascade_dsharp_in_force | while IFS='|' read -r _id _law val _rest; do [[ -n "$val" ]] && printf 'D\t%s\n' "$val"; done)"
fi
canon='^(0|[1-9][0-9]*)$'   # an index as the runner must print it: "010" is not 10, and bash would read it as 8
run_segment() {  # run_segment <index> — prove what can be proven in the batchable segment that starts there
  local from="$1" got="" i verdict summary
  seg_end="$from"
  while IFS=$'\t' read -r i verdict summary; do
    case "$i" in
      S) [[ "$verdict" =~ $canon ]] && runner_builds=$((runner_builds + verdict))
         [[ "$summary" =~ $canon ]] && runner_secs=$((runner_secs + summary)) ;;
      E) [[ "$verdict" =~ $canon ]] && [[ "$verdict" -ge "$from" && "$verdict" -lt ${#validators[@]} ]] && seg_end="$verdict" ;;
      T) [[ -n "$verdict" && "$tuning_seen" != *"$verdict"* ]] && tuning_seen="${tuning_seen:+$tuning_seen, }$verdict" ;;
      M) if [[ "$verdict" == unknown ]]; then daemon_note="${daemon_note:+$daemon_note; }unknown (${summary:-quiet log})"
         elif [[ "$verdict" =~ $canon ]]; then daemon_note="${daemon_note:+$daemon_note; }$verdict started (${summary:-?})"; fi ;;
      *) [[ "$i" =~ $canon && "$verdict" == PASS ]] && got="$got$i	${summary:-gradle build}
" ;;
    esac
  done < <( { for i in "${!validators[@]}"; do printf 'V\t%s\t%s\n' "$i" "${validators[$i]}"; done
              printf '%s\n' "$laws_in"
            } | python3 -B "$ROOT/tests/lib/gradle_runner.py" "$ROOT" "$(cascade_envelope)" "$LOGDIR" "$from" 2>>"$LOGDIR/runner.err" )
  while IFS=$'\t' read -r i summary; do   # only indexes inside the segment the runner declared
    [[ -n "$i" && "$i" -ge "$from" && "$i" -le "$seg_end" ]] && proven[$i]="$summary"
  done <<< "$got"
}

idx=-1; n_proven=0; n_alone=0; alone_secs=0
for v in "${validators[@]:-}"; do
  idx=$((idx + 1))
  [[ -z "$v" ]] && continue
  n=$((n + 1))
  if [[ "$use_runner" -eq 1 && "$idx" -gt "$seg_end" && "$v" =~ $gradle_re ]]; then
    run_segment "$idx"
  fi
  if [[ -n "${proven[$idx]:-}" ]]; then
    k=$((k + 1)); n_proven=$((n_proven + 1)); echo "PASS  $v"
    continue
  fi
  log=/dev/null; [[ -n "$LOGDIR" ]] && log="$LOGDIR/$idx.log"
  started=$SECONDS
  if ( cd "$ROOT" && eval "$v" ) >"$log" 2>&1; then
    k=$((k + 1)); echo "PASS  $v"
  else
    echo "FAIL  $v"
    loop_detail "$log"
  fi
  n_alone=$((n_alone + 1)); alone_secs=$((alone_secs + SECONDS - started))
done
if [[ -n "$LOGDIR" && "$n" -gt 0 ]]; then
  if [[ "$runner_builds" -gt 0 ]]; then
    # t69: the suffixes appear only when the runner reported tuning; with BDD_GRADLE_TUNING=off this line is t62's.
    echo "loop: $n lines — $n_proven proven in $runner_builds gradle build(s) (${runner_secs}s), $n_alone ran alone (${alone_secs}s); logs in .cascade/loop/${tuning_seen:+; tuning: $tuning_seen}${daemon_note:+; daemon: $daemon_note}"
  else
    echo "loop: $n lines ran alone (${alone_secs}s); logs in .cascade/loop/"
  fi
fi

# A law the diff cannot reach is printed as its own state and is not counted: `not affected` is never a pass.
for o in "${not_affected[@]:-}"; do
  [[ -z "$o" ]] && continue
  echo "not affected  $o"
done

# An omitted in-force D# is a FAIL entry, never a skipped one.
for o in "${omitted[@]:-}"; do
  [[ -z "$o" ]] && continue
  n=$((n + 1))
  echo "FAIL  in-force D# omitted from /goal: $o"
done

[[ -n "$goal_note" ]] && echo "$goal_note"
echo
echo "LOOP $k/$n"
if [[ "$k" -eq "$n" && "$n" -gt 0 ]]; then
  # A receipt for I10: the accept edge may only be asked for after the loop actually passed on THIS tree.
  # It names the hop and fingerprints every tracked+untracked file, so any edit after the loop invalidates it.
  fp="$(cascade_worktree_sha "$ROOT")"
  if [[ -z "$fp" ]]; then
    # A receipt with no fingerprint cannot describe this tree; the Stop hook would refuse it anyway, and
    # misreport why (t59). Say so here, where the cause can still be seen.
    rm -f "$ROOT/.cascade/loop-receipt" 2>/dev/null || true
    echo "LOOP $k/$n, but the tree could not be fingerprinted — no receipt written, so the accept edge would be refused."
    echo "  see why: git status   (the fingerprint needs a readable git work tree; it prints nothing when git fails)"
    exit 1
  fi
  mkdir -p "$ROOT/.cascade" 2>/dev/null || true
  printf '%s %s %s\n' "$hop" "$stage" "$fp" > "$ROOT/.cascade/loop-receipt" 2>/dev/null || true
  python3 -B "$ROOT/tests/lib/decisions.py" "$ROOT" loop "PASS" "LOOP $k/$n on $hop $stage — accept edge unlocked" 2>/dev/null || true
  echo "Hop edge. STITCH NEEDED: accept execute for stage $stage, or send back."
  exit 0
fi
rm -f "$ROOT/.cascade/loop-receipt" 2>/dev/null || true
echo "not n/n — do not ask for accept."
exit 1
