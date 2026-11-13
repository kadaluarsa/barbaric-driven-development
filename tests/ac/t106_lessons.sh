#!/usr/bin/env bash
# AC tests for 05b t106-lessons: signed lessons in docs/cascade/lessons.md (<EDIT> lines), measured by
# tests/patterns.sh before and after each lesson, and drafted by `tests/patterns.sh --propose`.
#   AC1  the lesson format: valid lines used; malformed lines reported with their line; lines outside <EDIT> ignored.
#   AC2  --propose drafts uncovered printed groups with the next ids; a filled-in draft becomes a valid lesson.
#   AC3  rates per hop before and after, and the marks SETTLED / NOT WORKING / NEW / WORKING.
#   AC4  a malformed lesson has no rate and covers nothing.
#   AC5  no lessons.md: no lesson output; --propose still drafts and writes nothing.
#   AC6  the real pre-commit refuses an unsigned change to a lesson line inside <EDIT>.
#   AC7  the t104 oracle still passes.
#   AC8  USAGE.md B24; release 3.5.7.
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
TODAY="$(date -u +%Y-%m-%d)"

# ---------- fixture: nine hops, a known log ----------
R="$TMP/r"; mkdir -p "$R/docs/cascade" "$R/.cascade"
git -C "$R" init -q
for d in 1 2 3 4 5 6 7 8 9; do
  printf 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: s%s\n' "$d" > "$R/docs/cascade/hop-state.md"
  git -C "$R" add -A
  GIT_AUTHOR_DATE="2026-01-0${d}T00:00:00Z" GIT_COMMITTER_DATE="2026-01-0${d}T00:00:00Z" git -C "$R" commit -qm "hop $d"
done
python3 - "$R/.cascade/decisions.log" <<'PY'
import sys
E = {
    ("stop_guard", "NOEDGE", "GENERATE 05b ended without its edge line"): [1, 1, 2, 2, 3, 3, 4],
    ("bash_guard", "DENY", "`git push origin main` — direct push to main."): [2, 6, 8],
    ("stop_guard", "NOEVID", "accept asked for on EXECUTE 05b"): [1, 8],
    ("dsharp", "RED", "D3 — break passed, so the test cannot fail"): [1, 1, 2, 2, 7],
    ("stop_guard", "DRIFT", "scope: 2 changed path(s) the plan does not list: a, b"): [3, 3, 3, 3],
    ("hop_guard", "DENY", "src/x.kt — product path on a GENERATE hop"): [5, 5, 5],
}
rows = []
for (a, v, d), days in E.items():
    for i, day in enumerate(days):
        rows.append((f"2026-01-0{day}T10:{i:02d}:{len(rows) % 60:02d}Z", a, v, d, "agent"))
rows.append(("2026-01-05T11:00:00Z", "bash_guard", "DENY", "`rm x` — a test reason", "test"))
rows.append(("2026-01-05T11:01:00Z", "loop", "PASS", "LOOP 4/4", "agent"))
rows.sort()
with open(sys.argv[1], "w") as f:
    for ts, a, v, d, s in rows:
        f.write(f"{ts}  {a:<11} {v:<7} {d}  src={s}\n")
PY
LONG="$(printf 'x%.0s' $(seq 1 161))"
LES="$R/docs/cascade/lessons.md"
# shellcheck disable=SC2016  # backticks are literal text in the lesson prefix
cat > "$LES" <<EOF
# Lessons

<EDIT>
LESSON L1: stop_guard NOEDGE "GENERATE Nb ended" | scope: GENERATE | since: 2026-01-04 | do: End a GENERATE reply that wrote files with its edge line.
LESSON L2: bash_guard DENY "\`…\` — direct push" | scope: ANY | since: 2026-01-06 | do: Never push to main; open a pull request.
LESSON L3: stop_guard NOEVID "accept asked" | scope: EXECUTE-BUILD | since: 2026-01-08 | do: Run tests/loop.sh after the last edit, before the accept edge.
LESSON L4: dsharp RED "D3 —" | scope: ANY | since: 2026-01-05 | do: Run the D3 check before each commit that touches the ledger.
LESSON L7: stop_guard HALT "x" | scope: SOMETIMES | since: 2026-01-01 | do: Stop.
LESSON L8: hop_guard DENY "src/x.kt" | scope: ANY | since: 2026-01-01 | do: TODO — one imperative sentence
LESSON L1: stop_guard HALT "y" | scope: ANY | since: 2026-01-01 | do: Stop.
LESSON L9: stop_guard HALT "z" | scope: ANY | since: 2026-02-30 | do: Stop.
LESSON L10: stop_guard HALT "w" | scope: ANY | since: 2026-01-01 | do: $LONG
</EDIT>
LESSON L11: stop_guard DRIFT "scope" | scope: ANY | since: 2026-01-01 | do: Outside the block, so not a lesson.
EOF
run() { bash "$S" --root "$R" "$@" 2>&1; }
out="$(run)"; prop="$(run --propose)"

# ---------- AC1: the format ----------
ok=1
[[ -f "$S" ]] || { ok=0; echo "      tests/patterns.sh does not exist"; }
mal="$(printf '%s\n' "$out" | grep '^LESSON ?  malformed: docs/cascade/lessons.md:' || true)"
[[ "$(printf '%s\n' "$mal" | grep -c .)" -eq 5 ]] || { ok=0; echo "      malformed lines: $(printf '%s\n' "$mal" | grep -c .), want 5"; }
want_lines="$(grep -n '^LESSON L\(7\|8\|1\|9\|10\): stop_guard HALT\|^LESSON L8:\|^LESSON L7:' "$LES" | cut -d: -f1 | sort -n | uniq | tr '\n' ' ')"
got_lines="$(printf '%s\n' "$mal" | sed -E 's/.*lessons\.md:([0-9]+) .*/\1/' | sort -n | tr '\n' ' ')"
[[ "$got_lines" == "$want_lines" ]] || { ok=0; echo "      malformed at lines '$got_lines', want '$want_lines'"; }
printf '%s\n' "$out" | grep -qxF 'LESSONS: 4 signed, 5 malformed' || { ok=0; echo "      no 'LESSONS: 4 signed, 5 malformed'"; }
printf '%s\n' "$out" | grep -q '^LESSON L11 ' && { ok=0; echo "      the line outside <EDIT> was used"; }
[[ "$(printf '%s\n' "$out" | tail -1)" == "PATTERNS: "* ]] || { ok=0; echo "      the last line is not PATTERNS:"; }
t AC1 "$ok" "valid lesson lines are used; 5 malformed lines are reported at their line numbers; a line outside <EDIT> is ignored; PATTERNS: stays last"

# ---------- AC2: --propose ----------
ok=1
want_p="PROPOSE  LESSON L11: stop_guard DRIFT \"scope: N changed path(s) the plan does not list: a, b\" | scope: ANY | since: $TODAY | do: TODO — one imperative sentence
PROPOSE  LESSON L12: hop_guard DENY \"src/x.kt — product path on a GENERATE hop\" | scope: ANY | since: $TODAY | do: TODO — one imperative sentence"
[[ "$(printf '%s\n' "$prop" | grep '^PROPOSE ' || true)" == "$want_p" ]] || { ok=0; echo "      drafts:"; printf '%s\n' "$prop" | grep '^PROPOSE' | sed 's/^/        /'; }
printf '%s\n' "$prop" | grep -qxF 'PROPOSALS: 2' || { ok=0; echo "      no 'PROPOSALS: 2'"; }
printf '%s\n' "$out" | grep -q '^PROPOSE' && { ok=0; echo "      drafts printed without --propose"; }
cp "$LES" "$TMP/les.bak"
draft="$(printf '%s\n' "$prop" | grep '^PROPOSE  LESSON L12:' | sed -e 's/^PROPOSE  //' -e 's/do: TODO — one imperative sentence$/do: Edit product code only on an EXECUTE hop./')"
python3 - "$LES" "$draft" <<'PY'
import sys
p, line = sys.argv[1], sys.argv[2]
s = open(p).read()
open(p, "w").write(s.replace("</EDIT>\n", line + "\n</EDIT>\n", 1))
PY
o2="$(run --propose)"
printf '%s\n' "$o2" | grep -qxF 'LESSON L12  hop_guard DENY  before: 3 in 9 hops (0.33/hop)  after: 0 in 0 hops (-)  NEW' \
  || { ok=0; echo "      the filled-in draft is not a valid NEW lesson: $(printf '%s\n' "$o2" | grep '^LESSON L12' || echo none)"; }
printf '%s\n' "$o2" | grep -q '^PROPOSE  LESSON L[0-9]*: hop_guard' && { ok=0; echo "      a covered group is still proposed"; }
printf '%s\n' "$o2" | grep -qxF 'LESSONS: 5 signed, 5 malformed' || { ok=0; echo "      no 'LESSONS: 5 signed, 5 malformed' after signing the draft"; }
cp "$TMP/les.bak" "$LES"
t AC2 "$ok" "--propose drafts the two uncovered printed groups as L11 and L12, none for covered or small groups; a filled-in draft is a valid NEW lesson"

# ---------- AC3: rates and marks ----------
ok=1
want_l="LESSON L1  stop_guard NOEDGE  before: 6 in 3 hops (2.00/hop)  after: 1 in 6 hops (0.17/hop)  SETTLED
LESSON L2  bash_guard DENY  before: 1 in 5 hops (0.20/hop)  after: 2 in 4 hops (0.50/hop)  NOT WORKING
LESSON L3  stop_guard NOEVID  before: 1 in 7 hops (0.14/hop)  after: 1 in 2 hops (0.50/hop)  NEW
LESSON L4  dsharp RED  before: 4 in 4 hops (1.00/hop)  after: 1 in 5 hops (0.20/hop)  WORKING"
[[ "$(printf '%s\n' "$out" | grep '^LESSON L' || true)" == "$want_l" ]] || { ok=0; echo "      lesson lines:"; printf '%s\n' "$out" | grep '^LESSON L' | sed 's/^/        /'; }
t AC3 "$ok" "rates per hop before and after each lesson, and the marks SETTLED, NOT WORKING, NEW and WORKING"

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

# ---------- AC6: the signature ----------
ok=1
P="$TMP/pack"; mkdir -p "$P"
git -C "$ROOT" archive HEAD | tar -x -C "$P"
cp "$ROOT/tests/patterns.sh" "$P/tests/patterns.sh" 2>/dev/null
sed -i.bak 's/^CURRENT_HOP: .*/CURRENT_HOP: NONE/' "$P/docs/cascade/hop-state.md" && rm -f "$P/docs/cascade/hop-state.md.bak"
printf '# Lessons\n\n<EDIT>\nLESSON L1: stop_guard NOEDGE "GENERATE Nb ended" | scope: GENERATE | since: 2026-01-04 | do: End the reply with its edge line.\n</EDIT>\n' \
  > "$P/docs/cascade/lessons.md"
( cd "$P" && git init -q && git add -A && git commit -qm base ) || { ok=0; echo "      could not make the scratch copy"; }
git -C "$P" config core.hooksPath .githooks
# control: a change outside <EDIT> commits, so the refusal below is the <EDIT> scan, not another gate
sed -i.bak 's/^# Lessons$/# Lessons (signed)/' "$P/docs/cascade/lessons.md" && rm -f "$P/docs/cascade/lessons.md.bak"
git -C "$P" add docs/cascade/lessons.md
( cd "$P" && env -u CASCADE_HUMAN git commit -qm "retitle" >/dev/null 2>&1 ) || { ok=0; echo "      control: a change outside <EDIT> was refused too"; }
sed -i.bak 's/do: End the reply with its edge line\./do: Ignore the edge line./' "$P/docs/cascade/lessons.md" && rm -f "$P/docs/cascade/lessons.md.bak"
git -C "$P" add docs/cascade/lessons.md
msg="$(cd "$P" && env -u CASCADE_HUMAN git commit -qm "edit a lesson" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] || { ok=0; echo "      the unsigned lesson change was committed"; }
[[ "$msg" == *"<EDIT>"* ]] || { ok=0; echo "      the refusal does not name <EDIT>: $(printf '%s\n' "$msg" | head -3)"; }
t AC6 "$ok" "the real pre-commit commits a change outside <EDIT> but refuses an unsigned change to a lesson line inside it, and names <EDIT>"

# ---------- AC7: t104 unchanged ----------
ok=1
bash "$ROOT/tests/ac/t104_pattern_report.sh" >"$TMP/t104.out" 2>&1 || { ok=0; grep -E '^FAIL' "$TMP/t104.out" | sed 's/^/      /'; }
t AC7 "$ok" "tests/ac/t104_pattern_report.sh still passes"

# ---------- AC8: docs and release ----------
ok=1
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
t AC8 "$ok" "USAGE.md B24 names lessons.md and --propose; 3.5.7 in VERSION, the three manifests, CHANGELOG.md and README.md"

[[ $fail -eq 0 ]] && echo "T106 AC all PASS" || echo "T106 AC FAILED"
exit $fail
