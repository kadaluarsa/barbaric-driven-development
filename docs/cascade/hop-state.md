# Hop state

> 🧑 **HUMAN-OWNED FILE.** Every `CURRENT_HOP`, `CURRENT_STAGE`, `CURRENT_SLICE`, and `AUTOPILOT:` line
> is yours. The agent proposes changes; you approve in the permission dialog — that click is your signature.
> Works from any Claude Code client (Remote, web included) — no terminal needed.
> Fallback for plain git: `bash tests/sign.sh`.

This file turns over three or four times per slice — that is the hop
counter ticking, not drift. It is kept apart from `envelope.md` so your laws keep a readable history:
`git log docs/cascade/envelope.md` shows decisions, this one shows movement.

---

## 🧑 HUMAN: Decision points in this file

| Line | What you decide | How |
|---|---|---|
| `CURRENT_HOP:` | Whether a cascade is running | `NONE` = idle. `GENERATE` or `EXECUTE` = hop in progress. |
| `CURRENT_STAGE:` | Which stage is active | Agent proposes; you approve the edge. |
| `CURRENT_SLICE:` | Which slice is active | Agent proposes; you approve. |
| `AUTOPILOT:` | Pre-sign a list of slices | Fill inside `<EDIT>` — agent advances automatically. |

---

## Where are we?

```
CURRENT_HOP: GENERATE
CURRENT_STAGE: 06
CURRENT_SLICE: t82-task-routing
```

`NONE` means no cascade is running. `GENERATE` writes spec and plan only; `EXECUTE` builds one named
slice. One hop per reply, and you stand on every edge between them.

---

## Overnight list

<EDIT>
AUTOPILOT: 05b t78-carry-out, 05b t79-zero-test-guard, 05b t80-carry-matching
</EDIT>

Empty means you take every hop edge yourself. Sign a list — `AUTOPILOT: 05b checkout, 05b refunds,
10 audit` — and the agent advances along it while every law stays green, halting the moment one does not.
Stage 11 and the merge can never be listed. See USAGE.md §B3.

---

## 🤖 AGENT: Rules for reading this file

| Rule | Detail |
|---|---|
| `CURRENT_HOP` | Determines what you may do: `NONE` = idle. `GENERATE` = spec+plan only. `EXECUTE` = build only. |
| `AUTOPILOT:` | Only advance to the next entry on the list. Never skip entries. Never add new ones. |
| `<EDIT>` block | Never write inside it. If `AUTOPILOT:` is still inside `<EDIT>`, the list is unsigned. |
| Edge lines | After every hop, print `STITCH NEEDED: ...` and stop. |
