#!/usr/bin/env bash
# AC tests for 05b t59-scale-hardening. What the cascade's own checks cost must follow what changed, not the
# size of the repo — and no verdict may change on a tree the old code could check (I18).
#   AC1  cascade_worktree_sha spawns the same number of git processes at 50 files and at 500.
#        RED TWIN: the pre-t59 per-file fingerprint, embedded below, must fail that check.
#   AC2  the fingerprint changes on every edit the old one saw (and on mode, flags and same-second edits),
#        never on ignored or .cascade/ files or on staging, and never writes to .git.
#   AC4  sign.sh signs exactly what the pre-t59 sign.sh signed, with a constant git/grep/sh count.
#        RED TWIN: the pre-t59 sign.sh must fail the constant-count check.
#   AC5  autopilot's GENERATE->EXECUTE edge needs docs/cascade/<stage>-<slug>.md, exactly.
#        RED TWIN: autopilot.py with the substring match restored must allow the 06 collision.
# AC3/AC3b/AC3c (the Stop hook and loop.sh) run through the real hook in tests/enforcement.sh T59.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Hermetic: a user's global git config (commit signing, hooksPath, templates) must not slow or bend this.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---- process counting ----------------------------------------------------------------------------------
# A shim per tool logs its name and execs the real one. Builtins are not counted; nor are sort/comm/tr/sed,
# whose count is constant either way.
mkdir -p "$TMP/shim"
for tool in git grep sh; do
  real="$(command -v "$tool")"
  printf '#!/bin/sh\necho %s >> "$SHIM_LOG"\nexec "%s" "$@"\n' "$tool" "$real" > "$TMP/shim/$tool"
  chmod +x "$TMP/shim/$tool"
done
count() {  # count <regex of tool names> <command…>  -> how many times those tools ran
  local pat="$1"; shift
  : > "$TMP/shim.log"
  ( export PATH="$TMP/shim:$PATH" SHIM_LOG="$TMP/shim.log"; "$@" ) >/dev/null 2>&1
  grep -cE "^($pat)\$" "$TMP/shim.log" | tr -d ' '
}

new_fp() { ( . "$ROOT/tests/lib/cascade.sh"; cascade_worktree_sha "$1" ); }
old_fp() {  # the pre-t59 fingerprint, verbatim — the red twin for AC1
  ( cd "$1" 2>/dev/null || return 0
    { git ls-files -z 2>/dev/null; git ls-files -z --others --exclude-standard 2>/dev/null; } \
      | tr '\0' '\n' | grep -v '^\.cascade/' | LC_ALL=C sort | while IFS= read -r f; do
          [[ -f "$f" ]] && printf '%s %s\n' "$f" "$(git hash-object "$f" 2>/dev/null)"
        done | git hash-object --stdin 2>/dev/null )
}

# ---- AC1  process count is constant in the file count ---------------------------------------------------
mkfiles() {  # mkfiles <dir> <n>
  local d="$1" n="$2" i
  mkdir -p "$d/src"
  ( cd "$d" && git init -q && for ((i = 0; i < n; i++)); do echo "$i" > "src/f$i.txt"; done \
      && git add -A && git commit -qm init )
}
mkfiles "$TMP/a50" 50; mkfiles "$TMP/a500" 500
n50="$(count git new_fp "$TMP/a50")"; n500="$(count git new_fp "$TMP/a500")"
o50="$(count git old_fp "$TMP/a50")"; o500="$(count git old_fp "$TMP/a500")"
ok=0; [[ "$n50" -gt 0 && "$n50" -eq "$n500" ]] && ok=1
[[ "$ok" -eq 1 ]] || echo "  new fingerprint: $n50 git processes at 50 files, $n500 at 500"
t AC1 "$ok" "cascade_worktree_sha runs $n50 git processes at 50 files and $n500 at 500 — constant, not one per file"
ok=0; [[ "$o500" -gt "$o50" ]] && ok=1
t AC1-twin "$ok" "RED TWIN: the pre-t59 per-file fingerprint fails that check ($o50 git processes at 50 files, $o500 at 500)"

# ---- AC2  correctness -------------------------------------------------------------------------------------
R="$TMP/c"; mkdir -p "$R"
( cd "$R" && git init -q && printf 'aaaa\n' > f && printf 'x\n' > g && printf 'y\n' > h && printf '*.log\n' > .gitignore \
    && git add -A && git commit -qm i )
ok=1
a="$(new_fp "$R")"; b="$(new_fp "$R")"
[[ "$a" == t2:* && "$a" == "$b" ]] || { ok=0; echo "  not stable, or not the t2: scheme: '$a' then '$b'"; }
changes() {  # changes <label> <edit> <undo>
  local before after
  before="$(new_fp "$R")"; ( cd "$R" && eval "$2" ) >/dev/null 2>&1; after="$(new_fp "$R")"
  [[ -n "$after" && "$after" != "$before" ]] || { ok=0; echo "  did not change on: $1"; }
  ( cd "$R" && eval "$3" ) >/dev/null 2>&1
}
same() {  # same <label> <edit> <undo>
  local before after
  before="$(new_fp "$R")"; ( cd "$R" && eval "$2" ) >/dev/null 2>&1; after="$(new_fp "$R")"
  [[ -n "$after" && "$after" == "$before" ]] || { ok=0; echo "  changed on: $1"; }
  ( cd "$R" && eval "$3" ) >/dev/null 2>&1
}
changes "a one-byte edit to a tracked file"   "printf 'aaab\n' > f"  "git checkout -q -- f"
changes "a same-size edit in the same second as the commit" \
  "printf 'cccc\n' > f && git add f && git commit -qm c && printf 'dddd\n' > f" "git checkout -q -- f"
changes "a same-size edit with its mtime restored (touch -r)" \
  "cp -p f ../f.ref && sleep 1 && printf 'zzzz\n' > f && touch -r ../f.ref f" "git checkout -q -- f"
changes "a new untracked, non-ignored file"   "echo n > new.txt"     "rm -f new.txt"
changes "a deleted tracked file"              "rm h"                 "git checkout -q -- h"
changes "chmod +x on a tracked file"          "chmod +x g"           "chmod -x g"
changes "an edit to an assume-unchanged file" \
  "git update-index --assume-unchanged f && printf 'bbbb\n' > f" "git update-index --no-assume-unchanged f && git checkout -q -- f"
changes "an edit to a skip-worktree file" \
  "git update-index --skip-worktree g && printf 'q\n' > g" "git update-index --no-skip-worktree g && git checkout -q -- g"
same "a new ignored file"                     "echo l > x.log"       "rm -f x.log"
same "a new file under .cascade/"             "mkdir -p .cascade && echo r > .cascade/r" "rm -rf .cascade"
same "an untracked embedded repo with no commit" "git init -q sub && echo y > sub/b" "rm -rf sub"
# Staging is not a change to the working tree: the fingerprint describes files, not the index.
( cd "$R" && printf 'eeee\n' > f ); s1="$(new_fp "$R")"; ( cd "$R" && git add f ); s2="$(new_fp "$R")"
[[ -n "$s1" && "$s1" == "$s2" ]] || { ok=0; echo "  staging an edit changed the fingerprint"; }
( cd "$R" && git reset -q && git checkout -q -- f )
# Nothing is written to .git: not the index, not its flags, not the staged list, not the object store.
( cd "$R" && git update-index --assume-unchanged f && git update-index --skip-worktree g && printf 'y2\n' > h \
    && git add h && printf 'aaa9\n' > f && echo u > untracked.txt )
st() { ( cd "$R" && git hash-object .git/index && git ls-files -v && git diff --cached --name-only \
           && find .git/objects -type f | wc -l ); }
before="$(st)"; new_fp "$R" >/dev/null; after="$(st)"
[[ "$before" == "$after" ]] || { ok=0; echo "  a fingerprint run changed the real index, its flags, the staged list or .git/objects"; }
( cd "$R" && git update-index --no-assume-unchanged f && git update-index --no-skip-worktree g && git reset -q \
    && git checkout -q -- f h && rm -f untracked.txt )
# A repo with no commits, a linked worktree, and no repo at all.
mkdir -p "$TMP/fresh" && ( cd "$TMP/fresh" && git init -q && echo q > a )
[[ "$(new_fp "$TMP/fresh")" == t2:* ]] || { ok=0; echo "  no fingerprint in a repo with no commits"; }
( cd "$R" && git worktree add -q "$TMP/wt" 2>/dev/null )
w1="$(new_fp "$TMP/wt")"; echo late > "$TMP/wt/late.txt"; w2="$(new_fp "$TMP/wt")"
[[ "$w1" == t2:* && "$w2" == t2:* && "$w1" != "$w2" ]] || { ok=0; echo "  linked worktree: '$w1' then '$w2'"; }
( cd "$R" && git worktree remove --force "$TMP/wt" 2>/dev/null )
mkdir -p "$TMP/norepo"; [[ -z "$(new_fp "$TMP/norepo")" ]] || { ok=0; echo "  printed a fingerprint outside a git repo"; }
t AC2 "$ok" "the fingerprint changes on every edit the old one saw plus mode, flags and same-second edits; never on ignored, .cascade/ or staged-only changes; writes nothing to .git; works with no commits and in a linked worktree; empty outside a repo"

# ---- AC4  sign.sh: same targets, constant cost --------------------------------------------------------------
# The pre-t59 sign.sh, verbatim below the header, so the comparison does not depend on git history.
cat > "$TMP/old_sign.sh" <<'OLD'
#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(git rev-parse --show-toplevel)" || { echo "not a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1
GITDIR="$(git rev-parse --git-dir)"; [[ "$GITDIR" == /* ]] || GITDIR="$ROOT/$GITDIR"
TOKENS="$GITDIR/cascade-human-ok"
sha() { python3 -B -c 'import sys,hashlib; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
human_owned() {
  { echo "docs/cascade/envelope.md"; echo "docs/cascade/hop-state.md"
    git ls-files 'tests/inv/*' 2>/dev/null
    git ls-files 'docs/**/*.md' 'docs/*.md' 2>/dev/null | xargs -I{} sh -c 'grep -lq "<EDIT>" "{}" 2>/dev/null && echo "{}"'
  } | sort -u
}
targets=()
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  git diff --quiet HEAD -- "$f" 2>/dev/null || targets+=("$f")
done < <(human_owned)
[[ ${#targets[@]} -gt 0 ]] || { echo "Nothing to sign: no human-owned file differs from HEAD."; exit 0; }
for f in "${targets[@]}"; do echo "$(sha "$f") $f" >> "$TOKENS"; echo "  signed  $f"; done
OLD
signed() {  # signed <sign.sh> <repo>  -> the sorted list of paths it signs
  ( cd "$2" && bash "$1" 2>/dev/null ) | sed -n 's/^  signed  //p' | LC_ALL=C sort
}
mkdocs() {  # mkdocs <dir> <docs> <stitched> <changed>
  local d="$1" n="$2" st="$3" ch="$4" i
  mkdir -p "$d/docs/cascade" "$d/docs/sub/deep" "$d/tests/inv" "$d/notes"
  ( cd "$d" && git init -q
    printf '# env\n<EDIT>\nx\n</EDIT>\n' > docs/cascade/envelope.md; printf 'CURRENT_HOP: NONE\n' > docs/cascade/hop-state.md
    for ((i = 0; i < n; i++)); do
      if [[ "$i" -lt "$st" ]]; then printf '# d%s\n<EDIT>v</EDIT>\n' "$i"; else printf '# d%s\nplain\n' "$i"; fi \
        > "docs/sub/d$i.md"
    done
    printf '<EDIT>deep</EDIT>\n' > docs/sub/deep/gone.md; printf '<EDIT>top</EDIT>\n' > docs/top.md
    printf '<EDIT>not a doc</EDIT>\n' > notes/x.txt; printf 'def test(): pass\n' > tests/inv/test_D1.py
    git add -A && git commit -qm init
    for ((i = 0; i < ch; i++)); do echo more >> "docs/sub/d$i.md"; done           # stitched docs, edited
    echo more >> "docs/sub/d$((n - 1)).md"                                          # a plain doc, edited
    echo more >> docs/cascade/envelope.md; echo '# more' >> tests/inv/test_D1.py; echo more >> docs/top.md
    rm docs/sub/deep/gone.md                                                        # tracked, deleted
    printf '<EDIT>new</EDIT>\n' > docs/untracked.md                                 # untracked, stitched
    echo more >> notes/x.txt )
}
mkdocs "$TMP/s20" 20 10 5; mkdocs "$TMP/s200" 200 100 50
cp -R "$TMP/s20" "$TMP/s20old"
new_list="$(signed "$ROOT/tests/sign.sh" "$TMP/s20")"; old_list="$(signed "$TMP/old_sign.sh" "$TMP/s20old")"
ok=0; [[ -n "$new_list" && "$new_list" == "$old_list" ]] && ok=1
[[ "$ok" -eq 1 ]] || { echo "  new signs:"; echo "$new_list" | sed 's/^/    /'; echo "  old signed:"; echo "$old_list" | sed 's/^/    /'; }
# Count on fresh copies: the signing run above appended tokens, which does not change what is signed.
for d in s20 s200; do cp -R "$TMP/$d" "$TMP/$d.n"; cp -R "$TMP/$d" "$TMP/$d.o"; done
sign_in() { ( cd "$2" && bash "$1" ); }
c20="$(count 'git|grep|sh' sign_in "$ROOT/tests/sign.sh" "$TMP/s20.n")"; c200="$(count 'git|grep|sh' sign_in "$ROOT/tests/sign.sh" "$TMP/s200.n")"
d20="$(count 'git|grep|sh' sign_in "$TMP/old_sign.sh" "$TMP/s20.o")"; d200="$(count 'git|grep|sh' sign_in "$TMP/old_sign.sh" "$TMP/s200.o")"
[[ "$c20" -gt 0 && "$c20" -eq "$c200" ]] || { ok=0; echo "  new sign.sh: $c20 git/grep/sh processes at 20 docs, $c200 at 200"; }
t AC4 "$ok" "sign.sh signs exactly what the pre-t59 sign.sh signed ($(echo "$new_list" | grep -c .) files), with $c20 git/grep/sh processes at 20 docs and $c200 at 200"
ok=0; [[ "$d200" -gt "$d20" ]] && ok=1
t AC4-twin "$ok" "RED TWIN: the pre-t59 sign.sh fails the constant-count check ($d20 processes at 20 docs, $d200 at 200)"

# ---- AC5  exact spec match -------------------------------------------------------------------------------------
edge() {  # edge <lib dir> <root> <stage> <slug>  -> exit code of autopilot's GENERATE->EXECUTE decision
  printf 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: %s\nCURRENT_SLICE: %s\nAUTOPILOT: %s %s\n' "$3" "$4" "$3" "$4" > "$TMP/before.md"
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: %s\nCURRENT_SLICE: %s\nAUTOPILOT: %s %s\n' "$3" "$4" "$3" "$4" > "$TMP/after.md"
  python3 -B "$1/autopilot.py" "$TMP/before.md" "$TMP/after.md" "$2" 2>"$TMP/ap.err"; echo $?
}
P="$TMP/ap"; mkdir -p "$P/docs/cascade"
printf '# an older slice\n' > "$P/docs/cascade/06-audit-logging.md"
printf '# its critique\n' > "$P/docs/cascade/06-logging-critique.md"
ok=1
[[ "$(edge "$ROOT/tests/lib" "$P" 06 logging)" -ne 0 ]] && grep -q 'docs/cascade/06-logging.md' "$TMP/ap.err" \
  || { ok=0; echo "  06 logging advanced on 06-audit-logging.md alone, or the refusal does not name the path: $(cat "$TMP/ap.err")"; }
printf '# 05b older\n' > "$P/docs/cascade/05b-login-rate-limit.md"
[[ "$(edge "$ROOT/tests/lib" "$P" 05b login)" -ne 0 ]] && grep -q 'docs/cascade/05b-login.md' "$TMP/ap.err" \
  || { ok=0; echo "  05b login advanced without docs/cascade/05b-login.md: $(cat "$TMP/ap.err")"; }
printf '# the spec\n' > "$P/docs/cascade/06-logging.md"
[[ "$(edge "$ROOT/tests/lib" "$P" 06 logging)" -eq 0 ]] || { ok=0; echo "  refused with docs/cascade/06-logging.md present: $(cat "$TMP/ap.err")"; }
t AC5 "$ok" "autopilot needs docs/cascade/<stage>-<slug>.md exactly: an older 06-audit-logging.md or a critique never stands in for 06 logging, 05b login is refused without its own spec, and the exact file is accepted"
# RED TWIN: restore the substring match in a copy of the library; the collision must then pass.
cp -R "$ROOT/tests/lib" "$TMP/twinlib"
python3 - "$TMP/twinlib/autopilot.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = "if not os.path.isfile(os.path.join(root, spec_rel)):"
new = "if not any(plan[idx][1] in f for f in os.listdir(os.path.join(root, 'docs', 'cascade')) if f not in ('envelope.md', 'hop-state.md', 'goal.md')):"
if old not in s:
    sys.exit("twin: the exact-match line was not found — update the red twin with the code")
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
twin_ok=$?
rm -f "$P/docs/cascade/06-logging.md"
ok=0; [[ "$twin_ok" -eq 0 && "$(edge "$TMP/twinlib" "$P" 06 logging)" -eq 0 ]] && ok=1
t AC5-twin "$ok" "RED TWIN: with the substring match restored, 06-audit-logging.md satisfies 06 logging — so AC5 can tell the two apart"

echo
if [[ "$fail" -ne 0 ]]; then echo "t59-scale-hardening: FAIL"; exit 1; fi
echo "t59-scale-hardening: PASS"
