#!/usr/bin/env bash
# AC tests for 05b t93-adaptive-effort-routing — THE ORACLE for this slice, written at GENERATE before any
# implementation and pinned (with tests/ac/data/t93_effort_cases.json) in
# docs/cascade/05b-t93-adaptive-effort-routing.oracle. EXECUTE builds against it and does not edit it.
#   AC1  exact defaults, phases, route mapping and phase precedence (table).
#   AC2  every single risk tag floors high in every phase; a low override keeps the high target (table).
#   AC3  same-task state: escalation on new evidence, stall, changed-without-evidence, retention, task reset.
#   AC4  fictional OpenAI/Anthropic/Gemini level+budget profiles resolve; null mapping and bad overrides do not.
#   AC5  transition precedence is total: unsupported > absent-current > equal > next-session > update > unknown.
#   AC6  strict inputs: malformed context/profile, bounds, size, dup keys, NaN, UTF-8 -> exit 2 without leaking
#        input content; --help 0; portable byte-identical output from any cwd and host env; 14-key shape.
#   AC7  the seam's EFFORT line: one bounded advisory line on routed prompts, silence on whitespace/idle
#        questions, BDD_EFFORT=off byte-preserves the rest, a missing helper never blocks the prompt.
#   AC8  standalone install ships the helper+wrapper and is idempotent; the three bdd-work copies agree.
#   AC9  RED TWINS on tests/lib/effort.py: always-low fails risk cases, always-high fails simple plans,
#        ignoring task identity fails state cases, always-preserves-cache fails transitions, applied fails status.
# Every table expectation follows the spec's Decision contract, Policy and Frozen interpretations.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED PLUGIN_ROOT BDD_HOOK_HOST CLAUDE_PLUGIN_ROOT BDD_MODEL BDD_EFFORT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 BDD_AUTO_REFRESH=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOOKS="$ROOT/.claude/hooks"
DATA="$ROOT/tests/ac/data/t93_effort_cases.json"
SENTINEL=SENTINEL-7c1f

# ---- the table runner (python): exact per-case comparison, t-style group summaries -------------------------------
mkdir -p "$TMP/py"
cat > "$TMP/py/runner.py" <<'PY'
#!/usr/bin/env python3
"""Run the frozen t93 case table against the CLI. --root = wrapper mode, --module = direct module (twins)."""
import json, os, subprocess, sys

argv = sys.argv[1:]
def opt(name, need=True):
    if name in argv:
        i = argv.index(name)
        if need:
            return argv[i + 1]
        return True
    return None

data = json.load(open(opt("--data"), encoding="utf-8"))["cases"]
only = (opt("--only") or "").split(",") if opt("--only") else []
only = [x for x in only if x]
if only:
    wanted, data = set(only), [c for c in data if c["id"] in only]
    missing = wanted - {c["id"] for c in data}
    if missing:
        print("FAIL  runner unknown case ids: " + ",".join(sorted(missing))); sys.exit(1)
if not data:
    print("FAIL  runner no cases selected"); sys.exit(1)
tmp = opt("--tmp"); os.makedirs(tmp, exist_ok=True)
KEYS = {"schema_version", "route", "phase", "quality_target", "reasons", "next_action", "resolved_setting",
        "compatibility", "transition", "cache_effect", "application_status", "warnings", "profile", "state"}
MAP = {"bug-fix": "debug", "feature": "code", "refactor": "code", "verification": "verify",
       "investigation": "investigate", "ambiguous": "unknown"}

def expect_phase(ctx):
    p = ctx.get("phase")
    if p and p != "unknown":   # phase "unknown" is no knowledge: it maps like an absent phase (spec, frozen)
        return p
    hop, stage = ctx.get("hop", "NONE"), ctx.get("stage", "")
    if hop == "GENERATE":
        return "spec"
    if hop == "EXECUTE" and stage in ("10", "11"):
        return "review"
    return MAP[ctx["route"]]

def run_cli(c):
    cw = os.path.join(tmp, c["id"] + ".ctx.json")
    open(cw, "w", encoding="utf-8").write(json.dumps(c["context"], sort_keys=True))
    if opt("--module"):
        cmd = ["python3", "-B", opt("--module"), "--context", cw]
    else:
        cmd = ["bash", os.path.join(opt("--root"), "tests", "effort.sh"), "--context", cw]
    if c.get("profile") is not None:
        pw = os.path.join(tmp, c["id"] + ".prof.json")
        open(pw, "w", encoding="utf-8").write(json.dumps(c["profile"], sort_keys=True))
        cmd += ["--profile", pw]
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r

def check(c):
    r = run_cli(c)
    if r.returncode != 0:
        return [f"exit={r.returncode} stderr={r.stderr[:120]}"]
    problems = []
    if not (r.stdout.endswith("\n") and not r.stdout.endswith("\n\n")):
        problems.append("stdout must end with exactly one newline")
    try:
        o = json.loads(r.stdout)
    except ValueError:
        return problems + ["stdout is not JSON"]
    if not isinstance(o, dict):
        return problems + ["decision is not an object"]
    if set(o) != KEYS:
        problems.append("keys " + ",".join(sorted(set(o) ^ KEYS)))
    if list(o) != sorted(o):
        problems.append("keys not sorted")
    e = c["expect"]
    if o.get("application_status") != "not_applied":
        problems.append(f"application_status={o.get('application_status')}")
    for k, want in (("schema_version", 1), ("quality_target", e["quality_target"]),
                    ("next_action", e["next_action"]), ("compatibility", e["compatibility"]),
                    ("transition", e["transition"]), ("cache_effect", e["cache_effect"]),
                    ("resolved_setting", e["resolved_setting"]), ("reasons", e["reasons"]),
                    ("warnings", e["warnings"]), ("state", e["state"]), ("profile", e["profile_object"])):
        if o.get(k) != want:
            problems.append(f"{k}={json.dumps(o.get(k))} want {json.dumps(want)}")
    if o.get("route") != c["context"]["route"]:
        problems.append(f"route={o.get('route')}")
    if o.get("phase") != expect_phase(c["context"]):
        problems.append(f"phase={o.get('phase')} want {expect_phase(c['context'])}")
    return problems

groups, counts = [], {}
for c in data:
    problems = check(c)
    g = c["group"]
    counts.setdefault(g, [0, 0]); counts[g][1] += 1
    if problems:
        print(f"FAIL  {c['id']}  " + "; ".join(problems)[:220])
    else:
        counts[g][0] += 1
bad = 0
for g, (k, n) in sorted(counts.items()):
    ok = int(k == n)
    bad |= 1 - ok
    print(f"{'PASS' if ok else 'FAIL'}  {g}-table  {k}/{n} exact cases")
sys.exit(bad)
PY

python3 -B "$TMP/py/runner.py" --data "$DATA" --root "$ROOT" --tmp "$TMP/table" || fail=1

# ---- AC6 — strict inputs: every malformed file exits 2, silently --------------------------------------------------------------------------
jfield() {  # jfield <field> <want> — parse-based field check: the spec pins sorted keys and encoding, not separators
  python3 -c 'import json,sys
try:
    sys.exit(0 if json.loads(sys.stdin.read()).get(sys.argv[1]) == sys.argv[2] else 1)
except ValueError:
    sys.exit(1)' "$1" "$2"
}
ac6=1
ct() { # ct <label> <body> — malformed context file
  local label="$1" f="$TMP/bad-$1.json" o e r
  printf '%s' "$2" > "$f"
  o="$(bash "$ROOT/tests/effort.sh" --context "$f" 2>"$TMP/err")"; r=$?; e="$(cat "$TMP/err")"
  [[ $r -eq 2 && -z "$o" && -n "$e" && ${#e} -le 4096 && "$e$o" != *"$SENTINEL"* ]] || { echo "FAIL  AC6-ctx-$label  rc=$r out=${#o} err=${#e}"; ac6=0; }
}
pt() { # pt <label> <profile body> — valid context, malformed profile
  local label="$1" f="$TMP/bp-$1.json" o e r
  printf '%s' '{"schema_version": 1, "route": "feature"}' > "$TMP/goodctx.json"
  printf '%s' "$2" > "$f"
  o="$(bash "$ROOT/tests/effort.sh" --context "$TMP/goodctx.json" --profile "$f" 2>"$TMP/err")"; r=$?; e="$(cat "$TMP/err")"
  [[ $r -eq 2 && -z "$o" && -n "$e" && ${#e} -le 4096 && "$e$o" != *"$SENTINEL"* ]] || { echo "FAIL  AC6-prof-$label  rc=$r out=${#o} err=${#e}"; ac6=0; }
}
ct bad-json            '{'
ct missing-route       "{\"schema_version\": 1, \"task_id\": \"$SENTINEL\"}"
ct version-string      '{"schema_version": "1", "route": "feature"}'
ct version-bool        '{"schema_version": true, "route": "feature"}'
ct version-2           '{"schema_version": 2, "route": "feature"}'
ct version-float       '{"schema_version": 1.0, "route": "feature"}'
ct route-caps          '{"schema_version": 1, "route": "Feature"}'
ct route-sentinel      "{\"schema_version\": 1, \"route\": \"$SENTINEL\"}"
ct phase-bad           '{"schema_version": 1, "route": "feature", "phase": "Design"}'
ct hop-bad             "{\"schema_version\": 1, \"route\": \"feature\", \"hop\": \"$SENTINEL\"}"
ct stage-bad           '{"schema_version": 1, "route": "feature", "stage": "12"}'
ct stage-bad2          '{"schema_version": 1, "route": "feature", "stage": "05a"}'
ct risk-unknown        "{\"schema_version\": 1, \"route\": \"feature\", \"risk_tags\": [\"$SENTINEL\"]}"
ct risk-dup            '{"schema_version": 1, "route": "feature", "risk_tags": ["auth", "auth"]}'
ct risk-not-list       '{"schema_version": 1, "route": "feature", "risk_tags": "auth"}'
ct task-long           "{\"schema_version\": 1, \"route\": \"feature\", \"task_id\": \"$SENTINEL-$(python3 -c 'print("x"*130)')\"}"
ct task-number         '{"schema_version": 1, "route": "feature", "task_id": 5}'
ct prev-empty          '{"schema_version": 1, "route": "feature", "previous": {}}'
ct prev-partial        "{\"schema_version\": 1, \"route\": \"feature\", \"previous\": {\"task_id\": \"$SENTINEL\", \"quality_target\": \"medium\", \"failure_fingerprint\": \"f1\"}}"
ct prev-extra          '{"schema_version": 1, "route": "feature", "previous": {"task_id": "t1", "quality_target": "medium", "failure_fingerprint": "f1", "evidence_fingerprint": "e1", "note": "x"}}'
ct prev-target-bad     '{"schema_version": 1, "route": "feature", "previous": {"task_id": "t1", "quality_target": "urgent", "failure_fingerprint": null, "evidence_fingerprint": null}}'
ct failure-partial     "{\"schema_version\": 1, \"route\": \"feature\", \"failure\": {\"failure_fingerprint\": \"$SENTINEL\"}}"
ct failure-empty       '{"schema_version": 1, "route": "feature", "failure": {"failure_fingerprint": "", "evidence_fingerprint": "e1"}}'
ct setting-long        "{\"schema_version\": 1, \"route\": \"feature\", \"current_setting\": \"$SENTINEL-$(python3 -c 'print("y"*65)')\"}"
ct override-empty      '{"schema_version": 1, "route": "feature", "override": ""}'
ct override-long       "{\"schema_version\": 1, \"route\": \"feature\", \"override\": \"$SENTINEL-$(python3 -c 'print("z"*65)')\"}"
ct complexity-bad      "{\"schema_version\": 1, \"route\": \"feature\", \"complexity\": \"$SENTINEL\"}"
ct uncertainty-bad     '{"schema_version": 1, "route": "feature", "uncertainty": "certain"}'
ct extra-key           "{\"schema_version\": 1, \"route\": \"feature\", \"$SENTINEL\": 1}"
ct top-array           '[{"schema_version": 1, "route": "feature"}]'
ct top-string          '"'"$SENTINEL"'"'
ct dup-keys            '{"schema_version": 1, "route": "feature", "route": "bug-fix"}'
ct nan-value           '{"schema_version": 1, "route": NaN}'
ct inf-value           "{\"schema_version\": 1, \"task_id\": \"$SENTINEL\", \"uncertainty\": Infinity}"
ct bool-string         '{"schema_version": 1, "route": true}'
pt prof-http-source    '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "http://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-bad-date       '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-02-30", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-not-date       "{\"schema_version\": 1, \"provider\": \"p\", \"model\": \"$SENTINEL\", \"platform\": \"pf\", \"source_url\": \"https://example.test/x\", \"verified_on\": \"not-a-date\", \"control\": \"reasoning.effort\", \"update_mode\": \"turn-update\", \"cache_effect\": \"unknown\", \"supported_values\": [\"low\"], \"mapping\": {\"low\": \"low\", \"medium\": null, \"high\": null}}"
pt prof-no-values      '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": [], "mapping": {"low": null, "medium": null, "high": null}}'
pt prof-dup-values     '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low", "low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-mapping-partial '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low"}}'
pt prof-mapping-unknown '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "xx", "medium": null, "high": null}}'
pt prof-control-bad    "{\"schema_version\": 1, \"provider\": \"p\", \"model\": \"m\", \"platform\": \"pf\", \"source_url\": \"https://example.test/x\", \"verified_on\": \"2026-10-01\", \"control\": \"$SENTINEL\", \"update_mode\": \"turn-update\", \"cache_effect\": \"unknown\", \"supported_values\": [\"low\"], \"mapping\": {\"low\": \"low\", \"medium\": null, \"high\": null}}"
pt prof-other-noknob   '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "other", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-knob-mismatch  '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "control_name": "x.y", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-empty-provider '{"schema_version": 1, "provider": "", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-extra-key      "{\"schema_version\": 1, \"provider\": \"p\", \"model\": \"m\", \"platform\": \"pf\", \"source_url\": \"https://example.test/x\", \"verified_on\": \"2026-10-01\", \"control\": \"reasoning.effort\", \"update_mode\": \"turn-update\", \"cache_effect\": \"unknown\", \"supported_values\": [\"low\"], \"mapping\": {\"low\": \"low\", \"medium\": null, \"high\": null}, \"$SENTINEL\": {}}"
pt prof-no-version     '{"provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-mode-bad       "{\"schema_version\": 1, \"provider\": \"p\", \"model\": \"m\", \"platform\": \"pf\", \"source_url\": \"https://example.test/x\", \"verified_on\": \"2026-10-01\", \"control\": \"reasoning.effort\", \"update_mode\": \"$SENTINEL\", \"cache_effect\": \"unknown\", \"supported_values\": [\"low\"], \"mapping\": {\"low\": \"low\", \"medium\": null, \"high\": null}}"
pt prof-cache-bad      '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "maybe", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
# the same strictness the context side faces: dup keys, non-finite numbers, top level, version, bounds, case-sensitive enums (C3)
pt prof-dup-keys       '{"schema_version": 1, "schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-dup-nested     '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "low": "low", "medium": null, "high": null}}'
pt prof-nan            '{"schema_version": 1, "provider": NaN, "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-inf            "{\"schema_version\": 1, \"provider\": \"$SENTINEL\", \"model\": \"m\", \"platform\": \"pf\", \"source_url\": \"https://example.test/x\", \"verified_on\": \"2026-10-01\", \"control\": \"reasoning.effort\", \"update_mode\": \"turn-update\", \"cache_effect\": \"unknown\", \"supported_values\": [Infinity], \"mapping\": {\"low\": \"low\", \"medium\": null, \"high\": null}}"
pt prof-top-array      '[]'
pt prof-top-string     '"'"$SENTINEL"'"'
pt prof-version-float  '{"schema_version": 1.0, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-version-2      '{"schema_version": 2, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-identity-long  "{\"schema_version\": 1, \"provider\": \"$SENTINEL-$(python3 -c 'print("q"*2100)')\", \"model\": \"m\", \"platform\": \"pf\", \"source_url\": \"https://example.test/x\", \"verified_on\": \"2026-10-01\", \"control\": \"reasoning.effort\", \"update_mode\": \"turn-update\", \"cache_effect\": \"unknown\", \"supported_values\": [\"low\"], \"mapping\": {\"low\": \"low\", \"medium\": null, \"high\": null}}"
pt prof-native-long    "{\"schema_version\": 1, \"provider\": \"p\", \"model\": \"m\", \"platform\": \"pf\", \"source_url\": \"https://example.test/x\", \"verified_on\": \"2026-10-01\", \"control\": \"reasoning.effort\", \"update_mode\": \"turn-update\", \"cache_effect\": \"unknown\", \"supported_values\": [\"$SENTINEL-$(python3 -c 'print("z"*65)')\"], \"mapping\": {\"low\": \"low\", \"medium\": null, \"high\": null}}"
pt prof-mode-caps      '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "Turn-Update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'
pt prof-cache-caps     '{"schema_version": 1, "provider": "p", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "Unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}'

# invalid UTF-8 bytes in the profile file too (C3)
printf '{"schema_version": 1, "provider": "\xff\xfe", "model": "m", "platform": "pf", "source_url": "https://example.test/x", "verified_on": "2026-10-01", "control": "reasoning.effort", "update_mode": "turn-update", "cache_effect": "unknown", "supported_values": ["low"], "mapping": {"low": "low", "medium": null, "high": null}}' > "$TMP/prof-utf.json"
o="$(bash "$ROOT/tests/effort.sh" --context "$TMP/goodctx.json" --profile "$TMP/prof-utf.json" 2>"$TMP/err")"; r=$?; e="$(cat "$TMP/err")"
[[ $r -eq 2 && -z "$o" && -n "$e" ]] || { echo "FAIL  AC6-prof-utf8  rc=$r"; ac6=0; }

# invalid UTF-8 bytes
printf '{"schema_version": 1, "route": "\xff\xfe"}' > "$TMP/utf.json"
o="$(bash "$ROOT/tests/effort.sh" --context "$TMP/utf.json" 2>"$TMP/err")"; r=$?; e="$(cat "$TMP/err")"
[[ $r -eq 2 && -z "$o" && -n "$e" ]] || { echo "FAIL  AC6-utf8  rc=$r"; ac6=0; }

# oversized file (valid schema, 70 KiB of whitespace) -> the 64 KiB read cap, not a schema error
python3 -c 'open("'"$TMP"'/big.json","w").write(" " * 70000 + "{\"schema_version\": 1, \"route\": \"feature\"}")'
o="$(bash "$ROOT/tests/effort.sh" --context "$TMP/big.json" 2>"$TMP/err")"; r=$?
[[ $r -eq 2 && -z "$o" ]] || { echo "FAIL  AC6-bigfile  rc=$r"; ac6=0; }

# explicit unknown/unsupported decisions still exit 0
o="$(bash "$ROOT/tests/effort.sh" --context "$TMP/goodctx.json" 2>"$TMP/err")"; r=$?
[[ $r -eq 0 && -n "$o" ]] && printf '%s' "$o" | jfield compatibility unknown \
   && printf '%s' "$o" | jfield application_status not_applied \
  || { echo "FAIL  AC6-zero-unknown  rc=$r"; ac6=0; }
bash "$ROOT/tests/effort.sh" --help >/dev/null 2>&1 || { echo "FAIL  AC6-help"; ac6=0; }

# portable: byte-identical from any cwd and host env
printf '%s' '{"schema_version": 1, "route": "feature", "phase": "code"}' > "$TMP/port.json"
p1="$(bash "$ROOT/tests/effort.sh" --context "$TMP/port.json" 2>/dev/null)"
p2="$(cd "$TMP" && bash "$ROOT/tests/effort.sh" --context "$TMP/port.json" 2>/dev/null)"
p3="$(cd / && BDD_MODEL=zz BDD_HOOK_HOST=yy bash "$ROOT/tests/effort.sh" --context "$TMP/port.json" 2>/dev/null)"
[[ -n "$p1" && "$p1" == "$p2" && "$p1" == "$p3" ]] || { echo "FAIL  AC6-portable  outputs differ"; ac6=0; }
t AC6 "$ac6" "malformed context/profile inputs exit 2 with a bounded diagnostic that never echoes the input; size cap; --help; unknown/unsupported exit 0; portable bytes"

# ---- AC7 — the seam's EFFORT line ------------------------------------------------------------------------------------------
# mksb <dir> <HOP> <STAGE> — a scratch repo with the real hook and the pack's tests/lib (the helper lives there)
mksb() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests" "$d/.cascade"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"
  printf '# envelope\n\n## Laws\n\nnone\n' > "$d/docs/cascade/envelope.md"
  printf 'CURRENT_HOP: %s\nCURRENT_STAGE: %s\nCURRENT_SLICE: a\n' "$2" "$3" > "$d/docs/cascade/hop-state.md"
  printf '# skills\n' > "$d/docs/cascade/skill-binding.md"
  ( cd "$d" && git init -q )
}
seam_raw() {  # seam_raw <dir> <prompt> [ENV=V …] — seam.py's stdout left in the named out file, its exit status returned
  local out="$1" d="$2" p="$3"; shift 3
  printf '%s' "$p" | python3 -c 'import json,sys; print(json.dumps({"cwd": sys.argv[1], "prompt": sys.stdin.read(), "session_id": "s"}))' "$d" \
    | ( cd "$d" && env "$@" python3 -B "$HOOKS/seam.py" ) > "$out"
}
seam_ctx() {  # seam_ctx <dir> <prompt> [ENV=V …] — additionalContext of a UserPromptSubmit event (rc not preserved)
  local out="$TMP/seam-raw.json"
  seam_raw "$out" "$@" || true
  python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' < "$out" 2>/dev/null
}
n_effort() { grep -c '^EFFORT ' <<< "$1" || true; }   # EFFORT lines in an additionalContext
ac7=1
S1='the export button crashes on empty input, fix it'
D="$TMP/ac7e"; mksb "$D" EXECUTE 05b
c1="$(seam_ctx "$D" "$S1")"
l1="$(grep -m1 '^EFFORT ' <<< "$c1" || true)"
[[ "$c1" == *"ROUTE bug-fix"* && "$c1" == *"STEPS"* && "$(n_effort "$c1")" == 1 \
   && "$l1" == "EFFORT recommend=medium applied=unknown phase=debug"* && ${#l1} -le 240 \
   && "$(grep -v '^EFFORT ' <<< "$c1" | tail -1)" != "" && "$(tail -1 <<< "$c1")" == EFFORT* ]] \
  || { echo "FAIL  AC7-execute  [$(head -c 200 <<< "$l1")]"; ac7=0; }
D="$TMP/ac7g"; mksb "$D" GENERATE 05b
c2="$(seam_ctx "$D" 'add an export button to the report screen')"
[[ "$(n_effort "$c2")" == 1 && "$(grep -m1 '^EFFORT ' <<< "$c2")" == "EFFORT recommend=medium applied=unknown phase=spec"* ]] \
  || { echo "FAIL  AC7-generate-phase"; ac7=0; }
D="$TMP/ac7a"; mksb "$D" EXECUTE 10
c3="$(seam_ctx "$D" 'check that the export button works')"
[[ "$(n_effort "$c3")" == 1 && "$(grep -m1 '^EFFORT ' <<< "$c3")" == "EFFORT recommend=medium applied=unknown phase=review"* ]] \
  || { echo "FAIL  AC7-stage10-review"; ac7=0; }
D="$TMP/ac7n"; mksb "$D" NONE ""
c4="$(seam_ctx "$D" '   ')"; c5="$(seam_ctx "$D" 'how does the loop work?')"
c6="$(seam_ctx "$D" 'add a billing export feature')"
c7="$(seam_ctx "$D" 'refactor the export button and add pagination')"
[[ "$(n_effort "$c4")" == 0 && "$c4" != *ROUTE* ]] || { echo "FAIL  AC7-whitespace-silent"; ac7=0; }
[[ "$(n_effort "$c5")" == 0 && "$c5" != *ROUTE* ]] || { echo "FAIL  AC7-idle-question-silent"; ac7=0; }
[[ "$(n_effort "$c6")" == 1 && "$(grep -m1 '^EFFORT ' <<< "$c6")" == "EFFORT recommend=medium"* ]] \
  || { echo "FAIL  AC7-prompt-risk-word-stays-medium"; ac7=0; }
[[ "$c7" == *"ROUTE ambiguous"* && "$(n_effort "$c7")" == 1 && "$(grep -m1 '^EFFORT ' <<< "$c7")" == *phase=unknown* ]] \
  || { echo "FAIL  AC7-ambiguous-advised"; ac7=0; }
D="$TMP/ac7o"; mksb "$D" EXECUTE 05b
# an empty/whitespace prompt on an ACTIVE hop must carry no EFFORT line (C7b): the case the spec sentence describes
w1="$(seam_ctx "$D" '   ')"; w2="$(seam_ctx "$TMP/ac7g" '    ')"
[[ "$(n_effort "$w1")" == 0 && "$(n_effort "$w2")" == 0 ]] || { echo "FAIL  AC7-whitespace-active-hop"; ac7=0; }
co="$(seam_ctx "$D" "$S1" BDD_EFFORT=off)"
stripped="$(grep -v '^EFFORT ' <<< "$c1")"
[[ "$(n_effort "$co")" == 0 && "$co" == "$stripped" ]] \
  || { echo "FAIL  AC7-off-byte-identity"; ac7=0; }
D="$TMP/ac7m"; mksb "$D" EXECUTE 05b; rm -f "$D/tests/lib/effort.py"
seam_raw "$TMP/seam-m.json" "$D" "$S1"; rcm=$?   # rcm is seam.py's own exit status (C6), not the extractor's
cm="$(python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' < "$TMP/seam-m.json" 2>/dev/null)"
nline="$(grep -m1 '^EFFORT ' <<< "$cm" || true)"
[[ $rcm -eq 0 && "$(n_effort "$cm")" == 1 && "$nline" == "EFFORT unavailable"* \
   && ${#nline} -le 240 && "$cm" == *"ROUTE bug-fix"* && "$cm" == *"STEPS"* ]] \
  || { echo "FAIL  AC7-missing-helper-notice"; ac7=0; }
[[ "$(n_effort "$(seam_ctx "$D" '  ')")" == 0 ]] || { echo "FAIL  AC7-missing-helper-whitespace"; ac7=0; }
t AC7 "$ac7" "one bounded EFFORT advisory line on routed hop prompts (phase=debug/spec/review/unknown), silence on whitespace and idle questions, BDD_EFFORT=off byte-identical without it, a missing helper stays nonblocking"

# ---- AC8 — standalone install ships the new files, idempotently; bdd-work copies agree ----------------------------
ac8=1
D="$TMP/ac8"
mkdir -p "$D"; ( cd "$D" && git init -q )
# a minimal product repo the installer accepts
printf '# p\n' > "$D/README.md"; ( cd "$D" && git add -A && git -c core.hooksPath=/dev/null commit -qm init )
treehash() {  # treehash <dir> <out> — sha256 of every tracked-ish file outside .git and .cascade
  python3 -B - "$1" "$2" <<'PY'
import hashlib, os, sys
root, out = sys.argv[1], sys.argv[2]
rows = []
for dp, dn, fn in os.walk(root):
    dn[:] = [d for d in dn if d not in (".git", ".cascade", "__pycache__")]
    for f in fn:
        p = os.path.join(dp, f)
        rows.append((os.path.relpath(p, root), hashlib.sha256(open(p, "rb").read()).hexdigest()))
open(out, "w").write("\n".join(f"{h}  {r}" for r, h in sorted(rows)) + "\n")
PY
}
if ! ( cd "$D" && bash "$ROOT/install.sh" . >"$TMP/install1.log" 2>&1 ); then echo "FAIL  AC8-install  first install failed (see below)"; sed -n '1,8p' "$TMP/install1.log"; ac8=0; else
  [[ -f "$D/tests/lib/effort.py" && -f "$D/tests/effort.sh" ]] || { echo "FAIL  AC8-shipped  effort.py/effort.sh not installed"; ac8=0; }
  o2=""; r2=1
  if [[ -f "$D/tests/effort.sh" ]]; then o2="$(cd / && bash "$D/tests/effort.sh" --context "$TMP/goodctx.json" 2>/dev/null)"; r2=$?; fi
  { [[ $r2 -eq 0 && -n "$o2" ]] && printf '%s' "$o2" | jfield application_status not_applied; } \
    || { echo "FAIL  AC8-runs  installed wrapper exit=$r2"; ac8=0; }
  treehash "$D" "$TMP/hash1"
  ( cd "$D" && bash "$ROOT/install.sh" . >"$TMP/install2.log" 2>&1 )
  treehash "$D" "$TMP/hash2"
  cmp -s "$TMP/hash1" "$TMP/hash2" || { echo "FAIL  AC8-idempotent  the second install changed the tree"; ac8=0; }
fi
A="$ROOT/skills/bdd-work/SKILL.md"; B="$ROOT/.claude/skills/bdd-work/SKILL.md"; C="$ROOT/.agents/skills/bdd-work/SKILL.md"
if [[ -f "$A" && -f "$B" && -f "$C" ]] && cmp -s "$A" "$B" && cmp -s "$A" "$C" \
   && grep -qi effort "$A"; then :; else echo "FAIL  AC8-skill-parity  the three bdd-work copies must be identical and carry the effort guidance"; ac8=0; fi
t AC8 "$ac8" "standalone install ships tests/lib/effort.py + tests/effort.sh, runs offline from the product tree, reruns byte-identical; plugin/standalone bdd-work copies agree"

# ---- AC9 — red twins on the future implementation -------------------------------------------------------------------------
cat > "$TMP/py/twist.py" <<'PY'
#!/usr/bin/env python3
"""Rewrite a copy of tests/lib/effort.py with one named policy mutant, anchored on the public entry point.
Mutations handle both dict and dataclass representations of context/profile/decision: the spec pins the entry
point and the JSON output, not an internal type (C4: a mutant must flip named behavior, never a crash)."""
import ast, sys

src, dst, twist = sys.argv[1:4]
PRE = {
    "ignore-task": '    if isinstance(context, dict):\n        context = {**context, "task_id": None, "previous": None}\n    else:\n        context = _twin_dc.replace(context, task_id=None, previous=None)\n',
    "always-preserves-cache": '    if profile is not None:\n        profile = {**profile, "cache_effect": "preserves-prefix"} if isinstance(profile, dict) else _twin_dc.replace(profile, cache_effect="preserves-prefix")\n',
}
POST = {
    "always-low": '    _d = {**_d, "quality_target": "low"} if isinstance(_d, dict) else _twin_dc.replace(_d, quality_target="low")\n',
    "always-high": '    _d = {**_d, "quality_target": "high"} if isinstance(_d, dict) else _twin_dc.replace(_d, quality_target="high")\n',
    "returns-applied": '    _d = {**_d, "application_status": "applied"} if isinstance(_d, dict) else _twin_dc.replace(_d, application_status="applied")\n',
}
if twist not in PRE and twist not in POST:
    sys.exit(f"unknown twist {twist}")
text = open(src, encoding="utf-8").read()
tree = ast.parse(text)
lines = text.split("\n")
fn = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "recommend"), None)
assert fn, "twin anchor: module-level def recommend(context, profile) (spec: the public entry point)"
ln, col = fn.lineno - 1, fn.col_offset
col = lines[ln].index("recommend", col)   # col_offset points at `def`; the name follows it
assert lines[ln][col:col + 9] == "recommend", "twin anchor: def recommend( at module level"
lines[ln] = lines[ln][:col] + "recommend_twin_orig" + lines[ln][col + 9:]
guard = next((n for n in tree.body if isinstance(n, ast.If)
              and getattr(getattr(n.test, "left", None), "id", "") == "__name__"
              and getattr(getattr(n.test, "comparators", [None])[0], "value", None) == "__main__"), None)
assert guard, "twin anchor: if __name__ == \"__main__\": guard"
wrap = ["", "import dataclasses as _twin_dc", "", "def recommend(context, profile):",
        PRE.get(twist, "") + "    _d = recommend_twin_orig(context, profile)", POST.get(twist, "") + "    return _d"]
lines[guard.lineno - 1:guard.lineno - 1] = wrap
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PY

# Pristine module, direct-module path (Frozen interpretation 8's CLI contract), before any mutant runs (C4):
# if this fails, twin FAIL lines may be crash noise and prove nothing about the named behaviors.
ALLIDS="AC2-billing-plan,AC2-auth-code,AC1-complex-plan,AC3-failure-no-identity-debug,AC1-low-code,AC1-low-plan,AC1-normal-plan,AC3-escalate,AC3-stalled,AC3-retain-high,AC3-new-task-resets,AC5-invalidates-differs,AC5-unknown-cache-differs,AC1-phase-code,AC4-oai-medium"
tb=0
if [[ -f "$ROOT/tests/lib/effort.py" ]]; then
  mkdir -p "$TMP/twin-base"
  python3 -B "$TMP/py/runner.py" --data "$DATA" --module "$ROOT/tests/lib/effort.py" --only "$ALLIDS" --tmp "$TMP/twin-base" >/dev/null 2>&1 || tb=1
fi
t AC9-baseline "$((1 - tb))" "the clean tests/lib/effort.py passes the named cases through the direct-module path the twins rely on"

twin() {  # twin <name> <twist> <case ids, csv> — the mutant must FAIL each named case with a behavioral mismatch, not a crash
  local n="$1" w="$2" ids="$3"
  local d="$TMP/twin-$n" out rc ok id line
  mkdir -p "$d"
  if ! cp "$ROOT/tests/lib/effort.py" "$d/effort.py" 2>/dev/null; then echo "FAIL  AC9-$n  tests/lib/effort.py is missing"; fail=1; return; fi
  if ! python3 -B "$TMP/py/twist.py" "$d/effort.py" "$d/effort.py" "$w"; then echo "FAIL  AC9-$n  anchor: $w did not match the implementation"; fail=1; return; fi
  out="$(python3 -B "$TMP/py/runner.py" --data "$DATA" --module "$d/effort.py" --only "$ids" --tmp "$d" 2>&1)"; rc=$?
  ok=1; [[ $rc -ne 0 ]] || ok=0
  [[ $tb -eq 0 ]] || ok=0   # without the pristine baseline, a crashing mutant would look like detection
  # shellcheck disable=SC2086  # csv ids -> words is the point here
  for id in ${ids//,/ }; do
    line="$(grep -m1 "FAIL  $id" <<< "$out")"
    [[ -n "$line" && "$line" != *exit=* && "$line" != *"not JSON"* ]] || ok=0
  done
  t AC9-$n "$ok" "$w fails the named table cases on behavior, not on a crash"
}
twin low       always-low             "AC2-billing-plan,AC2-auth-code,AC1-complex-plan,AC3-failure-no-identity-debug"
twin high      always-high            "AC1-low-code,AC1-low-plan,AC1-normal-plan"
twin task      ignore-task            "AC3-escalate,AC3-stalled,AC3-retain-high,AC3-new-task-resets"
twin cache     always-preserves-cache "AC5-invalidates-differs,AC5-unknown-cache-differs"
twin applied   returns-applied        "AC1-phase-code,AC4-oai-medium"

exit "$fail"
