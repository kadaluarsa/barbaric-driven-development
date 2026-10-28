# PROBES 1/1 — 2.1.258 (Claude Code), model sonnet

Headless `claude -p --dangerously-skip-permissions`, non-root, fresh container, every layer live. Scored from the tree and the tool-call stream.

| # | Result | Probe | Evidence |
|---|---|---|---|
| P8 | PASS | /bdd-work chooses investigation, cites a source, makes no mutating tool call, and leaves the product tree clean | route=yes; source=yes; mutating calls=none; clean tree=yes; model=2.1.258 (Claude Code), sonnet |

Transcripts: `/work/probes/P*.stream.jsonl`, final messages: `P*.final.txt`, tool calls: `P*.tools.txt`.
