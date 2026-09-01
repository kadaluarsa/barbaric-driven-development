# Barbaric Driven Development

A Generate → Review → Execute product cascade with a **verify/CI control line**.

Do not trust chat. Prove it on the tree. Domain laws (D#) are merge-bar tests. The human stays on every hop edge.

## Control line (I15)

```
GENERATE  → spec+plan → STITCH NEEDED
you: approved, execute stage N
EXECUTE   → /goal = ACs + D# → /loop until those tests → CI red if D# fail → /diff
you: accepted, generate stage N+1
```

1. The conductor is the skill. A pack eval **fails** if GENERATE starts EXECUTE or stage N+1.
2. CI is the Dune bar: in-force D# validators are required checks. Green tests that omit D# do not pass.
3. `/loop` only on 05b / 06–09 / 10 punch, and only until that hop's `/goal`.
4. Auto-merge is illegal until CLEAN stage 10 + stage 11 READY.

Details: [CONTROL-LINE.md](CONTROL-LINE.md). Spec shapes: [docs/cascade/product-e2e-cascade.md](docs/cascade/product-e2e-cascade.md). Conductor (I1–I15): [docs/cascade/product-e2e-gre-pipeline.md](docs/cascade/product-e2e-gre-pipeline.md).

## Run it

Hand both files under `docs/cascade/` to a coding agent. Fill intake `<EDIT>` yourself. Type the control lines (`generate stage N`, `approved, execute stage N`, `accepted, generate stage N+1`). Do not ask the agent to run endlessly to READY. Stitches are the process.

## Pack eval

`./tests/control-line.sh` fails the PR if the pack drops I15, lets GENERATE execute, or allows auto-merge before 11 READY.
