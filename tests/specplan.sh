#!/usr/bin/env bash
# The spec and plan check (t94). `bash tests/specplan.sh` prints `SPECPLAN k/n` or `SPECPLAN n/a`; exit 0 iff it holds.
# `--index` reads staged text, for the pre-commit hook. The rules live in docs/cascade/specplan-rules.md.
# Its red twins live in tests/ac/t94_specplan_contract.sh.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$ROOT/tests/lib/specplan.py" "$ROOT" "$@"
