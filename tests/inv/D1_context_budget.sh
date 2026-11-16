#!/usr/bin/env bash
# D1 (t107) — the prompt hook MUST NOT add more than 400 bytes per prompt over release 3.5.6. The prompt hook
# (.claude/hooks/seam.py) adds context to every prompt. This test measures that context, in bytes, for each hop class
# and for no hop, with four kinds of prompt, in two scratch repositories with the same fixture: one from release 3.5.6
# (c75e048) and one from this tree. A row fails when it grew by more than the limit. The law's check line in
# docs/cascade/laws/context.md gives the limit (--grow); the law, its lines and this file are the human's.
#
# usage: tests/inv/D1_context_budget.sh [--grow N] [--root DIR]      (default N = 400)
#   --root DIR    measure DIR (a copy of this pack) instead of this tree; 3.5.6 always comes from this clone's history
#   BUDGET_PAD=N  the red twin: the measured tree's prompt hook adds N bytes to every context it prints
#
#   BUDGET GENERATE/feature        3.5.6: 4321 bytes  now: 4700 bytes  grew: +379  limit: +400  PASS
#   BUDGET fixture: the lessons line is 368 bytes on GENERATE/plain
#   BUDGET 24/24  (each prompt may grow at most +400 bytes over 3.5.6)
# Exit 0 when every row is in the limit, 1 when one is over, 2 when 3.5.6 is not in this clone, 64 on a bad argument.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK="$(cd "$HERE/../.." && pwd)"
PAD="${BUDGET_PAD:-0}"
BASE=c75e048fc5b22d3d5b4ad50825b3d2f1545c8777   # release 3.5.6, the last release before t107
GROW=400
SRC=""
usage() { echo "usage: tests/inv/D1_context_budget.sh [--grow N] [--root DIR]" >&2; exit 64; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --grow) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || usage; GROW=$((10#$2)); shift 2 ;;
    --root) [[ $# -ge 2 && -d "$2" ]] || usage; SRC="$(cd "$2" && pwd)"; shift 2 ;;
    *) usage ;;
  esac
done
[[ "$PAD" =~ ^[0-9]+$ ]] || usage
if ! git -C "$PACK" cat-file -e "$BASE^{commit}" 2>/dev/null; then
  echo "BUDGET: release 3.5.6 ($BASE) is not in this clone — fetch full history (actions/checkout fetch-depth: 0)" >&2
  exit 2
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/old" "$TMP/new"
git -C "$PACK" archive "$BASE" | tar -x -C "$TMP/old"
if [[ -n "$SRC" ]]; then
  ( cd "$SRC" && tar --exclude=./.git --exclude=./.cascade -cf - . ) | tar -x -C "$TMP/new"
else   # this tree as it is on disk: tracked files and new files git does not ignore
  ( cd "$PACK" && git ls-files -z -co --exclude-standard | python3 -B -c '
import os, sys
sys.stdout.write("\0".join(p for p in sys.stdin.read().split("\0") if p and os.path.isfile(p)))' \
    | tar --null -T - -cf - ) | tar -x -C "$TMP/new"
fi
python3 -B - "$TMP/old" "$TMP/new" "$GROW" "$PAD" <<'PY'
import json, os, re, subprocess, sys

old, new, grow, pad = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
CLASSES = [("GENERATE", "GENERATE", "05b"), ("EXECUTE-BUILD", "EXECUTE", "05b"), ("EXECUTE-DESIGN", "EXECUTE", "03"),
           ("EXECUTE-AUDIT", "EXECUTE", "10"), ("EXECUTE-PRR", "EXECUTE", "11"), ("IDLE", "NONE", "05b")]
# The route lines (ROUTE, STEPS, HINT, EFFORT) differ by the kind of prompt, so each class is measured with each kind.
PROMPTS = [("plain", "continue"), ("feature", "add a feature: export the report as CSV"),
           ("bug-fix", "fix the bug where login fails with a 500 error"),
           ("refactor", "refactor the parser into two modules")]
ENV = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "CASCADE_", "BDD_", "CLAUDE"))}
ENV.update(GIT_AUTHOR_NAME="fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
           GIT_COMMITTER_NAME="fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
# The fixture's lessons fill the t107 line: every one is unsettled and in scope ANY, so each class may show three.
LESSONS = [
    ("stop_guard", "NOEDGE", "GENERATE Nb ended without its edge line",
     "End every reply of a running hop with its STITCH NEEDED line, after the last tool call, even when the reply only "
     "reports a failure or a question."),
    ("stop_guard", "HALT", "AUTOPILOT HALT: the gate failed",
     "Run every edge commit in the background under caffeinate, and wait for its notification before you report the "
     "edge, so a sleeping machine cannot fail the gate."),
    ("hop_guard", "DENY", "product write on a GENERATE hop",
     "Write no product file on a GENERATE hop: the spec, the plan and the frozen oracle are the only files it changes."),
    ("git", "SENDBACK", "send back EXECUTE Nb",
     "Read the oracle before you build."),
]


def sh(cwd, *args, **kw):
    return subprocess.run(list(args), cwd=cwd, env={**ENV, **kw.pop("env", {})}, capture_output=True, text=True, **kw)


def set_hop(tree, hop, stage, slice_):
    p = os.path.join(tree, "docs", "cascade", "hop-state.md")
    s = open(p, encoding="utf-8").read()
    for k, v in (("CURRENT_HOP", hop), ("CURRENT_STAGE", stage), ("CURRENT_SLICE", slice_)):
        s = re.sub(rf"(?m)^{k}:.*$", f"{k}: {v}", s, count=1)
    s = re.sub(r"(?m)^AUTOPILOT:.*$", "AUTOPILOT:", s)   # each tree's own list differs; the fixture signs none
    open(p, "w", encoding="utf-8").write(s)


def fixture(tree):
    """The same git history, decisions.log and lessons.md in each tree: four GENERATE hops with events, before the
    lessons' day, so each lesson is NEW (not SETTLED, not NO MATCH). The line shows L1, L2 and L4 (L3 does not fit).
    No law shard in either tree, so both print the same laws line."""
    sh(tree, "rm", "-rf", ".cascade")
    laws = os.path.join(tree, "docs", "cascade", "laws")   # the hook is measured, not this repo's laws: none in either
    for f in (os.listdir(laws) if os.path.isdir(laws) else []):
        if f.endswith(".md") and f != "README.md":
            os.remove(os.path.join(laws, f))
    os.makedirs(os.path.join(tree, ".cascade"))
    sh(tree, "git", "init", "-q")
    set_hop(tree, "NONE", "05b", "s0")
    sh(tree, "git", "add", "-A")
    stamp = "2026-01-01T00:00:00Z"
    sh(tree, "git", "commit", "-qm", "fixture", env={"GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp})
    log = []
    for i in range(1, 5):
        set_hop(tree, "GENERATE", "05b", f"s{i}")
        stamp = f"2026-01-0{i + 1}T00:00:00Z"
        sh(tree, "git", "commit", "-qam", f"cascade: open GENERATE 05b s{i}",
           env={"GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp})
        for actor, verdict, why, _ in LESSONS[:3]:
            log.append(f"2026-01-0{i + 1}T06:00:00Z  {actor}  {verdict}  {why}  src=agent")
        if i == 1:   # the short fourth lesson ranks last and fills the room the third one leaves
            actor, verdict, why, _ = LESSONS[3]
            log.append(f"2026-01-02T07:00:00Z  {actor}  {verdict}  {why}  src=agent")
    open(os.path.join(tree, ".cascade", "decisions.log"), "w").write("\n".join(log) + "\n")
    with open(os.path.join(tree, "docs", "cascade", "lessons.md"), "w", encoding="utf-8") as f:
        f.write("# Lessons\n\n")
        for n, (actor, verdict, why, do) in enumerate(LESSONS, 1):
            f.write(f'LESSON L{n}: {actor} {verdict} "{why}" | scope: ANY | since: 2026-06-01 | do: {do}\n')


PADDER = """import json, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
r = subprocess.run([sys.executable, "-B", os.path.join(here, "seam_unpadded.py")], input=sys.stdin.read(),
                   capture_output=True, text=True)
if r.stdout.strip():
    d = json.loads(r.stdout)
    d["hookSpecificOutput"]["additionalContext"] += "x" * %d
    json.dump(d, sys.stdout)
sys.exit(r.returncode)
"""


def padded(tree, n):
    """The red twin: the prompt hook adds n bytes to every context it prints (BUDGET_PAD)."""
    hooks = os.path.join(tree, ".claude", "hooks")
    os.replace(os.path.join(hooks, "seam.py"), os.path.join(hooks, "seam_unpadded.py"))
    open(os.path.join(hooks, "seam.py"), "w").write(PADDER % n)


def context(tree, hop, stage, prompt, n):
    set_hop(tree, hop, stage, "budget")
    ev = {"cwd": tree, "prompt": prompt, "prompt_id": f"budget-{n}", "session_id": "budget",
          "hook_event_name": "UserPromptSubmit"}
    r = sh(tree, sys.executable, "-B", os.path.join(tree, ".claude", "hooks", "seam.py"), input=json.dumps(ev),
           timeout=120)
    if not r.stdout.strip():
        return ""
    try:
        return json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
    except (ValueError, KeyError, TypeError):
        print(f"BUDGET: the prompt hook printed no JSON in {tree}: {r.stdout[:200]!r} {r.stderr[:200]!r}")
        sys.exit(1)


for t in (old, new):
    fixture(t)
if pad:
    padded(new, pad)
ok = total = 0
lessons = 0
for label, hop, stage in CLASSES:
    for kind, prompt in PROMPTS:
        total += 1
        ca, cb = context(old, hop, stage, prompt, total), context(new, hop, stage, prompt, total)
        a, b = len(ca.encode("utf-8")), len(cb.encode("utf-8"))
        if (label, kind) == ("GENERATE", "plain"):
            lessons = max([len(x.encode("utf-8")) for x in cb.splitlines() if x.startswith("LESSONS THIS HOP: ")] or [0])
        passed = b - a <= grow
        ok += passed
        print(f"BUDGET {label + '/' + kind:<24} 3.5.6: {a} bytes  now: {b} bytes  grew: {b - a:+d}  limit: +{grow}  "
              f"{'PASS' if passed else 'FAIL'}")
print(f"BUDGET fixture: the lessons line is {lessons} bytes on GENERATE/plain")
print(f"BUDGET {ok}/{total}  (each prompt may grow at most +{grow} bytes over 3.5.6)")
sys.exit(0 if ok == total else 1)
PY
