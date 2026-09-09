#!/usr/bin/env bash
# The reads: manifest keeps each hop's context budget legible: one line per stage naming the prior
# artifacts that stage consumes. Without a check, the manifest rots the way any prose table rots —
# it reads as true long after a stage moved. This asserts three things about it: every stage has a
# row, no row names a stage at or after its own (a forward reference is a cycle, not a budget), and
# every named stage exists.
#
# Red twin: READS_MUTANT=1 injects a forward reference and this script MUST then fail. A validator
# that cannot fail is theater.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/docs/cascade/product-e2e-gre-pipeline.md"

python3 - "$DOC" "${READS_MUTANT:-}" <<'PY'
import re, sys

doc, mutant = sys.argv[1], sys.argv[2]
try:
    text = open(doc, encoding="utf-8").read()
except OSError as e:
    print(f"READS red: cannot read {doc}: {e}"); sys.exit(1)

block = re.search(r"<!-- reads-manifest:begin -->(.*?)<!-- reads-manifest:end -->", text, re.S)
if not block:
    print("READS red: no <!-- reads-manifest:begin/end --> block in the pipeline doc.")
    print("           The manifest table moved or was reformatted; restore the markers around it.")
    sys.exit(1)

# The cascade's stage order. 05b sits between 05 and 06: it is the build stage, and it may read 05.
ORDER = ["00", "01", "02", "03", "04", "05", "05b", "06", "07", "08", "09", "10", "11"]
rank = {s: i for i, s in enumerate(ORDER)}

rows = {}
for line in block.group(1).splitlines():
    line = line.strip()
    if not line.startswith("|"):
        continue
    cells = [c.strip() for c in line.strip("|").split("|")]
    if len(cells) < 2:
        continue
    stage = cells[0].split()[0] if cells[0].split() else ""
    if stage not in rank:          # header row, separator row
        continue
    rows[stage] = cells[1]

if mutant:
    # Inject a forward reference: stage 04 claims to read stage 09. If the checks below still pass,
    # they check nothing.
    rows["04"] = "03, 09"

fail = 0
for stage in ORDER:
    if stage not in rows:
        print(f"READS red: stage {stage} has no reads: row.")
        fail = 1

for stage, cell in sorted(rows.items(), key=lambda kv: rank[kv[0]]):
    if not cell:
        print(f"READS red: stage {stage} has an empty reads: cell. Write '—' if it reads nothing.")
        fail = 1
        continue
    for named in re.findall(r"\b(0[0-9]b?|1[01])\b", cell):
        if named not in rank:
            print(f"READS red: stage {stage} names stage {named}, which is not a cascade stage.")
            fail = 1
        elif rank[named] >= rank[stage]:
            print(f"READS red: stage {stage} names stage {named} — a stage cannot read itself or a "
                  f"later stage. That artifact does not exist when this hop runs.")
            fail = 1

if fail:
    sys.exit(1)
print(f"READS clean — {len(rows)} stages, no forward references")
PY
rc=$?

# No inversion here, deliberately. The envelope's convention is that a break command FAILS while the
# law holds: under READS_MUTANT the checks must reject, so a non-zero exit is the healthy twin and a
# zero exit is theater. Inverting the code would hide exactly the case the twin exists to expose.
[[ -n "${READS_MUTANT:-}" && "$rc" -eq 0 ]] && \
  echo "READS THEATER: the injected forward reference passed. The checks are not checking."
exit "$rc"
