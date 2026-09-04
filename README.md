# Barbaric Driven Development

**Your coding agent will tell you it's done. This makes it prove it.**

BDD is a Claude Code plugin (and a plain git layer for every other agent) that turns "trust me, tests pass" into red tests, computed gates, and one-click human signatures — so a product built by agents stays *correct* after the model, the prompt, and the team have all changed.

```bash
claude plugin marketplace add kadaluarsa/barbaric-driven-development
claude plugin install bdd@bdd
```

Then open any repo and type what you want built. That's the install.

## What you get

- **Laws that can fail.** Declare a product law — *balance MUST NOT go negative* — with a validator *and* a red twin (a command that must fail). A law with no teeth is flagged `THEATER`; an unproven one blocks the loop. `DSHARP k/n` tells you the truth every time.
- **Gates that compute, not read.** Stage 10 is scored from the tree (`path:` exists, `test:` green); READY counts only when a human signed it; merge is `ALLOWED` or `REFUSED` by a script. The agent never types a score.
- **One click to sign.** Hop edges, laws, list changes: the agent proposes the exact edit, the permission dialog is your signature. No files to hand-edit, no keys to type.
- **Autopilot with a bar.** Sign a slice list once, run `/barbar auto`, sleep. It advances only while every law is green, and halts — never improvises — when one isn't.
- **Layers, not prompts.** CI › git hooks › agent hooks › rules. Turn the model off and the bar still holds.

## Measured, not asserted

| | |
|---|---|
| Fresh container, install from zero, every layer exercised | **22/22** |
| Real agent, headless, safeguards off except these, 7 conformance probes | **7/7** |
| Two features of rising difficulty + a trap that contradicts a law + audit + gate | **7/7** strict |
| Same, on autopilot with one `/barbar auto` | **4/4** |

Eight earlier runs each found one thing — an installer that nested on upgrade, a law test rewritten to fit an API change, a "VIP exception" carved into *balance never negative* — and each became a test. Transcripts are in [`evals/`](evals/). The one failure the layers can't fully close is named in [`AUDIT.md`](AUDIT.md): a human still reads the diff at the edge.

## 30 seconds of use

```
you:    add multi-currency balances; credit/debit take a currency code
agent:  drafts the brief, proposes the edge   → dialog: "HUMAN SIGNATURE NEEDED"
you:    approve
agent:  spec → build → LOOP n/n → next slice → … → AUTOPILOT HALT: list complete
you:    /audit, sign READY, /barbar merge → ALLOWED → open the PR
```

Don't know your laws yet? `/barbar init` scans the repo and proposes them. You sign what you accept.

## Who it's for

Teams shipping with coding agents who've been burned by a "done" that wasn't. Anything money, tenancy, safety or data loss makes unforgiving. Products meant to outlive the model that builds them.

Not for a weekend prototype — the hop edge is a cost you pay on purpose.

## Works with

Claude Code gets all four layers (plugin). Codex, Cursor, Copilot, Gemini, Aider, Windsurf, Zed and humans get the git hooks, CI and rules — the parts that don't need an agent's cooperation. Pairs with [Superpowers](https://github.com/obra/superpowers) for craft; BDD is the constitution, Superpowers is the toolkit.

## Read next

- [`USAGE.md`](USAGE.md) — the operator's manual: what you type, what you check, what `BLOCKED` means
- [`INTEGRATION.md`](INTEGRATION.md) — layers, per-agent matrix, conformance probes
- [`CONTROL-LINE.md`](CONTROL-LINE.md) — the law: I15–I18, tests T1–T31
- [`AUDIT.md`](AUDIT.md) — the honest audit, including where the ceiling is

MIT. Built by running it on itself until it stopped lying.
