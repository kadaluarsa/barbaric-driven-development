#!/usr/bin/env bash
# Oracle strength (t109): script-made mutants of this hop's change, judged by the slice's frozen oracle, in place.
#   bash tests/mutants.sh     EXECUTE 05b: `MUTANTS k/n killed`; exit 0 when every survivor is answered, else 1
# A survivor is answered by a human-signed `| <id> | equivalent <reason> |` row in docs/cascade/05b-<slug>-mutants.md,
# or by a stronger oracle (send the slice back to GENERATE). Signed in the envelope's <EDIT>: `- MUTANTS: off`,
# `- MUTANTS_MAX: <n>` (40), `- MUTANTS_TIMEOUT: <s>` (600). Environment values are ignored.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$ROOT/tests/lib/mutants.py" "$ROOT" "$@"
