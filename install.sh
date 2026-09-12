#!/usr/bin/env bash
# Wire this pack into a product repo. Idempotent.
#   bash /path/to/barbaric-driven-development/install.sh [target-repo]
#   bash /path/to/barbaric-driven-development/install.sh --check [target-repo]   # drift: exit 1 if any
#   shipped file differs from the pack (a softened hook, a deleted test), or the pack version changed
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Same repository, not same path: a linked worktree of the pack resolves to a different working
# tree but the same common git dir. Comparing paths once let an install strip Layer 2 out of the
# pack's own repo — see T54.
repo_id() { git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$1"; }
MODE=install; [[ "${1:-}" == "--check" ]] && { MODE=check; shift; }
# Plugin mode: the bdd plugin already wires hooks, commands and the skill machine-wide, so the repo gets only
# the durable layers (git hooks, tests, envelope, rules). Detected automatically; force with --plugin / --no-plugin.
PLUGIN=auto; case "${1:-}" in --plugin) PLUGIN=1; shift ;; --no-plugin) PLUGIN=0; shift ;; esac
DST="$(cd "${1:-.}" && pwd)"
git -C "$DST" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $DST" >&2; exit 1; }   # worktrees have a .git *file*
VERSION="$(cat "$SRC/VERSION" 2>/dev/null || echo unknown)"
if [[ "$PLUGIN" == auto ]]; then
  if [[ -n "${BDD_PLUGIN_ROOT:-}" ]] || ls -d "$HOME"/.claude/plugins/cache/*/bdd* >/dev/null 2>&1 || grep -q '"bdd' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null; then PLUGIN=1; else PLUGIN=0; fi
fi
MANIFEST="$DST/.cascade/manifest"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
shipped=()
record() { local rel="$1"; if [[ -d "$DST/$rel" ]]; then while IFS= read -r f; do shipped+=("${f#"$DST"/}"); done < <(find "$DST/$rel" -type f | sort); else shipped+=("$rel"); fi; }

if [[ "$MODE" == check ]]; then
  if [[ -f "$DST/.cascade/disabled/state.json" ]]; then
    echo "DISABLED: BDD is stood down in this repo — Layers 1 and 2 are off on purpose, not drifted."
    echo "  Layer 0 (CI + branch protection) is untouched: this work still goes red in CI and cannot merge."
    echo "  Re-enable with:  bdd enable"
    exit 0
  fi
  [[ -f "$MANIFEST" ]] || { echo "DRIFT: no $MANIFEST — run install.sh first"; exit 1; }
  installed_v="$(head -1 "$MANIFEST" | sed -n 's/^version //p')"
  rc=0
  [[ "$installed_v" == "$VERSION" ]] || { echo "VERSION: this repo has $installed_v, the pack is $VERSION — refresh with:"; echo "  bash $SRC/install.sh . && git add -A && git commit -m 'cascade: update pack to $VERSION'"; rc=1; }
  mode="$(sed -n 's/^mode //p' "$MANIFEST" | head -1)"
  while IFS=' ' read -r want rel; do
    [[ "$want" == version || "$want" == mode || "$want" == plugin_root ]] && continue
    if [[ ! -f "$DST/$rel" ]]; then echo "MISSING  $rel"; rc=1
    elif [[ "$(sha "$DST/$rel")" != "$want" ]]; then echo "DRIFTED  $rel"; rc=1; fi
  done < "$MANIFEST"
  for rel in .githooks .claude/hooks .claude/settings.json tests/lib .cascade; do
    if ( cd "$DST" && git check-ignore -q "$rel" 2>/dev/null ); then echo "IGNORED  $rel (gitignored — not in the repo, not in CI)"; rc=1; fi
  done
  if [[ "$mode" == plugin ]]; then :   # hooks come from the plugin, not this repo
  elif ! python3 -B -c "import json,sys; d=json.load(open(sys.argv[1])); h=d.get('hooks',{}); sys.exit(0 if all(any('.claude/hooks/'+n in json.dumps(h.get(e,[])) for n in ns) for e,ns in {'PreToolUse':['hop_guard.py','bash_guard.py'],'Stop':['stop_guard.py'],'SessionStart':['preserve.py'],'UserPromptSubmit':['seam.py']}.items()) else 1)" "$DST/.claude/settings.json" 2>/dev/null; then
    echo "UNWIRED  .claude/settings.json is missing a cascade hook entry — Layer 2 is off"; rc=1
  fi
  [[ "$rc" -eq 0 ]] && echo "CASCADE $VERSION ($mode): no drift in $(grep -cE '^[0-9a-f]{64} ' "$MANIFEST") shipped files; hooks $([[ "$mode" == plugin ]] && echo 'from the plugin' || echo wired); nothing gitignored" || echo "CASCADE drift detected — a shipped enforcement file changed, vanished, is unwired, or is gitignored (I18)"
  exit "$rc"
fi

# Pack-owned files: replaced on every install (idempotent; a re-run never nests dirs or leaves stale files).
copy() { mkdir -p "$DST/$(dirname "$1")"; rm -rf "${DST:?}/$1"; cp -RL "$SRC/$1" "$DST/$1"; echo "  + $1"; record "$1"; }   # -L: the pack keeps commands/ and skills/ as links
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
if [[ "$PLUGIN" == 1 && ( "$DST" == "$SRC" || "$(repo_id "$DST")" == "$(repo_id "$SRC")" ) ]]; then
  # The pack repo is Layer 2's source, not a consumer of it: .claude/hooks/*.py are the files packaged into
  # the plugin. Stripping them here deletes the product — every later plugin install would ship no Layer 2,
  # standalone installs would have nothing to copy, and the pack could no longer test itself.
  echo "  = this is the pack itself — Layer 2 stays; plugin mode strips hooks from products, never from the source"
elif [[ "$PLUGIN" == 1 ]]; then
  echo "  = hooks provided by the bdd plugin — none wired into this repo"
  # A repo installed standalone earlier: strip our hook entries so the same call is not judged twice; keep theirs.
  rm -rf "$DST/.claude/hooks" "$DST/.claude/skills/cascade-farm"
  copy .claude/commands   # the plugin namespaces its own as /bdd:barbar; this repo copy makes plain /barbar work
  if [[ -f "$DST/.claude/settings.json" ]]; then python3 -B - "$DST/.claude/settings.json" <<'PYSTRIP'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); hooks = d.get("hooks", {}); n = 0
for ev in list(hooks):
    keep = [e for e in hooks[ev] if not any(".claude/hooks/" in h.get("command", "") and "cascade" not in h.get("command", "") and any(x in h.get("command", "") for x in ("hop_guard", "bash_guard", "stop_guard", "preserve.py", "seam.py", "sign_ok")) for h in e.get("hooks", []))]
    n += len(hooks[ev]) - len(keep); hooks[ev] = keep
    if not hooks[ev]: del hooks[ev]
if not hooks: d.pop("hooks", None)
json.dump(d, open(p, "w"), indent=2); open(p, "a").write("\n")
print(f"  ~ .claude/settings.json ({n} project-level cascade hook entries removed; the plugin provides them)")
PYSTRIP
  fi
else
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
fi
[[ "$PLUGIN" == 1 ]] || copy .claude/skills
echo "Layer 3 — rules (every agent)"
# An existing AGENTS.md is the product's own: append the cascade rules rather than keeping a file the agent
# reads instead of them (a repo that already had AGENTS.md never received the hop law).
if [[ -f "$DST/AGENTS.md" ]]; then
  if grep -q 'Barbaric Driven Development' "$DST/AGENTS.md"; then echo "  = AGENTS.md (already carries the cascade rules)"
  else { echo; echo "---"; echo; cat "$SRC/AGENTS.md"; } >> "$DST/AGENTS.md"; echo "  ~ AGENTS.md (cascade rules appended; your own rules kept above)"; fi
else copy AGENTS.md; fi
keep .github/copilot-instructions.md; keep .cursor/rules/cascade.mdc
# Existing CLAUDE.md / GEMINI.md: append the import rather than keeping a file that never loads the rules.
for shim in CLAUDE.md GEMINI.md; do
  if [[ -f "$DST/$shim" ]]; then
    grep -q '@AGENTS.md' "$DST/$shim" && echo "  = $shim (already imports AGENTS.md)" || { printf '\n@AGENTS.md\n' >> "$DST/$shim"; echo "  ~ $shim (appended @AGENTS.md)"; }
  else keep "$shim"; fi   # product-owned from the first install: never in the manifest
done
copy CONTROL-LINE.md; copy docs/cascade/product-e2e-cascade.md; for st in "$SRC"/docs/cascade/stages/*.md; do copy "docs/cascade/stages/$(basename "$st")"; done; copy docs/cascade/product-e2e-gre-pipeline.md; copy docs/cascade/skill-binding.md   # pack-owned: the seam and T36 read it, so it must track the pack
keep docs/cascade/envelope.md; keep docs/cascade/goal.md
# Hop state moved out of the envelope so the law history stays readable. Creating hop-state.md in a repo
# whose envelope still carries CURRENT_HOP would silently reset a running hop to NONE — the readers fall
# back to the envelope when the file is absent, so an existing repo is safest left exactly as it is.
if grep -q '^CURRENT_HOP:' "$DST/docs/cascade/envelope.md" 2>/dev/null; then
  echo "  = docs/cascade/envelope.md still holds the hop state (pre-split repo) — left as is, everything reads it"
  echo "    to split it later: move the CURRENT_HOP/STAGE/SLICE and AUTOPILOT lines into docs/cascade/hop-state.md"
  echo "    between hops, and sign that commit (bash tests/sign.sh)"
else
  keep docs/cascade/hop-state.md
fi

# Enforcement that git ignores never reaches teammates or CI. Say so, loudly, and in --check.
ignored_warn() {
  local bad=0
  for rel in .githooks .claude/hooks .claude/commands .claude/settings.json tests/lib .cascade docs/cascade/envelope.md; do
    if ( cd "$DST" && git check-ignore -q "$rel" 2>/dev/null ); then echo "  ! IGNORED by .gitignore: $rel — this layer will not be committed (I18). Un-ignore it."; bad=1; fi
  done
  return "$bad"
}
ignored_warn || true
# Python bytecode from hooks/lib must never be staged (a stray .pyc once tripped the EDIT scan).
# The decision log is a local record, never committed: an autopilot run must not dirty the tree it audits.
for pat in '__pycache__/' '*.pyc' '.cascade/decisions.log' '.cascade/loop-receipt' '.cascade/punch-rounds'; do grep -qxF "$pat" "$DST/.gitignore" 2>/dev/null || echo "$pat" >> "$DST/.gitignore"; done
find "$DST/.claude/hooks" "$DST/tests/lib" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
mkdir -p "$DST/.cascade"
{ echo "version $VERSION"; echo "mode $([[ "$PLUGIN" == 1 ]] && echo plugin || echo standalone)"; [[ "$PLUGIN" == 1 ]] && echo "plugin_root $SRC"; for rel in "${shipped[@]}"; do [[ -f "$DST/$rel" ]] && echo "$(sha "$DST/$rel") $rel"; done; } > "$MANIFEST"
echo "  + .cascade/manifest ($VERSION, $([[ "$PLUGIN" == 1 ]] && echo plugin || echo standalone) mode, ${#shipped[@]} shipped files) — verify later with: install.sh --check"
echo
echo "Next:"
echo "  1. Name your laws: run /barbar init (or: bdd init) to scan this repo and get proposals in docs/cascade/proposals.md,"
echo "     then copy the ones you accept into docs/cascade/envelope.md and commit with CASCADE_HUMAN=1."
echo "  2. Protect main (see INTEGRATION.md, Layer 0)."
echo "  3. bash tests/barbar.sh   -> BARBAR n/n"
