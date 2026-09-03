#!/usr/bin/env bash
# Machine-wide install: /barbar, /loop, /audit in every Claude Code session on this machine, and a `bdd` terminal
# command. Project-level files (install.sh) still give a repo its layers; this only makes the commands reachable
# from anywhere and tells you when a repo has no BDD yet.
#   bash install-global.sh            # uses this pack checkout as the pack path
#   BDD_PACK=/path bash install-global.sh
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK="${BDD_PACK:-$SRC}"
CMDS="$HOME/.claude/commands"; BIN="$HOME/.local/bin"; CFG="$HOME/.config/bdd"
mkdir -p "$CMDS" "$BIN" "$CFG"
printf '%s\n' "$PACK" > "$CFG/pack"

guard='If `tests/barbar.sh` does not exist in the current repo, stop and say: "BDD is not installed in this repo — run `bdd install .` (or `bash '"$PACK"'/install.sh .`), commit with `CASCADE_HUMAN=1`, then restart the session." Do nothing else in that case.'
for c in barbar loop audit; do
  { echo "---"; sed -n '2,3p' "$SRC/.claude/commands/$c.md"; echo "---"; echo "$guard"; echo; sed '1,/^---$/{/^---$/!d;}' "$SRC/.claude/commands/$c.md" | sed '1,/^---$/d'; } > "$CMDS/$c.md"
  echo "  + ~/.claude/commands/$c.md (user-level; works from any directory)"
done

cat > "$BIN/bdd" <<'BDD'
#!/usr/bin/env bash
# bdd — Barbaric Driven Development from the terminal.
#   bdd install [repo]   wire the pack into a repo        bdd check [repo]   drift / wiring / gitignore
#   bdd farm             BARBAR k/n                       bdd merge          the gate
#   bdd loop             LOOP k/n (this hop)              bdd audit          AUDIT k/n (stage 10)
#   bdd status           autopilot status                 bdd auto           run the signed list headless (nohup, logs to autopilot.log)
#   bdd upgrade          git pull the pack                bdd pack           print the pack path
set -euo pipefail
PACK="$(cat "$HOME/.config/bdd/pack" 2>/dev/null || true)"
[[ -d "$PACK" ]] || { echo "bdd: pack path missing — re-run install-global.sh" >&2; exit 1; }
here() { [[ -f tests/barbar.sh ]] || { echo "bdd: no BDD in $(pwd) — run: bdd install ." >&2; exit 1; }; }
case "${1:-help}" in
  install) bash "$PACK/install.sh" "${2:-.}" ;;
  check)   bash "$PACK/install.sh" --check "${2:-.}" ;;
  farm)    here; bash tests/barbar.sh ;;
  merge)   here; bash tests/barbar.sh merge ;;
  loop)    here; bash tests/loop.sh ;;
  audit)   here; bash tests/audit.sh ;;
  status)  here; python3 tests/lib/autopilot.py --status . ;;
  auto)    here; command -v claude >/dev/null || { echo "bdd auto needs Claude Code (claude) on PATH" >&2; exit 1; }
           echo "autopilot: $(python3 tests/lib/autopilot.py --status .) — logging to autopilot.log"
           nohup claude -p "/barbar auto" --dangerously-skip-permissions > autopilot.log 2>&1 &
           echo "started (pid $!). Ends at list end, AUTOPILOT HALT, or the cap. tail -f autopilot.log" ;;
  upgrade) git -C "$PACK" pull --ff-only && echo "pack at $(git -C "$PACK" log --oneline -1)" ;;
  pack)    echo "$PACK" ;;
  *)       sed -n '2,8p' "$0" ;;
esac
BDD
chmod +x "$BIN/bdd"; echo "  + ~/.local/bin/bdd"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "  ! add to PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\"  (in ~/.zshrc)";; esac
echo; echo "Pack: $PACK ($(git -C "$PACK" log --oneline -1 2>/dev/null || echo 'not a git checkout'))"
echo "Restart Claude Code sessions to pick up the user-level commands. Inside a repo with BDD: /barbar, /loop, /audit. Elsewhere they tell you to install."
