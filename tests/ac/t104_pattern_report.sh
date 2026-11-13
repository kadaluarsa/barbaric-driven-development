#!/usr/bin/env bash
# AC tests for 05b t104-pattern-report: `bash tests/patterns.sh [--root DIR] [--since DATE] [--min N]` groups the
# src=agent and src=human events of .cascade/decisions.log, and the send-back commits, by actor, verdict and
# normalized reason, and prints `seen N times in M hops` with up to three evidence lines. Read-only; no LLM; no gate.
#   AC1  known repeats in a fixture print the expected groups and counts; D# ids stay apart; a send-back commit counts.
#   AC2  src=test lines and lines with no src= field never count; the last line gives their numbers.
#   AC3  PASS/CONTINUE/SIGNED/SIGN? are not events; --min hides small groups; bad arguments exit 64.
#   AC4  each evidence line resolves to the log line or the commit, and to the right hop (author time; only
#        hop-state commits start a hop; `-` before the first); at most three, the newest.
#   AC5  --since keeps events on or after the day; the not-counted numbers describe the whole file.
#   AC6  read-only: worktree, .git (except its index), HOME and TMPDIR unchanged; exit 0, also with no log or empty.
#   AC7  no network or LLM call, and no write call, in the script.
#   AC8  runs on this repository; USAGE.md B23; release 3.5.6 in VERSION, the manifests, CHANGELOG and README.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOG_SRC
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
S="$ROOT/tests/patterns.sh"
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------- fixture: three hops, one send-back commit that is not a hop, a known log ----------
R="$TMP/r"; mkdir -p "$R/docs/cascade" "$R/.cascade"
git -C "$R" init -q
commit() {  # commit <author date> <committer date> <subject> — commit what is in the tree, print the hash
  git -C "$R" add -A
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$2" git -C "$R" commit -qm "$3"
  git -C "$R" rev-parse HEAD
}
hs() { printf 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: %s\n' "$1" > "$R/docs/cascade/hop-state.md"; }
hs a; H1="$(commit 2026-01-01T00:00:00Z 2026-01-01T00:00:00Z "hop a")"
echo x > "$R/README"
SB="$(commit 2026-01-01T06:00:00Z 2026-01-01T06:00:00Z "cascade: send back to GENERATE 05b a — wrong scope")"
# H2's committer time is a month late (a rebase): the hop must follow the author time
hs b; H2="$(commit 2026-01-02T00:00:00Z 2026-02-01T00:00:00Z "hop b")"
hs c; H3="$(commit 2026-01-03T00:00:00Z 2026-01-03T00:00:00Z "hop c")"
LOG="$R/.cascade/decisions.log"
# the t103 line format: ts, actor (11), verdict (7), detail, then `  src=<x>` (absent on old lines)
python3 - "$LOG" <<'PY'
import sys
rows = [
    ("2025-12-31T23:00:00Z", "stop_guard", "DRIFT", "scope: 2 changed path(s) the plan does not list: a, b", "agent"),
    ("2026-01-01T05:00:00Z", "stop_guard", "NOEDGE", "GENERATE 05b ended without its edge line", "agent"),
    ("2026-01-01T07:00:00Z", "human", "SENDBACK", "05b t9 — wrong scope", "human"),
    ("2026-01-01T08:00:00Z", "loop", "PASS", "LOOP 4/4 on EXECUTE 05b", "agent"),
    ("2026-01-01T08:01:00Z", "loop", "PASS", "LOOP 4/4 on EXECUTE 05b", "agent"),
    ("2026-01-01T08:02:00Z", "loop", "PASS", "LOOP 4/4 on EXECUTE 05b", "agent"),
    ("2026-01-02T01:00:00Z", "bash_guard", "DENY", "`git push origin main` — direct push to main.", "agent"),
    ("2026-01-02T02:00:00Z", "bash_guard", "DENY", "`git push origin \"main\"` — direct push to main.", "agent"),
    ("2026-01-02T03:00:00Z", "bash_guard", "DENY", "`git push -f origin main` — direct push to main.", "agent"),
    ("2026-01-02T04:00:00Z", "bash_guard", "DENY", "`rm -rf x` — a test reason", "test"),
    ("2026-01-02T04:00:01Z", "bash_guard", "DENY", "`rm -rf y` — a test reason", "test"),
    ("2026-01-02T04:00:02Z", "bash_guard", "DENY", "`rm -rf z` — a test reason", "test"),
    ("2026-01-02T04:00:03Z", "bash_guard", "DENY", "`rm -rf w` — a test reason", "test"),
    ("2026-01-02T04:00:04Z", "bash_guard", "DENY", "`rm -rf v` — a test reason", "test"),
    ("2026-01-02T04:30:00Z", "stop_guard", "HALT", "AUTOPILOT HALT: an old line", None),
    ("2026-01-02T04:31:00Z", "stop_guard", "HALT", "AUTOPILOT HALT: an old line", None),
    ("2026-01-02T04:32:00Z", "stop_guard", "HALT", "AUTOPILOT HALT: an old line", None),
    ("2026-01-02T05:00:00Z", "stop_guard", "NOEDGE", "GENERATE 05b ended without its edge line", "agent"),
    ("2026-01-02T06:00:00Z", "stop_guard", "CONTINUE", "signed edges remain", "agent"),
    ("2026-01-02T06:01:00Z", "stop_guard", "CONTINUE", "signed edges remain", "agent"),
    ("2026-01-02T06:02:00Z", "stop_guard", "CONTINUE", "signed edges remain", "agent"),
    ("2026-01-02T07:00:00Z", "human", "SENDBACK", "05b t12 — wrong scope", "human"),
    ("2026-01-02T08:00:00Z", "human", "SENDBACK", "05b t13 — wrong scope", "human"),
    ("2026-01-02T08:30:00Z", "sign_ok", "SIGNED", "edge 05b", "human"),
    ("2026-01-02T08:31:00Z", "sign_ok", "SIGNED", "edge 05b", "human"),
    ("2026-01-02T08:32:00Z", "sign_ok", "SIGNED", "edge 05b", "human"),
    ("2026-01-02T08:40:00Z", "hop_guard", "SIGN?", "edge needs a signature", "agent"),
    ("2026-01-02T08:41:00Z", "hop_guard", "SIGN?", "edge needs a signature", "agent"),
    ("2026-01-02T08:42:00Z", "hop_guard", "SIGN?", "edge needs a signature", "agent"),
    ("2026-01-02T09:00:00Z", "stop_guard", "NOEVID", "accept asked for on EXECUTE 05b", "agent"),
    ("2026-01-02T10:00:00Z", "dsharp", "RED", "D3 — break passed, so the test cannot fail", "agent"),
    ("2026-01-02T10:01:00Z", "dsharp", "RED", "D3 — break passed, so the test cannot fail", "agent"),
    ("2026-01-02T10:02:00Z", "dsharp", "RED", "D3 — break passed, so the test cannot fail", "agent"),
    ("2026-01-02T10:10:00Z", "dsharp", "RED", "D49 — break passed, so the test cannot fail", "agent"),
    ("2026-01-02T10:11:00Z", "dsharp", "RED", "D49 — break passed, so the test cannot fail", "agent"),
    ("2026-01-02T10:12:00Z", "dsharp", "RED", "D49 — break passed, so the test cannot fail", "agent"),
    ("2026-01-03T05:00:00Z", "stop_guard", "NOEDGE", "GENERATE 05b ended without its edge line", "agent"),
    ("2026-01-03T06:00:00Z", "stop_guard", "NOEDGE", "GENERATE 05b ended without its edge line", "agent"),
    ("2026-01-03T09:00:00Z", "stop_guard", "NOEVID", "accept asked for on EXECUTE 05b", "agent"),
]
with open(sys.argv[1], "w") as f:
    for ts, a, v, d, s in rows:
        f.write(f"{ts}  {a:<11} {v:<7} {d}" + (f"  src={s}" if s else "") + "\n")
PY
lno() { grep -n "^$1 " "$LOG" | cut -d: -f1; }   # the log line number of the event at that timestamp
LAST="PATTERNS: 5 group(s) at --min 3 from 20 event(s); 5 test line(s) and 3 line(s) with no src= not counted"
run() { bash "$S" --root "$R" "$@" 2>&1; }
block() { awk -v h="$1" 'index($0, h) == 1 {f=1; next} /^PATTERN/ {f=0} f'; }   # the lines under one PATTERN head
heads() { grep '^PATTERN ' || true; }

# ---------- AC1: groups and counts ----------
ok=1
[[ -f "$S" ]] || { ok=0; echo "      tests/patterns.sh does not exist"; }
out="$(run)"; rc=$?
[[ $rc -eq 0 ]] || { ok=0; echo "      exit $rc"; }
want="PATTERN  stop_guard NOEDGE  seen 4 times in 3 hops
PATTERN  bash_guard DENY  seen 3 times in 1 hop
PATTERN  dsharp RED  seen 3 times in 1 hop
PATTERN  dsharp RED  seen 3 times in 1 hop
PATTERN  human SENDBACK  seen 3 times in 2 hops"
[[ "$(printf '%s\n' "$out" | heads)" == "$want" ]] || { ok=0; echo "      groups:"; printf '%s\n' "$out" | heads | sed 's/^/        /'; }
# shellcheck disable=SC2016  # the backticks are literal text in the reason
for r in '  reason: `…` — direct push to main.' '  reason: Nb tN — wrong scope' \
         '  reason: D3 — break passed, so the test cannot fail' '  reason: D49 — break passed, so the test cannot fail'; do
  printf '%s\n' "$out" | grep -qxF "$r" || { ok=0; echo "      no line: $r"; }
done
[[ "$(printf '%s\n' "$out" | tail -1)" == "$LAST" ]] || { ok=0; echo "      last line: $(printf '%s\n' "$out" | tail -1)"; }
o1="$(run --min 1)"
printf '%s\n' "$o1" | grep -qxF 'PATTERN  git SENDBACK  seen 1 time in 1 hop' || { ok=0; echo "      the send-back commit is not a 'git SENDBACK' event"; }
printf '%s\n' "$o1" | grep -qxF '  reason: cascade: send back to GENERATE Nb a — wrong scope' || { ok=0; echo "      the send-back commit's reason"; }
t AC1 "$ok" "a fixture with known repeats prints the expected groups (count order, then actor, verdict, reason) and counts; D3 and D49 stay apart; a send-back commit is an event"

# ---------- AC2: test lines and old lines never count ----------
ok=1
printf '%s\n' "$o1" | grep -q 'a test reason\|HALT' && { ok=0; echo "      a src=test or old-format group printed"; }
cp "$LOG" "$TMP/log.bak"
for i in 1 2 3 4 5; do
  printf '2026-01-03T10:00:0%sZ  stop_guard  NOEDGE  GENERATE 05b ended without its edge line  src=test\n' "$i" >> "$LOG"
  printf '2026-01-03T10:01:0%sZ  stop_guard  NOEDGE  GENERATE 05b ended without its edge line\n' "$i" >> "$LOG"
done
out2="$(run)"
[[ "$(printf '%s\n' "$out2" | heads)" == "$want" ]] || { ok=0; echo "      10 more test/old lines changed a group"; }
[[ "$(printf '%s\n' "$out2" | tail -1)" == "PATTERNS: 5 group(s) at --min 3 from 20 event(s); 10 test line(s) and 8 line(s) with no src= not counted" ]] \
  || { ok=0; echo "      last line after 10 more: $(printf '%s\n' "$out2" | tail -1)"; }
cp "$TMP/log.bak" "$LOG"
t AC2 "$ok" "src=test lines and lines with no src= field never count; the last line counts them"

# ---------- AC3: non-events, --min, bad arguments ----------
ok=1
printf '%s\n' "$o1" | grep -qE '^PATTERN  [a-z_]+ (PASS|CONTINUE|SIGNED|SIGN\?) ' && { ok=0; echo "      a success verdict printed as a pattern"; }
printf '%s\n' "$out" | grep -q 'NOEVID' && { ok=0; echo "      NOEVID (2 events) printed at the default --min 3"; }
printf '%s\n' "$(run --min 2)" | grep -qxF 'PATTERN  stop_guard NOEVID  seen 2 times in 2 hops' || { ok=0; echo "      --min 2 does not print NOEVID"; }
[[ "$(printf '%s\n' "$o1" | tail -1)" == "PATTERNS: 8 group(s) at --min 1 from 20 event(s); 5 test line(s) and 3 line(s) with no src= not counted" ]] \
  || { ok=0; echo "      --min 1 last line: $(printf '%s\n' "$o1" | tail -1)"; }
for bad in "--min 0" "--min x" "--since 2026-13-01" "--since yesterday" "--bogus"; do
  # shellcheck disable=SC2086
  bash "$S" --root "$R" $bad >/dev/null 2>&1; rc=$?
  [[ $rc -eq 64 ]] || { ok=0; echo "      '$bad' exited $rc, want 64"; }
done
t AC3 "$ok" "PASS/CONTINUE/SIGNED/SIGN? are not events; a group below --min does not print; bad arguments exit 64"

# ---------- AC4: evidence resolves, to the right hop ----------
ok=1
hopc="$(git -C "$R" log --format=%H -- docs/cascade/hop-state.md)"
n=0
relog='^  evidence: \.cascade/decisions\.log:([0-9]+) hop ([0-9a-f]{7}|-) (.*)$'
recom='^  evidence: commit ([0-9a-f]{7}) hop ([0-9a-f]{7}|-) (.*)$'
while IFS= read -r ev; do
  n=$((n + 1)); h=""
  if [[ "$ev" =~ $relog ]]; then
    ln="${BASH_REMATCH[1]}"; h="${BASH_REMATCH[2]}"; txt="${BASH_REMATCH[3]}"
    [[ "$(sed -n "${ln}p" "$LOG" | sed -E 's/  src=[a-z]+$//')" == "$txt" ]] || { ok=0; echo "      log line $ln is not: $txt"; }
  elif [[ "$ev" =~ $recom ]]; then
    c="${BASH_REMATCH[1]}"; h="${BASH_REMATCH[2]}"; txt="${BASH_REMATCH[3]}"
    [[ "$(git -C "$R" log -1 --format=%s "$c" 2>/dev/null)" == "$txt" ]] || { ok=0; echo "      commit $c is not: $txt"; }
  else
    ok=0; echo "      bad evidence line: $ev"
  fi
  [[ "$h" == "-" ]] || printf '%s\n' "$hopc" | grep -q "^$h" || { ok=0; echo "      hop $h is not a hop-state commit"; }
done < <(printf '%s\n' "$o1" | grep 'evidence:')
[[ $n -eq 19 ]] || { ok=0; echo "      $n evidence lines at --min 1, want 19 (at most 3 per group)"; }
ev() { printf '%s\n' "$o1" | block "$1" | grep 'evidence:' | sed -E 's/.*(decisions\.log:|commit )([0-9a-f]+) hop ([^ ]+).*/\2 \3/' | sort -n; }
[[ "$(ev 'PATTERN  stop_guard NOEDGE')" == "$(printf '%s %s\n' "$(lno 2026-01-02T05:00:00Z)" "${H2:0:7}" \
     "$(lno 2026-01-03T05:00:00Z)" "${H3:0:7}" "$(lno 2026-01-03T06:00:00Z)" "${H3:0:7}")" ]] \
  || { ok=0; echo "      NOEDGE evidence (the newest three; H2, H3, H3): $(ev 'PATTERN  stop_guard NOEDGE' | tr '\n' ' ')"; }
[[ "$(ev 'PATTERN  human SENDBACK')" == "$(printf '%s %s\n' "$(lno 2026-01-01T07:00:00Z)" "${H1:0:7}" \
     "$(lno 2026-01-02T07:00:00Z)" "${H2:0:7}" "$(lno 2026-01-02T08:00:00Z)" "${H2:0:7}")" ]] \
  || { ok=0; echo "      SENDBACK evidence (H1 after a non-hop commit, then H2 by author time): $(ev 'PATTERN  human SENDBACK' | tr '\n' ' ')"; }
[[ "$(ev 'PATTERN  stop_guard DRIFT')" == "$(lno 2025-12-31T23:00:00Z) -" ]] || { ok=0; echo "      an event before the first hop is not in hop -"; }
[[ "$(ev 'PATTERN  git SENDBACK')" == "${SB:0:7} ${H1:0:7}" ]] || { ok=0; echo "      the send-back commit evidence: $(ev 'PATTERN  git SENDBACK')"; }
t AC4 "$ok" "each evidence line is the log line or commit it names and a hop-state commit by author time (- before the first); three per group, the newest"

# ---------- AC5: --since ----------
ok=1
! run --since 2026-01-03 | grep -q '^PATTERN ' || { ok=0; echo "      --since 2026-01-03 at --min 3 printed a group"; }
o5="$(run --since 2026-01-03 --min 1)"
[[ "$(printf '%s\n' "$o5" | heads)" == "PATTERN  stop_guard NOEDGE  seen 2 times in 1 hop
PATTERN  stop_guard NOEVID  seen 1 time in 1 hop" ]] || { ok=0; echo "      --since 2026-01-03 --min 1:"; printf '%s\n' "$o5" | heads | sed 's/^/        /'; }
[[ "$(printf '%s\n' "$o5" | tail -1)" == "PATTERNS: 2 group(s) at --min 1 from 3 event(s); 5 test line(s) and 3 line(s) with no src= not counted" ]] \
  || { ok=0; echo "      --since last line: $(printf '%s\n' "$o5" | tail -1)"; }
t AC5 "$ok" "--since keeps only events (log lines and commits) on or after that day; the not-counted numbers describe the whole file"

# ---------- AC6: read-only, exit 0 ----------
ok=1
H="$TMP/home"; TD="$TMP/tmpd"; mkdir -p "$H" "$TD"
snap() { python3 -B - "$R" <<'PY'
import hashlib, os, sys
r, rows = sys.argv[1], []
for d, ds, fs in os.walk(r):
    for f in fs + [""]:
        p = os.path.join(d, f)
        if os.path.relpath(p, r) == os.path.join(".git", "index"):
            continue   # git status in this check may refresh the index; the script must not need to
        if not f:   # a directory: present or not (git status in this check touches .git's mtime)
            rows.append(f"{os.path.relpath(p, r)} dir")
            continue
        rows.append(f"{os.path.relpath(p, r)} {os.stat(p).st_mtime_ns} {hashlib.sha1(open(p, 'rb').read()).hexdigest()}")
print("\n".join(sorted(rows)))
PY
  ( cd "$R" && git status --porcelain && git rev-parse HEAD ); }
b="$(snap)"
for a in "" "--min 1" "--since 2026-01-02" "--min 2" "--since 2026-01-01 --min 5"; do
  # shellcheck disable=SC2086
  HOME="$H" TMPDIR="$TD" bash "$S" --root "$R" $a >/dev/null 2>&1 || { ok=0; echo "      '$a' did not exit 0"; }
done
[[ "$(snap)" == "$b" ]] || { ok=0; echo "      the scratch repository changed"; }
[[ -z "$(ls -A "$H")$(ls -A "$TD")" ]] || { ok=0; echo "      the script wrote under HOME or TMPDIR"; }
E="$TMP/e"; mkdir -p "$E"; git -C "$E" init -q
o6="$(bash "$S" --root "$E" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || { ok=0; echo "      no log: exit $rc"; }
[[ "$(printf '%s\n' "$o6" | tail -1)" == "PATTERNS: 0 group(s) at --min 3 from 0 event(s); 0 test line(s) and 0 line(s) with no src= not counted" ]] \
  || { ok=0; echo "      no log: $(printf '%s\n' "$o6" | tail -1)"; }
[[ ! -e "$E/.cascade" ]] || { ok=0; echo "      no log: the script made .cascade/"; }
mkdir -p "$E/.cascade"; : > "$E/.cascade/decisions.log"
bash "$S" --root "$E" >/dev/null 2>&1 || { ok=0; echo "      empty log: exit not 0"; }
t AC6 "$ok" "read-only: worktree, .git, HOME and TMPDIR unchanged after five runs; exit 0 with no log and with an empty log"

# ---------- AC7: no network, no LLM, no writes ----------
ok=1
if [[ -f "$S" ]]; then
  grep -nE 'curl|wget|https?://|anthropic' "$S" && { ok=0; echo "      a network or LLM call"; }
  grep -nE "open\([^)]*['\"][wax]b?\+?['\"]|write_text|write_bytes|makedirs|os\.mkdir|\bmkdir\b|\btee\b|>>? *\"?\\\$[A-Za-z{]" "$S" \
    && { ok=0; echo "      a write call"; }
else ok=0; fi
t AC7 "$ok" "the script holds no network or LLM call and no write call (open w/a/x, write_text, mkdir, tee, redirect to a path)"

# ---------- AC8: this repository, docs, release ----------
ok=1
o8="$(bash "$S" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || { ok=0; echo "      this repository: exit $rc"; }
[[ "$(printf '%s\n' "$o8" | tail -1)" == "PATTERNS: "* ]] || { ok=0; echo "      this repository: last line $(printf '%s\n' "$o8" | tail -1)"; }
if ! grep -q '^### B23\.' "$ROOT/USAGE.md" || ! grep -q 'tests/patterns.sh' "$ROOT/USAGE.md"; then
  ok=0; echo "      USAGE.md has no B23 for tests/patterns.sh"
fi
python3 - "$ROOT" <<'PY' || ok=0
import json, os, sys
r = sys.argv[1]
v = open(os.path.join(r, "VERSION")).read().strip()
bad = [] if v == "3.5.6" else [f"VERSION is {v}, want 3.5.6"]
for p in (".claude-plugin/plugin.json", ".codex-plugin/plugin.json"):
    if json.load(open(os.path.join(r, p))).get("version") != v:
        bad.append(f"{p} is not {v}")
if v not in json.dumps(json.load(open(os.path.join(r, ".claude-plugin/marketplace.json")))):
    bad.append(f".claude-plugin/marketplace.json does not show {v}")
if f"## {v}" not in open(os.path.join(r, "CHANGELOG.md")).read():
    bad.append(f"CHANGELOG.md has no ## {v}")
if v not in open(os.path.join(r, "README.md")).read():
    bad.append(f"README.md does not show {v}")
for b in bad:
    print("      " + b)
sys.exit(1 if bad else 0)
PY
t AC8 "$ok" "runs on this repository; USAGE.md B23 names tests/patterns.sh; 3.5.6 in VERSION, the three manifests, CHANGELOG.md and README.md"

[[ $fail -eq 0 ]] && echo "T104 AC all PASS" || echo "T104 AC FAILED"
exit $fail
