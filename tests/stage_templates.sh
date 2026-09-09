#!/usr/bin/env bash
# Stage templates live one-per-file under docs/cascade/stages/ so a hop loads the stage it is running
# instead of all twelve. Two failures are silent in prose and loud here: an index row pointing at a
# file nobody wrote sends a hop looking for a template that is not there, and a file nobody indexed is
# a template no hop will ever find.
#
# Three stages stay inside product-e2e-cascade.md because their templates carry <EDIT> blocks, and
# moving human-authored lines between files is a change only the human can sign. That is a rule, not
# an exception list, so it is checked in both directions: a stage stays in the pack if and only if its
# section carries <EDIT>. A template that grows an <EDIT> and is still split out fails here, and so
# does one kept back without needing to be.
#
# Red twin: STAGES_MUTANT=1 drops a stage from the index and this script MUST then fail.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" "${STAGES_MUTANT:-}" <<'PY'
import os, re, sys, glob

root, mutant = sys.argv[1], sys.argv[2]
doc = os.path.join(root, "docs/cascade/product-e2e-cascade.md")
stages_dir = os.path.join(root, "docs/cascade/stages")

try:
    text = open(doc, encoding="utf-8").read()
except OSError as e:
    print(f"STAGES red: cannot read {doc}: {e}"); sys.exit(1)

ALL = ["00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11"]

split, in_pack = {}, set()
for m in re.finditer(r"^\|\s*(0[0-9]|1[01])\s+—[^|]*\|\s*([^|]+?)\s*\|", text, re.M):
    stage, cell = m.group(1), m.group(2)
    f = re.search(r"stages/([A-Za-z0-9._-]+\.md)", cell)
    if f:
        split[stage] = f.group(1)
    elif "in this file" in cell:
        in_pack.add(stage)

if mutant:
    # Drop stage 07 from the index. If the checks below still pass, they check nothing.
    split.pop("07", None)

on_disk = {os.path.basename(p) for p in glob.glob(os.path.join(stages_dir, "*.md"))}

# The section of the pack that belongs to one stage, for the <EDIT> correspondence check.
# Templates embed '## Heading' lines inside their fenced blocks, so the section can only end at a
# structural boundary — another stage heading, or the trailer — never at any '## ' it happens to hit.
BOUNDARY = re.compile(r"^(?:### (?:0[1-9]|1[01]) — |## 0[0-9] — |## Stage prompts|## One-shot generator)")

def pack_section(stage):
    lines = text.split("\n")
    start = None
    for i, l in enumerate(lines):
        if re.match(rf"^#{{2,3}} {stage} — ", l):
            start = i
            break
    if start is None:
        return None
    for j in range(start + 1, len(lines)):
        if BOUNDARY.match(lines[j]):
            return "\n".join(lines[start:j])
    return "\n".join(lines[start:])

fail = 0
if not on_disk:
    print(f"STAGES red: {stages_dir} has no stage files."); sys.exit(1)

for s in ALL:
    if s in split and s in in_pack:
        print(f"STAGES red: stage {s} is indexed both to a file and as in-pack."); fail = 1; continue
    if s not in split and s not in in_pack:
        print(f"STAGES red: stage {s} has no row in the index table of product-e2e-cascade.md."); fail = 1; continue

    if s in split:
        fname = split[s]
        if fname not in on_disk:
            print(f"STAGES red: the index sends stage {s} to stages/{fname}, which does not exist."); fail = 1; continue
        body = open(os.path.join(stages_dir, fname), encoding="utf-8").read()
        if not re.search(rf"^#\s*{s}\s+—", body, re.M):
            print(f"STAGES red: stages/{fname} is indexed as stage {s} but carries no '# {s} — ' heading."); fail = 1
        if "<EDIT>" in body:
            print(f"STAGES red: stages/{fname} carries <EDIT>, so it cannot live outside the pack — "
                  f"moving human-authored lines between files needs a signature. Keep stage {s} in "
                  f"product-e2e-cascade.md and index it as 'in this file'."); fail = 1
    else:
        sec = pack_section(s)
        if sec is None:
            print(f"STAGES red: stage {s} is indexed as in-pack but has no section in product-e2e-cascade.md."); fail = 1
        elif "<EDIT>" not in sec:
            print(f"STAGES red: stage {s} is kept in the pack but carries no <EDIT> — the only reason to "
                  f"keep a template here. Split it out to stages/."); fail = 1

for orphan in sorted(on_disk - set(split.values())):
    print(f"STAGES red: stages/{orphan} is not named by the index — no hop will find it."); fail = 1

if fail:
    sys.exit(1)
print(f"STAGES clean — {len(split)} split out, {len(in_pack)} kept in the pack for <EDIT>, none orphaned")
PY
rc=$?

# No inversion, deliberately — same reasoning as tests/reads_manifest.sh: a break command that fails
# is the healthy twin, and a zero exit under the mutant is the theater this exists to expose.
[[ -n "${STAGES_MUTANT:-}" && "$rc" -eq 0 ]] && \
  echo "STAGES THEATER: the dropped index row passed. The checks are not checking."
exit "$rc"
