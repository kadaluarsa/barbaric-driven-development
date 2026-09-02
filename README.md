# Barbaric Driven Development

A Generate → Review → Execute product cascade with a verify/CI control line.

Do not trust chat. Prove it on the tree. Domain laws (D#) are merge-bar tests. The human stays on every hop edge.

This pack is how you run a product from intake to production-grade **without** letting a coding agent skip hops, execute while generating, or auto-merge before CLEAN 10 + 11 READY.

100% match of the [verify/CI talk](https://www.youtube.com/watch?v=Cmoh-yR-usA&t=2466s) means a **red test**, not a stronger prompt. T1–T7 below are that bar (I17).

## Two loops (I16)

Do not mix them.

| Command | Whose | Does |
|---------|-------|------|
| `/loop` | Ours (GRE) | One approved execute. `/goal` = ACs + in-scope D#. Print `LOOP k/n`. Stop at hop edge. Illegal on GENERATE, 01–04, and 11. |
| `/barbar` | Hers (eval farm) | Hill-climb control-line evals until `BARBAR n/n`. No product stages. `/barbar merge` only after CLEAN 10 + 11 READY. |

A prompt like “create feature on A based on B using C” is a GENERATE hop. It is not `/barbar`.

## Sequence

```
GENERATE  → spec+plan → STITCH NEEDED
you: approved, execute stage N
EXECUTE   → /goal = ACs + D# → /loop until LOOP n/n → /diff
you: accepted, generate stage N+1
… later, CLEAN 10 + 11 READY …
/barbar → BARBAR n/n
/barbar merge
```

Control lines (type these; do not paraphrase into a one-shot):

- `generate stage N`
- `approved, execute stage N`
- `accepted, generate stage N+1`
- `send back:`
- `generate 05b slice K`
- `promote ID:` / `reject ID as drift`
- `/loop` / `/barbar` / `/barbar merge`

`<EDIT>…</EDIT>` is human. The agent must not fill, guess, or delete those tags.

## Stages

00 Intake → 01 Problem → 02 Users → 03 PRD → 04 UX → 05 Tech → **05b** one named P0 slice per hop → 06 Sec → 07 Test → 08 SLOs → 09 Launch → **10 Feature Audit** → **11 PRR**.

Production-grade = CLEAN 10 + 11 READY. 01–04 are evidence/design, not the app. The app starts at 05b.

Greenfield and brownfield use the same commands. Brownfield execute may only stitch a named slice onto the existing tree.

## How to run a product

1. Copy both files under [`docs/cascade/`](docs/cascade/) into the product repo (or hand them to the coding agent).
2. Fill intake `<EDIT>` yourself.
3. Generate, stitch, execute, stitch. One hop per reply.
4. `/loop` only inside an approved execute of 05b / 06–09 / 10 punch.
5. `/barbar` scores this farm. It does not finish the product.

Durable truth is `docs/cascade/` in git. Chat and `/memory` are caches.

Spec shapes: [`docs/cascade/product-e2e-cascade.md`](docs/cascade/product-e2e-cascade.md).
Conductor (I1–I17): [`docs/cascade/product-e2e-gre-pipeline.md`](docs/cascade/product-e2e-gre-pipeline.md).
Control line: [`CONTROL-LINE.md`](CONTROL-LINE.md).
Farm skill: [`skills/barbar/SKILL.md`](skills/barbar/SKILL.md) (score only).

## Dune bar (I17)

If a T# is missing or red, the statement that we match that talk lever is false.

| ID | Talk | Evidence |
|----|------|----------|
| T1 | Skill | `/barbar` hard-stops feature one-shots. `evals/hops/fail-oneshot-feature.md` |
| T2 | Evals | Hop reports are scored. `tests/score_hops.py` |
| T3 | Hard CI | `.github/workflows/control-line.yml` runs the farm on `pull_request` and `push` to `main`. No `continue-on-error`. |
| T4 | Loop until n/n | `tests/barbar.sh` prints `BARBAR k/n` and exits 1 unless k=n |
| T5 | Auto-merge on green | Merge REFUSED without CLEAN 10 + 11 READY. ALLOWED on `evals/fixtures/ready-product`. |
| T6 | Don't trust chat | IMPLEMENTED without a path/test fails. `evals/hops/fail-implemented-without-evidence.md` |
| T7 | Verify before next | GENERATE that starts EXECUTE or N+1 fails. `evals/hops/fail-generate-executed.md` |

```
bash tests/i17_dune.sh
bash tests/barbar.sh          # BARBAR k/n; exit 1 unless k=n
bash tests/barbar.sh merge    # REFUSED on this pack repo
```

CI runs all three. `/barbar merge` prints ALLOWED or REFUSED. It does not `git push` this repo.

This pack keeps the hop edge on purpose. Unattended `/loop` through product stages is illegal (I15). Product D# as required GitHub checks live in the **product** repo, not here.

## Layout

```
CONTROL-LINE.md                 /loop vs /barbar + T1–T7
docs/cascade/                   spec pack + GRE conductor
evals/hops/                     hop-report fixtures
evals/fixtures/ready-product/   CLEAN 10 + READY 11 (merge ALLOWED)
evals/fixtures/dirty-product/   DIRTY / NOT READY (merge REFUSED)
skills/barbar/SKILL.md          farm-only skill
tests/control-line.sh           pack-law greps (I15–I17)
tests/i17_dune.sh               T1–T7
tests/score_hops.py             hop scorer
tests/barbar.sh                 the farm
.github/workflows/              required CI
```

## What this is not

- Not a “make A from B using C” build skill.
- Not Superpowers. Superpowers is craft on code-execute hops. Cascade outranks it (I14).
- Not permission to auto-merge `main` because chat said the tests passed.
