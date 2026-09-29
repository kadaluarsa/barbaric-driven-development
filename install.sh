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
# AGENTS.md's cascade block: from this heading (the same line in every version) to the end marker, or to the end
# of the file when there is none. `block_sha` hashes only that block, for the manifest's AGENTS.md#bdd-rules entry.
AGENTS_HEAD='# Agent rules — Barbaric Driven Development'
AGENTS_END='<!-- end of the Barbaric Driven Development rules'
block_sha() {
  awk -v h="$AGENTS_HEAD" -v m="$AGENTS_END" '$0 == h {on = 1} on {print} on && index($0, m) == 1 {exit}' "$1" \
    | { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; } | cut -d' ' -f1
}
entry_sha() { case "$1" in *'#bdd-rules') block_sha "$DST/${1%#bdd-rules}" ;; *) sha "$DST/$1" ;; esac; }
entry_file() { echo "$DST/${1%#bdd-rules}"; }
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
    if [[ ! -f "$(entry_file "$rel")" ]]; then echo "MISSING  $rel"; rc=1
    elif [[ "$(entry_sha "$rel")" != "$want" ]]; then echo "DRIFTED  $rel"; rc=1; fi
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
# `keep <dest> [<src>]`: the source defaults to the same path in the pack. Hop state and goal come from
# templates/ instead — the pack's own docs/cascade copies are its live state, not a starting point (t60).
keep() {
  local dest="$1" src="${2:-$1}"
  if [[ -e "$DST/$dest" ]]; then echo "  = $dest (kept)"
  else mkdir -p "$DST/$(dirname "$dest")"; cp -R "$SRC/$src" "$DST/$dest"; echo "  + $dest (yours now)"; fi
}

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
added = refreshed = 0
for event, entries in ours.get("hooks", {}).items():
    have = {h.get("command") for e in hooks.get(event, []) for h in e.get("hooks", [])}
    for entry in entries:
        cmds = {h.get("command") for h in entry.get("hooks", [])}
        if any(c not in have for c in cmds):
            hooks.setdefault(event, []).append(entry); added += 1
            continue
        # Already wired: keep the matcher of an entry that holds only the pack's own commands current, or an
        # upgrade never delivers a changed matcher (t60: SessionStart gained `startup`). An entry that carries
        # any command of the product's own is the product's, and is left exactly as it is.
        for e in hooks.get(event, []):
            mine = {h.get("command") for h in e.get("hooks", [])}
            if mine and mine <= cmds and "matcher" in entry and e.get("matcher") != entry["matcher"]:
                e["matcher"] = entry["matcher"]; refreshed += 1
os.makedirs(os.path.dirname(dst), exist_ok=True)
json.dump(theirs, open(dst, "w"), indent=2); open(dst, "a").write("\n")
print(f"  ~ .claude/settings.json (merged: {added} hook entries added, {refreshed} matchers refreshed, existing settings kept)")
PYMERGE
fi
[[ "$PLUGIN" == 1 ]] || copy .claude/skills
echo "Layer 3 — rules (every agent)"
# An existing AGENTS.md is the product's own: append the cascade rules rather than keeping a file the agent
# reads instead of them (a repo that already had AGENTS.md never received the hop law).
# The cascade block — from AGENTS_HEAD to the end marker, or to the end of the file in installs before 2.1.1 —
# is the pack's and is refreshed on every install; the product's rules above it (and anything after the marker)
# are never touched. The manifest watches the block alone (AGENTS.md#bdd-rules), so editing your own rules is
# not drift and editing the cascade rules is (t60).
agents_watched=1
if [[ -f "$DST/AGENTS.md" ]] && grep -qxF "$AGENTS_HEAD" "$DST/AGENTS.md"; then
  agents_rc=0
  python3 -B - "$SRC/AGENTS.md" "$DST/AGENTS.md" "$DST/.cascade/agents-rules.prev" "$AGENTS_HEAD" "$AGENTS_END" <<'PYAGENTS' || agents_rc=$?
import os, re, sys
src, dst, prev, head, marker = sys.argv[1:6]
block = open(src, encoding="utf-8").read()
block += "" if block.endswith("\n") else "\n"
lines = open(dst, encoding="utf-8").read().splitlines(keepends=True)
start = next(i for i, l in enumerate(lines) if l.rstrip("\n") == head)
end = next((i for i in range(start, len(lines)) if lines[i].startswith(marker)), None)
old = "".join(lines[start:] if end is None else lines[start:end + 1])
after = "" if end is None else "".join(lines[end + 1:])
if old == block:
    print("  = AGENTS.md (cascade rules current)")
    raise SystemExit(0)
if end is None:
    # No marker (every install before 2.1.1): the block runs to the end of the file — unless the team wrote their
    # own rules below it. Every heading any pack version ever had is known; a heading outside that set is the
    # team's, and replacing it would delete their rule from every clone at the next commit. Refuse instead.
    known = {"# Agent rules — Barbaric Driven Development", "## Non-negotiable", "## Commands are scripts, not prose",
             "## Ending every reply", "## Ending a hop reply", "## What enforces this"}
    known |= {l.rstrip("\n") for l in block.splitlines(keepends=True) if re.match(r"#{1,6} ", l)}
    fenced, theirs = False, []
    for l in lines[start:]:
        if l.lstrip().startswith(("```", "~~~")):
            fenced = not fenced
        elif not fenced and re.match(r"#{1,6} ", l) and l.rstrip("\n") not in known:
            theirs.append(l.strip())
    if theirs:
        print(f"  ! AGENTS.md: text below the cascade rules has sections the pack never wrote ({', '.join(theirs[:3])}) —\n"
              f"    left exactly as it is: not refreshed and not watched, so nothing of yours is lost. Move your rules above\n"
              f"    the '{head}' line and re-run install to get the current rules.")
        raise SystemExit(3)
    os.makedirs(os.path.dirname(prev), exist_ok=True)   # everything from the heading down was the block; keep a copy
    open(prev, "w", encoding="utf-8").write(old)
open(dst, "w", encoding="utf-8").write("".join(lines[:start]) + block + after)
print("  ~ AGENTS.md (cascade rules refreshed; your rules above kept" + (
    "; the replaced text, which ran to the end of the file, is in .cascade/agents-rules.prev)" if end is None
    else " and anything after the end marker)"))
PYAGENTS
  [[ "$agents_rc" -eq 0 ]] || agents_watched=0
elif [[ -f "$DST/AGENTS.md" ]] && grep -q 'Barbaric Driven Development' "$DST/AGENTS.md"; then
  echo "  ! AGENTS.md mentions the cascade but has no '$AGENTS_HEAD' line — left as is, not refreshed or watched"
elif [[ -f "$DST/AGENTS.md" ]]; then
  { echo; echo "---"; echo; cat "$SRC/AGENTS.md"; } >> "$DST/AGENTS.md"; echo "  ~ AGENTS.md (cascade rules appended; your own rules kept above)"
else
  cp "$SRC/AGENTS.md" "$DST/AGENTS.md"; echo "  + AGENTS.md"
fi
[[ "$agents_watched" -eq 1 ]] && grep -qxF "$AGENTS_HEAD" "$DST/AGENTS.md" && shipped+=("AGENTS.md#bdd-rules")
keep .github/copilot-instructions.md; keep .cursor/rules/cascade.mdc
# Existing CLAUDE.md / GEMINI.md: append the import rather than keeping a file that never loads the rules.
for shim in CLAUDE.md GEMINI.md; do
  if [[ -f "$DST/$shim" ]]; then
    grep -q '@AGENTS.md' "$DST/$shim" && echo "  = $shim (already imports AGENTS.md)" || { printf '\n@AGENTS.md\n' >> "$DST/$shim"; echo "  ~ $shim (appended @AGENTS.md)"; }
  else keep "$shim"; fi   # product-owned from the first install: never in the manifest
done
copy CONTROL-LINE.md; copy docs/cascade/product-e2e-cascade.md; for st in "$SRC"/docs/cascade/stages/*.md; do copy "docs/cascade/stages/$(basename "$st")"; done; copy docs/cascade/product-e2e-gre-pipeline.md; copy docs/cascade/skill-binding.md   # pack-owned: the seam and T36 read it, so it must track the pack
keep docs/cascade/envelope.md; keep docs/cascade/goal.md templates/goal.md
# Hop state moved out of the envelope so the law history stays readable. Creating hop-state.md in a repo
# whose envelope still carries CURRENT_HOP would silently reset a running hop to NONE — the readers fall
# back to the envelope when the file is absent, so an existing repo is safest left exactly as it is.
if grep -q '^CURRENT_HOP:' "$DST/docs/cascade/envelope.md" 2>/dev/null; then
  echo "  = docs/cascade/envelope.md still holds the hop state (pre-split repo) — left as is, everything reads it"
  echo "    to split it later: move the CURRENT_HOP/STAGE/SLICE and AUTOPILOT lines into docs/cascade/hop-state.md"
  echo "    between hops, and sign that commit (bash tests/sign.sh)"
else
  keep docs/cascade/hop-state.md templates/hop-state.md
fi

# Installs before 2.1.1 copied the pack's live hop state and goal into the product (t60). The AUTOPILOT line is
# the human's, and goal.md is the agent's next EXECUTE's: name what looks leaked and how to fix it, never edit.
warn_leaked() {
  local hs="$DST/docs/cascade/hop-state.md" entry st sl path
  [[ -f "$hs" ]] || hs="$DST/docs/cascade/envelope.md"
  if [[ -f "$hs" ]]; then
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      st="${entry%% *}"; sl="${entry#* }"
      [[ "$st" == 05b && "$sl" != "$st" ]] || continue
      [[ -f "$DST/docs/cascade/05b-$sl.md" ]] && continue
      grep -q "^- $sl:" "$DST/docs/cascade/05b-briefs.md" 2>/dev/null && continue
      echo "  ! LEAKED? ${hs#"$DST"/}: AUTOPILOT lists 05b '$sl', which has neither a spec nor a brief here —"
      echo "    likely the pack's own list, copied by an install before 2.1.1. The line is yours: clear it by approving"
      echo "    the dialog when your agent proposes it, or edit it and run  bash tests/sign.sh"
    done < <(sed -n 's/^AUTOPILOT: *//p' "$hs" | head -1 | tr ',' '\n' | sed 's/^ *//;s/ *$//')
  fi
  if [[ -f "$DST/docs/cascade/goal.md" ]]; then
    while IFS= read -r path; do
      [[ -n "$path" && ! -e "$DST/$path" ]] || continue
      echo "  ! LEAKED? docs/cascade/goal.md: VALIDATOR names $path, which does not exist here — your agent rewrites"
      echo "    goal.md at the next EXECUTE hop, or empty it now"
    done < <(sed -n 's/^VALIDATOR: *bash  *\([^ ]*\).*/\1/p' "$DST/docs/cascade/goal.md")
  fi
}
warn_leaked

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
for pat in '__pycache__/' '*.pyc' '.cascade/decisions.log' '.cascade/loop-receipt' '.cascade/punch-rounds' '.cascade/agents-rules.prev'; do grep -qxF "$pat" "$DST/.gitignore" 2>/dev/null || echo "$pat" >> "$DST/.gitignore"; done
find "$DST/.claude/hooks" "$DST/tests/lib" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
mkdir -p "$DST/.cascade"
{ echo "version $VERSION"; echo "mode $([[ "$PLUGIN" == 1 ]] && echo plugin || echo standalone)"; [[ "$PLUGIN" == 1 ]] && echo "plugin_root $SRC"; for rel in "${shipped[@]}"; do [[ -f "$(entry_file "$rel")" ]] && echo "$(entry_sha "$rel") $rel"; done; } > "$MANIFEST"
echo "  + .cascade/manifest ($VERSION, $([[ "$PLUGIN" == 1 ]] && echo plugin || echo standalone) mode, ${#shipped[@]} shipped files) — verify later with: install.sh --check"
echo
echo "Next:"
echo "  1. Name your laws: run /barbar init (or: bdd init) to scan this repo and get proposals in docs/cascade/proposals.md,"
echo "     then copy the ones you accept into docs/cascade/envelope.md and commit with CASCADE_HUMAN=1."
echo "  2. Protect main (see INTEGRATION.md, Layer 0)."
echo "  3. bash tests/barbar.sh   -> BARBAR n/n"
