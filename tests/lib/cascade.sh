#!/usr/bin/env bash
# Shared cascade state reader. Sourced by .githooks/*, .claude/hooks/*, tests/loop.sh.
# Single source of truth for "what hop are we on" and "what is product code".

cascade_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

# CASCADE_ENVELOPE lets a rule evaluate against a specific envelope (autopilot checks the pre-edge state).
cascade_envelope() { echo "${CASCADE_ENVELOPE:-$(cascade_root)/docs/cascade/envelope.md}"; }

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

# Every declared D# line as "D#|law|validator|twin" (missing fields empty). Declared != in force.
cascade_dsharp_declared() {
  local env_file; env_file="$(cascade_envelope)"
  [[ -f "$env_file" ]] || return 0
  tr -d '\r' < "$env_file" 2>/dev/null | grep -E '^D[0-9]+[[:space:]]*\|' | grep -v '{{' | while IFS='|' read -r id law val twin _rest; do   # {{…}} = template placeholder, not a law
    trim() { echo "${1:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }
    val="$(trim "$val")"; twin="$(trim "$twin")"
    case "$val"  in TODO|none|"") val="" ;; esac
    case "$twin" in TODO|none|"") twin="" ;; esac
    echo "$(echo "$id" | tr -d '[:space:]')|$(trim "$law")|$val|$twin"
  done
}

# In force (I13 + red twin): validator AND twin present. Emits "D#|law|validator|twin".
cascade_dsharp_in_force() {
  cascade_dsharp_declared | while IFS='|' read -r id law val twin; do
    [[ -n "$val" && -n "$twin" ]] && echo "$id|$law|$val|$twin"
  done
}

# Declared but not provable: no validator or no red twin. Emits "D#|law|missing".
cascade_dsharp_unproven() {
  cascade_dsharp_declared | while IFS='|' read -r id law val twin; do
    if [[ -z "$val" ]]; then echo "$id|$law|no validator"
    elif [[ -z "$twin" ]]; then echo "$id|$law|no red twin"
    fi
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
