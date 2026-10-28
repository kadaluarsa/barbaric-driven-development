# Cascade envelope

> 🧑 **HUMAN-OWNED FILE.** Every `D#` line, every locked decision, every accepted artifact
> is yours. The agent proposes; you approve in the permission dialog — that click is your signature.
> Works from any Claude Code client (Remote, web included) — no terminal needed.
> Fallback for plain git: `bash tests/sign.sh`.

## Where the cascade is *right now*

Moved to [`hop-state.md`](hop-state.md) so this file's history shows only decisions.

---

## 🧑 HUMAN: Your decisions at a glance

| Section | What you decide | How |
|---|---|---|
| `## Laws` | Which D# are in force | Approve agent's edit in dialog |
| `## Locked decisions` | Architecture, stack, scope locks | Fill `<EDIT>` block and sign |
| `## Accepted artifacts` | Which specs/code are canonical | Fill `<EDIT>` block and sign |

---

## Laws

A **law** is something your product must never do. Each law has:
- `check:` — a command that must **pass** (the validator)
- `break:` — a command that must **fail** (the **red twin** — the bug this law forbids, made runnable)

**Format:** copy this shape into the `<EDIT>` block below.
`reason:` must use a type from the [mutation type registry](mutation-types.md).
`path:` should point to a real file (optionally `:symbol`) in the repo.

```
### D<N> — <MUST / MUST NOT, one sentence>
check:  <command that passes while the law holds>
break:  <command that fails when the law is broken>
reason: <mutation type> — <what the mutant changes>
path:   <file where the mutation applies>
tier:   <which user tiers are covered>
```

`bash tests/dsharp_strength.sh` scores every law:

| Status | check: | break: | Meaning | 🧑 What to do |
|---|---|---|---|---|
| 🟢 **GREEN** | ✅ Passes | ❌ Fails | Law is in force | Nothing |
| 🔴 **RED** | ❌ Fails | ❌ Fails | Product broke the law | Fix the product |
| 🎭 **THEATER** | ✅ Passes | ✅ Passes | Test can't detect violations | Fix the test, not the law |
| ⚪ **UNPROVEN** | ? | ? | Missing validator or red twin | Write both, or `WAIVE_DSHARP:` in goal.md for one hop |

Don't know your laws? Run `/barbar init` — it scans the repo and proposes them for you to sign.

<EDIT>
### D1 — {{a user's balance MUST NOT go negative}}
check:  {{pytest tests/inv/test_D1.py}}
break:  {{INV_MUTANT=D1 pytest tests/inv/test_D1.py}}
reason: {{REMOVED_GUARD — removed the overdraft check}}
path:   {{src/wallet.py:withdraw()}}
tier:   {{all (standard + premium)}}
</EDIT>

---

## Law shards

Optional. When the laws above grow long, move a module's laws into `docs/cascade/laws/<module>.md`, in the same
format, inside an EDIT block — see [`laws/README.md`](laws/README.md). `tests/lib/laws.py` reads this file and
every shard as one set; one id twice anywhere is FATAL. Moving a law is a D# change: you sign it.

List every shard here, in a table inside an EDIT block you add (`bash tests/lint.sh` checks the list against
the files; reading never depends on it). One row per shard, for example `| laws/core.md | :core | D12–D40 |`.

---

## Locked decisions

> 🧑 **Fill this.** Decisions that cannot be reopened without a conflict notice.
> Each entry: `- {{what}} — locked {{YYYY-MM-DD}} — reason: {{why}}`

<EDIT>
None
</EDIT>

---

## Accepted artifacts

> 🧑 **Fill this.** Every accepted spec, design, or build artifact.
> Each entry: `- {{path}} — stage {{N}} — {{YYYY-MM-DD}}`

<EDIT>
docs/cascade/06-t82-task-routing.md — stage 06 — 2026-10-28 — spec+plan accepted
</EDIT>

---

## 🤖 AGENT: Rules for reading this file

| Rule | Detail |
|---|---|
| Source of truth | `docs/cascade/` in git. `/memory` is a cache. Chat residue is not. |
| `<EDIT>` blocks | Never write inside them. If required content is still `{{…}}`, STOP and ask. |
| D# lines | Human-owned. Propose changes; never edit directly. |
| `check:` / `break:` | Must be runnable commands. `check:` passes, `break:` fails. Both required for a law to be in force. |
