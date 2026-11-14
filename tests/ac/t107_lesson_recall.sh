#!/usr/bin/env bash
# AC tests for 05b t107-lesson-recall: the prompt hook shows the signed lessons that match the hop, under a byte cap,
# and a context budget test keeps every later slice from growing the per-prompt context without a human signature.
#   AC1  `tests/patterns.sh --recall <class>` shows only lessons whose scope is that class or ANY.
#   AC2  most events in the scope's latest 5 hops first, then most events in all its hops, then lesson id.
#   AC3  at most 3 lessons; the line and its newline at most 400 bytes (UTF-8); a lesson that does not fit is skipped
#        and a later one that fits is shown.
#   AC4  a SETTLED lesson, a NO MATCH lesson and a malformed line are never shown; each class shows a lesson.
#   AC5  nothing shown: no line and exit 0; --recall takes only --root; an unknown class or another option exits 64;
#        --recall writes nothing.
#   AC6  .claude/hooks/seam.py prints the line on its own, right after the DOC PARTS line, while a hop runs; not when
#        idle; a missing, failing, slow or over-long recall adds no line and changes nothing else; the hook's cap is
#        400 bytes with the newline, counted in UTF-8.
#   AC7  law D1 (docs/cascade/laws/context.md, human decision 2026-11-14): in force with its exact check and break,
#        GREEN; tests/inv/D1_context_budget.sh: 24 rows (6 classes x 4 prompts) in the limit at +400 on this tree,
#        the fixture's lessons line at least 300 bytes; red twin BUDGET_PAD=1024 fails every row; --grow is the limit;
#        a bad argument exits 64; the shard is indexed (lint clean); a new install ships no shard and indexes none;
#        the nightly regress job checks out full history.
#   AC8  t104 and t106 tests still pass; USAGE.md B25; release 3.5.8 or later.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOG_SRC BDD_HOOK_HOST PLUGIN_ROOT CLAUDE_PLUGIN_ROOT BDD_PLUGIN_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
S="$ROOT/tests/patterns.sh"
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------- fixture: 8 hops of 3 classes, events in them, one event with no hop ----------
R="$TMP/r"; mkdir -p "$R/docs/cascade" "$R/.cascade"
git -C "$R" init -q
hs() {  # hs <repo> <date> <hop> <stage> <slice> — commit the hop-state lines at that author time
  python3 - "$1/docs/cascade/hop-state.md" "$3" "$4" "$5" <<'PY'
import os, re, sys
p, hop, stage, slice_ = sys.argv[1:]
s = open(p).read() if os.path.isfile(p) else "CURRENT_HOP:\nCURRENT_STAGE:\nCURRENT_SLICE:\nAUTOPILOT:\n"
for k, v in (("CURRENT_HOP", hop), ("CURRENT_STAGE", stage), ("CURRENT_SLICE", slice_)):
    s = re.sub(rf"(?m)^{k}:.*$", f"{k}: {v}", s, count=1)
s = re.sub(r"(?m)^AUTOPILOT:.*$", "AUTOPILOT:", s)
open(p, "w").write(s)
PY
  git -C "$1" add -A
  GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" commit -qm "hop-state $3 $4 $5"
}
history() {  # history <repo>: the same hops in any repo
  hs "$1" 2026-01-01T00:00:00Z NONE 05b s0
  hs "$1" 2026-01-02T00:00:00Z GENERATE 05b a
  hs "$1" 2026-01-03T00:00:00Z EXECUTE 05b a
  hs "$1" 2026-01-04T00:00:00Z GENERATE 05b b
  hs "$1" 2026-01-05T00:00:00Z EXECUTE 05b b
  hs "$1" 2026-01-06T00:00:00Z EXECUTE 10 audit
  hs "$1" 2026-01-07T00:00:00Z NONE 10 audit
  hs "$1" 2026-01-08T00:00:00Z GENERATE 05b c
  hs "$1" 2026-01-09T00:00:00Z EXECUTE 05b c
  hs "$1" 2026-01-10T00:00:00Z GENERATE 05b d
  hs "$1" 2026-01-11T00:00:00Z NONE 05b d
}
history "$R"
python3 - "$R/.cascade/decisions.log" <<'PY'
import sys
E = {   # (actor, verdict, detail): days. GENERATE hops 02 04 08 10, EXECUTE-BUILD 03 05 09, EXECUTE-AUDIT 06.
    ("stop_guard", "NOEDGE", "GENERATE 05b ended without its edge line"): ["02", "02", "04", "07"],   # 07: no hop
    ("hop_guard", "DENY", "product write on an EXECUTE hop"): ["03"],
    ("stop_guard", "HALT", "the gate failed"): ["02", "03", "05", "06"],
    ("audit", "DIRTY", "row FR-1 has no test"): ["06", "06"],
    ("loop", "STUCK", "same failing set"): ["02", "02", "02", "02", "02"],
}
rows = []
for (a, v, d), days in E.items():
    for day in days:
        rows.append(f"2026-01-{day}T10:{len(rows):02d}:00Z  {a:<11} {v:<7} {d}  src=agent")
with open(sys.argv[1], "w") as f:
    f.write("\n".join(sorted(rows)) + "\n")
PY
LES="$R/docs/cascade/lessons.md"
lessons() {  # lessons <L1 do> <L3 do> <L8 do> <L9 do>
  cat > "$LES" <<EOF
# Lessons

LESSON L1: stop_guard NOEDGE "GENERATE Nb ended" | scope: GENERATE | since: 2026-06-01 | do: $1
LESSON L2: hop_guard DENY "product write" | scope: EXECUTE-BUILD | since: 2026-06-01 | do: Build two.
LESSON L3: stop_guard HALT "the gate" | scope: ANY | since: 2026-06-01 | do: $2
LESSON L4: audit DIRTY "row FR-" | scope: EXECUTE-AUDIT | since: 2026-06-01 | do: Audit four.
LESSON L5: loop STUCK "same failing" | scope: ANY | since: 2026-01-03 | do: Settled five.
LESSON L6: nobody NEVER "never seen" | scope: ANY | since: 2026-06-01 | do: No match six.
LESSON L7: stop_guard HALT "the gate" | scope: ANY | since: 2026-06-01 | do: TODO — one imperative sentence
LESSON L8: stop_guard NOEDGE "GENERATE" | scope: GENERATE | since: 2026-06-01 | do: $3
LESSON L9: stop_guard HALT "the gate" | scope: GENERATE | since: 2026-06-01 | do: $4
  LESSON L10: stop_guard HALT "the gate" | scope: ANY | since: 2026-06-01 | do: Indented ten.
EOF
}
lessons "Gen one." "Any three." "Gen eight." "Gen nine."
git -C "$R" add -A && GIT_AUTHOR_DATE=2026-01-12T00:00:00Z GIT_COMMITTER_DATE=2026-01-12T00:00:00Z git -C "$R" commit -qm lessons
rc() { bash "$S" --root "$R" --recall "$1" > "$TMP/out" 2> "$TMP/err"; echo $?; }
H="LESSONS THIS HOP: "

# ---------- AC1: scope ----------
ok=1
want() {  # the line each class must show (bash 3.2 has no associative arrays)
  case "$1" in
    GENERATE)      echo "${H}L1 Gen one.; L8 Gen eight.; L3 Any three." ;;
    EXECUTE-BUILD) echo "${H}L3 Any three.; L2 Build two." ;;
    EXECUTE-AUDIT) echo "${H}L3 Any three.; L4 Audit four." ;;
    *)             echo "${H}L3 Any three." ;;
  esac
}
for c in GENERATE EXECUTE-BUILD EXECUTE-AUDIT EXECUTE-DESIGN EXECUTE-PRR; do
  r="$(rc "$c")"
  [[ "$r" == 0 && "$(cat "$TMP/out")" == "$(want "$c")" ]] \
    || { ok=0; echo "      --recall $c: exit $r, got: $(cat "$TMP/out" "$TMP/err")"; echo "        want: $(want "$c")"; }
done
for c in GENERATE EXECUTE-BUILD EXECUTE-AUDIT EXECUTE-DESIGN EXECUTE-PRR; do   # no other class's lesson leaks in
  rc "$c" >/dev/null
  case "$c" in GENERATE) bad='L2 |L4 ' ;; EXECUTE-BUILD) bad='L1 |L4 |L8 |L9 ' ;; EXECUTE-AUDIT) bad='L1 |L2 |L8 |L9 ' ;;
               *) bad='L1 |L2 |L4 |L8 |L9 ' ;; esac
  grep -qE "$bad" "$TMP/out" && { ok=0; echo "      --recall $c shows a lesson of another scope: $(cat "$TMP/out")"; }
done
t AC1 "$ok" "--recall shows only the lessons whose scope is the hop class or ANY, for each of the 5 classes"

# ---------- AC2: order ----------
ok=1
# Latest 5 hops: GENERATE 02 04 08 10 (all 4); ANY 05 06 08 09 10; EXECUTE-BUILD 03 05 09; EXECUTE-AUDIT 06.
# (recent, all): L1 (3, 3) and L8 (3, 3) in GENERATE (the 01-07 event has no hop); L3 (2, 4); L9 (1, 1); L2 (1, 1);
# L4 (2, 2).
rc GENERATE >/dev/null   # L1 and L8 (3 recent) before L3 (2 recent, though 4 in all); L1 before L8 by id
[[ "$(cat "$TMP/out")" == "${H}L1 Gen one.; L8 Gen eight.; L3 Any three." ]] \
  || { ok=0; echo "      GENERATE order: $(cat "$TMP/out")"; }
rc EXECUTE-AUDIT >/dev/null   # L3 and L4 have 2 recent each; L3 has 4 in all, L4 2
[[ "$(cat "$TMP/out")" == "${H}L3 Any three.; L4 Audit four." ]] || { ok=0; echo "      EXECUTE-AUDIT order: $(cat "$TMP/out")"; }
rc EXECUTE-BUILD >/dev/null   # L3 (2 recent) before L2 (1), though L2 has the lower id
[[ "$(cat "$TMP/out")" == "${H}L3 Any three.; L2 Build two." ]] || { ok=0; echo "      EXECUTE-BUILD order: $(cat "$TMP/out")"; }
t AC2 "$ok" "events in the scope's latest 5 hops first (L1 3 before L3 2, though L3 has 4 in all); then all events (L3 4 before L4 2); then id (L1 before L8)"

# ---------- AC3: the two caps ----------
ok=1
rc GENERATE >/dev/null
grep -q 'L9 ' "$TMP/out" && { ok=0; echo "      a fourth lesson was shown: $(cat "$TMP/out")"; }
A150="$(printf 'a%.0s' $(seq 1 150))"; B150="$(printf 'b%.0s' $(seq 1 150))"; C150="$(printf 'c%.0s' $(seq 1 150))"
lessons "$B150" "$A150" "$C150" "Gen nine."
rc GENERATE >/dev/null
# L1 + L8 = 326 bytes; L3 (+155) does not fit in 399; L9 (+14) does.
want="${H}L1 ${B150}; L8 ${C150}; L9 Gen nine."
[[ "$(cat "$TMP/out")" == "$want" ]] || { ok=0; echo "      byte cap: got $(wc -c < "$TMP/out") bytes: $(cut -c1-60 "$TMP/out")… want ${#want}+1 bytes"; }
for k in 34 35; do   # room for L9's sentence: 399 - 326 - 2 - 3 = 68 bytes; "é" is 2 bytes
  E="$(python3 -c "print('é' * $k)")"
  lessons "$B150" "$A150" "$C150" "$E"
  rc GENERATE >/dev/null
  n="$(wc -c < "$TMP/out" | tr -d ' ')"
  if [[ $k -eq 34 ]]; then
    [[ "$(cat "$TMP/out")" == "${H}L1 ${B150}; L8 ${C150}; L9 ${E}" && "$n" -eq 400 ]] \
      || { ok=0; echo "      34 × é (68 bytes) should just fit: $n bytes with the newline"; }
  else
    [[ "$(cat "$TMP/out")" == "${H}L1 ${B150}; L8 ${C150}" ]] \
      || { ok=0; echo "      35 × é (70 bytes, 35 characters) must not fit — the cap counts bytes: $n bytes"; }
  fi
done
lessons "Gen one." "Any three." "Gen eight." "Gen nine."
t AC3 "$ok" "at most 3 lessons; the line and its newline at most 400 UTF-8 bytes (400 exactly fits, 402 does not); a lesson that does not fit is skipped and a later one that fits is shown"

# ---------- AC4: settled, no match, malformed ----------
ok=1
bash "$S" --root "$R" > "$TMP/full" 2>&1
grep -qE '^LESSON L5 .*SETTLED$' "$TMP/full" || { ok=0; echo "      the fixture's L5 is not SETTLED: $(grep '^LESSON L5' "$TMP/full")"; }
grep -qE '^LESSON L6 .*NO MATCH$' "$TMP/full" || { ok=0; echo "      the fixture's L6 is not NO MATCH: $(grep '^LESSON L6' "$TMP/full")"; }
grep -q 'malformed: docs/cascade/lessons.md:9 ' "$TMP/full" || { ok=0; echo "      the fixture's L7 is not malformed"; }
for c in GENERATE EXECUTE-BUILD EXECUTE-AUDIT EXECUTE-DESIGN EXECUTE-PRR; do
  rc "$c" >/dev/null
  grep -qE 'L5 |L6 |L7 |L10 |Settled|No match|TODO|Indented' "$TMP/out" && { ok=0; echo "      --recall $c: $(cat "$TMP/out")"; }
  grep -q "^${H}L[0-9]" "$TMP/out" || { ok=0; echo "      --recall $c shows no lesson at all"; }   # not a pass by silence
done
t AC4 "$ok" "a SETTLED lesson (5 events, the most), a NO MATCH lesson, a malformed line and an indented line are never shown, while each class shows a lesson"

# ---------- AC5: nothing to show; arguments; read only ----------
ok=1
grep -E '^LESSON L(5|6|7):' "$LES" > "$TMP/only"; { echo "# Lessons"; cat "$TMP/only"; } > "$LES"
r="$(rc GENERATE)"; [[ "$r" == 0 && ! -s "$TMP/out" ]] || { ok=0; echo "      only settled/no-match/malformed lessons: exit $r, out: $(cat "$TMP/out")"; }
rm -f "$LES"
r="$(rc GENERATE)"; [[ "$r" == 0 && ! -s "$TMP/out" ]] || { ok=0; echo "      no lessons.md: exit $r, out: $(cat "$TMP/out")"; }
git -C "$R" checkout -q -- docs/cascade/lessons.md
before="$(cd "$R" && git status --porcelain; cksum docs/cascade/lessons.md .cascade/decisions.log)"
rc GENERATE >/dev/null
[[ "$(cd "$R" && git status --porcelain; cksum docs/cascade/lessons.md .cascade/decisions.log)" == "$before" ]] \
  || { ok=0; echo "      --recall changed a file"; }
for args in "--recall ANY" "--recall" "--recall generate" "--recall GENERATE --propose" "--recall GENERATE --min 1" \
            "--since 2026-01-01 --recall GENERATE"; do
  # shellcheck disable=SC2086  # the words are the arguments
  bash "$S" --root "$R" $args >/dev/null 2>&1; r=$?
  [[ $r -eq 64 ]] || { ok=0; echo "      '$args' exited $r, want 64"; }
done
t AC5 "$ok" "nothing to show prints no line and exits 0 (no lessons.md too); --recall writes nothing; an unknown class, a missing class or another option with --recall exits 64"

# ---------- AC6: the prompt hook ----------
ok=1
copy_tree() {  # this tree as it is on disk: tracked files and new files git does not ignore
  mkdir -p "$1"
  ( cd "$ROOT" && git ls-files -z -co --exclude-standard | python3 -B -c '
import os, sys
sys.stdout.write("\0".join(p for p in sys.stdin.read().split("\0") if p and os.path.isfile(p)))' \
    | tar --null -T - -cf - ) | tar -x -C "$1"
}
F="$TMP/f"; copy_tree "$F"; rm -rf "$F/.cascade"; mkdir -p "$F/.cascade"
git -C "$F" init -q
history "$F"
cp "$R/.cascade/decisions.log" "$F/.cascade/decisions.log"; cp "$R/docs/cascade/lessons.md" "$F/docs/cascade/lessons.md"
git -C "$F" add -A && GIT_AUTHOR_DATE=2026-01-12T00:00:00Z GIT_COMMITTER_DATE=2026-01-12T00:00:00Z git -C "$F" commit -qm lessons
setcur() {  # the hop now, not committed
  python3 - "$F/docs/cascade/hop-state.md" "$1" "$2" <<'PY'
import re, sys
p, hop, stage = sys.argv[1:]
s = open(p).read()
s = re.sub(r"(?m)^CURRENT_HOP:.*$", f"CURRENT_HOP: {hop}", s, count=1)
s = re.sub(r"(?m)^CURRENT_STAGE:.*$", f"CURRENT_STAGE: {stage}", s, count=1)
s = re.sub(r"(?m)^CURRENT_SLICE:.*$", "CURRENT_SLICE: now", s, count=1)
open(p, "w").write(s)
PY
}
seam() {  # seam <out file>: run the prompt hook in F; the file gets its additionalContext; prints exit code and seconds
  python3 - "$F" "$1" <<'PY'
import json, os, subprocess, sys, time, uuid
tree, out = sys.argv[1:]
pid = uuid.uuid4().hex   # a new prompt each call: the hook ignores a prompt_id it has seen (and $(…) loses a counter)
env = {k: v for k, v in os.environ.items() if not k.startswith(("CASCADE_", "BDD_", "CLAUDE"))}
ev = {"cwd": tree, "prompt": "continue", "prompt_id": pid, "session_id": "t107", "hook_event_name": "UserPromptSubmit"}
t0 = time.time()
r = subprocess.run([sys.executable, "-B", os.path.join(tree, ".claude", "hooks", "seam.py")], input=json.dumps(ev),
                   capture_output=True, text=True, env=env, cwd=tree, timeout=120)
dt = time.time() - t0
ctx = ""
if r.stdout.strip():
    try:
        ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
    except (ValueError, KeyError, TypeError):
        ctx = "NOJSON " + r.stdout[:200]
open(out, "w").write(ctx)
print(f"{r.returncode} {dt:.1f}")
PY
}
nolesson() { grep -v '^LESSONS THIS HOP: ' "$1"; }
setcur GENERATE 05b
read -r r _ <<<"$(seam "$TMP/g.ctx")"
[[ "$r" == 0 ]] || { ok=0; echo "      the hook exited $r"; }
[[ "$(grep -c '^LESSONS THIS HOP: ' "$TMP/g.ctx")" == 1 ]] || { ok=0; echo "      GENERATE: not exactly one lessons line"; }
grep -qxF "$(want GENERATE)" "$TMP/g.ctx" || { ok=0; echo "      GENERATE: the line is not the --recall line: $(grep '^LESSONS' "$TMP/g.ctx")"; }
prev="$(grep -B1 '^LESSONS THIS HOP: ' "$TMP/g.ctx" | head -1)"
[[ "$prev" == "DOC PARTS THIS HOP: "* ]] || { ok=0; echo "      the line does not come right after the DOC PARTS line: ${prev:0:60}"; }
setcur EXECUTE 10
seam "$TMP/a.ctx" >/dev/null
grep -qxF "$(want EXECUTE-AUDIT)" "$TMP/a.ctx" || { ok=0; echo "      EXECUTE 10: $(grep '^LESSONS' "$TMP/a.ctx")"; }
setcur NONE 05b
seam "$TMP/i.ctx" >/dev/null
grep -q 'LESSONS THIS HOP' "$TMP/i.ctx" && { ok=0; echo "      idle: the hook showed lessons"; }
setcur GENERATE 05b
cp "$F/tests/patterns.sh" "$TMP/patterns.keep"
for stub in 'exit 1' 'echo "LESSONS THIS HOP: L1 x"; exit 3' 'sleep 30' "printf 'LESSONS THIS HOP: %0400d\n' 0" 'echo "something else"' MISSING; do
  if [[ "$stub" == MISSING ]]; then rm -f "$F/tests/patterns.sh"; else printf '#!/usr/bin/env bash\n%s\n' "$stub" > "$F/tests/patterns.sh"; fi
  read -r r secs <<<"$(seam "$TMP/s.ctx")"
  [[ "$r" == 0 ]] || { ok=0; echo "      recall stub '$stub': the hook exited $r"; }
  grep -q 'LESSONS THIS HOP' "$TMP/s.ctx" && { ok=0; echo "      recall stub '$stub': a lessons line was shown"; }
  [[ "$(nolesson "$TMP/s.ctx")" == "$(nolesson "$TMP/g.ctx")" ]] || { ok=0; echo "      recall stub '$stub': the rest of the context changed"; }
  python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) < 15 else 1)" "$secs" || { ok=0; echo "      recall stub '$stub': the hook took ${secs}s"; }
done
# The hook's own cap: 400 bytes with the newline, in UTF-8 (whatever the recall prints).
L399="LESSONS THIS HOP: L1 $(printf 'z%.0s' $(seq 1 378))"                              # 399 + newline = 400
L400="${L399}z"                                                                          # 401
LUTF="LESSONS THIS HOP: L1 $(python3 -c "print('é' * 190)")"                           # 211 characters, 401 bytes (402 with the newline)
for line in "$L399" "$L400" "$LUTF"; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$line" > "$F/tests/patterns.sh"
  seam "$TMP/c.ctx" >/dev/null
  n=$(( $(printf '%s' "$line" | wc -c) + 1 ))
  if [[ "$line" == "$L399" ]]; then
    grep -qxF "$line" "$TMP/c.ctx" || { ok=0; echo "      a $n-byte line (with the newline) was not shown"; }
  else
    grep -q 'LESSONS THIS HOP' "$TMP/c.ctx" && { ok=0; echo "      a $n-byte line (${#line} characters) was shown"; }
  fi
done
cp "$TMP/patterns.keep" "$F/tests/patterns.sh"
t AC6 "$ok" "the prompt hook shows the --recall line on its own, right after DOC PARTS, on GENERATE and EXECUTE, not when idle; a missing, failing, slow (30 s) or over-long recall, or other output, adds no line and changes nothing else; its cap is 400 UTF-8 bytes with the newline (400 shown; 401 not; a 211-character line of 401 bytes not)"

# ---------- AC7: the context budget is law D1 ----------
ok=1
B="$ROOT/tests/inv/D1_context_budget.sh"
CHK="bash tests/inv/D1_context_budget.sh --grow 400"
BRK="BUDGET_PAD=1024 bash tests/inv/D1_context_budget.sh --grow 400"
row="$(python3 -B "$ROOT/tests/lib/laws.py" "$ROOT/docs/cascade/envelope.md" --in-force 2>/dev/null | grep '^D1|')"
src="$(python3 -B "$ROOT/tests/lib/laws.py" "$ROOT/docs/cascade/envelope.md" --sources 2>/dev/null | grep '^D1|')"
IFS='|' read -r _ _ rchk rbrk _ <<<"$row"
[[ "$rchk" == "$CHK" && "$rbrk" == "$BRK" && "$src" == *"docs/cascade/laws/context.md" ]] \
  || { ok=0; echo "      D1 is not in force in docs/cascade/laws/context.md with check '$CHK' and break '$BRK': ${row:-none} ${src:-}"; }
if [[ ! -f "$B" ]]; then
  ok=0; echo "      tests/inv/D1_context_budget.sh does not exist"
else
  ( cd "$ROOT" && eval "$CHK" ) > "$TMP/b.out" 2>&1; r=$?
  [[ $r -eq 0 && "$(grep -c '^BUDGET .* PASS$' "$TMP/b.out")" == 24 && "$(tail -1 "$TMP/b.out")" == "BUDGET 24/24"* ]] \
    || { ok=0; echo "      the check on this tree: exit $r"; sed 's/^/        /' "$TMP/b.out" | head -30; }
  for c in GENERATE EXECUTE-BUILD EXECUTE-DESIGN EXECUTE-AUDIT EXECUTE-PRR IDLE; do
    for k in plain feature bug-fix refactor; do
      grep -qE "^BUDGET $c/$k +3\.5\.6: [0-9]+ bytes  now: [0-9]+ bytes  grew: [+-][0-9]+  limit: \+400  PASS$" "$TMP/b.out" \
        || { ok=0; echo "      no $c/$k row in the expected form"; }
    done
  done
  n="$(sed -n 's/^BUDGET fixture: the lessons line is \([0-9]*\) bytes on GENERATE\/plain$/\1/p' "$TMP/b.out")"
  [[ -n "$n" && "$n" -ge 300 && "$n" -le 399 ]] || { ok=0; echo "      the fixture's lessons line is '${n:-absent}' bytes, want 300..399 (the budget must measure a full line)"; }
  ( cd "$ROOT" && eval "$BRK" ) > "$TMP/t.out" 2>&1; r=$?
  [[ $r -eq 1 && "$(grep -c '^BUDGET .* FAIL$' "$TMP/t.out")" == 24 && "$(tail -1 "$TMP/t.out")" == "BUDGET 0/24"* ]] \
    || { ok=0; echo "      the red twin (1 KB more on every context): exit $r"; sed 's/^/        /' "$TMP/t.out" | tail -5; }
  BUDGET_PAD=1024 bash "$B" --grow 2000 > "$TMP/t2.out" 2>&1; r=$?
  [[ $r -eq 0 && "$(grep -c 'limit: +2000 ' "$TMP/t2.out")" == 24 ]] || { ok=0; echo "      --grow 2000 did not let the 1 KB twin pass: exit $r"; }
  for args in "--grow x" "--grow" "--root $TMP/no-such-dir" "--bogus"; do
    # shellcheck disable=SC2086  # the words are the arguments
    bash "$B" $args >/dev/null 2>&1; r=$?
    [[ $r -eq 64 ]] || { ok=0; echo "      '$args' exited $r, want 64"; }
  done
  BUDGET_PAD=x bash "$B" >/dev/null 2>&1; r=$?; [[ $r -eq 64 ]] || { ok=0; echo "      BUDGET_PAD=x exited $r, want 64"; }
fi
( cd "$ROOT" && DSHARP_CACHE=off bash tests/dsharp_strength.sh ) > "$TMP/d.out" 2>&1
grep -qE '^GREEN +D1 ' "$TMP/d.out" || { ok=0; echo "      dsharp_strength.sh does not score D1 GREEN: $(grep -E ' D1 ' "$TMP/d.out")"; }
bash "$ROOT/tests/lint.sh" > "$TMP/l.out" 2>&1
grep -q '^SHARDS' "$TMP/l.out" && { ok=0; echo "      lint: $(grep '^SHARDS' "$TMP/l.out")"; }
I="$TMP/inst"; mkdir -p "$I"; git -C "$I" init -q
( HOME="$TMP/nohome" bash "$ROOT/install.sh" --no-plugin "$I" >/dev/null 2>&1 )
[[ -f "$I/docs/cascade/envelope.md" && ! -e "$I/docs/cascade/laws/context.md" && ! -e "$I/tests/inv/D1_context_budget.sh" ]] \
  || { ok=0; echo "      a new install has no envelope, or ships the pack's shard or its test"; }
grep -q 'laws/context.md' "$I/docs/cascade/envelope.md" 2>/dev/null && { ok=0; echo "      a new install's envelope indexes laws/context.md, which it does not ship"; }
( cd "$I" && bash tests/lint.sh ) 2>&1 | grep -q '^SHARDS' && { ok=0; echo "      lint in a new install reports SHARDS"; }
python3 - "$ROOT/.github/workflows/nightly.yml" <<'PY' || ok=0
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r"(?ms)^  regress:\n(.*?)(?=^  [\w-]+:\n|\Z)", s)
if not m or not re.search(r"fetch-depth:\s*0\b", m.group(1)):
    print("      the nightly regress job does not check out full history (fetch-depth: 0); D1 needs the 3.5.6 commit")
    sys.exit(1)
PY
t AC7 "$ok" "law D1 is in force from docs/cascade/laws/context.md with its exact check and break and scores GREEN; the check: 24 rows (6 classes x 4 prompts) in +400 on this tree with a full fixture lessons line; red twin BUDGET_PAD=1024 fails all 24; --grow sets the limit; a bad argument exits 64; lint clean; a new install ships and indexes no shard; the nightly regress job checks out full history"

# ---------- AC8: earlier slices; docs and release ----------
ok=1
for x in t104_pattern_report t106_lessons; do
  bash "$ROOT/tests/ac/$x.sh" > "$TMP/$x.out" 2>&1 || { ok=0; echo "      tests/ac/$x.sh fails:"; grep -E '^FAIL' "$TMP/$x.out" | sed 's/^/        /'; }
done
if ! grep -q '^### B25\.' "$ROOT/USAGE.md" || ! grep -q -- '--recall' "$ROOT/USAGE.md" || ! grep -q 'context_budget.sh' "$ROOT/USAGE.md"; then
  ok=0; echo "      USAGE.md has no B25 naming --recall and context_budget.sh"
fi
python3 - "$ROOT" <<'PY' || ok=0
import json, os, sys
r = sys.argv[1]
v = open(os.path.join(r, "VERSION")).read().strip()
num = lambda s: tuple(int(x) for x in s.split("."))
# t107 shipped in 3.5.8: any later release passes (no exact pin, so a later slice does not have to change this test)
bad = [] if num(v) >= (3, 5, 8) else [f"VERSION is {v}, want 3.5.8 or later"]
for p in (".claude-plugin/plugin.json", ".codex-plugin/plugin.json"):
    if json.load(open(os.path.join(r, p))).get("version") != v:
        bad.append(f"{p} is not {v}")
if v not in json.dumps(json.load(open(os.path.join(r, ".claude-plugin/marketplace.json")))):
    bad.append(f".claude-plugin/marketplace.json does not show {v}")
if "## 3.5.8" not in open(os.path.join(r, "CHANGELOG.md")).read():
    bad.append("CHANGELOG.md has no ## 3.5.8")
if "3.5.8" not in open(os.path.join(r, "README.md")).read():
    bad.append("README.md does not show 3.5.8")
for b in bad:
    print("      " + b)
sys.exit(1 if bad else 0)
PY
t AC8 "$ok" "tests/ac/t104_pattern_report.sh and tests/ac/t106_lessons.sh still pass; USAGE.md B25 names --recall and context_budget.sh; 3.5.8 or later in VERSION and the manifests; CHANGELOG.md and README.md show 3.5.8"

[[ $fail -eq 0 ]] && echo "T107 AC all PASS" || echo "T107 AC FAILED"
exit $fail
