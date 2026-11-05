#!/usr/bin/env bash
# The spec-wording benchmark scorer (t94). `bash tests/specbench.sh score FILE` or `--dry-run`. It calls no model and
# claims no gain. The human starts any paid run; evals/specbench/README.md holds the protocol.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$ROOT/tests/lib/specbench.py" "$@"
