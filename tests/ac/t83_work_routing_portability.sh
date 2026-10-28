#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$repo_root" <<'PY'
from pathlib import Path
import re
import sys
import tempfile

root = Path(sys.argv[1])
paths = [
    root / "skills/bdd-work/SKILL.md",
    root / ".claude/skills/bdd-work/SKILL.md",
    root / ".agents/skills/bdd-work/SKILL.md",
]

def valid_skill(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return False
    match = re.match(r"\A---\n(.*?)\n---(?:\n|$)", text, re.DOTALL)
    if not match:
        return False
    metadata = match.group(1)
    name = re.search(r"(?m)^name:\s*([^\s#]+)\s*$", metadata)
    description = re.search(r"(?ms)^description:\s*(?:\n((?:[ \t]+.+\n?)+)|([^\n#][^\n]*))", metadata)
    return bool(name and name.group(1) == "bdd-work" and description and (description.group(1) or description.group(2)).strip())

missing = [str(path.relative_to(root)) for path in paths if not path.is_file()]
if missing:
    raise SystemExit("FAIL: missing skill copy: " + ", ".join(missing))
contents = [path.read_bytes() for path in paths]
if not (contents[0] == contents[1] == contents[2]):
    raise SystemExit("FAIL: bdd-work skill copies differ")
bad_metadata = [str(path.relative_to(root)) for path in paths if not valid_skill(path)]
if bad_metadata:
    raise SystemExit("FAIL: invalid required name/description metadata: " + ", ".join(bad_metadata))

# Prove the parity and metadata assertions reject representative regressions.
with tempfile.TemporaryDirectory(prefix="t83-skill-check-") as temp:
    scratch = Path(temp)
    copies = [scratch / f"copy-{index}.md" for index in range(3)]
    for target, data in zip(copies, contents):
        target.write_bytes(data)
    copies[2].write_bytes(copies[2].read_bytes() + b"\n# divergent\n")
    if len({path.read_bytes() for path in copies}) == 1:
        raise SystemExit("FAIL: parity check accepted a divergent copy")
    copies[2].write_bytes(re.sub(rb"(?m)^name:.*$", b"name:", contents[2], count=1))
    if valid_skill(copies[2]):
        raise SystemExit("FAIL: metadata check accepted an invalid name")

print("PASS: three skill copies match; required metadata is valid; negative fixtures reject divergence and invalid metadata")
PY
