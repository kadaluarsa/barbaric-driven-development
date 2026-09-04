#!/usr/bin/env bash
# bdd plugin hook runner. Claude Code substitutes ${CLAUDE_PLUGIN_ROOT} in hooks.json; this script turns it into
# BDD_PLUGIN_ROOT for the hook scripts (the seam uses it to offer install.sh in a repo without BDD).
export BDD_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$BDD_PLUGIN_ROOT/.claude/hooks/$1.py"
