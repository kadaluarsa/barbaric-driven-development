#!/usr/bin/env bash
# bdd plugin hook runner. Claude Code and Codex provide CLAUDE_PLUGIN_ROOT; Codex also provides PLUGIN_ROOT.
# The runner identifies the host so shared hooks emit only that host's supported response contract.
if [[ -n "${PLUGIN_ROOT:-}" ]]; then export BDD_HOOK_HOST=codex; else export BDD_HOOK_HOST=claude; fi
export BDD_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$BDD_PLUGIN_ROOT/.claude/hooks/$1.py"
