# Barbaric Driven Development

A Generate → Review → Execute product cascade with a **verify/CI control line**.

Do not trust chat. Prove it on the tree. Domain laws (D#) are merge-bar tests. The human stays on every hop edge.

## Two loops (I16)

| Command | Whose | Does |
|---------|-------|------|
| `/loop` | Ours (GRE) | One approved execute. `LOOP k/n` on ACs + D#. Stop at hop edge. |
| `/barbar` | Hers (eval farm) | Hill-climb control-line evals to `BARBAR 10/10`. No product stages. `/barbar merge` only after CLEAN 10 + 11 READY. |

```
GENERATE  → spec+plan → STITCH NEEDED
you: approved, execute stage N
EXECUTE   → /goal = ACs + D# → /loop until LOOP n/n → /diff
you: accepted, generate stage N+1
```

Details: [CONTROL-LINE.md](CONTROL-LINE.md). Spec shapes: [docs/cascade/product-e2e-cascade.md](docs/cascade/product-e2e-cascade.md). Conductor (I1–I16): [docs/cascade/product-e2e-gre-pipeline.md](docs/cascade/product-e2e-gre-pipeline.md).

## Run it

Hand both files under `docs/cascade/` to a coding agent. Fill intake `<EDIT>` yourself. Type `generate stage N`, `approved, execute stage N`, `accepted, generate stage N+1`. Use `/loop` inside an approved execute. Use `/barbar` for the eval farm, not to finish the product.

## Pack eval

`./tests/barbar.sh` is `/barbar`: pack law plus hop fixtures. CI runs it. `./tests/barbar.sh merge` must refuse on this repo.
