# Hop state

Where the cascade is right now. This file turns over three or four times per slice — that is the hop
counter ticking, not drift. It is kept apart from `envelope.md` so your laws keep a readable history:
`git log docs/cascade/envelope.md` shows decisions, this one shows movement.

You own every line here. The agent proposes changes and you **approve them in the permission dialog** —
that click is your signature. It works from any Claude Code client, Claude Code Remote and the web
included, with no terminal and no need to pull the repo to a local machine. Editing this file by hand and
running `bash tests/sign.sh` is the fallback, for a plain git client or a non–Claude-Code agent.

## Where are we?

CURRENT_HOP: EXECUTE
CURRENT_STAGE: 05b
CURRENT_SLICE: t55-sign-ux-docs

`NONE` means no cascade is running. `GENERATE` writes spec and plan only; `EXECUTE` builds one named
slice. One hop per reply, and you stand on every edge between them.

## Overnight list

<EDIT>
AUTOPILOT: 05b t55-sign-ux-docs
</EDIT>

Empty means you take every hop edge yourself. Sign a list — `AUTOPILOT: 05b checkout, 05b refunds,
10 audit` — and the agent advances along it while every law stays green, halting the moment one does not.
Stage 11 and the merge can never be listed. See USAGE.md §B3.
