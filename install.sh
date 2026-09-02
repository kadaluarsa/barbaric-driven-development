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
  for rel in .githooks .claude/hooks .claude/settings.json tests/lib .cascade; do
    if ( cd "$DST" && git check-ignore -q "$rel" 2>/dev/null ); then echo "IGNORED  $rel (gitignored — not in the repo, not in CI)"; rc=1; fi
  done
  if ! python3 -c "import json,sys; d=json.load(open(sys.argv[1])); h=d.get('hooks',{}); sys.exit(0 if all(any('.claude/hooks/'+n in json.dumps(h.get(e,[])) for n in ns) for e,ns in {'PreToolUse':['hop_guard.py','bash_guard.py'],'Stop':['stop_guard.py'],'SessionStart':['preserve.py'],'UserPromptSubmit':['seam.py']}.items()) else 1)" "$DST/.claude/settings.json" 2>/dev/null; then
    echo "UNWIRED  .claude/settings.json is missing a cascade hook entry — Layer 2 is off"; rc=1
  fi
  [[ "$rc" -eq 0 ]] && echo "CASCADE $VERSION: no drift in $(($(wc -l < "$MANIFEST") - 1)) shipped files; hooks wired; nothing gitignored" || echo "CASCADE drift detected — a shipped enforcement file changed, vanished, is unwired, or is gitignored (I18)"
  exit "$rc"
fi

# Pack-owned files: replaced on every install (idempotent; a re-run never nests dirs or leaves stale files).
copy() { mkdir -p "$DST/$(dirname "$1")"; rm -rf "${DST:?}/$1"; cp -R "$SRC/$1" "$DST/$1"; echo "  + $1"; record "$1"; }
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
copy .claude/hooks; copy .claude/commands
# A product usually already has .claude/settings.json: merge our hook entries in, never overwrite, never skip.
python3 - "$SRC/.claude/settings.json" "$DST/.claude/settings.json" <<'PYMERGE'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
ours = json.load(open(src))
try: theirs = json.load(open(dst))
except (OSError, ValueError): theirs = {}
hooks = theirs.setdefault("hooks", {})
added = 0
for event, entries in ours.get("hooks", {}).items():
    have = {h.get("command") for e in hooks.get(event, []) for h in e.get("hooks", [])}
    for entry in entries:
        if any(h.get("command") not in have for h in entry.get("hooks", [])):
            hooks.setdefault(event, []).append(entry); added += 1
os.makedirs(os.path.dirname(dst), exist_ok=True)
json.dump(theirs, open(dst, "w"), indent=2); open(dst, "a").write("\n")
print(f"  ~ .claude/settings.json (merged: {added} hook entries added, existing settings kept)")
PYMERGE
copy .claude/skills
echo "Layer 3 — rules (every agent)"
keep AGENTS.md; keep .github/copilot-instructions.md; keep .cursor/rules/cascade.mdc
# Existing CLAUDE.md / GEMINI.md: append the import rather than keeping a file that never loads the rules.
for shim in CLAUDE.md GEMINI.md; do
  if [[ -f "$DST/$shim" ]]; then
    grep -q '@AGENTS.md' "$DST/$shim" && echo "  = $shim (already imports AGENTS.md)" || { printf '\n@AGENTS.md\n' >> "$DST/$shim"; echo "  ~ $shim (appended @AGENTS.md)"; }
  else keep "$shim"; fi   # product-owned from the first install: never in the manifest
done
copy CONTROL-LINE.md; copy docs/cascade/product-e2e-cascade.md; copy docs/cascade/product-e2e-gre-pipeline.md; keep docs/cascade/skill-binding.md
keep docs/cascade/envelope.md; keep docs/cascade/goal.md

# Enforcement that git ignores never reaches teammates or CI. Say so, loudly, and in --check.
ignored_warn() {
  local bad=0
  for rel in .githooks .claude/hooks .claude/commands .claude/settings.json tests/lib .cascade docs/cascade/envelope.md; do
    if ( cd "$DST" && git check-ignore -q "$rel" 2>/dev/null ); then echo "  ! IGNORED by .gitignore: $rel — this layer will not be committed (I18). Un-ignore it."; bad=1; fi
  done
  return "$bad"
}
ignored_warn || true
mkdir -p "$DST/.cascade"
{ echo "version $VERSION"; for rel in "${shipped[@]}"; do [[ -f "$DST/$rel" ]] && echo "$(sha "$DST/$rel") $rel"; done; } > "$MANIFEST"
echo "  + .cascade/manifest ($VERSION, ${#shipped[@]} shipped files) — verify later with: install.sh --check"
echo
echo "Next:"
echo "  1. Fill docs/cascade/envelope.md <EDIT> tags. Name your D# with validator commands."
echo "  2. Protect main (see INTEGRATION.md, Layer 0)."
echo "  3. bash tests/barbar.sh   -> BARBAR n/n"
