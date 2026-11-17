#!/usr/bin/env bash
# Doc parts (t102): the line ranges of the pipeline doc and CONTROL-LINE.md that a hop reads.
#
# usage: tests/doc_parts.sh                              the parts for the current hop (`no hop running` on NONE)
#        tests/doc_parts.sh --hop <GENERATE|EXECUTE> --stage <stage>
#        tests/doc_parts.sh --check                      every part resolves; I1–I18 sit in gre@INVARIANTS
#        tests/doc_parts.sh --measure                    bytes per hop class vs the five whole files; >50 % is red
#
# The manifest lives in docs/cascade/product-e2e-gre-pipeline.md between <!-- doc-parts:begin/end -->. It is a
# budget, not a gate: nothing refuses a hop that reads more. USAGE.md §B21.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$ROOT/tests/lib/doc_parts.py" "$ROOT" "$@"
