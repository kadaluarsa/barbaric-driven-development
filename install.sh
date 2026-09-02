#!/usr/bin/env bash
# Wire this pack into a product repo. Idempotent.
#   bash /path/to/barbaric-driven-development/install.sh [target-repo]
#   bash /path/to/barbaric-driven-development/install.sh --check [target-repo]   # drift: exit 1 if any
#   shipped file differs from the pack (a softened hook, a deleted test), or the pack version changed
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=install; [[ "${1:-}" == "--check" ]] && { MODE=check; shift; }
DST="$(cd "${1:-.}" && pwd)"
[[ -d "$DST/.git" ]] || { echo "not a git repo: $DST" >&2; exit 1; }
VERSION="$(cat "$SRC/VERSION" 2>/dev/null || echo unknown)"
MANIFEST="$DST/.cascade/manifest"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
shipped=()
record() { local rel="$1"; if [[ -d "$DST/$rel" ]]; then while IFS= read -r f; do shipped+=("${f#"$DST"/}"); done < <(find "$DST/$rel" -type f | sort); else shipped+=("$rel"); fi; }

if [[ "$MODE" == check ]]; then
  [[ -f "$MANIFEST" ]] || { echo "DRIFT: no $MANIFEST — run install.sh first"; exit 1; }
  installed_v="$(head -1 "$MANIFEST" | sed -n 's/^version //p')"
  rc=0
  [[ "$installed_v" == "$VERSION" ]] || { echo "VERSION: installed $installed_v, pack $VERSION — re-run install.sh"; rc=1; }
  while IFS=' ' read -r want rel; do
    [[ "$want" == version ]] && continue
    if [[ ! -f "$DST/$rel" ]]; then echo "MISSING  $rel"; rc=1
    elif [[ "$(sha "$DST/$rel")" != "$want" ]]; then echo "DRIFTED  $rel"; rc=1; fi
  done < "$MANIFEST"
  [[ "$rc" -eq 0 ]] && echo "CASCADE $VERSION: no drift in $(($(wc -l < "$MANIFEST") - 1)) shipped files" || echo "CASCADE drift detected — a shipped enforcement file changed or vanished (I18)"
  exit "$rc"
fi

copy() { mkdir -p "$DST/$(dirname "$1")"; cp -R "$SRC/$1" "$DST/$1"; echo "  + $1"; record "$1"; }
# Templates the product owns after install (envelope, goal, shims, settings): copied once, never in the manifest.
keep() { if [[ -e "$DST/$1" ]]; then echo "  = $1 (kept)"; else mkdir -p "$DST/$(dirname "$1")"; cp -R "$SRC/$1" "$DST/$1"; echo "  + $1 (yours now)"; fi; }

echo "Layer 0 — CI + branch protection"
copy .github/workflows/control-line.yml
echo "Layer 1 — git hooks (every agent)"
copy .githooks; copy tests/lib
for f in "$SRC"/tests/*.sh "$SRC"/tests/*.py; do copy "tests/$(basename "$f")"; done   # every script, so a new one is never forgotten
copy evals/hops; copy evals/fixtures; copy evals/README.md   # the farm's fixtures — not the pack's spike or recorded probe runs
( cd "$DST" && git config core.hooksPath .githooks ) && echo "  git config core.hooksPath .githooks"
echo "Layer 2 — agent hooks (Claude Code)"
copy .claude/hooks; copy .claude/commands; keep .claude/settings.json
copy .claude/skills
echo "Layer 3 — rules (every agent)"
keep AGENTS.md; keep CLAUDE.md; keep GEMINI.md; keep .github/copilot-instructions.md; keep .cursor/rules/cascade.mdc
copy CONTROL-LINE.md; copy docs/cascade/product-e2e-cascade.md; copy docs/cascade/product-e2e-gre-pipeline.md; keep docs/cascade/skill-binding.md
keep docs/cascade/envelope.md; keep docs/cascade/goal.md

mkdir -p "$DST/.cascade"
{ echo "version $VERSION"; for rel in "${shipped[@]}"; do [[ -f "$DST/$rel" ]] && echo "$(sha "$DST/$rel") $rel"; done; } > "$MANIFEST"
echo "  + .cascade/manifest ($VERSION, ${#shipped[@]} shipped files) — verify later with: install.sh --check"
echo
echo "Next:"
echo "  1. Fill docs/cascade/envelope.md <EDIT> tags. Name your D# with validator commands."
echo "  2. Protect main (see INTEGRATION.md, Layer 0)."
echo "  3. bash tests/barbar.sh   -> BARBAR n/n"
