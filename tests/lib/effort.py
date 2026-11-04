#!/usr/bin/env python3
"""t93 adaptive effort routing — the deterministic, offline effort decision (no product network, no state writes).

    python3 -B effort.py --context FILE [--profile FILE]      JSON decision on stdout; 0, or 2 on input errors

The contract, the policy precedence and the frozen interpretations live in
docs/cascade/05b-t93-adaptive-effort-routing.md; the authority for behaviour is the pinned table in
tests/ac/data/t93_effort_cases.json. This module recommends; it never applies a host setting
(application_status is always not_applied). The CLI must route every decision through the module-level
recommend(context, profile) — the red twins rebind that name.
"""
from __future__ import annotations

import dataclasses
import datetime
import enum
import json
import sys

ROUTES = frozenset({"investigation", "bug-fix", "feature", "refactor", "verification", "ambiguous"})
PHASES = frozenset({"spec", "plan", "code", "debug", "review", "verify", "investigate", "unknown"})
HOPS = frozenset({"NONE", "GENERATE", "EXECUTE"})
STAGES = frozenset({""} | {f"{i:02d}" for i in range(12)} | {"05b"})
COMPLEXITY = frozenset({"simple", "normal", "complex", "unknown"})
UNCERTAINTY = frozenset({"known", "unknown", "high"})
RISKS = frozenset({"auth", "billing", "credits", "ownership", "security", "privacy", "concurrency",
                   "destructive-data", "irreversible-migration"})
CONTROLS = frozenset({"reasoning.effort", "output_config.effort", "thinkingConfig.thinkingLevel",
                      "thinkingConfig.thinkingBudget", "other"})
UPDATE = frozenset({"turn-update", "request-setting", "session-only", "unknown"})
CACHE = frozenset({"preserves-prefix", "invalidates-prefix", "unknown"})
CTX_KEYS = frozenset({"schema_version", "route", "hop", "stage", "phase", "complexity", "uncertainty",
                      "risk_tags", "task_id", "previous", "failure", "current_setting", "override"})
PREV_KEYS = frozenset({"task_id", "quality_target", "failure_fingerprint", "evidence_fingerprint"})
FAIL_KEYS = frozenset({"failure_fingerprint", "evidence_fingerprint"})
PROF_KEYS = frozenset({"schema_version", "provider", "model", "platform", "source_url", "verified_on",
                       "control", "control_name", "update_mode", "cache_effect", "supported_values", "mapping"})


class Level(enum.IntEnum):
    LOW, MEDIUM, HIGH = 0, 1, 2

    @property
    def label(self) -> str:
        return self.name.lower()


LABEL = {"low": Level.LOW, "medium": Level.MEDIUM, "high": Level.HIGH}
PHASE_BY_ROUTE = {"bug-fix": "debug", "feature": "code", "refactor": "code", "verification": "verify",
                  "investigation": "investigate", "ambiguous": "unknown"}


@dataclasses.dataclass(frozen=True)
class Previous:
    task_id: str
    quality_target: str
    failure_fingerprint: str | None
    evidence_fingerprint: str | None


@dataclasses.dataclass(frozen=True)
class Failure:
    failure_fingerprint: str
    evidence_fingerprint: str


@dataclasses.dataclass(frozen=True)
class EffortContext:
    route: str
    hop: str = "NONE"
    stage: str = ""
    phase: str = "unknown"
    complexity: str = "unknown"
    uncertainty: str = "unknown"
    risk_tags: tuple = ()
    task_id: str | None = None
    previous: Previous | None = None
    failure: Failure | None = None
    current_setting: str | None = None
    override: str | None = None


@dataclasses.dataclass(frozen=True)
class CapabilityProfile:
    provider: str
    model: str
    platform: str
    source_url: str
    verified_on: str
    control: str
    update_mode: str
    cache_effect: str
    supported_values: tuple
    mapping: dict


@dataclasses.dataclass(frozen=True)
class ProfileRef:
    provider: str
    model: str
    platform: str
    source_url: str
    verified_on: str


@dataclasses.dataclass(frozen=True)
class TaskState:
    task_id: str
    quality_target: str
    failure_fingerprint: str | None
    evidence_fingerprint: str | None


@dataclasses.dataclass(frozen=True)
class EffortDecision:
    schema_version: int
    route: str
    phase: str
    quality_target: str
    reasons: tuple
    next_action: str
    resolved_setting: str | None
    compatibility: str
    transition: str
    cache_effect: str
    application_status: str
    warnings: tuple
    profile: ProfileRef | None
    state: TaskState | None


class Bad(Exception):
    pass


def load(path: str):
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError:
        raise Bad("cannot read file")
    if len(raw) > 65536:
        raise Bad("file over 64 KiB")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise Bad("input is not valid UTF-8")

    def no_dup(pairs):
        d = {}
        for k, v in pairs:
            if k in d:
                raise Bad("duplicate JSON key")
            d[k] = v
        return d

    def no_const(_):
        raise Bad("non-finite number")

    try:
        return json.loads(text, object_pairs_hook=no_dup, parse_constant=no_const)
    except (ValueError, RecursionError) as exc:
        if isinstance(exc, Bad):
            raise
        raise Bad("invalid JSON")


def s_bound(v, name: str, limit: int, nonempty: bool = True) -> str:
    if not isinstance(v, str) or (nonempty and not v) or len(v) > limit:
        raise Bad(f"bad string: {name}")
    return v


def parse_context(value) -> EffortContext:
    if not isinstance(value, dict):
        raise Bad("context must be an object")
    if set(value) - CTX_KEYS:
        raise Bad("unknown context key")
    if type(value.get("schema_version")) is not int or value.get("schema_version") != 1:
        raise Bad("schema_version must be integer 1")
    route = value.get("route")
    if not isinstance(route, str) or route not in ROUTES:
        raise Bad("bad route")
    hop = value.get("hop", "NONE")
    stage = value.get("stage", "")
    phase = value.get("phase", "unknown")
    complexity = value.get("complexity", "unknown")
    uncertainty = value.get("uncertainty", "unknown")
    risks = value.get("risk_tags", [])
    if hop not in HOPS or stage not in STAGES or phase not in PHASES:
        raise Bad("bad hop/stage/phase")
    if complexity not in COMPLEXITY or uncertainty not in UNCERTAINTY:
        raise Bad("bad complexity/uncertainty")
    if not isinstance(risks, list) or not all(isinstance(r, str) and r in RISKS for r in risks) \
            or len(set(risks)) != len(risks):
        raise Bad("bad risk_tags")
    task_id = value.get("task_id")
    if task_id is not None:
        s_bound(task_id, "task_id", 128, nonempty=False)
        task_id = task_id or None
    prev = value.get("previous")
    if prev is not None:
        if not isinstance(prev, dict) or set(prev) != PREV_KEYS:
            raise Bad("bad previous")
        s_bound(prev.get("task_id"), "previous.task_id", 128)
        if prev.get("quality_target") not in LABEL:
            raise Bad("bad previous.quality_target")
        ff, ef = prev.get("failure_fingerprint"), prev.get("evidence_fingerprint")
        if ff is None and ef is None:
            pass
        elif ff is None or ef is None:
            raise Bad("partial previous fingerprints")
        else:
            s_bound(ff, "previous.failure_fingerprint", 128)
            s_bound(ef, "previous.evidence_fingerprint", 128)
        prev = Previous(prev["task_id"], prev["quality_target"], ff, ef)
    failure = value.get("failure")
    if failure is not None:
        if not isinstance(failure, dict) or set(failure) != FAIL_KEYS:
            raise Bad("bad failure")
        s_bound(failure.get("failure_fingerprint"), "failure.failure_fingerprint", 128)
        s_bound(failure.get("evidence_fingerprint"), "failure.evidence_fingerprint", 128)
        failure = Failure(failure["failure_fingerprint"], failure["evidence_fingerprint"])
    for key in ("current_setting", "override"):
        v = value.get(key)
        if v is not None:
            s_bound(v, key, 64)
    return EffortContext(route=route, hop=hop, stage=stage, phase=phase, complexity=complexity,
                         uncertainty=uncertainty, risk_tags=tuple(risks), task_id=task_id, previous=prev,
                         failure=failure, current_setting=value.get("current_setting"),
                         override=value.get("override"))


def parse_profile(value) -> CapabilityProfile:
    if not isinstance(value, dict):
        raise Bad("profile must be an object")
    if set(value) - PROF_KEYS:
        raise Bad("unknown profile key")
    if type(value.get("schema_version")) is not int or value.get("schema_version") != 1:
        raise Bad("profile schema_version must be integer 1")
    identity = {key: s_bound(value.get(key), key, 2048)
                for key in ("provider", "model", "platform", "source_url", "verified_on")}
    if not identity["source_url"].startswith("https://"):
        raise Bad("source_url must be https")
    try:
        datetime.date.fromisoformat(identity["verified_on"])
    except ValueError:
        raise Bad("verified_on must be YYYY-MM-DD")
    sv = value.get("supported_values")
    if not isinstance(sv, list) or not sv or not all(isinstance(x, str) and 0 < len(x) <= 64 for x in sv) \
            or len(set(sv)) != len(sv):
        raise Bad("bad supported_values")
    mp = value.get("mapping")
    if not isinstance(mp, dict) or set(mp) != set(LABEL):
        raise Bad("mapping needs exactly low/medium/high")
    for lvl, v in mp.items():
        if v is not None and v not in sv:
            raise Bad(f"mapping {lvl} not a supported value")
    control = value.get("control")
    if control not in CONTROLS:
        raise Bad("bad control")
    has_name = "control_name" in value
    if control == "other":
        if not has_name:
            raise Bad("control other needs control_name")
        s_bound(value["control_name"], "control_name", 64)
    elif has_name:
        raise Bad("control_name only for other")
    if value.get("update_mode") not in UPDATE or value.get("cache_effect") not in CACHE:
        raise Bad("bad update_mode/cache_effect")
    return CapabilityProfile(**identity, control=control, update_mode=value["update_mode"],
                             cache_effect=value["cache_effect"], supported_values=tuple(sv),
                             mapping=dict(mp))


def resolve_phase(c: EffortContext) -> str:
    if c.phase != "unknown":          # an explicit claim; phase "unknown" is no knowledge (frozen interpretation 1)
        return c.phase
    if c.hop == "GENERATE":
        return "spec"
    if c.hop == "EXECUTE" and c.stage in ("10", "11"):
        return "review"
    return PHASE_BY_ROUTE[c.route]


def recommend(context: EffortContext, profile: CapabilityProfile | None) -> EffortDecision:
    c = context
    phase = resolve_phase(c)
    reasons = {f"default:{phase}"}
    warnings = set()
    failure, prev = c.failure, c.previous
    if failure is not None:
        reasons.add("failure:observed")
    if c.complexity == "complex":
        reasons.add("complexity:complex")
    if c.uncertainty == "high":
        reasons.add("uncertainty:high")
    for tag in c.risk_tags:
        reasons.add(f"risk:{tag}")

    low_ok = (phase in {"code", "verify", "investigate", "plan"} and c.complexity == "simple"
              and c.uncertainty == "known" and not c.risk_tags and failure is None)
    if low_ok:
        reasons.add("simple:known-bounded")
    floor_high = (bool(c.risk_tags) or c.complexity == "complex" or c.uncertainty == "high"
                  or (phase == "debug" and failure is not None))
    rank = Level.HIGH if floor_high else (Level.LOW if low_ok else Level.MEDIUM)

    same_task = bool(c.task_id and prev is not None and prev.task_id == c.task_id)
    next_action = "continue"
    if failure is not None:
        if same_task and prev.failure_fingerprint is not None:
            if failure.evidence_fingerprint != prev.evidence_fingerprint:
                rank = max(rank, Level(min(2, LABEL[prev.quality_target] + 1)))
                reasons.add("failure:new-evidence")
            elif failure.failure_fingerprint == prev.failure_fingerprint:
                reasons.add("stalled:same-failure-no-new-evidence")
                next_action = "investigate"
            else:
                reasons.add("failure:changed-without-new-evidence")
                next_action = "investigate"
        else:
            reasons.add("failure:first-observation")
            next_action = "investigate"
    elif phase == "debug":
        next_action = "investigate"
    if same_task and LABEL[prev.quality_target] > rank and "failure:new-evidence" not in reasons:
        rank = Level(LABEL[prev.quality_target])
        reasons.add("retained:same-task-high-water")
    target = rank.label

    compat = "unknown"
    resolved = None
    if profile is None:
        warnings.add("profile:missing")
    else:
        mp = profile.mapping
        if c.override is not None:
            if c.override in profile.supported_values:
                compat, resolved = "supported", c.override
            else:
                compat = "unsupported"
                warnings.add("override:unsupported")
            if mp[target] is None:
                warnings.add("profile:mapping-unsupported")
        elif mp[target] is None:
            compat = "unsupported"
            warnings.add("profile:mapping-unsupported")
        else:
            compat, resolved = "supported", mp[target]

        def reverse(v):
            rr = [LABEL[k] for k, mv in mp.items() if mv == v]   # maximum reverse-mapped rank
            return max(rr) if rr else None

        if c.override is not None and compat == "supported":
            r = reverse(c.override)
            if r is None:
                warnings.add("setting:quality-comparison-unknown")
            elif r < rank:
                warnings.add("override:below-quality-target")
        if c.current_setting is not None:
            r = reverse(c.current_setting)
            if r is None:
                warnings.add("setting:quality-comparison-unknown")
            elif r < rank:
                warnings.add("current:below-quality-target")

    if compat == "unsupported":
        trans = "unsupported"
    elif profile is None or c.current_setting is None:
        trans = "unknown"
    elif c.current_setting == resolved:
        trans = "unchanged"
    elif profile.cache_effect == "invalidates-prefix" or profile.update_mode == "session-only":
        trans = "next-session"
    elif profile.cache_effect == "preserves-prefix" and profile.update_mode in ("turn-update", "request-setting"):
        trans = profile.update_mode
    else:
        trans = "unknown"
    if trans == "unchanged":
        cache = "unchanged"
    elif profile is None or compat == "unsupported":
        cache = "unknown"
    else:
        cache = profile.cache_effect

    if c.task_id is None:
        state = None
    else:
        if failure is not None:
            ff, ef = failure.failure_fingerprint, failure.evidence_fingerprint
        elif same_task:
            ff, ef = prev.failure_fingerprint, prev.evidence_fingerprint
        else:
            ff, ef = None, None
        state = TaskState(c.task_id, target, ff, ef)

    return EffortDecision(
        schema_version=1, route=c.route, phase=phase, quality_target=target, reasons=tuple(sorted(reasons)),
        next_action=next_action, resolved_setting=resolved, compatibility=compat, transition=trans,
        cache_effect=cache, application_status="not_applied", warnings=tuple(sorted(warnings)),
        profile=None if profile is None else ProfileRef(profile.provider, profile.model, profile.platform,
                                                         profile.source_url, profile.verified_on),
        state=state)


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if "--help" in argv or "-h" in argv:
        print("usage: effort.sh --context FILE [--profile FILE]")
        return 0
    try:
        if "--context" not in argv:
            raise Bad("missing --context")
        ctx = parse_context(load(argv[argv.index("--context") + 1]))
        prof = None
        if "--profile" in argv:
            prof = parse_profile(load(argv[argv.index("--profile") + 1]))
    except Bad as exc:
        print(f"effort: input error: {exc}", file=sys.stderr)
        return 2
    except (IndexError, KeyError):
        print("effort: input error: bad arguments", file=sys.stderr)
        return 2
    print(json.dumps(dataclasses.asdict(recommend(ctx, prof)), sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
