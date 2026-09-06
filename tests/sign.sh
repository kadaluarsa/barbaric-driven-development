#!/usr/bin/env bash
# `bdd sign` — a human signs the human-owned files they just edited, so the commit can come from anywhere
# (IDE, GUI client, terminal). Writes one-shot tokens that pre-commit consumes for exactly that content.
#
# The agent cannot run this: bash_guard denies any command naming sign.sh, bdd sign, or the token files.
#   bash tests/sign.sh            # sign every human-owned file that differs from HEAD
#   bash tests/sign.sh <path>…    # sign only these
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(git rev-parse --show-toplevel)" || { echo "not a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1
GITDIR="$(git rev-parse --git-dir)"; [[ "$GITDIR" == /* ]] || GITDIR="$ROOT/$GITDIR"
TOKENS="$GITDIR/cascade-human-ok"
sha() { python3 -B -c 'import sys,hashlib; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

human_owned() {   # files this pack treats as human-owned
  { echo "docs/cascade/envelope.md"
    git ls-files 'tests/inv/*' 2>/dev/null
    git ls-files 'docs/**/*.md' 'docs/*.md' 2>/dev/null | xargs -I{} sh -c 'grep -lq "<EDIT>" "{}" 2>/dev/null && echo "{}"'
  } | sort -u
}

targets=()
if [[ $# -gt 0 ]]; then targets=("$@"); else
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    git diff --quiet HEAD -- "$f" 2>/dev/null || targets+=("$f")
  done < <(human_owned)
fi

[[ ${#targets[@]} -gt 0 ]] || { echo "Nothing to sign: no human-owned file differs from HEAD."; exit 0; }
n=0
for f in "${targets[@]}"; do
  [[ -f "$f" ]] || { echo "  ! $f does not exist" >&2; continue; }
  echo "$(sha "$f") $f" >> "$TOKENS"; n=$((n + 1))
  echo "  signed  $f"
done
echo
echo "$n file(s) signed. Commit them now — from a terminal, an IDE, or any git client."
echo "A token covers exactly this content, once: edit again and you must sign again."
