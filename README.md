# Barbaric Driven Development

A Generate → Review → Execute product cascade with a **verify/CI control line**.

Do not trust chat. Prove it on the tree. Domain laws (D#) are merge-bar tests. The human stays on every hop edge.

100% match of the verify/CI talk means a **red test**, not a stronger prompt. T1–T7 in [CONTROL-LINE.md](CONTROL-LINE.md) are that bar (I17).

## Two loops (I16)

| Command | Whose | Does |
|---------|-------|------|
| `/loop` | Ours (GRE) | One approved execute. `LOOP k/n` on ACs + D#. Stop at hop edge. |
| `/barbar` | Hers (eval farm) | Hill-climb control-line evals to `BARBAR n/n`. No product stages. `/barbar merge` only after CLEAN 10 + 11 READY. |

```
GENERATE  → spec+plan → STITCH NEEDED
you: approved, execute stage N
EXECUTE   → /goal = ACs + D# → /loop until LOOP n/n → /diff
you: accepted, generate stage N+1
```

Details: [CONTROL-LINE.md](CONTROL-LINE.md). Spec shapes: [docs/cascade/product-e2e-cascade.md](docs/cascade/product-e2e-cascade.md). Conductor (I1–I17): [docs/cascade/product-e2e-gre-pipeline.md](docs/cascade/product-e2e-gre-pipeline.md).

Slash command in chat: `/barbar` loads [skills/barbar/SKILL.md](skills/barbar/SKILL.md) (farm only). Building still uses the GRE conductor, not this skill.

## Run it

Hand both files under `docs/cascade/` to a coding agent. Fill intake `<EDIT>` yourself. Type `generate stage N`, `approved, execute stage N`, `accepted, generate stage N+1`. Use `/loop` inside an approved execute. Use `/barbar` for the eval farm, not to finish the product.

## Pack eval (I17)

```
bash tests/i17_dune.sh    # T1–T7 must stay true
bash tests/barbar.sh      # farm → BARBAR k/n; exit 1 unless k=n
bash tests/barbar.sh merge
```

CI runs all three on pull_request and push to main, no continue-on-error. Merge on this pack repo must REFUSE. `evals/fixtures/ready-product` is the ALLOWED side of the gate. `/barbar merge` prints ALLOWED; it does not push this repo.
