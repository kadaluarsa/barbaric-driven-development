#!/usr/bin/env bash
# `bdd doctor` — is the pipeline working, not just intact?
#
# `install.sh --check` answers one question well: do the shipped files still match the pack — version,
# per-file SHA, nothing gitignored, hooks named in settings.json. That is the pack's *files*. It is not
# the pack *working*. A fresh clone carries every byte correctly and still has a dead Layer 1, because
# `core.hooksPath` is git config and does not travel with the tree.
#
# This walks I18's layer order — lowest layer that can enforce, first — and reports one line per check.
# It COMPOSES: install.sh --check, dsharp_strength.sh, reads_manifest.sh, stage_templates.sh and
# barbar.sh own their verdicts and this quotes them. Re-deriving a verdict it does not own is how two
# sources of truth start disagreeing, and the one that disagrees with the merge gate is the dangerous one.
#
# Doctor runs BECAUSE something may be wrong, so a missing file is a finding, never a stack trace. Every
# check is independent; one red never skips the rest.
#
# DOCTOR k/n: k green, n checks that RAN. A check that cannot run here prints `skipped` with a reason and
# is left out of n, so a skip can never inflate the score. Exit 0 only when k == n.
#
# Red twins: DOCTOR_MUTANT=hookspath|layer0|hopstate breaks that check and the run MUST go red.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

MUTANT="${DOCTOR_MUTANT:-}"
FAST="${DOCTOR_FAST:-}"
k=0; n=0; skipped=0

green() { n=$((n + 1)); k=$((k + 1)); printf '  %-4s%-17s%s\n' "$1" "$2" "$3"; }
red()   { n=$((n + 1));             printf '  %-4s%-17s%s\n' "$1" "$2" "RED — $3"; }
skip()  { skipped=$((skipped + 1)); printf '  %-4s%-17s%s\n' "$1" "$2" "skipped — $3"; }

version="$(cat VERSION 2>/dev/null || echo '?')"
mode="$(sed -n 's/^mode //p' .cascade/manifest 2>/dev/null | head -1)"
[[ -n "$mode" ]] || mode="not installed"
echo
echo "DOCTOR — $(basename "$ROOT") $version ($mode)"
echo

# ---- Layer 0 — CI + branch protection ----------------------------------------------------------
# The strongest layer, and the only one that survives a developer who ignores every other one.
wf_dir=".github/workflows"
if [[ "$MUTANT" == layer0 ]]; then wf_dir=".github/workflows-mutant-absent"; fi
if [[ ! -d "$wf_dir" ]]; then
  red "L0" "CI" "no $wf_dir — nothing runs the farm on push (I18 Layer 0). Add a workflow that runs tests/barbar.sh."
elif ! grep -rlq 'barbar\.sh' "$wf_dir" 2>/dev/null; then
  red "L0" "CI" "workflows exist but none runs tests/barbar.sh — CI is not the merge bar."
else
  green "L0" "CI" "$(find "$wf_dir" -name '*.yml' -o -name '*.yaml' | wc -l | tr -d ' ') workflows, farm invoked in $(basename "$(grep -rl 'barbar\.sh' "$wf_dir" | head -1)")"
fi

# Branch protection lives in GitHub's settings, not the tree. Doctor must not let a green line imply it
# checked something it cannot see — a false green on the strongest control is worse than no line at all.
skip "L0" "main" "branch protection is a GitHub setting, not readable from the tree — verify it yourself (INTEGRATION.md, Layer 0)"

# ---- Layer 1 — git hooks -------------------------------------------------------------------------
hp="$(git config core.hooksPath 2>/dev/null || true)"
[[ "$MUTANT" == hookspath ]] && hp=""
if [[ -z "$hp" ]]; then
  red "L1" "hooksPath" "core.hooksPath is unset — .githooks never runs. This does NOT travel with a clone. Fix: git config core.hooksPath .githooks"
else
  # A linked worktree resolves hooksPath to an absolute path inside the MAIN worktree. That is correct,
  # so this checks that the directory it names actually carries the hooks — not that the string matches.
  hpdir="$hp"; [[ "$hpdir" = /* ]] || hpdir="$ROOT/$hp"
  if [[ ! -d "$hpdir" ]]; then
    red "L1" "hooksPath" "core.hooksPath is '$hp' but that directory does not exist — no git hook runs"
  elif [[ ! -f "$hpdir/pre-commit" ]]; then
    red "L1" "hooksPath" "core.hooksPath is '$hp' but it has no pre-commit — Layer 1 is off"
  else
    green "L1" "hooksPath" "core.hooksPath -> ${hp/#$ROOT\//}"
  fi
fi

missing=""
for h in pre-commit pre-push; do
  [[ -f ".githooks/$h" ]] || { missing="$missing $h(absent)"; continue; }
  [[ -x ".githooks/$h" ]] || missing="$missing $h(not executable)"
done
if [[ -n "$missing" ]]; then
  red "L1" "git hooks" "problems:$missing — a hook that cannot execute is a layer that is off"
else
  green "L1" "git hooks" "pre-commit, pre-push present and executable"
fi

# ---- Layer 2 — agent hooks -----------------------------------------------------------------------
if [[ "$mode" == plugin ]]; then
  green "L2" "agent hooks" "provided by the plugin"
elif [[ ! -f .claude/settings.json ]]; then
  red "L2" "agent hooks" "no .claude/settings.json — Layer 2 is off"
else
  wired="$(python3 -B -c "
import json,sys
try: d=json.load(open('.claude/settings.json'))
except Exception as e: print('ERR '+str(e)); sys.exit(0)
h=d.get('hooks',{}); want={'PreToolUse':['hop_guard.py','bash_guard.py'],'Stop':['stop_guard.py'],'SessionStart':['preserve.py'],'UserPromptSubmit':['seam.py']}
miss=[n for e,ns in want.items() for n in ns if '.claude/hooks/'+n not in json.dumps(h.get(e,[]))]
print('OK' if not miss else 'MISS '+','.join(miss))
" 2>/dev/null)"
  case "$wired" in
    OK)    green "L2" "agent hooks" "5 wired in .claude/settings.json" ;;
    MISS*) red   "L2" "agent hooks" "not wired: ${wired#MISS } — those guards never fire" ;;
    *)     red   "L2" "agent hooks" "could not read .claude/settings.json (${wired:-no output})" ;;
  esac
fi

# ---- Pack integrity — delegated, never re-derived -------------------------------------------------
if [[ ! -f .cascade/manifest && -f install.sh && -f VERSION ]]; then
  skip "--" "pack" "this is the pack's own checkout ($version), not a repo the pack was installed into"
elif [[ ! -f .cascade/manifest ]]; then
  red "--" "pack" "no .cascade/manifest — the pack is not installed here. Fix: bdd install ."
else
  # A product never has install.sh — it is pack-owned. The checker lives in the pack, whose path the
  # manifest records in plugin mode; without it there is nothing to run, and saying so beats a red line
  # with no reason behind it.
  checker=""
  [[ -f install.sh ]] && checker="install.sh"
  if [[ -z "$checker" ]]; then
    pack_root="$(sed -n 's/^plugin_root //p' .cascade/manifest | head -1)"
    [[ -n "$pack_root" && -f "$pack_root/install.sh" ]] && checker="$pack_root/install.sh"
  fi
  if [[ -z "$checker" ]]; then
    skip "--" "pack" "the drift checker is pack-owned and this repo has no path to it — run: bdd check ."
  elif out="$(bash "$checker" --check . 2>&1)"; then
    green "--" "pack" "$(echo "$out" | tail -1)"
  else
    # Never print a bare RED: if the checker's output does not match the known prefixes, show its last
    # line rather than an empty reason. A finding you cannot act on is barely better than no finding.
    why="$(echo "$out" | grep -E '^(VERSION|MISSING|DRIFTED|IGNORED|UNWIRED)' | head -3 | tr '\n' ';' | sed 's/;$//')"
    [[ -n "$why" ]] || why="$(echo "$out" | grep -v '^[[:space:]]*$' | tail -1)"
    red "--" "pack" "${why:-$checker --check failed with no output}"
  fi
fi

# ---- Laws ------------------------------------------------------------------------------------------
if [[ ! -f tests/dsharp_strength.sh ]]; then
  skip "--" "laws" "tests/dsharp_strength.sh not present"
else
  out="$(bash tests/dsharp_strength.sh 2>&1)"; rc=$?
  score="$(echo "$out" | grep -oE 'DSHARP [0-9]+/[0-9]+' | tail -1)"
  if [[ "$score" == "DSHARP 0/0" ]]; then
    # No law in force is a real state, not a failure: a repo can be correctly wired before its laws are
    # named. Say what to run rather than scoring it red and teaching people to ignore doctor.
    green "--" "laws" "$score — no law in force yet (propose with /barbar init)"
  elif [[ "$rc" -eq 0 ]]; then
    green "--" "laws" "$score — every declared law GREEN"
  else
    red "--" "laws" "${score:-DSHARP red} — $(echo "$out" | grep -E 'THEATER|UNPROVEN|RED' | head -2 | tr '\n' ';' | sed 's/;$//')"
  fi
fi

# ---- Hop-state coherence ---------------------------------------------------------------------------
# An open hop pointing at a slice nobody wrote wastes a whole session before anyone notices.
hs=docs/cascade/hop-state.md
[[ -f "$hs" ]] || hs=docs/cascade/envelope.md   # pre-split repos keep the hop state in the envelope
if [[ ! -f "$hs" ]]; then
  red "--" "hop state" "no docs/cascade/hop-state.md or envelope.md — there is no cascade here"
else
  hop="$(sed -n 's/^CURRENT_HOP: *//p' "$hs" | head -1)"
  stage="$(sed -n 's/^CURRENT_STAGE: *//p' "$hs" | head -1)"
  slice="$(sed -n 's/^CURRENT_SLICE: *//p' "$hs" | head -1)"
  [[ "$MUTANT" == hopstate ]] && { hop=EXECUTE; stage=05b; slice=a-slice-nobody-wrote; }
  problem=""
  case "$hop" in
    ""|NONE) : ;;
    GENERATE|EXECUTE)
      [[ -n "$stage" ]] || problem="CURRENT_HOP is $hop but CURRENT_STAGE is empty"
      if [[ -z "$problem" && "$stage" == 05b ]]; then
        [[ -n "$slice" ]] || problem="a 05b hop with no CURRENT_SLICE — 05b builds one named slice"
        if [[ -z "$problem" && "$hop" == EXECUTE && ! -f "docs/cascade/05b-$slice.md" ]]; then
          problem="EXECUTE of 05b '$slice' but docs/cascade/05b-$slice.md does not exist — nothing was generated to execute"
        fi
      fi
      ;;
    *) problem="CURRENT_HOP is '$hop' — expected NONE, GENERATE or EXECUTE" ;;
  esac
  # An AUTOPILOT entry naming a slice nobody briefed halts the run at 3am, not now.
  if [[ -z "$problem" ]]; then
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      st="${entry%% *}"; sl="${entry#* }"
      [[ "$st" == 05b && "$sl" != "$st" ]] || continue
      [[ -f "docs/cascade/05b-$sl.md" ]] && continue
      grep -q "^- $sl:" docs/cascade/05b-briefs.md 2>/dev/null && continue
      problem="AUTOPILOT lists 05b '$sl' but it has neither a spec nor a brief"
      break
    done < <(sed -n 's/^AUTOPILOT: *//p' "$hs" | head -1 | tr ',' '\n' | sed 's/^ *//;s/ *$//')
  fi
  if [[ -n "$problem" ]]; then
    red "--" "hop state" "$problem"
  else
    green "--" "hop state" "${hop:-NONE}${stage:+ $stage}${slice:+ / $slice} — coherent"
  fi
fi

# ---- The manifests this pack added in 1.8.0 ---------------------------------------------------------
for m in reads_manifest stage_templates; do
  if [[ ! -f "tests/$m.sh" ]]; then
    skip "--" "$m" "tests/$m.sh not present (older pack)"
  elif out="$(bash "tests/$m.sh" 2>&1)"; then
    green "--" "$m" "$(echo "$out" | tail -1)"
  else
    red "--" "$m" "$(echo "$out" | head -1)"
  fi
done

# ---- End to end — the farm --------------------------------------------------------------------------
if [[ -n "$FAST" ]]; then
  skip "--" "farm" "DOCTOR_FAST set — run bash tests/barbar.sh for the full farm"
elif [[ ! -f tests/barbar.sh ]]; then
  skip "--" "farm" "tests/barbar.sh not present"
else
  out="$(bash tests/barbar.sh 2>&1)"; rc=$?
  score="$(echo "$out" | grep -oE 'BARBAR [0-9]+/[0-9]+' | tail -1)"
  if [[ "$rc" -eq 0 ]]; then
    green "--" "farm" "${score:-BARBAR n/n}"
  else
    red "--" "farm" "${score:-farm red} — $(echo "$out" | grep '^FAIL' | head -2 | tr '\n' ';' | sed 's/;$//')"
  fi
fi

echo
[[ "$skipped" -gt 0 ]] && echo "  ($skipped check(s) skipped — not counted either way)"
echo "DOCTOR $k/$n"
[[ "$k" -eq "$n" ]] || { echo "Not healthy. Each RED line names the layer and the command that fixes it."; exit 1; }
exit 0
