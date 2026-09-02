#!/usr/bin/env bash
# Static checks for everything that enforces: bash syntax under /bin/bash (3.2 on macOS), shellcheck when
# present, and python byte-compilation of every hook and helper. Exit non-zero on any finding.
set -uo pipefail
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
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "${files[@]}" 2>&1 | sed 's/^/  /' | head -40
  shellcheck -S warning "${files[@]}" >/dev/null 2>&1 || { echo "SHELLCHECK findings"; fail=1; }
else
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
[[ "$fail" -eq 0 ]] && echo "LINT clean" || { echo "LINT red"; exit 1; }
