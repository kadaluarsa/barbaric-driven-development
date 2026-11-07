#!/usr/bin/env bash
# CI's drift check (t96): the shipped enforcement files match the committed .cascade/manifest.
# install.sh --check needs the pack; a product's CI has no path to it. Prints DRIFT n/a in the pack, and
# never reads .cascade/disabled/: CI is Layer 0, which a disable must not reach.
# Limit: this compares with the repo's own manifest. A file and its hash changed together, or a softened
# copy of this script, needs a comparison with the pack; `bdd check .` makes that one.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/.cascade/manifest"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

if [[ ! -f "$MANIFEST" ]]; then
  if python3 -B -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("name") == "bdd" else 1)' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null; then
    echo "DRIFT n/a: this is the pack, which has no manifest"
    exit 0
  fi
  echo "DRIFT: no .cascade/manifest; run install.sh and commit the result"
  exit 1
fi

rc=0; n=0
while IFS=' ' read -r want rel; do
  [[ "$want" == version || "$want" == mode || "$want" == plugin_root ]] && continue
  [[ "$rel" == AGENTS.md ]] && continue   # copied once when absent; the product owns it after that
  n=$((n+1))
  if [[ ! -f "$ROOT/$rel" ]]; then echo "MISSING  $rel"; rc=1
  elif [[ "$(sha "$ROOT/$rel")" != "$want" ]]; then echo "DRIFTED  $rel"; rc=1; fi
done < "$MANIFEST"
for rel in .githooks .claude/hooks .claude/settings.json tests/lib .cascade; do
  if ( cd "$ROOT" && git check-ignore -q --no-index "$rel" 2>/dev/null ); then echo "IGNORED  $rel"; rc=1; fi
done
if [[ "$(sed -n 's/^mode //p' "$MANIFEST" | head -1)" != plugin ]] \
  && ! python3 -B -c "import json,sys; d=json.load(open(sys.argv[1])); h=d.get('hooks',{}); sys.exit(0 if all(any('.claude/hooks/'+n in json.dumps(h.get(e,[])) for n in ns) for e,ns in {'PreToolUse':['hop_guard.py','bash_guard.py'],'Stop':['stop_guard.py'],'SessionStart':['preserve.py'],'UserPromptSubmit':['seam.py']}.items()) else 1)" "$ROOT/.claude/settings.json" 2>/dev/null; then
  echo "UNWIRED  .claude/settings.json is missing a cascade hook entry"; rc=1
fi
[[ "$rc" -eq 0 ]] && echo "DRIFT clean: $n shipped files match .cascade/manifest" || echo "DRIFT detected: a shipped enforcement file changed, vanished, is unwired, or is gitignored (I18)"
exit "$rc"
