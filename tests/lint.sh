#!/usr/bin/env bash
# Static checks for everything that enforces: bash syntax under /bin/bash (3.2 on macOS), shellcheck when
# present, and python byte-compilation of every hook and helper. Exit non-zero on any finding.
set -uo pipefail
# Git exports GIT_DIR/GIT_WORK_TREE to hooks. Inherited by a script that runs `git init` in a temp dir, they
# redirect it at the real repo (this once flipped a product to core.bare=true and re-pointed a worktree's HEAD).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
shopt -s nullglob
for f in "$ROOT"/tests/*.sh "$ROOT"/tests/lib/*.sh "$ROOT"/.githooks/* "$ROOT"/install.sh "$ROOT"/evals/spike/*.sh; do
  [[ -f "$f" ]] || continue
  bash -n "$f" || { echo "SYNTAX  $f"; fail=1; }
  [[ -x /bin/bash ]] && /bin/bash -n "$f" 2>/dev/null || { [[ -x /bin/bash ]] && { echo "BASH3   $f"; fail=1; }; }
done
files=()
for f in "$ROOT"/tests/*.sh "$ROOT"/tests/lib/*.sh "$ROOT"/.githooks/* "$ROOT"/install.sh; do [[ -f "$f" ]] && files+=("$f"); done   # products have no install.sh
# Static analysis is most of this script's cost, and most of the pre-push gate's. In fast mode check only what
# this push actually changes: anything you are not pushing was linted when it was. CI, `barbar merge` and a
# plain `bash tests/lint.sh` still check everything. Falls back to the full set whenever git cannot say.
if [[ -n "${CASCADE_FAST:-}" ]] && command -v git >/dev/null 2>&1; then
  base="$(git -C "$ROOT" rev-parse --verify -q "@{upstream}" 2>/dev/null || git -C "$ROOT" rev-parse --verify -q origin/HEAD 2>/dev/null || true)"
  if [[ -n "$base" ]]; then
    changed=()
    while IFS= read -r rel; do
      [[ -n "$rel" && -f "$ROOT/$rel" ]] || continue
      for f in "${files[@]}"; do [[ "$f" == "$ROOT/$rel" ]] && changed+=("$f"); done
    done < <(git -C "$ROOT" diff --name-only --diff-filter=ACMR "$base" -- 'tests/*.sh' 'tests/lib/*.sh' '.githooks/*' 'install.sh' 2>/dev/null)
    files=("${changed[@]}")
    [[ ${#files[@]} -eq 0 ]] && echo "shellcheck: nothing shell-shaped changed since $base — skipped (CI lints everything)"
  fi
fi
if [[ ${#files[@]} -gt 0 ]] && command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "${files[@]}" 2>&1 | sed 's/^/  /' | head -40
  shellcheck -S warning "${files[@]}" >/dev/null 2>&1 || { echo "SHELLCHECK findings"; fail=1; }
elif [[ ${#files[@]} -gt 0 ]]; then
  echo "shellcheck not installed — skipped (CI has it)"
fi
python3 - "$ROOT" <<'PY' || fail=1
import py_compile, sys, glob, os
root = sys.argv[1]; bad = 0
for f in glob.glob(os.path.join(root, ".claude/hooks/*.py")) + glob.glob(os.path.join(root, "tests/**/*.py"), recursive=True):
    try: py_compile.compile(f, doraise=True)
    except Exception as e: print(f"PYTHON  {f}: {e}"); bad = 1
sys.exit(bad)
PY
# A T-range written in prose is a claim about the test suite that nothing checks, and it goes stale
# silently: README said "T1–T36" five releases after T41 existed, and a CONTROL-LINE edit anchored on a
# range that had already moved was a no-op nobody noticed. Same defect class as a stale shipped file —
# it reads as true. The enforcement suite starts at T8, so only ranges beginning there must end at its
# last test; T1–T7 is the separate I17 suite and is correct as written.
# (The ranges use an en dash: a bracket expression with a multibyte character does not match under
# macOS grep, so the extraction is done in python.)
if [[ -f "$ROOT/tests/enforcement.sh" && -f "$ROOT/CONTROL-LINE.md" ]]; then
  maxt="$(grep -oE '^t T[0-9]+' "$ROOT/tests/enforcement.sh" | grep -oE '[0-9]+' | sort -n | tail -1)"
  if [[ -n "$maxt" ]]; then
    for d in README.md CONTROL-LINE.md AUDIT.md; do
      [[ -f "$ROOT/$d" ]] || continue
      while IFS= read -r claimed; do
        [[ -z "$claimed" || "$claimed" == "$maxt" ]] || { echo "STALE   $d claims T8-T$claimed; the suite defines up to T$maxt"; fail=1; }
      done < <(python3 -c '
import re, sys
print("\n".join(m.group(1) for m in re.finditer(r"T8[\u2013-]T([0-9]+)", open(sys.argv[1], encoding="utf-8").read())))
' "$ROOT/$d")
    done
    grep -q "^| T$maxt |" "$ROOT/CONTROL-LINE.md" || { echo "STALE   CONTROL-LINE.md has no row for T$maxt — the newest test is undocumented"; fail=1; }
  fi
fi


# The reads: manifest is prose that claims something about the cascade's shape, and prose rots
# silently. Same defect class as the stale T-range above.
if [[ -f "$ROOT/tests/reads_manifest.sh" ]]; then
  bash "$ROOT/tests/reads_manifest.sh" | sed 's/^/  /'
  bash "$ROOT/tests/reads_manifest.sh" >/dev/null 2>&1 || fail=1
fi

[[ "$fail" -eq 0 ]] && echo "LINT clean" || { echo "LINT red"; exit 1; }
