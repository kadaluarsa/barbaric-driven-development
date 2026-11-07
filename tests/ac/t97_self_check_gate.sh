#!/usr/bin/env bash
# t97 oracle: the pack's self-check job reaches a verdict, and it passes only for the gate's real refusal.
# This file never runs the gate on $ROOT. The gate runs tests/regress.sh, and regress.md can hold this file after
# carry-out, so that call would not end. AC2 runs the real gate on fixtures through BARBAR_ROOT.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE BARBAR_ROOT
WF="$ROOT/.github/workflows/pack-self-check.yml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/t97.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ac() { if [[ "$2" -eq 1 ]]; then echo "  ok    $1"; else FAILS=$((FAILS+1)); echo "  FAIL  $1  ${3:-}"; fi; }

# job <field>: read one field of the self-check job from the workflow text, with no YAML library.
job() { python3 -B - "$WF" "$1" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
start = next((i for i, l in enumerate(lines) if l == "  self-check:"), None)
if start is None:
    sys.exit(0)
end = next((i for i in range(start + 1, len(lines)) if re.match(r"  \S", lines[i])), len(lines))
body = lines[start + 1:end]
field = sys.argv[2]
if field == "timeout":
    for l in body:
        m = re.match(r"    timeout-minutes:\s*(\d+)", l)
        if m:
            print(m.group(1))
elif field == "fetch-depth":
    for l in body:
        m = re.match(r"\s+fetch-depth:\s*(\d+)", l)
        if m:
            print(m.group(1))
elif field == "run":
    i = 0
    while i < len(body):
        m = re.match(r"(\s+)(?:- )?run:\s*(.*)$", body[i])
        if m and m.group(2).strip() not in ("|", "|-", ">"):
            print(m.group(2))
        elif m:
            i += 1
            ind = None
            while i < len(body) and (not body[i].strip() or ind is None or body[i].startswith(ind)):
                if ind is None and body[i].strip():
                    ind = re.match(r"\s*", body[i]).group(0)
                print(body[i][len(ind or ""):])
                i += 1
            continue
        i += 1
PY
}

job run > "$TMP/job.sh"
ac "AC0 the self-check job has a run step" "$([[ -s "$TMP/job.sh" ]] && echo 1 || echo 0)" "no self-check job or no run step in $WF"

# ---- A stub tests/barbar.sh. The job runs as GitHub runs it: `bash -e`, with the checkout as the working directory.
W="$TMP/stub"; mkdir -p "$W/tests"
cat > "$W/tests/barbar.sh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
[[ -n "${STUB_TEXT:-}" ]] && echo "$STUB_TEXT"
exit "${STUB_RC:-0}"
STUB
# stubrun <text> <rc>: sets JOB_RC and JOB_OUT.
stubrun() {
  : > "$TMP/stub.log"
  JOB_OUT="$(cd "$W" && STUB_LOG="$TMP/stub.log" STUB_TEXT="$1" STUB_RC="$2" bash -e "$TMP/job.sh" 2>&1)"; JOB_RC=$?
}
REAL="BARBAR merge REFUSED: need stage 10 CLEAN by tests/audit.sh (=0, AUDIT 0/0) AND stage 11 READY (=0) human-signed inside <EDIT> (=0) AND every D# GREEN (DSHARP 0/0)"

# ---- AC1 the job calls the gate alone, and passes on the pack's real refusal
stubrun "$REAL" 2
ac "AC1 the job passes on the gate's real refusal" "$([[ "$JOB_RC" -eq 0 ]] && echo 1 || echo 0)" "rc=$JOB_RC: $JOB_OUT"
ac "AC1 the job calls barbar.sh gate, one time, and not merge" "$([[ "$(cat "$TMP/stub.log")" == "gate" ]] && echo 1 || echo 0)" "calls: $(tr '\n' ';' < "$TMP/stub.log")"
ac "AC1 the job log shows the gate's output" "$(grep -qF 'BARBAR merge REFUSED' <<<"$JOB_OUT" && echo 1 || echo 0)"

# ---- AC2 the real gate, on fixtures: the text the job reads is the text the gate prints
real() { ( cd "$ROOT" && BARBAR_ROOT="$ROOT/evals/fixtures/$1" bash -e "$TMP/job.sh" >"$TMP/real.out" 2>&1 ); }
# A job that does not call `gate` alone can start the full farm here, so it fails with no real run.
if [[ "$(cat "$TMP/stub.log")" == "gate" ]]; then
  real no-prr-product; rc=$?
  ac "AC2 the real gate on a product with no stage 11: the job passes" "$([[ "$rc" -eq 0 ]] && echo 1 || echo 0)" "rc=$rc: $(tail -2 "$TMP/real.out" | cut -c1-200)"
  real ready-product; rc=$?
  ac "AC2 the real gate allows a ready product: the job fails" "$([[ "$rc" -ne 0 ]] && echo 1 || echo 0)" "rc=$rc"
else
  ac "AC2 the real gate runs" 0 "not run: the job does not call barbar.sh gate alone"
fi

# ---- AC3 a non-zero exit alone is not a refusal
nofail() { stubrun "$2" "$3"; ac "AC3 the job fails: $1" "$([[ "$JOB_RC" -ne 0 ]] && echo 1 || echo 0)" "the job passed with rc=$JOB_RC"; }
nofail "the gate allows"                       "BARBAR merge ALLOWED: 10 AUDIT 2/2 CLEAN + 11 READY (human-signed)" 0
nofail "the gate crashes with no text"         "" 1
nofail "the gate script is not found"          "bash: tests/barbar.sh: No such file or directory" 127
nofail "the farm refuses, not the gate"        "BARBAR merge REFUSED: farm is not n/n. Fix the farm; do not write product code to fix it." 2
nofail "stage 10 is clean"                     "BARBAR merge REFUSED: need stage 10 CLEAN by tests/audit.sh (=1, AUDIT 2/2) AND stage 11 READY (=0) human-signed inside <EDIT> (=0)" 2
nofail "stage 11 is ready"                     "BARBAR merge REFUSED: need stage 10 CLEAN by tests/audit.sh (=0, AUDIT 0/0) AND stage 11 READY (=1) human-signed inside <EDIT> (=1)" 2
nofail "refusal text with exit 0"              "$REAL" 0

# ---- AC4 the job has the time and the history that the gate needs
t="$(job timeout | head -1)"
ac "AC4 timeout-minutes is 15 to 60" "$([[ "$t" =~ ^[0-9]+$ && "$t" -ge 15 && "$t" -le 60 ]] && echo 1 || echo 0)" "timeout-minutes=${t:-none}"
d="$(job fetch-depth | head -1)"
ac "AC4 the checkout has the full history" "$([[ "$d" == "0" ]] && echo 1 || echo 0)" "fetch-depth=${d:-default}"

# ---- AC5 the rest of the workflow stays
ac "AC5 the workflow still runs on pull_request and on a push to main" \
  "$(grep -qE '^  pull_request:' "$WF" && grep -qE 'branches: \[main\]' "$WF" && echo 1 || echo 0)"
ac "AC5 the gradle-runner job stays" "$(grep -qE '^  gradle-runner:' "$WF" && grep -q 'timeout-minutes: 45' "$WF" && echo 1 || echo 0)"
ac "AC5 barbar.sh merge still runs the farm first" \
  "$(awk '/^  merge\)/{f=1} f&&/run_farm/{print "y"; exit}' "$ROOT/tests/barbar.sh" | grep -q y && echo 1 || echo 0)"

if [[ "$FAILS" -gt 0 ]]; then echo "T97 AC FAILED ($FAILS)"; exit 1; fi
echo "T97 AC all PASS"
