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
