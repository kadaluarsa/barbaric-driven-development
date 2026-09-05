#!/usr/bin/env bash
# Stage 10 as a script (I7). The agent proposes rows in docs/cascade/10-audit.md; this scores them
# against the tree. A verdict line in prose is ignored — only evidence counts.
#   IMPLEMENTED needs `path: X` (every X exists) AND `test: CMD` (exit 0)  — else MISSING / VIOLATED
#   D# rows take their status from tests/dsharp_strength.sh (GREEN -> IMPLEMENTED, else VIOLATED)
#   REFINED is canonical only inside <EDIT> (human-promoted, I8) — else it is DRIFTED
#   Every ID in the accepted PRD (FR-/NFR-) and every declared D# must have a row — else MISSING
# Prints one line per item, `AUDIT k/n`, and the verdict. Exit 0 only on CLEAN.
# usage: tests/audit.sh [--root DIR]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$(cd "$2" && pwd)"; shift 2 ;; *) echo "usage: audit.sh [--root DIR]" >&2; exit 64 ;; esac; done
AUDIT="$ROOT/docs/cascade/10-audit.md"; PRD="$ROOT/docs/cascade/03-prd.md"; ENV_FILE="$ROOT/docs/cascade/envelope.md"
[[ -f "$AUDIT" ]] || { echo "AUDIT 0/0"; echo "Audit verdict: DIRTY (no docs/cascade/10-audit.md)"; exit 1; }
STRENGTH="$(bash "$HERE/dsharp_strength.sh" --root "$ROOT" 2>&1 || true)"
python3 -B - "$ROOT" "$AUDIT" "$PRD" "$ENV_FILE" "$STRENGTH" <<'PY'
import os, re, subprocess, sys
root, audit_path, prd_path, env_path, strength = sys.argv[1:6]
text = open(audit_path, encoding="utf-8", errors="replace").read()
signed = "".join(re.findall(r"<EDIT>(.*?)</EDIT>", text, re.S))
ID = re.compile(r"^\s*\|\s*([A-Z]{1,4}-?\d+)\s*\|(.*)$")
rows = {}
for line in text.splitlines():
    m = ID.match(line)
    if not m: continue
    cols = [c.strip() for c in m.group(2).strip().strip("|").split("|")]
    if len(cols) < 3: continue
    rows[m.group(1)] = {"claim": cols[0], "evidence": cols[1], "status": cols[2].upper(), "line": line.strip()}
inventory = []
if os.path.exists(prd_path):
    inventory += sorted(set(re.findall(r"\b(?:FR|NFR)-\d+\b", open(prd_path, encoding="utf-8", errors="replace").read())))
dsharp = {}
for ln in strength.splitlines():
    m = re.match(r"^(GREEN|RED|THEATER|UNPROVEN)\s+(D\d+)", ln)   # strength already skips {{placeholder}} lines
    if m: dsharp[m.group(2)] = m.group(1)
inventory += sorted(dsharp)
for rid in rows:
    if rid not in inventory: inventory.append(rid)
def run(cmd):
    try: return subprocess.run(cmd, shell=True, cwd=root, capture_output=True, timeout=600).returncode == 0
    except Exception: return False
k = 0; out = []
for rid in inventory:
    row = rows.get(rid)
    if row is None:
        out.append(f"MISSING      {rid}  (no row)"); continue
    st, ev = row["status"], row["evidence"]
    if rid in dsharp:
        final = "IMPLEMENTED" if dsharp[rid] == "GREEN" else "VIOLATED"
        note = f"D# {dsharp[rid]}"
    elif st == "IMPLEMENTED":
        paths = re.findall(r"path:\s*([^\s|]+)", ev); tests = re.findall(r"test:\s*(.+?)(?=\s+path:|\s*$)", ev)
        missing = [p for p in paths if not os.path.exists(os.path.join(root, p))]
        if not paths or missing: final, note = "MISSING", ("no path:" if not paths else "path not on tree: " + ",".join(missing))
        elif not tests: final, note = "MISSING", "no test:"
        elif not all(run(t.strip()) for t in tests): final, note = "VIOLATED", "test red: " + "; ".join(t.strip() for t in tests)
        else: final, note = "IMPLEMENTED", f"{','.join(paths)} + {len(tests)} test(s) green"
    elif st == "REFINED":
        if row["line"] in signed: final, note = "IMPLEMENTED", "REFINED, human-promoted inside <EDIT>"
        else: final, note = "DRIFTED", "REFINED not promoted by a human (I8)"
    elif st in ("DRIFTED", "VIOLATED", "MISSING"):
        final, note = st, "as reported"
    else:
        final, note = "MISSING", f"unknown status {st!r}"
    if final == "IMPLEMENTED": k += 1
    out.append(f"{final:<12} {rid}  {row['claim'][:50]}  ({note})")
n = len(inventory)
print("\n".join(out))
print(f"AUDIT {k}/{n}")
clean = n > 0 and k == n
print("Audit verdict: " + ("CLEAN" if clean else "DIRTY"))
sys.exit(0 if clean else 1)
PY
