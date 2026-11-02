#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$repo_root" <<'PY'
from pathlib import Path
import os
import re
import subprocess
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

# An installer that omits the shared destination, overwrites a product's file,
# or creates project skill state in plugin mode must fail this fixture.
with tempfile.TemporaryDirectory(prefix="t83-install-") as temp:
    scratch = Path(temp)
    home = scratch / "home"
    home.mkdir()
    env = dict(os.environ, HOME=str(home))

    def install(label: str):
        repo = scratch / label
        repo.mkdir()
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        return repo

    def run_install(repo: Path, mode: str):
        return subprocess.run(["bash", str(root / "install.sh"), mode, str(repo)],
                              env=env, text=True, capture_output=True)

    relative_skill = Path(".agents/skills/bdd-work/SKILL.md")
    expected = contents[2]
    absent = install("absent")
    created = run_install(absent, "--no-plugin")
    if created.returncode or not (absent / relative_skill).is_file() or (absent / relative_skill).read_bytes() != expected:
        raise SystemExit("FAIL: standalone install did not create the shared skill with canonical bytes: " + created.stderr[-300:])

    previous = (absent / relative_skill).stat()
    identical = run_install(absent, "--no-plugin")
    current = (absent / relative_skill).stat()
    if (identical.returncode or (absent / relative_skill).read_bytes() != expected
            or (previous.st_ino, previous.st_mtime_ns) != (current.st_ino, current.st_mtime_ns)):
        raise SystemExit("FAIL: identical shared skill was not kept as a no-op")

    conflict = install("conflict")
    destination = conflict / relative_skill
    destination.parent.mkdir(parents=True)
    original = b"product-owned skill\n"
    destination.write_bytes(original)
    rejected = run_install(conflict, "--no-plugin")
    if (rejected.returncode == 0 or destination.read_bytes() != original
            or "CONFLICT:" not in rejected.stderr or str(relative_skill) not in rejected.stderr
            or (conflict / ".cascade").exists()):
        raise SystemExit("FAIL: conflicting shared skill was overwritten or not clearly rejected")

    plugin = install("plugin")
    plugin_result = run_install(plugin, "--plugin")
    if plugin_result.returncode or (plugin / relative_skill).exists():
        raise SystemExit("FAIL: plugin install created duplicate project skill state: " + plugin_result.stderr[-300:])
    if list(home.iterdir()):
        raise SystemExit("FAIL: install wrote to the user home")

print("PASS: standalone creates, keeps identical, rejects conflict without overwrite; plugin has no project skill copy; no home write")

# Probe records are intentionally small: no raw prompt, transcript, tool inputs,
# source contents, absolute paths, or personally identifying host information.
import json

artifact = root / "evals/probes/t83-native-skills.json"
if not artifact.is_file():
    raise SystemExit("FAIL: missing sanitized native-skill probe metadata")
records = json.loads(artifact.read_text(encoding="utf-8"))
clients = {"Codex CLI", "Cursor Agent CLI", "Gemini CLI", "OpenCode", "Zed"}
fields = {"client", "version", "discovery", "route", "source_evidence_present",
          "source_path_category", "tool_activity", "complete_tool_evidence", "clean_tree", "status"}
if not isinstance(records, list) or len(records) != len(clients) or {r.get("client") for r in records} != clients:
    raise SystemExit("FAIL: one probe record required for each initial native-skill client")

def validate(record):
    if set(record) != fields:
        return False
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9. +_-]*|unavailable", record["version"]):
        return False
    if record["discovery"] not in {"found", "not_found", "unverified"}:
        return False
    if record["route"] not in {"investigation", "other", "unverified"}:
        return False
    if record["source_path_category"] not in {"repo_relative_source", "none"}:
        return False
    if record["tool_activity"] not in {"read_only", "mutating", "unverified"}:
        return False
    if record["status"] not in {"supported", "unverified"}:
        return False
    if any(type(record[key]) is not bool for key in ("source_evidence_present", "complete_tool_evidence", "clean_tree")):
        return False
    proof = (record["version"] != "unavailable" and record["discovery"] == "found"
             and record["route"] == "investigation" and record["source_evidence_present"]
             and record["source_path_category"] == "repo_relative_source"
             and record["tool_activity"] == "read_only" and record["complete_tool_evidence"]
             and record["clean_tree"])
    return record["status"] != "supported" or proof

if not all(validate(record) for record in records):
    raise SystemExit("FAIL: unsafe probe metadata or supported claim without complete versioned evidence")
for doc in ("README.md", "USAGE.md", "INTEGRATION.md"):
    content = (root / doc).read_text(encoding="utf-8")
    for record in records:
        # A maintained, versioned status table is required in each user-facing guide.
        row = f'| {record["client"]} | {record["version"]} | {record["status"]} |'
        if row not in content:
            raise SystemExit(f"FAIL: {doc} lacks exact probe status for {record['client']}")

# A mutant with discovery alone must never earn a supported claim.
mutant = next(iter(records)).copy()
mutant.update(status="supported", complete_tool_evidence=False)
if validate(mutant):
    raise SystemExit("FAIL: discovery-only metadata was accepted as behavior evidence")
print("PASS: sanitized exact-version probe records and matching supported/unverified documentation")
PY
