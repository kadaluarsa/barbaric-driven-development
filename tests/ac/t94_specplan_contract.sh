#!/usr/bin/env bash
# AC tests for 05b t94-specplan-contract — THE ORACLE for this slice, written at GENERATE before any implementation
# and pinned in docs/cascade/05b-t94-specplan-contract.oracle.
#   AC1  contract: four fields; a missing field names itself; acceptance needs a command or manual:; numbered procedure.
#   AC2  language: limits read from the rules file; code, tables and headings do not count; banned terms fail; passive warns.
#   AC3  reach: n/a off 05b, without rules, or signed off; an unsigned off does nothing; bad rules fail closed; EXECUTE checks.
#   AC4  every host: tests/critique.sh, .githooks/pre-commit (staged text, not the working tree) and CI all carry the check.
#   AC5  rule text: AGENTS.md, the hop shape and the critic brief; install ships it; no conformance claim; this slice passes.
#   AC6  benchmark: exact per-arm report; bad input exits 2; no model or network call; no winner.
#   AC7  attention: the T8+ table moved; lint still goes red on a missing row; .ignore; the evidence stays tracked.
#   AC8  red twins: stubbing each named check lets the broken input through, so that check is what caught it.
#   AC9  traceability: each MUST has a check and a verifying task; each task names a real requirement; dependencies are
#        known and acyclic; plan tasks win over spec tasks; requirement and task text meet the language rules.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED PLUGIN_ROOT BDD_HOOK_HOST CLAUDE_PLUGIN_ROOT BDD_MODEL
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 BDD_AUTO_REFRESH=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HS=docs/cascade/hop-state.md
SPEC=docs/cascade/05b-a.md
PLAN=docs/cascade/plans/05b-a.md
RULES=docs/cascade/specplan-rules.md

words() { python3 -c 'import sys; print(" ".join(["word"]*int(sys.argv[1])) + ".")' "$1"; }
good_spec() {
  cat <<'EOF'
# Stage 05b — a — SPEC

The tool reads one file. The `tool --flag` command writes one report.

## Before vs after

```mermaid
flowchart LR
  A --> B
```

```mermaid
flowchart LR
  B --> A
```

## Benefits and trade-offs

| Item | Result |
|---|---|
| This table cell has very many words and it does not count because a table cell is not a sentence that the language check reads at all | ok |

## Requirements

| ID | Priority | Statement | Check |
|---|---|---|---|
| REQ-1 | MUST | The tool writes one report. | `bash tests/ac/a.sh` |
| REQ-2 | SHOULD | The report stays short. | manual: The human reads it. |

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | REQ-1 | Write the test. |
| T2 | T1 | REQ-1 | Run the test. |

## Execution contract

### allowed

- Change `lib/x.txt`.

### prohibited

- Change a law.

### procedure

1. Write the test.
2. Run the test.

### acceptance

- `bash tests/ac/a.sh` exits 0.
- manual: The human reads the report.
EOF
}
# mk <dir> <HOP> [stage] — slice a; a conforming spec committed; the hook wired
mk() {
  local d="$1" hop="$2" stage="${3:-05b}"; rm -rf "$d"; mkdir -p "$d/docs/cascade/plans" "$d/tests/ac" "$d/lib"
  cp -R "$ROOT/.githooks" "$d/.githooks"; cp -R "$ROOT/tests/lib" "$d/tests/lib"
  for f in critique.sh specplan.sh; do cp "$ROOT/tests/$f" "$d/tests/" 2>/dev/null; done
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"; echo x > "$d/lib/x.txt"
  printf '# envelope\n\n## Laws\n\nnone\n' > "$d/docs/cascade/envelope.md"
  printf 'CURRENT_HOP: %s\nCURRENT_STAGE: %s\nCURRENT_SLICE: a\n\n<EDIT>\n</EDIT>\n' "$hop" "$stage" > "$d/$HS"
  printf '# skills\n' > "$d/docs/cascade/skill-binding.md"
  printf '# briefs\n\n- a: brief\n' > "$d/docs/cascade/05b-briefs.md"
  printf '# regress\n' > "$d/docs/cascade/regress.md"
  printf '# rules\n\n<EDIT>\nSPECPLAN_MAX_WORDS_PROCEDURE: 20\nSPECPLAN_MAX_WORDS_DESCRIPTIVE: 25\nSPECPLAN_BANNED: etc. | and/or | as needed\n</EDIT>\n' > "$d/$RULES"
  good_spec > "$d/$SPEC"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main && git add -A && git -c core.hooksPath=/dev/null commit -qm init \
      && git config core.hooksPath .githooks )
}
run() { (cd "$1" && bash tests/specplan.sh 2>&1); }
rc() { (cd "$1" && bash tests/specplan.sh >/dev/null 2>&1); echo $?; }
drop() {  # drop <file> <### heading> — remove that subsection
  python3 - "$1" "$2" <<'PY'
import re, sys
p, h = sys.argv[1:3]
s = open(p, encoding="utf-8").read()
s2 = re.sub(r"^### " + re.escape(h) + r"\n.*?(?=^### |\Z)", "", s, flags=re.M | re.S)
assert s != s2
open(p, "w", encoding="utf-8").write(s2)
PY
}
D="$TMP/f"

# ---- AC1  contract -----------------------------------------------------------------------------------------------
ok=1
mk "$D" GENERATE; out="$(run "$D")"
[[ "$(rc "$D")" == 0 ]] || { ok=0; echo "  a conforming spec failed: $out"; }
grep -qE '^SPECPLAN [0-9]+/[0-9]+$' <<< "$out" || { ok=0; echo "  no SPECPLAN k/n line: $out"; }
for field in allowed prohibited procedure acceptance; do
  mk "$D" GENERATE; drop "$D/$SPEC" "$field"; out="$(run "$D")"
  [[ "$(rc "$D")" == 1 ]] && grep -E '^FAIL' <<< "$out" | grep -qw "$field" || { ok=0; echo "  missing $field not named: $out"; }
done
mk "$D" GENERATE; printf '\n- A row with no check.\n' >> "$D/$SPEC"; out="$(run "$D")"
[[ "$(rc "$D")" == 1 ]] && grep -E '^FAIL' <<< "$out" | grep -qw acceptance || { ok=0; echo "  an acceptance row with no command passed: $out"; }
mk "$D" GENERATE; sed -i.bak 's/^1\. Write/- Write/; s/^2\. Run/- Run/' "$D/$SPEC"; rm -f "$D/$SPEC.bak"; out="$(run "$D")"
[[ "$(rc "$D")" == 1 ]] && grep -E '^FAIL' <<< "$out" | grep -qw procedure || { ok=0; echo "  an unnumbered procedure passed: $out"; }
mk "$D" GENERATE; printf '# Stage 05b — a — SPEC\n\nOne sentence.\n' > "$D/$SPEC"; out="$(run "$D")"
[[ "$(rc "$D")" == 1 ]] && grep -qE '^FAIL.*Execution contract' <<< "$out" || { ok=0; echo "  no contract section passed: $out"; }
t AC1 "$ok" "the four contract fields are required and named; acceptance needs a command or manual:; the procedure is numbered"

# ---- AC2  language -----------------------------------------------------------------------------------------------
ok=1
sent() { mk "$D" GENERATE; { good_spec | sed '$d'; printf -- '- manual: Done.\n\n## Notes\n\n'; printf '%s\n' "$1"; } > "$D/$SPEC"; }
sent "$(words 25)"; [[ "$(rc "$D")" == 0 ]] || { ok=0; echo "  25 descriptive words failed: $(run "$D")"; }
sent "$(words 26)"; out="$(run "$D")"; [[ "$(rc "$D")" == 1 ]] && grep -qE '^FAIL.*26' <<< "$out" || { ok=0; echo "  26 descriptive words passed: $out"; }
sent "1. $(words 20)"; [[ "$(rc "$D")" == 0 ]] || { ok=0; echo "  20 procedural words failed: $(run "$D")"; }
sent "1. $(words 21)"; out="$(run "$D")"; [[ "$(rc "$D")" == 1 ]] && grep -qE '^FAIL.*21' <<< "$out" || { ok=0; echo "  21 procedural words passed: $out"; }
sent "$(words 24 | sed 's/\.$//') \`a very long inline command with many words inside it is one word\`."
[[ "$(rc "$D")" == 0 ]] || { ok=0; echo "  inline code did not count as one word: $(run "$D")"; }
sent "Short one. Short two. $(words 25)"; [[ "$(rc "$D")" == 0 ]] || { ok=0; echo "  sentences were not split: $(run "$D")"; }
sent "$(printf '```\n%s\n```' "$(words 60)")"; [[ "$(rc "$D")" == 0 ]] || { ok=0; echo "  a fenced block was counted: $(run "$D")"; }
sent "## $(words 60)"; [[ "$(rc "$D")" == 0 ]] || { ok=0; echo "  a heading was counted: $(run "$D")"; }
sent "Use this and/or that."; out="$(run "$D")"; [[ "$(rc "$D")" == 1 ]] && grep -qiE '^FAIL.*and/or' <<< "$out" || { ok=0; echo "  a banned term passed: $out"; }
sent "Use \`and/or\` as a literal."; [[ "$(rc "$D")" == 0 ]] || { ok=0; echo "  a banned term inside code failed: $(run "$D")"; }
sent "Run the job AS NEEDED."; [[ "$(rc "$D")" == 1 ]] || { ok=0; echo "  a banned term in capitals passed"; }
sent "The file was deleted by the job."; out="$(run "$D")"; [[ "$(rc "$D")" == 0 ]] && grep -qE '^WARN.*passive' <<< "$out" || { ok=0; echo "  passive voice did not warn without failing: $out"; }
mk "$D" GENERATE; words 26 > "$D/$PLAN"; out="$(run "$D")"; [[ "$(rc "$D")" == 1 ]] && grep -E '^FAIL' <<< "$out" | grep -q 'plans/05b-a.md' || { ok=0; echo "  a plan file was not read: $out"; }
mk "$D" GENERATE; words 26 >> "$D/$SPEC"; sed -i.bak 's/DESCRIPTIVE: 25/DESCRIPTIVE: 30/' "$D/$RULES"; rm -f "$D/$RULES.bak"
[[ "$(rc "$D")" == 0 ]] || { ok=0; echo "  the limit was not read from the rules file: $(run "$D")"; }
t AC2 "$ok" "limits come from the rules file; a numbered step and a sentence have separate limits; code, tables and headings do not count; banned terms fail; passive warns"

# ---- AC3  reach --------------------------------------------------------------------------------------------------
ok=1
broken() { words 26 >> "$1/$SPEC"; }
for pair in "NONE 05b" "GENERATE 06" "EXECUTE 06"; do
  set -- $pair; mk "$D" "$1" "$2"; broken "$D"; out="$(run "$D")"
  [[ "$(rc "$D")" == 0 ]] && grep -q '^SPECPLAN n/a' <<< "$out" || { ok=0; echo "  $pair was not n/a: $out"; }
done
mk "$D" GENERATE; broken "$D"; rm -f "$D/$RULES"; out="$(run "$D")"
[[ "$(rc "$D")" == 0 ]] && grep -q '^SPECPLAN n/a' <<< "$out" || { ok=0; echo "  no rules file was not n/a: $out"; }
mk "$D" GENERATE; broken "$D"; printf '\n<EDIT>\n- SPECPLAN: off\n</EDIT>\n' >> "$D/docs/cascade/envelope.md"; out="$(run "$D")"
[[ "$(rc "$D")" == 0 ]] && grep -q '^SPECPLAN n/a' <<< "$out" || { ok=0; echo "  the signed off was ignored: $out"; }
mk "$D" GENERATE; broken "$D"; printf '\n- SPECPLAN: off\n' >> "$D/docs/cascade/envelope.md"
[[ "$(rc "$D")" == 1 ]] || { ok=0; echo "  an off outside <EDIT> turned the check off"; }
mk "$D" EXECUTE; broken "$D"; [[ "$(rc "$D")" == 1 ]] || { ok=0; echo "  EXECUTE did not check the spec"; }
mk "$D" GENERATE; sed -i.bak '/MAX_WORDS_DESCRIPTIVE/d' "$D/$RULES"; rm -f "$D/$RULES.bak"; out="$(run "$D")"
[[ "$(rc "$D")" == 1 ]] && grep -qE '^FAIL.*MAX_WORDS_DESCRIPTIVE' <<< "$out" || { ok=0; echo "  a missing limit did not fail closed: $out"; }
mk "$D" GENERATE; sed -i.bak 's/DESCRIPTIVE: 25/DESCRIPTIVE: lots/' "$D/$RULES"; rm -f "$D/$RULES.bak"
[[ "$(rc "$D")" == 1 ]] || { ok=0; echo "  a garbage limit did not fail closed"; }
mk "$D" GENERATE; printf '# rules\n\nSPECPLAN_MAX_WORDS_PROCEDURE: 900\nSPECPLAN_MAX_WORDS_DESCRIPTIVE: 900\n' > "$D/$RULES"
[[ "$(rc "$D")" == 1 ]] || { ok=0; echo "  limits outside <EDIT> were accepted"; }
mk "$D" GENERATE; rm -f "$D/$SPEC"; [[ "$(rc "$D")" == 1 ]] || { ok=0; echo "  a missing spec passed"; }
t AC3 "$ok" "n/a off 05b, without rules, or with a signed off; an unsigned off is ignored; EXECUTE checks; missing, garbage or unsigned limits and a missing spec fail closed"

# ---- AC4  every host ---------------------------------------------------------------------------------------------
ok=1
crit() {
  printf '# c\n\n## Brief\n\n| C# | s | f | e |\n|---|---|---|---|\n| C1 | low | x | `y` |\n\n## Spec\n\nNone.\n' > "$1/docs/cascade/05b-a-critique.md"
  ( cd "$1" && git add -A && git -c core.hooksPath=/dev/null commit -qm critique )
  printf '\n## Dispositions\n\n| C# | DISPOSITION |\n|---|---|\n| C1 | fixed b |\n' >> "$1/docs/cascade/05b-a-critique.md"
  ( cd "$1" && git add -A && git -c core.hooksPath=/dev/null commit -qm answers )
}
mk "$D" GENERATE; crit "$D"; (cd "$D" && bash tests/critique.sh >/dev/null 2>&1) || { ok=0; echo "  critique.sh failed on a good spec: $(cd "$D" && bash tests/critique.sh 2>&1)"; }
words 26 >> "$D/$SPEC"; ( cd "$D" && git add -A && git -c core.hooksPath=/dev/null commit -qm broken )
out="$(cd "$D" && bash tests/critique.sh 2>&1)"; r=$?
[[ "$r" -ne 0 ]] && grep -qE '^CRITIQUE [0-9]+/[0-9]+' <<< "$out" && grep -qE '^SPECPLAN [0-9]+/[0-9]+' <<< "$out" || { ok=0; echo "  critique.sh passed a broken spec (rc $r): $out"; }

mk "$D" GENERATE; words 26 >> "$D/$SPEC"; (cd "$D" && git add "$SPEC")
out="$(cd "$D" && git commit -qm x 2>&1)"; r=$?
[[ "$r" -ne 0 ]] && grep -q 'BLOCKED' <<< "$out" && grep -q 'SPECPLAN\|specplan' <<< "$out" || { ok=0; echo "  pre-commit let a broken spec land (rc $r): $out"; }
good_spec > "$D/$SPEC"; printf 'Short.\n' >> "$D/$SPEC"
out="$(cd "$D" && git commit -qm x 2>&1)"; r=$?
[[ "$r" -ne 0 ]] || { ok=0; echo "  pre-commit read the working tree, not the staged text"; }
(cd "$D" && git add "$SPEC"); out="$(cd "$D" && git commit -qm y 2>&1)" || { ok=0; echo "  pre-commit refused a fixed spec: $out"; }

mk "$D" GENERATE; words 26 >> "$D/$PLAN"; (cd "$D" && git add "$PLAN")
out="$(cd "$D" && git commit -qm x 2>&1)"; [[ $? -ne 0 ]] || { ok=0; echo "  pre-commit let a broken plan land"; }
mk "$D" GENERATE; words 26 >> "$D/$SPEC"; echo note > "$D/docs/cascade/note.md"; (cd "$D" && git add docs/cascade/note.md)
out="$(cd "$D" && git commit -qm x 2>&1)" || { ok=0; echo "  pre-commit blocked a commit that does not stage the spec or plan: $out"; }
mk "$D" GENERATE; words 26 >> "$D/$SPEC"; rm -f "$D/tests/lib/specplan.py"; (cd "$D" && git add "$SPEC")
out="$(cd "$D" && git commit -qm x 2>&1)"; [[ $? -ne 0 ]] || { ok=0; echo "  rules present, checker gone: pre-commit let the spec land"; }
grep -qE 'run: bash tests/specplan\.sh' "$ROOT/.github/workflows/control-line.yml" || { ok=0; echo "  CI does not run tests/specplan.sh"; }
t AC4 "$ok" "tests/critique.sh, the pre-commit hook (staged text; spec and plan; a missing checker fails closed) and CI all carry the check, and an unrelated commit passes"

# ---- AC5  rule text, install, this slice ---------------------------------------------------------------------------
ok=1
grep -q 'ASD-STE100' "$ROOT/AGENTS.md" || { ok=0; echo "  AGENTS.md does not name ASD-STE100"; }
grep -q 'specplan' "$ROOT/AGENTS.md" || { ok=0; echo "  AGENTS.md does not name the check"; }
python3 - "$ROOT/docs/cascade/product-e2e-gre-pipeline.md" <<'PY' || ok=0
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
shape = re.search(r"^## Generate hop — required output shape$(.*?)^## ", s, re.M | re.S)
critic = re.search(r"You are an independent critic\.(.*?)Write its rows", s, re.S)
for name, m in (("the GENERATE hop shape", shape), ("the critic brief", critic)):
    if not (m and "ASD-STE100" in m.group(1)):
        print(f"  {name} does not name ASD-STE100"); sys.exit(1)
for need in ("Execution contract", "## Requirements", "## Tasks"):
    if not (shape and need in shape.group(1)):
        print(f"  the GENERATE hop shape does not require {need}"); sys.exit(1)
PY
R="$ROOT/$RULES"
if [[ -f "$R" ]]; then
  python3 - "$R" <<'PY' || ok=0
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<EDIT>(.*?)</EDIT>", s, re.S)
if not m: print("  the rules are not inside <EDIT>"); sys.exit(1)
for k in ("SPECPLAN_MAX_WORDS_PROCEDURE", "SPECPLAN_MAX_WORDS_DESCRIPTIVE", "SPECPLAN_BANNED"):
    if not re.search(rf"^{k}: *\S", m.group(1), re.M): print(f"  {k} is not signed in <EDIT>"); sys.exit(1)
if "does not claim" not in s: print("  the rules file claims conformance or says nothing on it"); sys.exit(1)
if not re.search(r"not (ship|include|contain)[^.]*dictionary|dictionary[^.]*not (shipped|included)", s, re.I):
    print("  the rules file does not say that the pack ships no dictionary"); sys.exit(1)
PY
else ok=0; echo "  $RULES does not exist"; fi
I="$TMP/inst"; mkdir -p "$I"; ( cd "$I" && git init -q && git commit -q --allow-empty -m init && bash "$ROOT/install.sh" . ) >/dev/null 2>&1
for f in tests/specplan.sh tests/lib/specplan.py "$RULES" docs/cascade/control-line-evidence.md; do
  [[ -f "$I/$f" ]] || { ok=0; echo "  install does not ship $f"; }
done
out="$(cd "$ROOT" && bash tests/specplan.sh 2>&1)"; r=$?
[[ "$r" -eq 0 ]] && grep -qE '^SPECPLAN [0-9]+/[0-9]+$' <<< "$out" || { ok=0; echo "  this slice's own spec and plan do not pass (rc $r): $out"; }
t AC5 "$ok" "AGENTS.md, the hop shape and the critic brief carry the rule; the signed rules claim no conformance and ship no dictionary; install ships it; this slice passes its own check"

# ---- AC6  benchmark ----------------------------------------------------------------------------------------------
ok=1
J="$TMP/runs.jsonl"
python3 - "$J" <<'PY'
import json, sys
rows = []
for arm, passes, lines in (("A", (1, 0, 0, 0), (10, 20, 30, 40)), ("B", (1, 1, 0, 0), (5, 5, 15, 25)), ("C", (1, 1, 1, 1), (1, 2, 3, 4))):
    for i, (p, l) in enumerate(zip(passes, lines)):
        rows.append({"task": "t1" if i < 2 else "t2", "arm": arm, "run": i % 2 + 1, "hidden_pass": bool(p), "changed_lines": l,
                     "repairs": i, "tokens": 1000 + i, "seconds": 60 + i, "tool_calls": 10 + i})
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
SB="$ROOT/tests/specbench.sh"
out="$(bash "$SB" score "$J" 2>&1)"; r=$?
[[ "$r" -eq 0 ]] || { ok=0; echo "  a valid file failed (rc $r): $out"; }
grep -qx 'ARM A runs=4 pass_rate=0.25 changed_lines=10/25/40 repairs=0/1.5/3 tokens=1000/1001.5/1003 seconds=60/61.5/63 tool_calls=10/11.5/13' <<< "$out" || { ok=0; echo "  arm A is wrong: $out"; }
grep -q '^ARM B runs=4 pass_rate=0.50 changed_lines=5/10/25 ' <<< "$out" || { ok=0; echo "  arm B is wrong: $out"; }
grep -q '^ARM C runs=4 pass_rate=1.00 changed_lines=1/2.5/4 ' <<< "$out" || { ok=0; echo "  arm C is wrong: $out"; }
grep -qiE 'winner|best arm|proves' <<< "$out" && { ok=0; echo "  the report names a winner: $out"; }
grep -qx 'SPECBENCH report: no gain claimed' <<< "$out" || { ok=0; echo "  no closing line: $out"; }
[[ "$(bash "$SB" score "$J" 2>&1)" == "$out" ]] || { ok=0; echo "  the report is not deterministic"; }
bad() {  # bad <label> <python filter over rows>
  python3 - "$J" "$TMP/bad.jsonl" "$2" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
rows = eval(sys.argv[3])
open(sys.argv[2], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  local o r; o="$(bash "$SB" score "$TMP/bad.jsonl" 2>&1)"; r=$?
  [[ "$r" -eq 2 ]] && grep -q 'specbench: input error' <<< "$o" || { ok=0; echo "  $1 was not an input error (rc $r): $o"; }
}
bad "a missing arm" '[x for x in rows if x["arm"] != "C"]'
bad "a task missing from one arm" '[x for x in rows if not (x["arm"] == "B" and x["task"] == "t2")]'
bad "one run per task" '[x for x in rows if x["run"] == 1]'
bad "an unknown arm" '[{**x, "arm": "D"} if x["arm"] == "C" else x for x in rows]'
bad "a missing field" '[{k: v for k, v in x.items() if k != "tokens"} for x in rows]'
bad "a non-boolean pass" '[{**x, "hidden_pass": 1} for x in rows]'
printf 'not json\n' > "$TMP/bad.jsonl"; o="$(bash "$SB" score "$TMP/bad.jsonl" 2>&1)"; [[ $? -eq 2 ]] || { ok=0; echo "  bad JSON was not an input error: $o"; }
o="$(bash "$SB" score "$TMP/none.jsonl" 2>&1)"; [[ $? -eq 2 ]] || { ok=0; echo "  a missing file was not an input error: $o"; }
STUB="$TMP/stub"; mkdir -p "$STUB"; LOG="$TMP/calls.log"; : > "$LOG"
for c in claude codex curl wget docker; do printf '#!/bin/sh\necho %s >> "%s"\nexit 0\n' "$c" "$LOG" > "$STUB/$c"; chmod +x "$STUB/$c"; done
out="$(PATH="$STUB:$PATH" bash "$SB" --dry-run 2>&1)"; r=$?
[[ "$r" -eq 0 ]] || { ok=0; echo "  --dry-run failed (rc $r): $out"; }
for a in A B C; do grep -q "^ARM $a runs=" <<< "$out" || { ok=0; echo "  --dry-run has no arm $a: $out"; }; done
[[ ! -s "$LOG" ]] || { ok=0; echo "  --dry-run called: $(tr '\n' ' ' < "$LOG")"; }
T="$ROOT/evals/specbench/tasks.tsv"
python3 - "$T" <<'PY' || ok=0
import csv, collections, sys
try:
    rows = list(csv.DictReader(open(sys.argv[1], encoding="utf-8"), delimiter="\t"))
except OSError:
    print("  evals/specbench/tasks.tsv does not exist"); sys.exit(1)
kinds = collections.Counter(r.get("kind") for r in rows)
if len(rows) < 6 or any(kinds[k] < 2 for k in ("bug-fix", "feature", "refactor")):
    print(f"  the task set is short: {dict(kinds)}"); sys.exit(1)
if any(not r.get("task") or not r.get("request") for r in rows):
    print("  a task row has no id or request"); sys.exit(1)
PY
t AC6 "$ok" "the benchmark reports exact per-arm spreads and no winner; bad input exits 2; --dry-run calls no model or network; the task set has two tasks of each kind"

# ---- AC7  attention ----------------------------------------------------------------------------------------------
ok=1
CL="$ROOT/CONTROL-LINE.md"; EV="$ROOT/docs/cascade/control-line-evidence.md"
grep -qE '^\| T([89]|[0-9]{2,}) \|' "$CL" && { ok=0; echo "  CONTROL-LINE.md still holds T8+ rows"; }
sz="$(wc -c < "$CL" | tr -d ' ')"; [[ "$sz" -le 12288 ]] || { ok=0; echo "  CONTROL-LINE.md is $sz bytes (limit 12288)"; }
grep -q 'control-line-evidence.md' "$CL" || { ok=0; echo "  CONTROL-LINE.md has no pointer to the table"; }
grep -qE '^\| T1 \|' "$CL" || { ok=0; echo "  the T1–T7 Dune bar left CONTROL-LINE.md"; }
maxt="$(grep -oE '^t T[0-9]+' "$ROOT/tests/enforcement.sh" | grep -oE '[0-9]+' | sort -n | tail -1)"
n=0; [[ -f "$EV" ]] && n="$(grep -cE '^\| T([89]|[0-9]{2,}) \|' "$EV")"
[[ "$n" -ge 75 ]] || { ok=0; echo "  the evidence file holds $n rows (want at least 75)"; }
grep -qE "^\\| T$maxt \\|" "$EV" 2>/dev/null || { ok=0; echo "  the evidence file has no row for the newest test T$maxt"; }
bash "$ROOT/tests/control-line.sh" >/dev/null 2>&1 || { ok=0; echo "  tests/control-line.sh is red"; }
L="$TMP/lintcopy"; mkdir -p "$L"
for x in tests docs .github .claude .githooks commands skills evals README.md USAGE.md AUDIT.md AGENTS.md CHANGELOG.md CONTROL-LINE.md INTEGRATION.md VERSION install.sh; do
  [[ -e "$ROOT/$x" ]] && cp -R "$ROOT/$x" "$L/$x"
done
( cd "$L" && git init -q && git add -A >/dev/null 2>&1 && git -c core.hooksPath=/dev/null commit -qm c >/dev/null 2>&1 )
out="$(cd "$L" && bash tests/lint.sh 2>&1)"; grep -q 'has no row for T' <<< "$out" && { ok=0; echo "  positive control: an intact table was reported stale"; }
if [[ -f "$L/docs/cascade/control-line-evidence.md" ]]; then
  sed -i.bak "/^| T$maxt |/d" "$L/docs/cascade/control-line-evidence.md"; rm -f "$L/docs/cascade/control-line-evidence.md.bak"
  out="$(cd "$L" && bash tests/lint.sh 2>&1)"; r=$?
  [[ "$r" -ne 0 ]] && grep -q "no row for T$maxt" <<< "$out" || { ok=0; echo "  RED TWIN: lint passed with the newest row removed (rc $r)"; }
fi
(cd "$L" && bash tests/control-line.sh >/dev/null 2>&1) || { ok=0; echo "  positive control: tests/control-line.sh is red on an intact copy"; }
rm -f "$L/$RULES"; (cd "$L" && bash tests/control-line.sh >/dev/null 2>&1) && { ok=0; echo "  RED TWIN: tests/control-line.sh passed with the rules file deleted"; }
for p in evals/stress evals/probes; do
  grep -qE "^$p/?\$" "$ROOT/.ignore" 2>/dev/null || { ok=0; echo "  .ignore does not name $p"; }
  [[ -n "$(git -C "$ROOT" ls-files "$p" | head -1)" ]] || { ok=0; echo "  $p is no longer tracked"; }
done
t AC7 "$ok" "the T8+ table moved and CONTROL-LINE.md is at most 12 KiB with a pointer and T1–T7; lint goes red on a missing row and control-line.sh on a deleted rules file (red twins); .ignore hides the tracked evidence"

# ---- AC8  red twins ----------------------------------------------------------------------------------------------
ok=1
stub() { (cd "$1" && python3 -B -c '
import os, sys
sys.path.insert(0, os.path.join(os.getcwd(), "tests", "lib"))
import specplan
setattr(specplan, sys.argv[1], lambda *a, **k: [])
sys.argv = ["specplan.py", os.getcwd()]
sys.exit(specplan.main())
' "$2" >/dev/null 2>&1); echo $?; }
mk "$D" GENERATE; drop "$D/$SPEC" prohibited
[[ "$(stub "$D" nothing_to_stub 2>/dev/null)" == 1 ]] || { ok=0; echo "  the unstubbed run did not fail on a missing field"; }
[[ "$(stub "$D" check_contract)" == 0 ]] || { ok=0; echo "  RED TWIN check_contract: stubbing it did not let a missing field through"; }
mk "$D" GENERATE; words 26 >> "$D/$SPEC"
[[ "$(stub "$D" nothing_to_stub 2>/dev/null)" == 1 ]] || { ok=0; echo "  the unstubbed run did not fail on a long sentence"; }
[[ "$(stub "$D" check_language)" == 0 ]] || { ok=0; echo "  RED TWIN check_language: stubbing it did not let a long sentence through"; }
mk "$D" GENERATE; sed -i.bak '/^| T1 | — | REQ-1/d; /^| T2 | T1 | REQ-1/d' "$D/$SPEC"; rm -f "$D/$SPEC.bak"
[[ "$(stub "$D" nothing_to_stub 2>/dev/null)" == 1 ]] || { ok=0; echo "  the unstubbed run did not fail with no tasks"; }
[[ "$(stub "$D" check_trace)" == 0 ]] || { ok=0; echo "  RED TWIN check_trace: stubbing it did not let an untraced spec through"; }
t AC8 "$ok" "red twins: with check_contract, check_language or check_trace stubbed the broken spec passes, so each named check is what catches it"

# ---- AC9  traceability -------------------------------------------------------------------------------------------
ok=1
edit() {  # edit <file> <old> <new> — exact replace; the fixture text must hold <old>
  python3 - "$@" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert a in s, a
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
red() {  # red <label> <grep -E pattern for the FAIL line>
  local o; o="$(run "$D")"
  [[ "$(rc "$D")" == 1 ]] && grep -E '^FAIL' <<< "$o" | grep -qE "$2" || { ok=0; echo "  $1 did not fail naming $2: $o"; }
}
green() { [[ "$(rc "$D")" == 0 ]] || { ok=0; echo "  $1 failed: $(run "$D")"; }; }
REQ1='| REQ-1 | MUST | The tool writes one report. | `bash tests/ac/a.sh` |'
REQ2='| REQ-2 | SHOULD | The report stays short. | manual: The human reads it. |'
TK1='| T1 | — | REQ-1 | Write the test. |'
TK2='| T2 | T1 | REQ-1 | Run the test. |'
mk "$D" GENERATE; edit "$D/$SPEC" "$REQ2" '| REQ-2 | MUST | The report stays short. | manual: The human reads it. |'; red "a MUST with no task" 'REQ-2'
mk "$D" GENERATE; green "a SHOULD with no task"
mk "$D" GENERATE; edit "$D/$SPEC" "$TK2" '| T2 | T1 | REQ-9 | Run the test. |'; red "an unknown requirement" 'REQ-9'
mk "$D" GENERATE; edit "$D/$SPEC" "$TK2" '| T2 | T1 | — | Run the test. |'; red "a task that verifies nothing" 'T2'
mk "$D" GENERATE; edit "$D/$SPEC" "$TK2" '| T2 | T9 | REQ-1 | Run the test. |'; red "an unknown dependency" 'T9'
mk "$D" GENERATE; edit "$D/$SPEC" "$TK1" '| T1 | T2 | REQ-1 | Write the test. |'; red "a dependency cycle" 'cycle'
mk "$D" GENERATE; edit "$D/$SPEC" "$TK2" '| T1 | — | REQ-1 | Run the test. |'; red "a duplicate task id" 'T1'
mk "$D" GENERATE; edit "$D/$SPEC" "$REQ2" '| REQ-1 | SHOULD | The report stays short. | manual: The human reads it. |'; red "a duplicate requirement id" 'REQ-1'
mk "$D" GENERATE; edit "$D/$SPEC" "$REQ1" '| REQ-1 | MUST | The tool writes one report. | later |'; red "a MUST with no check" 'REQ-1'
mk "$D" GENERATE; edit "$D/$SPEC" "$REQ1" '| REQ-1 | NICE | The tool writes one report. | `x` |'; red "an unknown priority" 'REQ-1'
mk "$D" GENERATE; edit "$D/$SPEC" "## Requirements" "## Needs"; red "no Requirements section" 'Requirements'
mk "$D" GENERATE; edit "$D/$SPEC" "## Tasks" "## Steps"; red "no Tasks section" 'Tasks'
mk "$D" GENERATE; printf '# Plan\n\n## Tasks\n\n| ID | Depends on | Verifies | Action |\n|---|---|---|---|\n| T1 | — | REQ-2 | Write the test. |\n' > "$D/$PLAN"
red "plan tasks that drop REQ-1, with spec tasks that cover it" 'REQ-1'
mk "$D" GENERATE; printf '# Plan\n\n## Tasks\n\n| ID | Depends on | Verifies | Action |\n|---|---|---|---|\n| T1 | — | REQ-1 | Write the test. |\n' > "$D/$PLAN"; edit "$D/$SPEC" "$TK1" '| T1 | — | REQ-9 | Write the test. |'
green "plan tasks that replace broken spec tasks"
mk "$D" GENERATE; edit "$D/$SPEC" "The tool writes one report. |" "$(words 26) |"; red "a long requirement statement" '26 words'
mk "$D" GENERATE; edit "$D/$SPEC" "Write the test. |" "$(words 21) |"; red "a long task action" '21 words'
mk "$D" GENERATE; edit "$D/$SPEC" "The report stays short. |" "Keep it short as needed. |"; red "a banned term in a statement" 'as needed'
mk "$D" GENERATE; printf '\n## Notes\n\n| %s | x |\n' "$(words 26)" >> "$D/$SPEC"; green "a long cell in another table"
t AC9 "$ok" "each MUST has a check and a verifying task; each task verifies a real requirement; dependencies are known and acyclic; plan tasks win; requirement and task text meet the language rules"

if [[ "$fail" -ne 0 ]]; then echo; echo "T94 AC FAILED"; exit 1; fi
echo; echo "T94 AC all PASS"
