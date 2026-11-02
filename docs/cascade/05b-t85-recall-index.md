# Stage 05b — t85-recall-index — SPEC

## User story IDs from the PRD

BDD's product is the cascade itself; the stories this slice serves:

- **S-RI1** — As an agent whose context was just compacted, resumed or cleared mid-hop, I am told *where* this
  slice's work lives — the brief line, the spec and its plan and AC anchors, the critique, the goal, the last loop
  pass, the last halt — as paths and line numbers I can open, so I do not reconstruct the slice from chat residue.
- **S-RI2** — As an operator, the re-injected context stays short: pointers, not file contents, capped, and never a
  path to a file that is not there.
- **S-RI3** — As an operator with no hop running, nothing changes.

## The problem, stated as cost

After `compact`, `resume`, `clear` or `fork`, `.claude/hooks/preserve.py` injects the invariants, the hop
(`Current hop:` / `Current slice:`, `preserve.py:264-266`), the laws and the last 12 decisions (`preserve.py:291`).
It does not say where the slice's own artifacts are. The control line then forbids the obvious fallback
("Do not reconstruct locks from compacted conversation", `preserve.py:34-35`), so the agent either rereads broadly —
the briefs file is 400+ lines, a spec+plan 200+ — or works from the compacted summary.

What the agent needs is already on disk, in fixed places:

| Artifact | Where | Known since |
|---|---|---|
| the slice's brief | `docs/cascade/05b-briefs.md`, a `- <slug>:` line | t57 |
| spec + plan | `docs/cascade/<stage>-<slice>.md` (`# Stage … — PLAN`, `## Acceptance criteria`, `## In scope this execute`) | t59 |
| critique | `docs/cascade/05b-<slice>-critique.md` | t57 |
| candidates | `docs/cascade/05b-<slice>-candidates.md` (`tests/lib/diverge.py:82`) | t58 |
| goal | `docs/cascade/goal.md` (`GOAL_SLICE:`) | t77 |
| last loop pass | `.cascade/loop-history` (`tests/lib/watchdog.py`) | t84 |
| last halt / budget / cap / watchdog | `.cascade/decisions.log` — older than the 12-line tail after a long run | t59 |
| the hop's commits | `git log <hop base>..HEAD` (`tests/lib/affected.py:hop_base`) | t66 |

Inline the pointer, spill the content: the index says where each thing is and one line of status, and the agent
opens what this hop needs.

## Before vs after

Before:

```mermaid
flowchart TD
  C[compact / resume / clear / fork] --> P[preserve.py]
  P --> I[invariants + Current hop + Current slice + laws + last 12 decisions]
  I --> A{agent: where is this slice's work?}
  A -->|guess| R[reread briefs/specs broadly, or trust the compacted summary]
```

After:

```mermaid
flowchart TD
  C[compact / resume / clear / fork] --> P[preserve.py]
  P --> I[invariants + Current hop + Current slice]
  I --> H{hop GENERATE or EXECUTE with a slice?}
  H -->|no| L[laws + decisions, as today]
  H -->|yes| X[tests/lib/recall.py: one line per artifact that exists, ≤25 lines]
  X --> L
  X -.->|crash or 10 s timeout| L
  L --> A[agent opens brief:line, spec plan:line, goal, last loop pass — on demand]
```

## Benefits and trade-offs

| | Today | After t85 |
|---|---|---|
| After a context break mid-hop | hop and slice names only | plus a recall index: `path:line` for the brief, spec, plan, AC, scope list; critique, candidates, goal; last loop pass; last halt; commits since the hop opened |
| A halt older than the last 12 decisions | not shown | the newest HALT / BUDGET / CAP / WATCHDOG / NUDGECAP line, with its time |
| Context cost | — | ≤25 lines, ≤240 chars each; no file contents beyond the brief's first 200 characters |
| A file that does not exist | — | never listed |
| No hop running, or plain startup | — | unchanged (byte-identical output) |
| A broken `recall.py` | — | the index is omitted; the rest of the injection is unchanged |
| Not chosen: inlining the spec or plan | — | thousands of tokens on every compact; the pointer costs one line |
| Not chosen: a model-written summary of the hop | — | chat residue by another name; the index is computed from files |

## What the slice adds — and the line it must not cross

The line: **the index only adds pointers and one-line statuses computed from files; it changes no gate, verdict,
hop field or law, and injects nothing at NONE or on plain startup.**

### 1. `tests/lib/recall.py <root>` (new)

Prints nothing unless `CURRENT_HOP` is `GENERATE` or `EXECUTE` and `CURRENT_SLICE` is set. Otherwise prints, in this
order, only the lines whose source exists:

```
brief      docs/cascade/05b-briefs.md:<line>  <the line's text after "- <slug>:", whitespace collapsed, ≤200 chars>
spec       docs/cascade/<stage>-<slice>.md  (plan :<line>, AC :<line>, scope :<line>)
critique   docs/cascade/05b-<slice>-critique.md  (<k> findings, <m> answered)
candidates docs/cascade/05b-<slice>-candidates.md
goal       docs/cascade/goal.md  (for <slice> | for ANOTHER slice: <x> — reset it; <n> validators)
loop       last pass <age> ago: LOOP <k>/<n>[, <first FAIL line>]   (.cascade/loop-history)
halt       <timestamp> <actor> <verdict> <detail>   (.cascade/decisions.log)
commits    <n> since the hop opened at <sha7>; newest: <subject>
```

- `brief`: 05b only; the first column-0 line `- <slug>:` (a `[diverge]` tag after the colon allowed). Line numbers are
  1-based, so `sed -n <line>p <path>` prints the anchored line.
- `spec`: anchors present in the doc only; a doc with none prints the path alone.
- `critique`: `k` = rows under `## Brief` and `## Spec`, `m` = rows under `## Dispositions` (shape only, as in
  `tests/lib/critique.py`); never a verdict.
- `goal`: EXECUTE only.
- `loop`: the newest `.cascade/loop-history` line whose slice and hop base match (t84's format); none → omitted.
- `halt`: the newest `decisions.log` line whose verdict is `HALT`, `BUDGET`, `CAP`, `WATCHDOG` or `NUDGECAP`, read from
  the last 2000 lines; none → omitted.
- `commits`: needs a hop base (`affected.hop_base`); none → omitted.
- Every line is cut at 240 characters; at most 25 lines; exit 0 always.

### 2. `preserve.py` prints it

On `compact` / `resume` / `clear` / `fork`, right after `Current slice:`, `preserve.py` runs `recall.py` (10-second
timeout) and, when it prints anything, appends:

```
Recall index — pointers, not content; open what this hop needs (durable truth is these files):
  <each line>
```

Empty output, a crash or a timeout appends nothing. `startup` stays the version line alone (T15).

## What the slice must not touch

- Any gate, verdict, receipt, hop field, law or decision line.
- `preserve.py`'s output at NONE, on `startup`, and every line it prints today (the index is inserted, nothing moves
  or is removed).

## Acceptance criteria

`tests/ac/t85_recall_index.sh`, scratch git repos; `preserve.py` fed a SessionStart event:

- **AC1 — GENERATE.** A fixture on GENERATE 05b `a` with a brief line, a spec with all three anchors, a critique with
  3 findings and 2 dispositions: the compact output holds the brief's `path:line` (and `sed -n` of it starts
  `- a:`), the spec anchors (each `sed -n` gives the heading), `(3 findings, 2 answered)`; no `goal` or `loop` line.
- **AC2 — EXECUTE.** The same slice on EXECUTE with a goal for `a`, one real `tests/loop.sh` pass (`LOOP 1/2`), and a
  `HALT` line followed by 20 other decisions: `goal … for a; 2 validators`, `loop … LOOP 1/2, FAIL  false`, the
  `HALT` line, and `commits 1 since the hop opened`.
- **AC3 — no dead path.** Without the critique and candidates files, neither line appears. **Red twin:** a
  `recall.py` that lists the critique without checking it exists shows it.
- **AC4 — the cap.** A 3000-line `decisions.log`, a 600-character brief and a spec: at most 25 index lines, none over
  240 characters. **Red twin:** a `recall.py` without the cut prints a line over 240.
- **AC5 — a goal for another slice** prints `for ANOTHER slice: b — reset it`.
- **AC6 — unchanged when idle.** At NONE, and on `startup`, `preserve.py`'s output is byte-identical with and without
  `tests/lib/recall.py` present.
- **AC7 — a broken index is harmless.** A `recall.py` that raises: the output is valid JSON, holds `Current hop:`, and
  equals the no-`recall.py` output.

Gate: `bash tests/ac/t85_recall_index.sh`, `bash tests/enforcement.sh` (T85), lint.

## Laws

`bash tests/dsharp_strength.sh` prints `DSHARP 0/0`: NO LAW IN FORCE in this repo. The slice adds no D# and changes
none.

# Stage 05b — PLAN

## Goal

EXECUTE adds a computed recall index to the context `preserve.py` re-injects after a break mid-hop, with no gate or
verdict changed (T85).

## In scope this execute

- [ ] `tests/lib/recall.py` (new).
- [ ] `.claude/hooks/preserve.py` — run it after `Current slice:`.
- [ ] `tests/ac/t85_recall_index.sh` (AC1–AC7, two red twins); `tests/enforcement.sh` T85; `CONTROL-LINE.md` T85 row.
- [ ] `tests/ac/t69_gradle_tuning.sh` — `recall` in the shipped-paths parity list (as t84 did for `watchdog`).
- [ ] `USAGE.md` (after a context break), `CHANGELOG.md` (the unreleased 3.1.0 entry).
- [ ] `docs/cascade/goal.md`: `bash tests/goal.sh reset`, then this hop's validators.

## Out of scope this execute

- t86 (halt notify).
- Changing what `seam.py` injects on every prompt.
- Long-term memory across slices.

## Definition of done

- `bash tests/ac/t85_recall_index.sh` exits 0 and its red twins go red; `bash tests/enforcement.sh` exits 0 with T85;
  lint green; `bash tests/loop.sh` n/n on this hop's goal.

## Risks / UNKNOWNs that still block

- **U1 — the brief text is chat-shaped.** Its first 200 characters are human prose re-injected as context. It is the
  human's own committed brief, capped, and labelled as a pointer; a prompt-injection in a brief already reaches the
  agent on every GENERATE hop that reads it.

## Ask of you

1. **Ship in the unreleased 3.1.0** with t84 (no separate version). *Default taken.*
2. **25-line cap.** *Default taken.*

## Invariants this hop

- PRESERVE run: no
- /goal set to: n/a — GENERATE; EXECUTE's goal is AC1–AC7 + T85 + lint
- /model /effort: as set by the session
- /plan: skipped — this document is the plan
- INVARIANTS I1–I18: held; nothing loosens (I18)
- Skills: none invoked; brainstorming skipped (brief committed, `5710b55`)
- critique: pending
- reads: AGENTS.md, hop-state.md, envelope.md, 05b-briefs.md (t85), preserve.py, _common.py, decisions.py,
  watchdog.py, affected.py, critique.py, diverge.py, enforcement.sh (T15)
