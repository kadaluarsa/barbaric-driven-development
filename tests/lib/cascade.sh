#!/usr/bin/env bash
# Shared cascade state reader. Sourced by .githooks/*, .claude/hooks/*, tests/loop.sh.
# Single source of truth for "what hop are we on" and "what is product code".

cascade_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

# CASCADE_ENVELOPE lets a rule evaluate against a specific envelope (autopilot checks the pre-edge state).
cascade_envelope() { echo "${CASCADE_ENVELOPE:-$(cascade_root)/docs/cascade/envelope.md}"; }

# Hop state — CURRENT_HOP/STAGE/SLICE and AUTOPILOT — lives in its own file. It turns over 3–4 times per
# slice while the laws beside it change twice a year, and mixing them made the law history unreadable.
# Repos installed before the split keep everything in the envelope, so fall back to it when the file is
# absent. CASCADE_ENVELOPE (autopilot's pre-edge check) still overrides both.
cascade_hopstate() {
  if [[ -n "${CASCADE_ENVELOPE:-}" ]]; then echo "$CASCADE_ENVELOPE"; return; fi
  if [[ -n "${CASCADE_HOPSTATE:-}" ]]; then echo "$CASCADE_HOPSTATE"; return; fi
  local h; h="$(cascade_root)/docs/cascade/hop-state.md"
  [[ -f "$h" ]] && echo "$h" || cascade_envelope
}

# GENERATE | EXECUTE | NONE
cascade_hop() {
  local env_file; env_file="$(cascade_hopstate)"
  [[ -f "$env_file" ]] || { echo NONE; return; }
  local hop
  hop="$(grep -m1 -E '^CURRENT_HOP:' "$env_file" 2>/dev/null | sed -E 's/^CURRENT_HOP:[[:space:]]*//' | tr -d '[:space:]')"
  hop="$(printf '%s' "$hop" | tr '[:lower:]' '[:upper:]')"
  case "$hop" in
    GENERATE) echo GENERATE ;;
    EXECUTE)  echo EXECUTE ;;
    *)        echo NONE ;;
  esac
}

cascade_stage() {
  local env_file; env_file="$(cascade_hopstate)"
  [[ -f "$env_file" ]] || { echo ""; return; }
  grep -m1 -E '^CURRENT_STAGE:' "$env_file" 2>/dev/null \
    | sed -E 's/^CURRENT_STAGE:[[:space:]]*//' | tr -d '[:space:]'
}

cascade_slice() {
  local env_file; env_file="$(cascade_hopstate)"
  [[ -f "$env_file" ]] || { echo ""; return; }
  grep -m1 -E '^CURRENT_SLICE:' "$env_file" 2>/dev/null \
    | sed -E 's/^CURRENT_SLICE:[[:space:]]*//' | tr -d '[:space:]'
}

# Domain laws come from one reader: tests/lib/laws.py (friendly ### blocks or the legacy one-liner).
_laws() { python3 -B "$(cascade_root)/tests/lib/laws.py" "$(cascade_envelope)" "$1" 2>/dev/null || true; }
cascade_dsharp_declared() { _laws --declared; }
cascade_dsharp_in_force() { _laws --in-force; }
cascade_dsharp_unproven() { _laws --unproven; }

# Paths writable during a GENERATE hop. Override with docs/cascade/generate-writable.txt.
cascade_generate_writable() {
  local root over
  root="$(cascade_root)"; over="$root/docs/cascade/generate-writable.txt"
  if [[ -f "$over" ]]; then
    grep -vE '^[[:space:]]*(#|$)' "$over"
  else
    printf '%s\n' 'docs/' 'evals/' 'tests/' '.githooks/' '.claude/' '.github/' '.cursor/' '.windsurf/' '.continue/' '.cascade/' '*.md'
  fi
}

# 0 = product code (forbidden on GENERATE), 1 = allowed
cascade_is_product_path() {
  local path="$1" pat
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    if [[ "$pat" == */ ]]; then
      [[ "$path" == "$pat"* ]] && return 1
    else
      # shellcheck disable=SC2053
      [[ "$path" == $pat ]] && return 1
      [[ "$path" == */$pat ]] && return 1
    fi
  done < <(cascade_generate_writable)
  return 0
}

# Layer 2 (agent hooks, commands, skill) lives in the repo for a standalone install and in the plugin
# otherwise. install.sh records the plugin path in .cascade/manifest so tests can find it from a terminal.
cascade_layer2_root() {
  local root; root="$(cascade_root)"
  [[ -d "$root/.claude/hooks" ]] && { echo "$root"; return; }
  [[ -n "${BDD_PLUGIN_ROOT:-}" && -d "$BDD_PLUGIN_ROOT/.claude/hooks" ]] && { echo "$BDD_PLUGIN_ROOT"; return; }
  local rec; rec="$(sed -n 's/^plugin_root //p' "$root/.cascade/manifest" 2>/dev/null | head -1)"
  [[ -n "$rec" && -d "$rec/.claude/hooks" ]] && { echo "$rec"; return; }
  echo ""
}

# A fingerprint of the working tree, for the loop receipt (I10): edit anything after `loop.sh` passed and the
# receipt no longer matches. Covers tracked files and untracked non-ignored ones, `.cascade/` excluded,
# deletions counted, plus file mode, symlinks (as links) and an embedded repo's checked-out commit.
#
# It is git's own tree of the working tree, built in a TEMPORARY copy of the index, so git re-hashes only
# files whose stat data changed since the last commit or refresh: cost follows what changed, not the size
# of the repo (t59: 235s -> ~0.15s at 60k files, where one `git hash-object` per file used to run). New
# blobs go to a temporary object directory that reads the real store as an alternate, so nothing is written
# to .git; the real index, its flags and HEAD are never touched.
#
# Prints `t2:<tree>` — the prefix names the scheme, so a receipt from an older pack is told apart — or
# nothing when the tree cannot be fingerprinted (not a git repo, git failed). Callers treat empty as "no
# fingerprint": loop.sh writes no receipt and the Stop hook refuses the edge (t59).
cascade_worktree_sha() {
  local root="${1:-$(cascade_root)}"
  ( cd "$root" 2>/dev/null || exit 0
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
    gi="$(git rev-parse --git-path index 2>/dev/null)" || exit 0
    objs="$(cd "$(git rev-parse --git-path objects 2>/dev/null)" 2>/dev/null && pwd)" || exit 0
    tmp="$(mktemp -d 2>/dev/null)" || exit 0
    trap 'rm -rf "$tmp"' EXIT
    mkdir "$tmp/objects" || exit 0
    # -p keeps the index's own mtime: git's racy-entry check compares it with each file's, so an edit made
    # in the same second as the last index write is still re-hashed. No index yet: start from none.
    if [[ -f "$gi" ]]; then cp -p "$gi" "$tmp/index" || exit 0; fi
    export GIT_INDEX_FILE="$tmp/index" GIT_OBJECT_DIRECTORY="$tmp/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$objs"
    # Trust stat, ctime included, whatever the user's config says: ctime cannot be set back, so an edit that
    # restores a file's size and mtime is still seen. No fsmonitor or untracked cache to vouch for a file.
    g() { git -c core.trustctime=true -c core.checkStat=default -c core.fsmonitor=false \
              -c core.ignoreStat=false -c core.untrackedCache=false "$@"; }
    # assume-unchanged and skip-worktree would hide an edit from `add`; the old per-file hash saw it. One flag
    # per call: `update-index` given both clears only the first.
    g ls-files -z -v 2>/dev/null | tr '\0' '\n' | sed -n 's/^[a-z] //p' \
      | g update-index --no-assume-unchanged --stdin >/dev/null 2>&1 || :
    g ls-files -z -v 2>/dev/null | tr '\0' '\n' | sed -n 's/^S //p' \
      | g update-index --no-skip-worktree --stdin >/dev/null 2>&1 || :
    # --ignore-errors: an untracked embedded repo with no commit is skipped, as the old `[[ -f ]]` skipped it.
    g add -A --ignore-errors -- . ':(exclude).cascade' >/dev/null 2>&1 || :
    tree="$(g write-tree 2>/dev/null)" || exit 0
    [[ -n "$tree" ]] && echo "t2:$tree" )
}
