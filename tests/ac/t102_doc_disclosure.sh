#!/usr/bin/env bash
# AC tests for 05b t102-doc-disclosure: a doc-parts manifest names, per hop class, the line ranges of the pipeline doc
# and CONTROL-LINE.md that a hop reads; the prompt hook prints them; closed briefs move to an archive that readers
# still search. No line of the two docs moves.
#   AC1  the manifest resolves on the real tree; every range lies inside its file; I1–I18 sit in the INVARIANTS range.
#   AC2  reads drop by at least half for all six hop classes — recomputed here from the printed ranges.
#   AC3  a renamed heading or a deleted manifest block fails --check (red twins).
#   AC4  no removed line in the two docs since 5b26e2c; AGENTS.md loses at most 2 lines.
#   AC5  seam.py prints DOC PARTS THIS HOP on GENERATE 05b, not on NONE; without doc_parts.py the rest is identical.
#   AC6  briefs.sh archive moves exactly the closed briefs, byte-identical, idempotent, refuses dirty and duplicates.
#   AC7  recall, diverge and briefs.sh find read the archive.
#   AC8  preserve.py output on GENERATE (compact) and NONE (startup) is byte-identical to 5b26e2c's.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED BDD_RECALL_TIMEOUT BDD_PLUGIN_ROOT \
      PLUGIN_ROOT BDD_HOOK_HOST CLAUDE_PLUGIN_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 BDD_AUTO_REFRESH=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell
BASE=5b26e2c   # the commit that opened GENERATE 05b t102 — the docs as they were before this slice
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GRE=docs/cascade/product-e2e-gre-pipeline.md
uid() { python3 -c 'import uuid; print(uuid.uuid4().hex)'; }

# The six hop classes as (hop, stage) pairs.
CLASSES=("GENERATE 05b" "GENERATE 03" "EXECUTE 05b" "EXECUTE 03" "EXECUTE 10" "EXECUTE 11")

# ---------- AC1: the manifest resolves on the real tree ----------
ok=1
if [[ ! -f "$ROOT/tests/doc_parts.sh" ]]; then
  ok=0; echo "  tests/doc_parts.sh does not exist"
else
  out="$(bash "$ROOT/tests/doc_parts.sh" --check 2>&1)"; rc=$?
  [[ $rc -eq 0 ]] || { ok=0; echo "  --check exit $rc: $out"; }
  for c in "${CLASSES[@]}"; do
    set -- $c
    bash "$ROOT/tests/doc_parts.sh" --hop "$1" --stage "$2" > "$TMP/parts.$1.$2" 2>&1 || { ok=0; echo "  --hop $1 --stage $2 failed"; }
    python3 - "$ROOT" "$TMP/parts.$1.$2" "$c" <<'PY' || ok=0
import os, re, sys
root, f, cls = sys.argv[1:4]
rows = [l for l in open(f, encoding="utf-8").read().splitlines() if l.strip()]
if not rows:
    print(f"  {cls}: no parts printed"); sys.exit(1)
bad = 0
for l in rows:
    m = re.match(r"^(\S+):(\d+)-(\d+)\s+(\d+)\s+(.+)$", l)
    if not m:
        print(f"  {cls}: malformed line: {l}"); bad = 1; continue
    p, a, b = m.group(1), int(m.group(2)), int(m.group(3))
    n = len(open(os.path.join(root, p), encoding="utf-8").read().splitlines())
    if not (1 <= a <= b <= n):
        print(f"  {cls}: range {p}:{a}-{b} outside 1..{n}"); bad = 1
sys.exit(bad)
PY
  done
  # I1..I18 inside the INVARIANTS range
  python3 - "$ROOT" "$TMP/parts.GENERATE.05b" <<'PY' || ok=0
import os, re, sys
root, f = sys.argv[1:3]
rng = None
for l in open(f, encoding="utf-8"):
    m = re.match(r"^(\S+):(\d+)-(\d+)\s+\d+\s+(.+)$", l.strip())
    if m and "INVARIANTS" in m.group(4):
        rng = (m.group(1), int(m.group(2)), int(m.group(3)))
if not rng:
    print("  no INVARIANTS part for GENERATE 05b"); sys.exit(1)
lines = open(os.path.join(root, rng[0]), encoding="utf-8").read().splitlines()
seg = lines[rng[1] - 1:rng[2]]
miss = [f"I{i}" for i in range(1, 19) if not any(x.startswith(f"I{i} ") for x in seg)]
if miss:
    print(f"  INVARIANTS range {rng} misses {miss}"); sys.exit(1)
PY
fi
t AC1 "$ok" "the manifest resolves; ranges lie inside their files; I1–I18 are in the INVARIANTS range"

# ---------- AC2: reads drop by at least half, recomputed here ----------
ok=1
if [[ ! -f "$ROOT/tests/doc_parts.sh" ]]; then
  ok=0; echo "  tests/doc_parts.sh does not exist"
else
  for c in "${CLASSES[@]}"; do
    set -- $c
    python3 - "$ROOT" "$TMP/parts.$1.$2" "$c" <<'PY' || ok=0
import os, re, sys
root, f, cls = sys.argv[1:4]
whole = ["docs/cascade/hop-state.md", "docs/cascade/envelope.md", "docs/cascade/product-e2e-gre-pipeline.md",
         "docs/cascade/product-e2e-cascade.md", "CONTROL-LINE.md"]
size = lambda p: os.path.getsize(os.path.join(root, p))
base = sum(size(p) for p in whole)
after = sum(size(p) for p in whole[:2] + [whole[3]])
seen = set()
for l in open(f, encoding="utf-8"):
    m = re.match(r"^(\S+):(\d+)-(\d+)\s", l.strip())
    if not m:
        continue
    p, a, b = m.group(1), int(m.group(2)), int(m.group(3))
    lines = open(os.path.join(root, p), "rb").read().split(b"\n")
    for i in range(a, b + 1):
        if (p, i) not in seen:
            seen.add((p, i)); after += len(lines[i - 1]) + 1
r = after / base
print(f"  {cls}: {after}/{base} = {r:.0%}")
sys.exit(0 if r <= 0.5 else 1)
PY
  done
  bash "$ROOT/tests/doc_parts.sh" --measure >/dev/null 2>&1 || { ok=0; echo "  --measure exited non-zero"; }
fi
t AC2 "$ok" "every hop class reads at most half of the five whole files (computed by the oracle)"

# ---------- AC3: red twins — a renamed heading, a deleted block ----------
ok=1
if [[ ! -f "$ROOT/tests/doc_parts.sh" ]]; then
  ok=0; echo "  tests/doc_parts.sh does not exist"
else
  D="$TMP/ac3"; mkdir -p "$D/docs/cascade"
  cp -R "$ROOT/tests" "$D/tests"; cp "$ROOT/CONTROL-LINE.md" "$D/"
  cp "$ROOT"/docs/cascade/*.md "$D/docs/cascade/"
  sed -i.bak 's/^## Stage 10 — audit hop output shape$/## Stage 10 — audit output (renamed)/' "$D/$GRE"
  out="$(bash "$D/tests/doc_parts.sh" --check 2>&1)"; rc=$?
  [[ $rc -ne 0 ]] || { ok=0; echo "  RED TWIN: a renamed heading still passes --check"; }
  grep -q 'Stage 10 — audit hop output shape' <<< "$out" || { ok=0; echo "  --check does not name the broken part: $out"; }
  cp "$ROOT/$GRE" "$D/$GRE"
  python3 - "$D/$GRE" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = re.sub(r"<!-- doc-parts:begin -->.*?<!-- doc-parts:end -->", "", s, flags=re.S)
open(p, "w", encoding="utf-8").write(s)
PY
  bash "$D/tests/doc_parts.sh" --check >/dev/null 2>&1 && { ok=0; echo "  RED TWIN: a deleted manifest block still passes --check"; }
fi
t AC3 "$ok" "RED TWINS: a renamed heading and a deleted manifest block fail --check"

# ---------- AC4: no line of the two docs moves or changes ----------
ok=1
rm_lines="$(git -C "$ROOT" diff "$BASE" -- "$GRE" CONTROL-LINE.md | grep -E '^-[^-]|^-$' | wc -l | tr -d ' ')"
[[ "$rm_lines" -eq 0 ]] || { ok=0; echo "  $rm_lines removed line(s) in the two docs since $BASE"; }
ag="$(git -C "$ROOT" diff "$BASE" -- AGENTS.md | grep -E '^-[^-]|^-$' | wc -l | tr -d ' ')"
[[ "$ag" -le 2 ]] || { ok=0; echo "  AGENTS.md lost $ag lines (at most 2: read items 3 and 5)"; }
t AC4 "$ok" "no removed line in the pipeline doc or CONTROL-LINE.md; AGENTS.md changes at most 2 lines"

# ---------- fixture for AC5–AC8 ----------
# mk <dir> <hop> <slice> [autopilot] — the real docs and tests, a small envelope; tests/ and .claude/ are ignored so
# that swapping them does not change git state.
mk() {
  local d="$1" hop="$2" sl="$3" ap="${4:-}"
  rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/.claude"
  cp -R "$ROOT/tests" "$d/tests"; cp -R "$ROOT/.claude/hooks" "$d/.claude/hooks"
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  cp "$ROOT/$GRE" "$ROOT/docs/cascade/product-e2e-cascade.md" "$d/docs/cascade/"; cp "$ROOT/CONTROL-LINE.md" "$d/"
  printf '.cascade/\ntests/\n.claude/\n' > "$d/.gitignore"
  printf '# envelope\n\n## Laws\n\nnone\n' > "$d/docs/cascade/envelope.md"
  printf 'CURRENT_HOP: %s\nCURRENT_STAGE: 05b\nCURRENT_SLICE: %s\n\n<EDIT>\nAUTOPILOT: %s\n</EDIT>\n' "$hop" "$sl" "$ap" \
    > "$d/docs/cascade/hop-state.md"
  printf -- '- a: alpha brief\n  second line of a\n- b: bravo brief\n- c: charlie brief\n  more c\n- d: delta brief, no spec\n' \
    > "$d/docs/cascade/05b-briefs.md"
  for s in a b c; do printf '# Stage 05b — %s — SPEC\n\n## Acceptance criteria\n\n- AC1\n' "$s" > "$d/docs/cascade/05b-$s.md"; done
  git -C "$d" init -q && git -C "$d" add -A && git -C "$d" commit -qm init
}
seam() {  # seam <dir> — the hook's additionalContext, or empty
  printf '{"cwd":"%s","prompt":"how does the loop work","session_id":"%s","prompt_id":"%s"}' "$1" "$(uid)" "$(uid)" \
    | (cd "$1" && python3 -B "$1/.claude/hooks/seam.py" 2>/dev/null) \
    | python3 -c 'import json,sys
t=sys.stdin.read().strip()
print(json.loads(t).get("hookSpecificOutput",{}).get("additionalContext","") if t else "")'
}

# ---------- AC5: the prompt hook ----------
ok=1
D="$TMP/ac5"; mk "$D" GENERATE b
ctx="$(seam "$D")"
line="$(grep '^DOC PARTS THIS HOP:' <<< "$ctx" | head -1)"
[[ -n "$line" ]] || { ok=0; echo "  GENERATE 05b: no 'DOC PARTS THIS HOP:' line"; }
grep -q 'Spec critic' <<< "$line" || { ok=0; echo "  the line does not name the Spec critic range: $line"; }
grep -qE "$GRE:[0-9]+-[0-9]+" <<< "$line" || { ok=0; echo "  the line has no <path>:<start>-<end> range"; }
[[ ${#line} -le 700 ]] || { ok=0; echo "  the line is ${#line} characters (max 700)"; }
without_line="$(grep -v '^DOC PARTS THIS HOP:' <<< "$ctx")"
rm -f "$D/tests/lib/doc_parts.py"
ctx2="$(seam "$D")"
[[ "$ctx2" == "$without_line" ]] || { ok=0; echo "  without doc_parts.py the output differs beyond the doc-parts line"; diff <(echo "$without_line") <(echo "$ctx2") | head -5; }
D="$TMP/ac5n"; mk "$D" NONE b
grep -q '^DOC PARTS THIS HOP:' <<< "$(seam "$D")" && { ok=0; echo "  NONE: a doc-parts line is printed"; }
t AC5 "$ok" "the hook prints the ranges on GENERATE 05b (≤700 chars), not on NONE; no lib changes nothing else"

# ---------- AC6: the archive moves exactly the closed briefs ----------
ok=1
D="$TMP/ac6"; mk "$D" GENERATE b "05b c, 05b d"
orig="$(cat "$D/docs/cascade/05b-briefs.md")"
if [[ ! -f "$D/tests/briefs.sh" ]]; then
  ok=0; echo "  tests/briefs.sh does not exist"
else
  # dirty briefs file: refused, nothing changes
  printf '  dirty\n' >> "$D/docs/cascade/05b-briefs.md"
  bash "$D/tests/briefs.sh" archive >/dev/null 2>&1 && { ok=0; echo "  a dirty briefs file was not refused"; }
  [[ ! -f "$D/docs/cascade/05b-briefs-archive.md" ]] || { ok=0; echo "  a refused run created the archive"; }
  git -C "$D" checkout -q -- docs/cascade/05b-briefs.md
  out="$(bash "$D/tests/briefs.sh" archive 2>&1)"; rc=$?
  [[ $rc -eq 0 ]] || { ok=0; echo "  archive exit $rc: $out"; }
  live="$(cat "$D/docs/cascade/05b-briefs.md")"
  arch="$(cat "$D/docs/cascade/05b-briefs-archive.md" 2>/dev/null)"
  python3 - "$orig" "$live" "$arch" <<'PY' || ok=0
import sys
orig, live, arch = sys.argv[1:4]
a = "- a: alpha brief\n  second line of a"
bad = 0
if a not in arch: print("  the archive does not hold brief a byte for byte"); bad = 1
for s in ("- b:", "- c:", "- d:"):
    if s in arch: print(f"  {s} was archived but is open, listed or has no spec"); bad = 1
    if s not in live: print(f"  {s} left the live file"); bad = 1
if "- a:" in live: print("  brief a is still in the live file"); bad = 1
body = [l for l in arch.splitlines() if not l.startswith("# ")]
merged = sorted(l for l in live.splitlines() + body if l.strip())
if merged != sorted(l for l in orig.splitlines() if l.strip()):
    print("  live + archive do not hold every original line exactly once"); bad = 1
sys.exit(bad)
PY
  git -C "$D" add -A && git -C "$D" commit -qm archive
  out="$(bash "$D/tests/briefs.sh" archive 2>&1)"
  grep -q 'nothing to move' <<< "$out" || { ok=0; echo "  a second run did not print 'nothing to move': $out"; }
  # a slug in both files: refused
  printf -- '- d: delta again\n' >> "$D/docs/cascade/05b-briefs-archive.md"; git -C "$D" commit -qam dup
  bash "$D/tests/briefs.sh" archive >/dev/null 2>&1 && { ok=0; echo "  a slug in both files was not refused"; }
  git -C "$D" reset -q --hard HEAD~1
fi
t AC6 "$ok" "archive moves only the closed brief, byte-identical, idempotent; refuses dirty and duplicate"

# ---------- AC7: readers find an archived brief ----------
ok=1
if [[ ! -f "$D/tests/briefs.sh" ]]; then
  ok=0; echo "  tests/briefs.sh does not exist"
else
  f="$(bash "$D/tests/briefs.sh" find a 2>&1)"
  grep -q '05b-briefs-archive.md:[0-9]' <<< "$f" || { ok=0; echo "  find a: $f"; }
  bash "$D/tests/briefs.sh" find nosuch >/dev/null 2>&1 && { ok=0; echo "  find of a missing slug exited 0"; }
  r="$(python3 -B -c "import sys; sys.path.insert(0, '$D/tests/lib'); import recall; print(recall.brief('$D', 'a'))" 2>&1)"
  grep -q '05b-briefs-archive.md' <<< "$r" || { ok=0; echo "  recall.brief(a): $r"; }
  printf -- '- e: [diverge 2] pick a store\n' >> "$D/docs/cascade/05b-briefs-archive.md"
  g="$(python3 -B -c "import sys; sys.path.insert(0, '$D/tests/lib'); import diverge; print(diverge.tag('$D', 'e'))" 2>&1)"
  [[ "$g" == 2 ]] || { ok=0; echo "  diverge.tag(e) from the archive: $g"; }
fi
t AC7 "$ok" "briefs.sh find, recall.brief and diverge.tag read the archive"

# ---------- AC8: preserve output does not change ----------
ok=1
OLD="$TMP/old"; mkdir -p "$OLD"
git -C "$ROOT" archive "$BASE" tests .claude/hooks | tar -x -C "$OLD"
pj() {  # pj <dir> <source> — preserve.py's stdout
  printf '{"cwd":"%s","source":"%s","session_id":"%s"}' "$1" "$2" "$(uid)" | (cd "$1" && python3 -B "$1/.claude/hooks/preserve.py")
}
for case in "GENERATE compact" "NONE startup"; do
  set -- $case
  D="$TMP/ac8"; mk "$D" "$1" a
  new="$(pj "$D" "$2")"
  rm -rf "$D/tests" "$D/.claude/hooks"; cp -R "$OLD/tests" "$D/tests"; cp -R "$OLD/.claude/hooks" "$D/.claude/hooks"
  old="$(pj "$D" "$2")"
  [[ "$new" == "$old" ]] || { ok=0; echo "  $1 $2: preserve output differs from $BASE"; diff <(echo "$old") <(echo "$new") | head -6; }
done
t AC8 "$ok" "preserve.py output (GENERATE compact, NONE startup) is byte-identical to $BASE"

[[ $fail -eq 0 ]] && echo "t102: all AC PASS" || echo "t102: FAIL"
exit "$fail"
