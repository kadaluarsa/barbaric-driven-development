#!/usr/bin/env bash
# The ten-year stress fixture behind t59's numbers: a synthetic repo with N tracked files (default 60,000 —
# five sixths source, one sixth spec and critique docs), 150 laws and one `true` validator, with this pack's
# scripts installed the way tests/enforcement.sh's mkrepo does. It times the parts that grow with a repo:
# the loop-receipt fingerprint, a whole `loop.sh` run, and sign.sh's scan of human-owned docs.
#
# Opt-in: not in goal.md, CI or the farm — it writes 60,000 files (about 20s on a fast disk, much longer on a
# slow one), and a gate that heavy is the kind that gets skipped.
# usage: bash tests/stress/ten_year.sh [files]
# AC7 bars (exit 1 if missed): fingerprint under 1s, sign.sh under 1s, loop.sh under 5s.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
N="${1:-60000}"
[[ "$N" =~ ^[0-9]+$ && "$N" -ge 60 ]] || { echo "usage: ten_year.sh [files, at least 60]" >&2; exit 64; }
# Hermetic: a user's global git config (commit signing above all) would time the config, not the pack.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"
now() { python3 -c 'import time; print(int(time.time() * 1000))'; }   # `date +%N` is GNU-only

echo "building a $N-file repo …"
python3 - "$R" "$N" <<'PY'
import os, sys
root, n = sys.argv[1], int(sys.argv[2])
docs = n // 6; src = n - docs; slices = docs // 2
for i in range(src):
    d = os.path.join(root, "src", f"m{i // 500:04d}"); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, f"f{i}.py"), "w").write(f"# module {i}\nX = {i}\n" + "pass\n" * (5 + i % 55))
cd = os.path.join(root, "docs", "cascade"); os.makedirs(cd, exist_ok=True)
for s in range(slices):
    slug = f"s{s:05d}-feature"
    open(os.path.join(cd, f"05b-{slug}.md"), "w").write(
        f"# 05b {slug}\n\n" + "line\n" * 40 + ("<EDIT>CHOSEN: O1</EDIT>\n" if s % 10 == 0 else ""))
    open(os.path.join(cd, f"05b-{slug}-critique.md"), "w").write(f"# critique {slug}\n" + "finding\n" * 20)
open(os.path.join(cd, "05b-briefs.md"), "w").write("".join(f"- s{s:05d}-feature: brief {s}\n" for s in range(slices)))
env = ["# envelope", ""]
for i in range(1, 151):
    env += [f"### D{i} — invariant {i} MUST hold", "check:  true", "break:  false", ""]
open(os.path.join(cd, "envelope.md"), "w").write("\n".join(env))
open(os.path.join(cd, "hop-state.md"), "w").write("CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: stress\n")
open(os.path.join(cd, "goal.md"), "w").write("VALIDATOR: true\n")
PY
mkdir -p "$R/tests"; cp -R "$ROOT/tests/lib" "$R/tests/lib"; cp "$ROOT/tests/loop.sh" "$ROOT/tests/sign.sh" "$R/tests/"
( cd "$R" && git init -q && git add -A && git commit -qm "ten years" ) || { echo "could not build the fixture" >&2; exit 1; }

fp() { ( . "$R/tests/lib/cascade.sh"; cascade_worktree_sha "$R" ); }
bad=0
bar() {  # bar <label> <ms> <limit ms> <note>
  local verdict=ok; [[ "$2" -lt "$3" ]] || { verdict="OVER ${3}ms"; bad=1; }
  printf '%-44s %7s ms  %-12s %s\n' "$1" "$2" "$verdict" "$4"
}
printf '%-44s %7s\n' "files tracked" "$(git -C "$R" ls-files | wc -l | tr -d ' ')"
s=$(now); a="$(fp)"; e=$(( $(now) - s )); bar "fingerprint, first run" "$e" 1000 "$a"
s=$(now); b="$(fp)"; e=$(( $(now) - s )); bar "fingerprint, again" "$e" 1000 "$([[ "$a" == "$b" ]] && echo stable || echo "UNSTABLE: $b")"
[[ -n "$a" && "$a" == "$b" ]] || bad=1
echo "# edit" >> "$R/src/m0001/f500.py"
s=$(now); c="$(fp)"; e=$(( $(now) - s )); bar "fingerprint after a one-line edit" "$e" 1000 "$([[ "$c" != "$b" ]] && echo changed || echo "MISSED THE EDIT")"
[[ -n "$c" && "$c" != "$b" ]] || bad=1
( cd "$R" && git checkout -q -- src/m0001/f500.py )
s=$(now); out="$(cd "$R" && bash tests/loop.sh 2>&1)"; e=$(( $(now) - s ))
bar "loop.sh (one validator, 150 laws)" "$e" 5000 "$(echo "$out" | grep -E '^LOOP ' | head -1)"
echo "$out" | grep -qE '^LOOP 1/1$' || bad=1
s=$(now); out="$(cd "$R" && bash tests/sign.sh 2>&1)"; e=$(( $(now) - s ))
bar "sign.sh, nothing changed" "$e" 1000 "$(echo "$out" | head -1)"
echo "# more" >> "$R/docs/cascade/05b-s00000-feature.md"
s=$(now); out="$(cd "$R" && bash tests/sign.sh 2>&1)"; e=$(( $(now) - s ))
bar "sign.sh, one stitched doc changed" "$e" 1000 "$(echo "$out" | grep -c '^  signed') signed"
echo
if [[ "$bad" -ne 0 ]]; then echo "TEN-YEAR: FAIL"; exit 1; fi
echo "TEN-YEAR: PASS"
