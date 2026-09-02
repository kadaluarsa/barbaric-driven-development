#!/usr/bin/env bash
# Shared cascade state reader. Sourced by .githooks/*, .claude/hooks/*, tests/loop.sh.
# Single source of truth for "what hop are we on" and "what is product code".

cascade_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

cascade_envelope() { echo "$(cascade_root)/docs/cascade/envelope.md"; }

# GENERATE | EXECUTE | NONE
cascade_hop() {
  local env_file; env_file="$(cascade_envelope)"
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
  local env_file; env_file="$(cascade_envelope)"
  [[ -f "$env_file" ]] || { echo ""; return; }
  grep -m1 -E '^CURRENT_STAGE:' "$env_file" 2>/dev/null \
    | sed -E 's/^CURRENT_STAGE:[[:space:]]*//' | tr -d '[:space:]'
}

# Emit "D#|law|validator" for every D# that has a validator command (= in force, I13).
cascade_dsharp_in_force() {
  local env_file; env_file="$(cascade_envelope)"
  [[ -f "$env_file" ]] || return 0
  grep -E '^D[0-9]+[[:space:]]*\|' "$env_file" 2>/dev/null | while IFS='|' read -r id law val; do
    val="$(echo "$val" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -z "$val" || "$val" == "TODO" || "$val" == "none" ]] && continue
    echo "$(echo "$id" | tr -d '[:space:]')|$(echo "$law" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')|$val"
  done
}

# Paths writable during a GENERATE hop. Override with docs/cascade/generate-writable.txt.
cascade_generate_writable() {
  local root over
  root="$(cascade_root)"; over="$root/docs/cascade/generate-writable.txt"
  if [[ -f "$over" ]]; then
    grep -vE '^[[:space:]]*(#|$)' "$over"
  else
    printf '%s\n' 'docs/' 'evals/' 'tests/' '.githooks/' '.claude/' '.github/' '.cursor/' '.windsurf/' '.continue/' '*.md'
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
