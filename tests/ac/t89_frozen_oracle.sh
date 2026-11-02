#!/usr/bin/env bash
# AC tests for 05b t89-frozen-oracle — THE ORACLE for this slice, written at GENERATE before any implementation and
# pinned in docs/cascade/05b-t89-frozen-oracle.oracle. EXECUTE builds against it and does not edit it.
# Scratch repos with the real hooks wired.
#   AC1  GENERATE gate: no manifest → red; --write pins sha256; an edit → hash differs; a missing file → missing.
#   AC2  the spec edge: the Stop hook's spec gate and autopilot's GENERATE→EXECUTE gate name tests/oracle.sh.
#   AC3  frozen in session (hop_guard). RED TWIN: oracle_frozen() returning False lets the edit through.
#   AC4  frozen at commit (pre-commit); extra tests land; the human's key lands.
#   AC5  the loop refuses a changed oracle, an oracle missing from the goal, no manifest. RED TWIN: no oracle.sh call.
#   AC6  send-back: GENERATE can change the oracle again; --write on EXECUTE exits 2.
#   AC7  `- ORACLE: off` signed → off; stage 06 is unaffected.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED PLUGIN_ROOT BDD_HOOK_HOST CLAUDE_PLUGIN_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 BDD_AUTO_REFRESH=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOOKS="$ROOT/.claude/hooks"
HS=docs/cascade/hop-state.md
MAN=docs/cascade/05b-a.oracle

# mk <dir> <HOP> <STAGE> [envelope body] — slice a; tests/ac/a.sh is the oracle candidate (passes)
mk() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests/ac"
  cp -R "$ROOT/.githooks" "$d/.githooks"; cp -R "$ROOT/tests/lib" "$d/tests/lib"
  for f in loop.sh oracle.sh critique.sh diverge.sh; do cp "$ROOT/tests/$f" "$d/tests/"; done
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"
  printf '# envelope\n\n## Laws\n\n%s\n' "${4:-none}" > "$d/docs/cascade/envelope.md"
  printf 'CURRENT_HOP: %s\nCURRENT_STAGE: %s\nCURRENT_SLICE: a\n\n<EDIT>\n%s\n</EDIT>\n' "$2" "$3" "${AP:-}" > "$d/$HS"
  printf '# skills\n' > "$d/docs/cascade/skill-binding.md"
  echo '# spec' > "$d/docs/cascade/$3-a.md"
  printf '#!/usr/bin/env bash\necho oracle-a\n' > "$d/tests/ac/a.sh"
  printf '# goal\n\n```\nGOAL_STAGE: %s\nGOAL_SLICE: a\nVALIDATOR: bash tests/ac/a.sh\n```\n' "$3" > "$d/docs/cascade/goal.md"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main && git add -A && git -c core.hooksPath=/dev/null commit -qm init \
      && git config core.hooksPath .githooks )
}
pin() {  # pin <dir> — write the manifest on GENERATE with the tool, commit without hooks (setup)
  ( cd "$1" && bash tests/oracle.sh --write tests/ac/a.sh >/dev/null 2>&1 && git add -A && git -c core.hooksPath=/dev/null commit -qm pin )
}
to_exec() {  # to_exec <dir> — the human's GENERATE→EXECUTE (setup)
  sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: EXECUTE/' "$1/$HS" && rm -f "$1/$HS.bak"
  ( cd "$1" && git add -A && git -c core.hooksPath=/dev/null commit -qm exec )
}
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
uid() { python3 -c 'import uuid; print(uuid.uuid4().hex)'; }
guard() {  # guard <dir> <rel path> — hop_guard's output for an Edit of that file
  python3 - "$1" "$2" <<'PY' | (cd "$1" && python3 -B "$HOOKS/hop_guard.py")
import json, sys, os
d, rel = sys.argv[1], sys.argv[2]; f = os.path.join(d, rel)
old = open(f).read().splitlines()[-1] if os.path.exists(f) else ""
print(json.dumps({"tool_name": "Edit", "cwd": d, "session_id": "s1",
                  "tool_input": {"file_path": f, "old_string": old, "new_string": old + " # weakened"}}))
PY
}

# ---- AC1 the GENERATE gate --------------------------------------------------------------------------------------
D="$TMP/ac1"; mk "$D" GENERATE 05b
o="$(cd "$D" && bash tests/oracle.sh 2>&1)"; r=$?
t AC1a "$([[ $r -ne 0 && "$o" == *"no oracle manifest: $MAN"* ]] && echo 1 || echo 0)" "no manifest: red, naming the manifest path"
(cd "$D" && bash tests/oracle.sh --write tests/ac/a.sh >/dev/null 2>&1)
o="$(cd "$D" && bash tests/oracle.sh 2>&1)"; r=$?
t AC1b "$([[ $r -eq 0 && "$(grep -v '^#' "$D/$MAN" | grep -v '^$')" == "$(sha "$D/tests/ac/a.sh")  tests/ac/a.sh" && "$o" == *"ORACLE 3/3"* ]] && echo 1 || echo 0)" \
  "--write pins '<sha256>  tests/ac/a.sh'; the gate is ORACLE 3/3"
echo 'exit 0' >> "$D/tests/ac/a.sh"; o="$(cd "$D" && bash tests/oracle.sh 2>&1)"; r=$?
t AC1c "$([[ $r -ne 0 && "$o" == *"hash differs: tests/ac/a.sh"* ]] && echo 1 || echo 0)" "an edited oracle file: hash differs"
rm "$D/tests/ac/a.sh"; o="$(cd "$D" && bash tests/oracle.sh 2>&1)"; r=$?
t AC1d "$([[ $r -ne 0 && "$o" == *"missing: tests/ac/a.sh"* ]] && echo 1 || echo 0)" "a listed file that is gone: missing"

# ---- AC2 the spec edge ------------------------------------------------------------------------------------------
D="$TMP/ac2"; mk "$D" GENERATE 05b
s="$(printf '{"cwd":"%s","session_id":"%s","prompt_id":"%s","stop_hook_active":false,"last_assistant_message":"STITCH NEEDED: review spec+plan for stage 05b."}' "$D" "$(uid)" "$(uid)" | (cd "$D" && python3 -B "$HOOKS/stop_guard.py"))"
t AC2a "$([[ "$s" == *"oracle.sh"* ]] && echo 1 || echo 0)" "the Stop hook's spec gate names tests/oracle.sh when there is no manifest"
D="$TMP/ac2b"; AP="AUTOPILOT: 05b a, 05b b" mk "$D" GENERATE 05b
cp "$D/$HS" "$TMP/before"; sed 's/^CURRENT_HOP:.*/CURRENT_HOP: EXECUTE/' "$TMP/before" > "$TMP/after"
why="$(cd "$D" && python3 -B tests/lib/autopilot.py "$TMP/before" "$TMP/after" "$D" 2>&1)"
t AC2b "$([[ "$why" == *"tests/oracle.sh is red"* ]] && echo 1 || echo 0)" "autopilot refuses GENERATE→EXECUTE naming tests/oracle.sh"

# ---- AC3 frozen in session --------------------------------------------------------------------------------------
D="$TMP/ac3"; mk "$D" GENERATE 05b; pin "$D"; to_exec "$D"; printf '#!/usr/bin/env bash\necho extra\n' > "$D/tests/ac/extra.sh"
g1="$(guard "$D" tests/ac/a.sh)"; g2="$(guard "$D" "$MAN")"; g3="$(guard "$D" tests/ac/extra.sh)"
t AC3 "$([[ "$g1" == *"frozen oracle"* && "$g2" == *"frozen oracle"* && "$g3" != *"frozen oracle"* ]] && echo 1 || echo 0)" \
  "EXECUTE: an edit to the oracle file or the manifest is a frozen-oracle decision; another test file is not"
cp -R "$HOOKS" "$TMP/hooks3"
python3 - "$TMP/hooks3/hop_guard.py" <<'PY'
import re, sys; p=sys.argv[1]; s=open(p).read()
m = re.search(r"def oracle_frozen\(root: str, rel: str\) -> bool:\n", s)
assert m, "twin anchor: oracle_frozen(root, rel) -> bool"
open(p, "w").write(s[:m.end()] + "    return False\n" + s[m.end():])
PY
g="$(python3 - "$D" <<'PY' | (cd "$D" && python3 -B "$TMP/hooks3/hop_guard.py")
import json, sys, os
d = sys.argv[1]; f = os.path.join(d, "tests/ac/a.sh"); old = open(f).read().splitlines()[-1]
print(json.dumps({"tool_name": "Edit", "cwd": d, "session_id": "s1",
                  "tool_input": {"file_path": f, "old_string": old, "new_string": old + " # weakened"}}))
PY
)"
t AC3t "$([[ "$g" != *"frozen oracle"* ]] && echo 1 || echo 0)" "RED TWIN: oracle_frozen() returning False lets the oracle edit through"

# ---- AC4 frozen at commit ---------------------------------------------------------------------------------------
commit() { ( cd "$1" && git add -A && env "${@:2}" git commit -qm change </dev/null >/dev/null 2>"$TMP/err" ); RC=$?; ERR="$(cat "$TMP/err")"; }
D="$TMP/ac4"; mk "$D" GENERATE 05b; pin "$D"; to_exec "$D"
echo '# weakened' >> "$D/tests/ac/a.sh"; commit "$D"
t AC4a "$([[ $RC -ne 0 && "$ERR" == *"frozen oracle"* && "$ERR" == *"tests/ac/a.sh"* ]] && echo 1 || echo 0)" "committing a changed oracle file is BLOCKED, naming it"
( cd "$D" && git reset -q --hard HEAD ); rm "$D/tests/ac/a.sh"; commit "$D"
t AC4b "$([[ $RC -ne 0 && "$ERR" == *"frozen oracle"* ]] && echo 1 || echo 0)" "committing a deleted oracle file is BLOCKED"
( cd "$D" && git reset -q --hard HEAD ); printf '#!/usr/bin/env bash\necho extra\n' > "$D/tests/ac/extra.sh"; commit "$D"
t AC4c "$([[ $RC -eq 0 ]] && echo 1 || echo 0)" "a new extra test lands"
echo '# human change' >> "$D/tests/ac/a.sh"; commit "$D" CASCADE_HUMAN=1
t AC4d "$([[ $RC -eq 0 ]] && echo 1 || echo 0)" "the human's key lands a changed oracle"

# ---- AC5 the loop -----------------------------------------------------------------------------------------------
D="$TMP/ac5"; mk "$D" GENERATE 05b; pin "$D"; to_exec "$D"
o="$(cd "$D" && bash tests/loop.sh 2>&1)"; r=$?
t AC5a "$([[ $r -eq 0 && "$o" == *"PASS  bash tests/ac/a.sh"* ]] && echo 1 || echo 0)" "oracle intact and in the goal: the loop runs it (n/n)"
echo '# weakened' >> "$D/tests/ac/a.sh"; ( cd "$D" && git add -A && git -c core.hooksPath=/dev/null commit -qm sneak )
o="$(cd "$D" && bash tests/loop.sh 2>&1)"; r=$?
t AC5b "$([[ $r -eq 3 && "$o" == *"LOOP REFUSED"* && "$o" == *"hash differs: tests/ac/a.sh"* ]] && echo 1 || echo 0)" "a changed oracle: LOOP REFUSED (exit 3), hash differs"
D="$TMP/ac5c"; mk "$D" GENERATE 05b; pin "$D"; to_exec "$D"
printf '# goal\n\n```\nGOAL_STAGE: 05b\nGOAL_SLICE: a\nVALIDATOR: true\n```\n' > "$D/docs/cascade/goal.md"
o="$(cd "$D" && bash tests/loop.sh 2>&1)"; r=$?
t AC5c "$([[ $r -eq 3 && "$o" == *"not a goal validator: tests/ac/a.sh"* ]] && echo 1 || echo 0)" "the oracle left out of the goal: LOOP REFUSED"
D="$TMP/ac5d"; mk "$D" EXECUTE 05b
o="$(cd "$D" && bash tests/loop.sh 2>&1)"; r=$?
t AC5d "$([[ $r -eq 3 && "$o" == *"no oracle manifest"* ]] && echo 1 || echo 0)" "EXECUTE 05b with no manifest: LOOP REFUSED"
D="$TMP/ac5t"; mk "$D" GENERATE 05b; pin "$D"; to_exec "$D"
grep -v 'oracle.sh' "$D/tests/loop.sh" > "$D/tests/loop.t" && mv "$D/tests/loop.t" "$D/tests/loop.sh"
echo '# weakened' >> "$D/tests/ac/a.sh"
o="$(cd "$D" && bash tests/loop.sh 2>&1)"; r=$?
t AC5t "$([[ $r -eq 0 ]] && echo 1 || echo 0)" "RED TWIN: a loop without the oracle.sh call runs the edited oracle to n/n"

# ---- AC6 send-back ----------------------------------------------------------------------------------------------
D="$TMP/ac6"; mk "$D" GENERATE 05b; pin "$D"; to_exec "$D"
o="$(cd "$D" && bash tests/oracle.sh --write tests/ac/a.sh 2>&1)"; r=$?
sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/' "$D/$HS" && rm -f "$D/$HS.bak"; ( cd "$D" && git add -A && git -c core.hooksPath=/dev/null commit -qm sendback )
g="$(guard "$D" tests/ac/a.sh)"; echo '# fixed' >> "$D/tests/ac/a.sh"; (cd "$D" && bash tests/oracle.sh --write tests/ac/a.sh >/dev/null 2>&1)
t AC6 "$([[ $r -eq 2 && "$o" == *"frozen on EXECUTE"* && "$g" != *"frozen oracle"* && "$(cut -d' ' -f1 < "$D/$MAN" | grep -v '^#' | head -1)" == "$(sha "$D/tests/ac/a.sh")" ]] && echo 1 || echo 0)" \
  "--write on EXECUTE exits 2; after a send-back the oracle is editable and --write re-pins it"

# ---- AC7 opt-out and other stages -------------------------------------------------------------------------------
D="$TMP/ac7"; mk "$D" EXECUTE 05b $'<EDIT>\n- ORACLE: off\n</EDIT>'
o1="$(cd "$D" && bash tests/oracle.sh 2>&1)"; o2="$(cd "$D" && bash tests/loop.sh 2>&1)"; r2=$?
D="$TMP/ac7b"; mk "$D" EXECUTE 06; o3="$(cd "$D" && bash tests/loop.sh 2>&1)"; r3=$?
t AC7 "$([[ "$o1" == *"ORACLE off (signed)"* && $r2 -eq 0 && $r3 -eq 0 && "$o3" != *"oracle"* ]] && echo 1 || echo 0)" \
  "ORACLE: off signed → off, the loop runs without a manifest; stage 06 is untouched"

exit "$fail"
