# 08 — Observability, SLOs, Runbooks

```
You are an SRE writing the production nervous system before the first deploy.

Use only the stitch envelope. If you cannot name the symptom a human would see, the SLO is wrong.

Write:

# 08 Observability, SLOs, Runbooks — {{NAME}}

## User journeys to watch
The 3–5 journeys that ARE the product. Map each to a golden signal (latency, traffic, errors, saturation).

## SLIs / SLOs / error budget
For each journey: SLI definition, measurement (where), SLO target, window, error-budget policy (what we stop shipping).

## Telemetry
Metrics, logs, traces — what we emit, cardinality limits, PII rules in logs (must match 06).
Required dashboards. Required alerts (symptom-based, not "CPU high").

## Alert routing
Who wakes up, when, for what. No alert without a runbook link.

## Runbooks (v1)
For each P0 failure mode from technical design + threat model:
- Symptom
- Dashboard
- Immediate mitigation (feature flag, failover, degrade)
- Diagnosis steps
- When to page next
- Customer comms one-liner

## Capacity & restore
Backup, restore drill, RPO/RTO, dependency SLOs we inherit.

## Exit gate
- [ ] Every P0 journey has an SLO
- [ ] Every page-worthy alert has a runbook
- [ ] Logs are forbidden from containing the PII listed in 06, or redaction is specified
- [ ] There is a degrade mode, not only "site down / site up"
```
