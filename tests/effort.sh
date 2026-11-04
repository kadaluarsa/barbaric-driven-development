#!/usr/bin/env bash
# t93 portable effort CLI — a thin wrapper over tests/lib/effort.py. No model calls, no network, no writes.
# usage: bash tests/effort.sh --context FILE [--profile FILE] | --help
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$HERE/tests/lib/effort.py" "$@"
