#!/usr/bin/env bash
# Wire this pack into a product repo. Idempotent.
#   bash /path/to/barbaric-driven-development/install.sh [target-repo]
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST="$(cd "${1:-.}" && pwd)"
[[ -d "$DST/.git" ]] || { echo "not a git repo: $DST" >&2; exit 1; }

copy() { mkdir -p "$DST/$(dirname "$1")"; cp -R "$SRC/$1" "$DST/$1"; echo "  + $1"; }
keep() { [[ -e "$DST/$1" ]] && echo "  = $1 (kept)" || copy "$1"; }

echo "Layer 0 — CI + branch protection"
copy .github/workflows/control-line.yml
echo "Layer 1 — git hooks (every agent)"
copy .githooks; copy tests/lib; copy tests/loop.sh; copy tests/barbar.sh
copy tests/score_hops.py; copy tests/control-line.sh; copy tests/i17_dune.sh; copy tests/enforcement.sh
copy evals
( cd "$DST" && git config core.hooksPath .githooks ) && echo "  git config core.hooksPath .githooks"
echo "Layer 2 — agent hooks (Claude Code)"
copy .claude/hooks; copy .claude/commands; keep .claude/settings.json
copy .claude/skills
echo "Layer 3 — rules (every agent)"
keep AGENTS.md; keep CLAUDE.md; keep GEMINI.md; keep .github/copilot-instructions.md; keep .cursor/rules/cascade.mdc
copy CONTROL-LINE.md; copy docs/cascade/product-e2e-cascade.md; copy docs/cascade/product-e2e-gre-pipeline.md
keep docs/cascade/envelope.md; keep docs/cascade/goal.md

echo
echo "Next:"
echo "  1. Fill docs/cascade/envelope.md <EDIT> tags. Name your D# with validator commands."
echo "  2. Protect main (see INTEGRATION.md, Layer 0)."
echo "  3. bash tests/barbar.sh   -> BARBAR n/n"
