#!/usr/bin/env bash
# t97 oracle: the pack's self-check job reaches a verdict, and it passes only for the gate's real refusal on the pack.
# This file never runs the gate on $ROOT. The gate runs tests/regress.sh, and regress.md can hold this file after
# carry-out, so that call would not end. AC2 runs the real gate on fixtures through BARBAR_ROOT.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE BARBAR_ROOT
WF="$ROOT/.github/workflows/pack-self-check.yml"
FULL="$ROOT/.github/workflows/pack-install-repair.yml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/t97.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ac() { if [[ "$2" -eq 1 ]]; then echo "  ok    $1"; else FAILS=$((FAILS+1)); echo "  FAIL  $1  ${3:-}"; fi; }
yes_if() { if "$@"; then echo 1; else echo 0; fi; }

# job <field>: read the self-check job from the workflow text, with no YAML library.
job() { python3 -B - "$WF" "$1" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
start = next((i for i, l in enumerate(lines) if l == "  self-check:"), None)
jobs = next((i for i, l in enumerate(lines) if l == "jobs:"), len(lines))
field = sys.argv[2]
if field == "top":
    # Every key above `jobs:` must be expected, so nothing can filter or disable the workflow.
    allowed = {"name", "on", "pull_request", "push", "branches", "permissions", "contents"}
    for l in lines[:jobs]:
        s = l.strip()
        if not s or s.startswith("#"):
            continue
        k = s.split(":", 1)[0]
        if k not in allowed:
            print(s)
        elif k == "branches" and s != "branches: [main]":
            print(s)
    sys.exit(0)
if start is None:
    sys.exit(0)
end = next((i for i in range(start + 1, len(lines)) if re.match(r"  \S", lines[i])), len(lines))
body = lines[start + 1:end]
# Split the job's own keys from the text of its run blocks.
keys, run = [], []
i = 0
while i < len(body):
    l = body[i]
    m = re.match(r"(\s*)(- )?([\w-]+):\s*(.*)$", l)
    if m and m.group(3) == "run":
        keys.append((len(m.group(1)), "run", m.group(4)))
        if m.group(4).strip() in ("|", "|-", ">"):
            i += 1
            ind = None
            while i < len(body) and (not body[i].strip() or ind is None or body[i].startswith(ind)):
                if ind is None and body[i].strip():
                    ind = re.match(r"\s*", body[i]).group(0)
                run.append(body[i][len(ind or ""):])
                i += 1
            continue
        run.append(m.group(4))
    elif m:
        keys.append((len(m.group(1)), m.group(3), m.group(4)))
    elif l.strip() and not l.strip().startswith("#"):
        keys.append((0, "unparsed:" + l.strip(), ""))
    i += 1
if field == "run":
    print("\n".join(run))
elif field == "timeout":
    for ind, k, v in keys:
        if k == "timeout-minutes" and ind == 4:
            print(v.split("#")[0].strip())
elif field == "fetch-depth":
    for ind, k, v in keys:
        if k == "fetch-depth":
            print(v.split("#")[0].strip())
elif field == "bad":
    # Allow only the keys the job needs. continue-on-error, if, env, shell, needs, strategy, working-directory and a
    # step-level limit can each make the job green, or cancel it, whatever its run step says.
    allowed = {"runs-on", "timeout-minutes", "steps", "uses", "with", "fetch-depth", "name", "run"}
    for ind, k, v in keys:
        if k not in allowed or (k == "timeout-minutes" and ind != 4):
            print(k)
PY
}

job run > "$TMP/job.sh"
ac "AC0 the self-check job has a run step" "$([[ -s "$TMP/job.sh" ]] && echo 1 || echo 0)" "no self-check job or no run step in $WF"

# ---- A stub tests/barbar.sh. The job runs as GitHub runs a step with no shell key: `bash -e`, in the checkout.
W="$TMP/stub"; mkdir -p "$W/tests"
cat > "$W/tests/barbar.sh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
[[ -n "${BARBAR_ROOT:-}" ]] && echo "BARBAR_ROOT=$BARBAR_ROOT" >> "$STUB_LOG"
[[ -n "${STUB_TEXT:-}" ]] && echo "$STUB_TEXT"
exit "${STUB_RC:-0}"
STUB
# stubrun <text> <rc>: sets JOB_RC and JOB_OUT.
stubrun() {
  : > "$TMP/stub.log"
  JOB_OUT="$(cd "$W" && STUB_LOG="$TMP/stub.log" STUB_TEXT="$1" STUB_RC="$2" bash -e "$TMP/job.sh" 2>&1)"; JOB_RC=$?
}
REAL="BARBAR merge REFUSED: need stage 10 CLEAN by tests/audit.sh (=0, AUDIT 0/0) AND stage 11 READY (=0) human-signed inside <EDIT> (=0) AND every D# GREEN (DSHARP 0/0)"

# ---- AC1 the job calls the gate alone, on the pack, and passes on the pack's real refusal
stubrun "$REAL" 2
ac "AC1 the job passes on the gate's real refusal" "$([[ "$JOB_RC" -eq 0 ]] && echo 1 || echo 0)" "rc=$JOB_RC: $JOB_OUT"
ac "AC1 the job calls barbar.sh gate, one time, on the pack" "$([[ "$(cat "$TMP/stub.log")" == "gate" ]] && echo 1 || echo 0)" "calls: $(tr '\n' ';' < "$TMP/stub.log")"
ac "AC1 the job log shows the gate's output" "$(grep -qF 'BARBAR merge REFUSED' <<<"$JOB_OUT" && echo 1 || echo 0)"
ac "AC1 the job never names BARBAR_ROOT" "$(grep -q 'BARBAR_ROOT' "$TMP/job.sh" && echo 0 || echo 1)"

# ---- AC2 the real gate, on fixtures: the text the job reads is the text the gate prints
real() { ( cd "$ROOT" && BARBAR_ROOT="$ROOT/evals/fixtures/$1" bash -e "$TMP/job.sh" >"$TMP/real.out" 2>&1 ); }
# A job that does not call `gate` alone can start the full farm here, so it fails with no real run.
if [[ "$(cat "$TMP/stub.log")" == "gate" ]] && ! grep -q 'BARBAR_ROOT' "$TMP/job.sh"; then
  real no-prr-product; rc=$?
  ac "AC2 the real gate on a product with no stage 11: the job passes" "$([[ "$rc" -eq 0 ]] && echo 1 || echo 0)" "rc=$rc: $(tail -2 "$TMP/real.out" | cut -c1-200)"
  real ready-product; rc=$?
  ac "AC2 the real gate allows a ready product: the job fails" "$([[ "$rc" -ne 0 ]] && echo 1 || echo 0)" "rc=$rc"
else
  ac "AC2 the real gate runs" 0 "not run: the job does not call barbar.sh gate alone, on the pack"
fi

# ---- AC3 a non-zero exit alone is not a refusal
nofail() { stubrun "$2" "$3"; ac "AC3 the job fails: $1" "$([[ "$JOB_RC" -ne 0 ]] && echo 1 || echo 0)" "the job passed with rc=$JOB_RC"; }
nofail "the gate allows"                       "BARBAR merge ALLOWED: 10 AUDIT 2/2 CLEAN + 11 READY (human-signed)" 0
nofail "the gate crashes with no text"         "" 1
nofail "the gate script is not found"          "bash: tests/barbar.sh: No such file or directory" 127
nofail "the farm refuses, not the gate"        "BARBAR merge REFUSED: farm is not n/n. Fix the farm; do not write product code to fix it." 2
nofail "stage 10 is clean"                     "BARBAR merge REFUSED: need stage 10 CLEAN by tests/audit.sh (=1, AUDIT 2/2) AND stage 11 READY (=0) human-signed inside <EDIT> (=0)" 2
nofail "stage 11 is ready"                     "BARBAR merge REFUSED: need stage 10 CLEAN by tests/audit.sh (=0, AUDIT 0/0) AND stage 11 READY (=1) human-signed inside <EDIT> (=1)" 2
nofail "tests/audit.sh crashed: no score"      "BARBAR merge REFUSED: need stage 10 CLEAN by tests/audit.sh (=0, ) AND stage 11 READY (=0) human-signed inside <EDIT> (=0)" 2
nofail "refusal text with exit 0"              "$REAL" 0

# ---- AC4 the job has the time and the history that the gate needs
t="$(job timeout | head -1)"
ac "AC4 timeout-minutes is 15 to 60" "$([[ "$t" =~ ^[0-9]+$ && "$t" -ge 15 && "$t" -le 60 ]] && echo 1 || echo 0)" "timeout-minutes=${t:-none}"
d="$(job fetch-depth | head -1)"
ac "AC4 the checkout has the full history" "$([[ "$d" == "0" ]] && echo 1 || echo 0)" "fetch-depth=${d:-default}"

# ---- AC5 YAML cannot switch the job off, and the rest of the workflow stays
bad="$(job bad)"
ac "AC5 the job holds only the keys it needs" "$([[ -z "$bad" ]] && echo 1 || echo 0)" "$(tr '\n' ' ' <<<"$bad")"
top="$(job top)"
ac "AC5 no filter or default above jobs" "$([[ -z "$top" ]] && echo 1 || echo 0)" "$(tr '\n' ' ' <<<"$top")"
ac "AC5 the workflow still runs on pull_request and on a push to main" \
  "$(grep -qE '^  pull_request:[[:space:]]*$' "$WF" && grep -qE '^    branches: \[main\]' "$WF" && echo 1 || echo 0)"
ac "AC5 the gradle-runner job stays" "$(grep -qE '^  gradle-runner:' "$WF" && echo 1 || echo 0)"
ac "AC5 barbar.sh merge still runs the farm first" \
  "$(awk '/^  merge\)/{f=1} f&&/run_farm/{print "y"; exit}' "$ROOT/tests/barbar.sh" | grep -q y && echo 1 || echo 0)"

# ---- AC6 the suite holds the fast t96 line, so the gate and the regress job stay inside their limits
RG="$ROOT/docs/cascade/regress.md"
ac "AC6 regress.md runs t96 fast" "$(grep -qE '^REGRESS: T96_FAST=1 bash tests/ac/t96_install_repairs\.sh[[:space:]]*$' "$RG" && echo 1 || echo 0)"
ac "AC6 regress.md does not run the full t96" "$(grep -qE '^REGRESS: bash tests/ac/t96_install_repairs\.sh' "$RG" && echo 0 || echo 1)" "goal.sh carry-out adds this line back; remove it before the commit"

# ---- AC7 a scheduled pack-only workflow keeps the full t96 running
if [[ -f "$FULL" ]]; then
  ac "AC7 the full workflow runs on a schedule and by hand" "$(grep -qE '^  schedule:' "$FULL" && grep -qE '^  workflow_dispatch:' "$FULL" && echo 1 || echo 0)"
  ac "AC7 it runs the full t96" "$(grep -qE '^[[:space:]]+run: bash tests/ac/t96_install_repairs\.sh[[:space:]]*$' "$FULL" && echo 1 || echo 0)"
  ac "AC7 it does not set T96_FAST" "$(grep -q 'T96_FAST' "$FULL" && echo 0 || echo 1)"
  ft="$(sed -nE 's/^[[:space:]]+timeout-minutes:[[:space:]]*([0-9]+).*/\1/p' "$FULL" | head -1)"
  ac "AC7 its limit is 120 to 360 minutes" "$([[ "$ft" =~ ^[0-9]+$ && "$ft" -ge 120 && "$ft" -le 360 ]] && echo 1 || echo 0)" "timeout-minutes=${ft:-none}"
  ac "AC7 it has no switch-off key" "$(grep -qE '^[[:space:]]*(- )?(continue-on-error|if):' "$FULL" && echo 0 || echo 1)"
else
  ac "AC7 the full workflow exists" 0 "no $FULL"
fi
ac "AC7 install.sh does not ship it" "$(grep -q 'pack-install-repair' "$ROOT/install.sh" && echo 0 || echo 1)"

if [[ "$FAILS" -gt 0 ]]; then echo "T97 AC FAILED ($FAILS)"; exit 1; fi
echo "T97 AC all PASS"
