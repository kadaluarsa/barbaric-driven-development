#!/usr/bin/env bash
# The frozen-oracle gate (t89). A slice's acceptance tests are written at GENERATE, pinned by sha256 in
# docs/cascade/05b-<slug>.oracle with the exact goal commands that run them (`run:` lines), and judge every builder
# alike: on EXECUTE they are read-only and the loop checks them against the manifest committed when the hop opened.
#   bash tests/oracle.sh                                  GENERATE 05b gate: PASS/FAIL lines, `ORACLE k/n`
#   bash tests/oracle.sh --write --run CMD [--run …] PATH…  pin the oracle (GENERATE 05b only; exit 2 elsewhere)
#   bash tests/oracle.sh --loop                           EXECUTE 05b, called by tests/loop.sh: exit 0 green, 3 refused
# A signed `- ORACLE: off` inside <EDIT> in envelope.md turns it off on every hop. Its red twins live in
# tests/ac/t89_frozen_oracle.sh.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$ROOT/tests/lib/oracle.py" "$ROOT" "$@"
