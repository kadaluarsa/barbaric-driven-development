# Stage 05b — stage-reads-manifest — SPEC

## User story IDs from the PRD

BDD's product is the cascade itself; the story this slice serves:

- **S-RM1** — As an operator running a mid-cascade hop, I can see exactly which prior artifacts this
  stage consumes, so the hop does not carry stages it is not running.
- **S-RM2** — As an operator, I can trust the manifest is honest, because a test fails if a stage
  claims to read an artifact from a stage that has not been accepted by then.

## The problem, stated as cost

`## What each stage generates vs executes` in `product-e2e-gre-pipeline.md` says what each stage
*produces*. Nothing says what each stage *consumes*. With that gap, the safe reading of AGENTS.md
("`envelope.md` and `hop-state.md` are truth", plus the accepted-artifact list) is to carry every
accepted artifact into every hop. Per-hop context then grows with the pile rather than with the work:
a stage 08 hop drags 01's problem statement and 02's JTBD alongside the 05 design it actually needs.

The 22-hop floor is the method and is not in scope to change. What this slice removes is each hop
paying for stages it is not on.

## What the slice adds

A `reads:` line per stage, in the existing generates/executes table's own document, plus the hop
shapes citing it.

| Stage | reads: |
|-------|--------|
| 00 Intake | — (human-authored) |
| 01 Problem | 00 |
| 02 Users | 00, 01 |
| 03 PRD | 01, 02 |
| 04 UX | 03 |
| 05 Tech design | 03, envelope D# laws |
| 05b Build | 03 (the slice's story IDs only), 05, envelope D# laws, this slice's spec |
| 06 Sec/privacy | 03, 05, envelope D# laws |
| 07 Quality | 03, 05, envelope D# laws |
| 08 SRE | 05, 09 if accepted, envelope D# laws |
| 09 Launch | 03, 05 |
| 10 Feature Audit | 03, accepted 05b slice specs, the tree |
| 11 PRR | 10 scoreboard, 06–09, envelope D# laws |

Two rules govern every row:

1. `envelope.md` and `hop-state.md` are read on every hop regardless — they are truth, and they are
   ~2.5 KB together. They are not listed per-row.
2. A stage may only name artifacts from stages that precede it. A manifest naming a later stage is a
   cycle and the test rejects it.

## Files likely touched

- `docs/cascade/product-e2e-gre-pipeline.md` — add the `reads:` column to the generates/executes
  table; add the two governing rules under it; cite the manifest from the GENERATE and EXECUTE hop
  output shapes.
- `tests/inv/test_reads_manifest.sh` (new) — the validator.
- `tests/lint.sh` — call the new validator.

## Tests that must pass

- `bash tests/inv/test_reads_manifest.sh` — parses the table and asserts: every stage 00–11 plus 05b
  has a `reads:` cell; no cell names a stage at or after its own; every named stage exists.
- Red twin: `READS_MUTANT=1 bash tests/inv/test_reads_manifest.sh` — injects a forward reference and
  must **fail**. A validator that cannot fail is THEATER and does not count.
- `bash tests/lint.sh` stays green.
- `bash tests/enforcement.sh` stays green — this slice must not perturb the hook suite.

## What the user can do when the slice is done

Open the pipeline doc at any stage and read, in one line, the set of prior artifacts that hop loads —
and rely on it, because a forward reference or a missing row fails a test rather than passing silently.

## What the agent must not touch

- `<EDIT>` blocks anywhere. Human-authored.
- `docs/cascade/envelope.md`, `docs/cascade/hop-state.md` — human-owned lines.
- Any existing `tests/inv/*` file. This slice adds one new file under a new id; it changes none.
- The stage list itself. No stage is added, removed, merged, or renumbered.
- `product-e2e-cascade.md` — the template split is a separate brief (`stage-template-split`).
- The hooks in `.claude/hooks/`. No enforcement layer is weakened (I18).

## D# IDs this slice can break

None of D1–D∗ in `envelope.md` are touched — the envelope's `<EDIT>` law block is still the example
template, so no product law is in force. This slice introduces no product code and no new law. The
validator above is a lint-level test, not a D#.

If the human wants the manifest to be a law rather than a lint, that is an `<EDIT>` to `envelope.md`
they make and sign — see Ask 3.

---

# Stage 05b — PLAN

## Goal

Execute adds a `reads:` manifest to the stage table in `product-e2e-gre-pipeline.md`, makes the
GENERATE and EXECUTE hop shapes cite it, and lands one validator with a red twin that keeps the
manifest honest. No product code, no stage renumbering, no template split.

## In scope this execute

- [ ] `reads:` column on the generates/executes table → `docs/cascade/product-e2e-gre-pipeline.md`
- [ ] The two governing rules under that table → same file
- [ ] One line in each hop output shape citing the manifest → same file
- [ ] `tests/inv/test_reads_manifest.sh` with `READS_MUTANT=1` red twin → new file
- [ ] `tests/lint.sh` calls it → `tests/lint.sh`

## Out of scope this execute

- Splitting `product-e2e-cascade.md` into per-stage files (brief: `stage-template-split`)
- Extracting the I1–I18 card (brief: `invariant-card`)
- Trimming AGENTS.md's "read before doing anything" list
- Teaching `tests/loop.sh` to enforce the manifest at hop time — lint first, gate later if it holds
- Any measurement harness for token counts

## Definition of done

1. `bash tests/inv/test_reads_manifest.sh` exits 0.
2. `READS_MUTANT=1 bash tests/inv/test_reads_manifest.sh` exits non-zero.
3. `bash tests/lint.sh` exits 0 and its output names the new validator.
4. `bash tests/enforcement.sh` exits 0 — unchanged from before the slice.
5. `git diff --stat` touches exactly the three files named in scope, and no `<EDIT>` block.

## Risks / UNKNOWNs that still block

- **Parser brittleness.** The validator reads a markdown table. If the table is later reformatted the
  test breaks noisily rather than silently — acceptable, but the failure message must say so.
- **The manifest is advice, not enforcement.** Nothing at hop time stops a hop reading more than its
  row. This slice makes the budget legible; it does not police it. Naming that limit honestly rather
  than overclaiming.
- **05b's row is per-slice.** "03, the slice's story IDs only" is a judgment call, not a file list.
  The test can check the row exists and is well-formed; it cannot check the operator obeyed it.

## Ask of you

1. **Confirm the manifest rows above**, especially 08 (does SRE genuinely need 09, or only 05?) and
   11 (is 06–09 the right set, or only the 10 scoreboard plus the laws?).
2. **Lint or gate?** This slice lands it as a lint in `tests/lint.sh`. Say if you want
   `tests/loop.sh` to refuse a hop on a malformed manifest instead — that is a bigger blast radius
   and I would rather you choose it than assume it.
3. **Law or not?** If the manifest should be a D# in `envelope.md` with a check/break pair, that is
   an `<EDIT>` you author and sign. I will not propose envelope law text.
4. **Slice order.** `stage-template-split` is the larger token win but touches twelve files;
   `invariant-card` is the smallest. Confirm this one goes first.

## Invariants this hop

- PRESERVE run: no (session not compacted)
- /goal set to: the five DoD items above
- /model /effort: Opus 5, default effort
- /plan: used — this is the plan
- INVARIANTS I1–I18: held. One hop, GENERATE only, spec + plan, no product code, no stage 05b EXECUTE,
  no enforcement layer weakened.
