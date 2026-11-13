#!/usr/bin/env bash
# AC tests for 05b t106-lessons: human-signed lessons in docs/cascade/lessons.md, measured by tests/patterns.sh per
# real hop (in the lesson's scope) before and after each lesson, and drafted by `tests/patterns.sh --propose`.
#   AC1  the lesson format: valid lines used (a 160-character sentence, scope EXECUTE-AUDIT); each malformed line
#        reported at its line number with the field at fault; an indented line ignored.
#   AC2  --propose drafts uncovered printed groups with the next ids; a `"` in a reason becomes `'`; a filled-in draft
#        becomes a valid lesson.
#   AC3  rates per hop before and after; hops are real edges (a hop-state commit that keeps the triple is not one, a
#        NONE close ends the hop, an event with no hop running does not count); scope filters the hops; the marks
#        NO MATCH / SETTLED / NOT WORKING / WORKING / NEW, and NEW when there is no before hop.
#   AC4  a malformed lesson has no rate and covers nothing.
#   AC5  no lessons.md: no lesson output; --propose still drafts and writes nothing.
#   AC6  the signature, pre-commit: adding, changing or removing a LESSON line needs it (a new file too); other lines
#        do not; the human key commits.
#   AC7  the signature, agent hook: hop_guard asks the human (or denies with no human) for a write that adds or changes
#        a LESSON line, and lets a write with no LESSON change through.
#   AC8  tests/ac/t104_pattern_report.sh still passes; USAGE.md B24; release 3.5.7.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOG_SRC BDD_HOOK_HOST PLUGIN_ROOT CLAUDE_PLUGIN_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
S="$ROOT/tests/patterns.sh"
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TODAY="$(date -u +%Y-%m-%d)"

# ---------- fixture: nine GENERATE hops, one hop-state commit that is not an edge, a NONE close ----------
R="$TMP/r"; mkdir -p "$R/docs/cascade" "$R/.cascade"
git -C "$R" init -q
hs() {  # hs <date> <hop> <slice> [note] — commit a hop-state version at that author time
  printf 'CURRENT_HOP: %s\nCURRENT_STAGE: 05b\nCURRENT_SLICE: %s\n%s\n' "$2" "$3" "${4:-}" > "$R/docs/cascade/hop-state.md"
  git -C "$R" add -A
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "$R" commit -qm "hop-state $2 $3 ${4:-}"
}
for d in 1 2 3 4; do hs "2026-01-0${d}T00:00:00Z" GENERATE "s$d"; done
hs 2026-01-04T12:00:00Z GENERATE s4 "a note: same hop, not an edge"
for d in 5 6 7 8 9; do hs "2026-01-0${d}T00:00:00Z" GENERATE "s$d"; done
hs 2026-01-10T00:00:00Z NONE s9
python3 - "$R/.cascade/decisions.log" <<'PY'
import sys
E = {
    ("stop_guard", "NOEDGE", "GENERATE 05b ended without its edge line"): ["01", "01", "02", "02", "03", "03", "04", "10"],
    ("bash_guard", "DENY", "`git push origin main` — direct push to main."): ["02", "06", "08"],
    ("stop_guard", "NOEVID", "accept asked for on EXECUTE 05b"): ["01", "08"],
    ("dsharp", "RED", "D3 — break passed, so the test cannot fail"): ["01", "01", "02", "02", "07"],
    ("stop_guard", "DRIFT", "scope: 2 changed path(s) the plan does not list: a, b"): ["03", "03", "03", "03"],
    ("hop_guard", "DENY", "\"src/x.kt\" — product path on a GENERATE hop"): ["05", "05", "05"],
}
rows = []
for (a, v, d), days in E.items():
    for i, day in enumerate(days):
        hh = "13" if (day == "04" and a == "stop_guard" and v == "NOEDGE") else "10"   # 01-04 13:00: after the note
        rows.append((f"2026-01-{day}T{hh}:{i:02d}:{len(rows) % 60:02d}Z", a, v, d, "agent"))
rows.append(("2026-01-05T11:00:00Z", "bash_guard", "DENY", "`rm x` — a test reason", "test"))
rows.append(("2026-01-05T11:01:00Z", "loop", "PASS", "LOOP 4/4", "agent"))
rows.sort()
with open(sys.argv[1], "w") as f:
    for ts, a, v, d, s in rows:
        f.write(f"{ts}  {a:<11} {v:<7} {d}  src={s}\n")
PY
D160="$(printf 'y%.0s' $(seq 1 160))"; D161="${D160}y"
LES="$R/docs/cascade/lessons.md"
# shellcheck disable=SC2016  # backticks are literal text in the lesson prefix
cat > "$LES" <<EOF
# Lessons

LESSON L1: stop_guard NOEDGE "GENERATE Nb ended" | scope: GENERATE | since: 2026-01-04 | do: End a GENERATE reply that wrote files with its edge line.
LESSON L2: bash_guard DENY "\`…\` — direct push" | scope: ANY | since: 2026-01-06 | do: Never push to main; open a pull request.
LESSON L3: stop_guard NOEVID "accept asked" | scope: ANY | since: 2026-01-08 | do: Run tests/loop.sh after the last edit, before the accept edge.
LESSON L4: dsharp RED "D3 —" | scope: ANY | since: 2026-01-05 | do: Run the D3 check before each commit that touches the ledger.
LESSON L5: stop_guard NOEDGE "GENERATE Nb ended" | scope: EXECUTE-AUDIT | since: 2026-01-04 | do: $D160
LESSON L6: dsharp RED "D3 —" | scope: ANY | since: 2025-12-01 | do: Read the D3 law shard first.
LESSON L7: loop FAIL "x" | scope: SOMETIMES | since: 2026-01-01 | do: Stop.
LESSON L8: hop_guard DENY "'src/x.kt'" | scope: ANY | since: 2026-01-01 | do: TODO — one imperative sentence
LESSON L1: stop_guard HALT "y" | scope: ANY | since: 2026-01-01 | do: Stop.
LESSON L9: sign_ok DENY "z" | scope: ANY | since: 2026-02-30 | do: Stop.
LESSON L10: bash_guard WARN "w" | scope: ANY | since: 2026-01-01 | do: $D161
  LESSON L11: stop_guard DRIFT "scope" | scope: ANY | since: 2026-01-01 | do: Indented, so not a lesson line.
EOF
run() { bash "$S" --root "$R" "$@" 2>&1; }
out="$(run)"; prop="$(run --propose)"
ln_of() { grep -n "^$1" "$LES" | head -1 | cut -d: -f1; }   # the line number of the first line that starts so

# ---------- AC1: the format ----------
ok=1
[[ -f "$S" ]] || { ok=0; echo "      tests/patterns.sh does not exist"; }
mal="$(printf '%s\n' "$out" | grep '^LESSON ?  malformed: docs/cascade/lessons.md:' || true)"
[[ "$(printf '%s\n' "$mal" | grep -c .)" -eq 5 ]] || { ok=0; echo "      malformed lines: $(printf '%s\n' "$mal" | grep -c .), want 5"; }
why() { printf '%s\n' "$mal" | grep "lessons.md:$1 " || true; }   # the malformed report for that line
[[ "$(why "$(ln_of 'LESSON L7:')")" == *scope* ]] || { ok=0; echo "      L7 (bad scope) is not reported as a scope fault"; }
[[ "$(why "$(ln_of 'LESSON L8:')")" == *TODO* ]] || { ok=0; echo "      L8 (do: TODO) is not reported as a TODO fault"; }
[[ "$(why "$(ln_of 'LESSON L1: stop_guard HALT')")" == *L1* ]] || { ok=0; echo "      the repeated L1 is not reported by its id"; }
[[ "$(why "$(ln_of 'LESSON L9:')")" == *since* ]] || { ok=0; echo "      L9 (no such day) is not reported as a since fault"; }
[[ "$(why "$(ln_of 'LESSON L10:')")" == *160* ]] || { ok=0; echo "      L10 (161 characters) is not reported as a 160 fault"; }
printf '%s\n' "$out" | grep -qxF 'LESSONS: 6 signed, 5 malformed' || { ok=0; echo "      no 'LESSONS: 6 signed, 5 malformed'"; }
printf '%s\n' "$out" | grep -q '^LESSON L11 ' && { ok=0; echo "      the indented line was used"; }
[[ "$(printf '%s\n' "$out" | tail -1)" == "PATTERNS: "* ]] || { ok=0; echo "      the last line is not PATTERNS:"; }
t AC1 "$ok" "valid lessons are used (160 characters, scope EXECUTE-AUDIT); each malformed line is reported at its line with the field at fault; an indented line is ignored"

# ---------- AC2: --propose ----------
ok=1
want_p="PROPOSE  LESSON L11: stop_guard DRIFT \"scope: N changed path(s) the plan does not list: a, b\" | scope: ANY | since: $TODAY | do: TODO — one imperative sentence
PROPOSE  LESSON L12: hop_guard DENY \"'src/x.kt' — product path on a GENERATE hop\" | scope: ANY | since: $TODAY | do: TODO — one imperative sentence"
[[ "$(printf '%s\n' "$prop" | grep '^PROPOSE ' || true)" == "$want_p" ]] || { ok=0; echo "      drafts:"; printf '%s\n' "$prop" | grep '^PROPOSE' | sed 's/^/        /'; }
printf '%s\n' "$prop" | grep -qxF 'PROPOSALS: 2' || { ok=0; echo "      no 'PROPOSALS: 2'"; }
printf '%s\n' "$out" | grep -q '^PROPOSE' && { ok=0; echo "      drafts printed without --propose"; }
cp "$LES" "$TMP/les.bak"
printf '%s\n' "$prop" | grep '^PROPOSE  LESSON L12:' \
  | sed -e 's/^PROPOSE  //' -e 's/do: TODO — one imperative sentence$/do: Edit product code only on an EXECUTE hop./' >> "$LES"
o2="$(run --propose)"
printf '%s\n' "$o2" | grep -qxF 'LESSON L12  hop_guard DENY  before: 3 in 9 hops (0.33/hop)  after: 0 in 0 hops (-)  NEW' \
  || { ok=0; echo "      the filled-in draft is not a valid NEW lesson: $(printf '%s\n' "$o2" | grep '^LESSON L12' || echo none)"; }
printf '%s\n' "$o2" | grep -q '^PROPOSE  LESSON L[0-9]*: hop_guard' && { ok=0; echo "      a covered group is still proposed"; }
printf '%s\n' "$o2" | grep -qxF 'LESSONS: 7 signed, 5 malformed' || { ok=0; echo "      no 'LESSONS: 7 signed, 5 malformed' after adding the draft"; }
cp "$TMP/les.bak" "$LES"
t AC2 "$ok" "--propose drafts the two uncovered printed groups as L11 and L12 (a \" in the reason becomes '), none for covered or small groups; a filled-in draft is a valid NEW lesson"

# ---------- AC3: rates, hops, scope, marks ----------
ok=1
want_l="LESSON L1  stop_guard NOEDGE  before: 6 in 3 hops (2.00/hop)  after: 1 in 6 hops (0.17/hop)  SETTLED
LESSON L2  bash_guard DENY  before: 1 in 5 hops (0.20/hop)  after: 2 in 4 hops (0.50/hop)  NOT WORKING
LESSON L3  stop_guard NOEVID  before: 1 in 7 hops (0.14/hop)  after: 1 in 2 hops (0.50/hop)  NEW
LESSON L4  dsharp RED  before: 4 in 4 hops (1.00/hop)  after: 1 in 5 hops (0.20/hop)  WORKING
LESSON L5  stop_guard NOEDGE  before: 0 in 0 hops (-)  after: 0 in 0 hops (-)  NO MATCH
LESSON L6  dsharp RED  before: 0 in 0 hops (-)  after: 5 in 9 hops (0.56/hop)  NEW"
[[ "$(printf '%s\n' "$out" | grep '^LESSON L' || true)" == "$want_l" ]] || { ok=0; echo "      lesson lines:"; printf '%s\n' "$out" | grep '^LESSON L' | sed 's/^/        /'; }
printf '%s\n' "$out" | grep -qxF 'PATTERN  stop_guard NOEDGE  seen 8 times in 5 hops' \
  || { ok=0; echo "      the NOEDGE group head (4 real hops and -): $(printf '%s\n' "$out" | grep 'PATTERN  stop_guard NOEDGE' || echo none)"; }
t AC3 "$ok" "rates per real hop in the lesson's scope; a same-triple commit is no hop, NONE ends one, no-hop events do not count; marks NO MATCH, SETTLED, NOT WORKING, WORKING, NEW (and NEW with no before hop)"

# ---------- AC4: a malformed lesson is not used ----------
ok=1
printf '%s\n' "$out" | grep -qE '^LESSON L(7|8|9|10)  ' && { ok=0; echo "      a malformed lesson has a rate line"; }
printf '%s\n' "$prop" | grep -q '^PROPOSE  LESSON L12: hop_guard DENY' || { ok=0; echo "      the group the malformed L8 names is not proposed"; }
t AC4 "$ok" "a malformed lesson gets no rate line and covers no group"

# ---------- AC5: no lessons.md; --propose writes nothing ----------
ok=1
mv "$LES" "$TMP/les.off"
o5="$(run)"; o5p="$(run --propose)"
printf '%s\n' "$o5" | grep -qE '^(LESSON|LESSONS:|PROPOSE)' && { ok=0; echo "      lesson output with no lessons.md"; }
[[ "$(printf '%s\n' "$o5p" | grep -c '^PROPOSE  LESSON L')" -eq 5 ]] || { ok=0; echo "      --propose with no lessons.md: want 5 drafts (L1–L5)"; }
printf '%s\n' "$o5p" | grep -q '^PROPOSE  LESSON L1: stop_guard NOEDGE' || { ok=0; echo "      --propose with no lessons.md does not start at L1"; }
printf '%s\n' "$o5p" | grep -qxF 'PROPOSALS: 5' || { ok=0; echo "      no 'PROPOSALS: 5'"; }
mv "$TMP/les.off" "$LES"
H="$TMP/home"; TD="$TMP/tmpd"; mkdir -p "$H" "$TD"
snap() { python3 -B - "$R" <<'PY'
import hashlib, os, sys
r, rows = sys.argv[1], []
for d, ds, fs in os.walk(r):
    for f in fs:
        p = os.path.join(d, f)
        if os.path.relpath(p, r) == os.path.join(".git", "index"):
            continue
        rows.append(f"{os.path.relpath(p, r)} {os.stat(p).st_mtime_ns} {hashlib.sha1(open(p, 'rb').read()).hexdigest()}")
print("\n".join(sorted(rows)))
PY
  ( cd "$R" && git status --porcelain && git rev-parse HEAD ); }
b="$(snap)"
HOME="$H" TMPDIR="$TD" bash "$S" --root "$R" --propose >/dev/null 2>&1 || { ok=0; echo "      --propose did not exit 0"; }
HOME="$H" TMPDIR="$TD" bash "$S" --root "$R" --propose --min 1 >/dev/null 2>&1 || { ok=0; echo "      --propose --min 1 did not exit 0"; }
[[ "$(snap)" == "$b" ]] || { ok=0; echo "      --propose changed the repository"; }
[[ -z "$(ls -A "$H")$(ls -A "$TD")" ]] || { ok=0; echo "      --propose wrote under HOME or TMPDIR"; }
t AC5 "$ok" "with no lessons.md there is no lesson output and --propose drafts from L1; --propose writes nothing"

# ---------- a scratch copy of this repository, hop NONE, no lessons.md, hooks on ----------
P="$TMP/pack"; mkdir -p "$P"
git -C "$ROOT" archive HEAD | tar -x -C "$P"
rm -f "$P/docs/cascade/lessons.md"
sed -i.bak 's/^CURRENT_HOP: .*/CURRENT_HOP: NONE/' "$P/docs/cascade/hop-state.md" && rm -f "$P/docs/cascade/hop-state.md.bak"
( cd "$P" && git init -q && git add -A && git commit -qm base ) || echo "      could not make the scratch copy"
git -C "$P" config core.hooksPath .githooks
PL="$P/docs/cascade/lessons.md"
L1='LESSON L1: stop_guard NOEDGE "GENERATE Nb ended" | scope: GENERATE | since: 2026-01-04 | do: End the reply with its edge line.'
# shellcheck disable=SC2016  # backticks are literal text
L2='LESSON L2: bash_guard DENY "`…` — direct push" | scope: ANY | since: 2026-01-06 | do: Never push to main.'
pc() {  # pc <message> — stage lessons.md and commit with the real pre-commit; prints the exit code, hook text to $TMP/pc.out
  ( cd "$P" && git add -A docs/cascade && env -u CASCADE_HUMAN git commit -qm "$1" >"$TMP/pc.out" 2>&1 ); echo $?
}

# ---------- AC6: the signature, pre-commit ----------
ok=1
printf '# Lessons\n' > "$PL"
[[ "$(pc 'a lessons file with no lesson')" -eq 0 ]] || { ok=0; echo "      a lessons.md with no LESSON line was refused"; }
printf '# Lessons\n\n%s\n' "$L1" > "$PL"
[[ "$(pc 'add L1 unsigned')" -ne 0 ]] || { ok=0; echo "      an unsigned new LESSON line was committed"; }
grep -q 'lessons.md' "$TMP/pc.out" || { ok=0; echo "      the refusal does not name lessons.md: $(head -2 "$TMP/pc.out")"; }
( cd "$P" && git add -A docs/cascade && CASCADE_HUMAN=1 git commit -qm "add L1, human key" >/dev/null 2>&1 ) || { ok=0; echo "      the human key did not commit L1"; }
printf '# Lessons (signed)\n\n%s\n' "$L1" > "$PL"
[[ "$(pc 'retitle')" -eq 0 ]] || { ok=0; echo "      a change outside the LESSON lines was refused"; }
printf '# Lessons (signed)\n\n%s\n' "${L1/End the reply with its edge line./Ignore the edge line.}" > "$PL"
[[ "$(pc 'change L1 unsigned')" -ne 0 ]] || { ok=0; echo "      an unsigned change to L1 was committed"; }
( cd "$P" && git reset -q && git checkout -q -- docs/cascade/lessons.md )
printf '# Lessons (signed)\n\n%s\n%s\n' "$L1" "$L2" > "$PL"
[[ "$(pc 'append L2 unsigned')" -ne 0 ]] || { ok=0; echo "      an unsigned added LESSON line was committed"; }
( cd "$P" && git reset -q && git checkout -q -- docs/cascade/lessons.md )
rm -f "$PL"
[[ "$(pc 'remove the lessons unsigned')" -ne 0 ]] || { ok=0; echo "      an unsigned removal of lessons.md was committed"; }
( cd "$P" && git reset -q && git checkout -q -- docs/cascade/lessons.md )
t AC6 "$ok" "pre-commit: adding (a new file too), changing or removing a LESSON line needs the human's signature; other lines do not; the human key commits"

# ---------- AC7: the signature, agent hook ----------
ok=1
hg() {  # hg <tool> <permission mode> <json tool_input> — run the real hop_guard in the scratch copy, print its stdout
  local id; id="t106-$RANDOM-$RANDOM"
  printf '{"tool_name":"%s","tool_use_id":"%s","cwd":"%s","permission_mode":"%s","tool_input":%s}' "$1" "$id" "$P" "$2" "$3" \
    | ( cd "$P" && python3 -B .claude/hooks/hop_guard.py 2>/dev/null )
}
js() { python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"; }
cur="$(cat "$PL")"
o="$(hg Write default "{\"file_path\":$(js "$PL"),\"content\":$(js "$cur"$'\n'"$L2")}")"
[[ "$o" == *'"ask"'* ]] || { ok=0; echo "      a Write that adds a LESSON line is not sent to the human: ${o:-allowed}"; }
o="$(hg Edit default "{\"file_path\":$(js "$PL"),\"old_string\":\"End the reply\",\"new_string\":\"Skip the reply\"}")"
[[ "$o" == *'"ask"'* ]] || { ok=0; echo "      an Edit that changes a LESSON line is not sent to the human: ${o:-allowed}"; }
o2="$(hg Write bypassPermissions "{\"file_path\":$(js "$PL"),\"content\":$(js "$cur"$'\n'"$L2")}")"
[[ "$o2" == *'"deny"'* ]] || { ok=0; echo "      with no human present, a LESSON write is not denied: ${o2:-allowed}"; }
o="$(hg Edit default "{\"file_path\":$(js "$PL"),\"old_string\":\"# Lessons (signed)\",\"new_string\":\"# Lessons, signed\"}")"
[[ -z "$o" ]] || { ok=0; echo "      an Edit with no LESSON change was stopped: $o"; }
t AC7 "$ok" "hop_guard asks the human for a Write or Edit that adds or changes a LESSON line, denies it with no human present, and lets other edits through"

# ---------- AC8: t104 unchanged; docs and release ----------
ok=1
bash "$ROOT/tests/ac/t104_pattern_report.sh" >"$TMP/t104.out" 2>&1 || { ok=0; grep -E '^FAIL' "$TMP/t104.out" | sed 's/^/      /'; }
if ! grep -q '^### B24\.' "$ROOT/USAGE.md" || ! grep -q 'lessons.md' "$ROOT/USAGE.md" || ! grep -q -- '--propose' "$ROOT/USAGE.md"; then
  ok=0; echo "      USAGE.md has no B24 naming lessons.md and --propose"
fi
python3 - "$ROOT" <<'PY' || ok=0
import json, os, sys
r = sys.argv[1]
v = open(os.path.join(r, "VERSION")).read().strip()
bad = [] if v == "3.5.7" else [f"VERSION is {v}, want 3.5.7"]
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
t AC8 "$ok" "tests/ac/t104_pattern_report.sh still passes; USAGE.md B24 names lessons.md and --propose; 3.5.7 in VERSION, the manifests, CHANGELOG.md and README.md"

[[ $fail -eq 0 ]] && echo "T106 AC all PASS" || echo "T106 AC FAILED"
exit $fail
