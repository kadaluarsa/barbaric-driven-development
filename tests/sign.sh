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
  # One `git grep` over the tracked docs, not a grep per doc: 38s -> well under 1s at 10,000 docs (t59). Same
  # pathspecs as the old `git ls-files`, so the same matching rules over the same working-tree content.
  { echo "docs/cascade/envelope.md"; echo "docs/cascade/hop-state.md"
    git -c core.quotePath=false ls-files 'tests/inv/*' 2>/dev/null
    git -c core.quotePath=false ls-files 'docs/cascade/laws/*.md' 2>/dev/null | grep -v '/README\.md$'   # law shards (t67)
    git -c core.quotePath=false grep -l -F '<EDIT>' -- 'docs/**/*.md' 'docs/*.md' 2>/dev/null
  } | LC_ALL=C sort -u
}

targets=()
if [[ $# -gt 0 ]]; then targets=("$@"); else
  # Human-owned files that differ from HEAD: one `git diff` for all of them, not one per file (t59). With no
  # HEAD yet, every one is a target, as the old per-file `git diff --quiet HEAD` made it.
  if git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    changed() { git -c core.quotePath=false diff --name-only HEAD -- docs/ tests/inv/ 2>/dev/null | LC_ALL=C sort -u; }
  else
    changed() { human_owned; }
  fi
  while IFS= read -r f; do
    [[ -f "$f" ]] && targets+=("$f")
  done < <(LC_ALL=C comm -12 <(human_owned) <(changed))
  # Law shards (t67) that `git diff HEAD` cannot see or that no longer exist: a new, untracked shard, and a shard
  # removed (or renamed away) since HEAD. Both carry or drop laws, so both are the human's to sign.
  while IFS= read -r f; do
    [[ -n "$f" && "$f" != */README.md ]] && targets+=("$f")
  done < <({ git -c core.quotePath=false ls-files --others --exclude-standard -- 'docs/cascade/laws/*.md'
             git -c core.quotePath=false diff --no-renames --name-only --diff-filter=D HEAD -- 'docs/cascade/laws/*.md'; } 2>/dev/null)   # as pre-commit sees it: a rename removes the old path
fi

[[ ${#targets[@]} -gt 0 ]] || { echo "Nothing to sign: no human-owned file differs from HEAD."; exit 0; }
n=0
for f in "${targets[@]}"; do
  if [[ ! -f "$f" ]]; then
    # A removed law shard is signed as removed: pre-commit hashes a path with no staged blob as empty content.
    if [[ "$f" == docs/cascade/laws/*.md ]] && git cat-file -e "HEAD:$f" 2>/dev/null; then
      echo "$(printf '' | python3 -B -c 'import sys,hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())') $f" >> "$TOKENS"
      n=$((n + 1)); echo "  signed  $f (removed)"
    else
      echo "  ! $f does not exist" >&2
    fi
    continue
  fi
  echo "$(sha "$f") $f" >> "$TOKENS"; n=$((n + 1))
  echo "  signed  $f"
done
echo
echo "$n file(s) signed. Commit them now — from a terminal, an IDE, or any git client."
echo "A token covers exactly this content, once: edit again and you must sign again."
