# Stage 05b — stage-template-split — SPEC

## User story IDs from the PRD

- **S-TS1** — As an operator running stage N, I load stage N's spec template and not the other eleven.
- **S-TS2** — As an operator, I can trust the index is complete, because a test fails if a stage file
  is missing from the index or an indexed stage has no file.

## The problem, stated as cost

`product-e2e-cascade.md` is 31 KB and holds all twelve stage templates. A hop uses exactly one. The
[`reads:` manifest](product-e2e-gre-pipeline.md) now says which *artifacts* a hop consumes; this slice
does the same for the *templates*, which the manifest does not cover because they are one file.

Measured, by region:

| Region | Lines | Bytes |
|---|---|---|
| Header — how to run it, stitch envelope, the I15–I18 rules | 1–104 | 5,610 |
| 00 Intake template | 105–132 | 1,099 |
| Stage templates 01–11 | 133–747 | 21,847 |
| Trailer — one-shot generator, stitch order, editing convention | 748–819 | 2,410 |

The 21,847 bytes in the middle are what a hop pays for eleven times over.

## Correction to the brief's DoD

The brief said the parent ends "under 4 KB". It cannot, and I would rather say so now than miss the
bar at execute. `tests/control-line.sh` asserts `Rule (I15)`, `Rule (I16)`, `Rule (I18)` and
`conductor eval fails if it does` in this file, and `tests/i17_dune.sh` asserts `Rule (I17)` — all of
them live in the 5.6 KB header. Moving them to make a byte target would be weakening an enforcement
layer to make a hop pass (I18). The header stays.

Honest target: **parent ≤ 11 KB**, from 31 KB. A hop then loads ~10 KB of parent plus ~2 KB of one
stage instead of 31 KB — roughly a 19 KB saving per hop, every hop.

## What the slice adds

`docs/cascade/stages/` with twelve files:

```
00-intake.md   01-problem.md   02-users.md    03-prd.md
04-ux.md       05-tech-design.md              06-security.md
07-quality.md  08-observability.md            09-launch.md
10-feature-audit.md             11-prr.md
```

Each file carries that stage's section verbatim — the prompt, the template, the exit gate. No wording
is rewritten in this slice; it is a move, so `git log --follow` stays useful and a send-back is a
clean revert.

The parent keeps its header and trailer, and gains a dispatch index in place of the templates:

| Stage | Template |
|-------|----------|
| 01 Problem & Opportunity | `stages/01-problem.md` |
| … | … |

## Files likely touched

- `docs/cascade/product-e2e-cascade.md` — templates out, index in
- `docs/cascade/stages/*.md` — twelve new files (moved content)
- `docs/cascade/product-e2e-gre-pipeline.md` — three references: the conductor prompt (line 23), the
  GENERATE output shape (line 333), the stage 10 note (line 419)
- `AGENTS.md` — line 12's one-line description of the pack
- `install.sh` — line 116 ships the pack; the new directory must ship too, or an installed repo gets
  an index pointing at files it does not have
- `tests/stage_templates.sh` — new validator
- `tests/lint.sh` — call it

## Tests that must pass

- `bash tests/stage_templates.sh` — every stage 00–11 has a file under `stages/`; every file is named
  by the index; no file in `stages/` is orphaned; each file contains its own stage heading.
- Red twin: `STAGES_MUTANT=1 bash tests/stage_templates.sh` — drops a stage from the index and must
  **fail**.
- `bash tests/control-line.sh` green — the I15/I16/I18 assertions still find their strings.
- `bash tests/i17_dune.sh` green — the I17 assertion still finds its string.
- `bash tests/reads_manifest.sh` green — untouched, but it reads the sibling doc.
- `bash tests/lint.sh` green, naming the new validator.
- `bash tests/enforcement.sh` green — T8–T51 unchanged, including T38 and the install path.
- `bash install.sh` into a scratch directory produces a repo whose `tests/stage_templates.sh` passes.

## What the user can do when the slice is done

Open one ~2 KB file for the stage in play instead of loading a 31 KB pack, and rely on the index being
complete because a missing or orphaned stage fails a test.

## What the agent must not touch

- `<EDIT>` blocks anywhere.
- `envelope.md`, `hop-state.md` — human-owned lines.
- **`evals/` — twenty frozen transcripts name this file.** They are recorded history, not references
  to update. Rewriting them would falsify the record.
- The header's I15–I18 rule text, and `tests/control-line.sh` / `tests/i17_dune.sh` themselves.
- The wording of any stage template. This slice moves; it does not edit.
- The stage list. Nothing added, removed, renumbered.
- `.claude/hooks/` — no enforcement layer weakened (I18).
- The `invariant-card` brief.

## D# IDs this slice can break

None. No law is in force in `envelope.md`, and this slice adds no product code and no law.

---

# Stage 05b — PLAN

## Goal

Execute moves the eleven stage templates plus 00 Intake out of `product-e2e-cascade.md` into
`docs/cascade/stages/`, leaves a dispatch index behind, updates the five places that point at the
pack, and lands one validator with a red twin that keeps the index honest.

## In scope this execute

- [ ] Twelve stage files, content moved verbatim → `docs/cascade/stages/`
- [ ] Dispatch index replaces the templates → `docs/cascade/product-e2e-cascade.md`
- [ ] Three pointer updates → `docs/cascade/product-e2e-gre-pipeline.md`
- [ ] One pointer update → `AGENTS.md`
- [ ] Ship the new directory → `install.sh`
- [ ] `tests/stage_templates.sh` with `STAGES_MUTANT=1` red twin → new file
- [ ] `tests/lint.sh` calls it

## Out of scope this execute

- Rewording any template. A move, not an edit.
- Trimming the 5.6 KB header or the 2.4 KB trailer.
- The `invariant-card` brief.
- Teaching `tests/loop.sh` to enforce which template a hop loaded.
- Touching `evals/`.

## Definition of done

1. `docs/cascade/product-e2e-cascade.md` ≤ 11 KB.
2. Twelve files exist under `docs/cascade/stages/`, and their combined content equals the removed
   region — verified by diffing the concatenation against `git show HEAD:` of the original span.
3. `bash tests/stage_templates.sh` exits 0; `STAGES_MUTANT=1 …` exits non-zero.
4. `bash tests/lint.sh`, `tests/control-line.sh`, `tests/i17_dune.sh`, `tests/enforcement.sh` all
   exit 0.
5. `install.sh` run into a scratch dir yields a tree where `tests/stage_templates.sh` passes.
6. `git status` shows no change under `evals/` and no change inside any `<EDIT>` block.

## Risks / UNKNOWNs that still block

- **Install manifest drift.** If `install.sh` ships the index but not `stages/`, an installed repo
  gets a dangling index and the failure appears in the user's repo, not ours. DoD 5 is the guard, and
  it is the item most likely to fail.
- **A test asserting on the pack by line number** rather than by string. I checked the four known
  assertions and all are `grep`-by-string, but `tests/enforcement.sh` is 51 tests deep and I have not
  read all of it. If one breaks, that is a real finding to report at the edge — not something to fix
  by loosening the test.
- **`git log --follow` across a split.** Moving twelve regions out of one file gives each new file a
  shallow history. Verbatim moves keep `git log -M` useful; any rewording in the same commit would
  not.

## Ask of you

1. **Confirm the corrected DoD** — parent ≤ 11 KB, not the brief's 4 KB, for the enforcement reason
   above. This is the one answer I need before execute.
2. **Directory name.** `docs/cascade/stages/` — say if you want `templates/` or something else, since
   renaming after install.sh ships it is a migration.
3. **Stage 00.** It sits above the "Stage prompts" heading and is human-filled. Moving it is
   consistent; leaving it in the parent is also defensible. The plan moves it. Say if not.

## Invariants this hop

- PRESERVE run: no
- /goal set to: the six DoD items above
- /model /effort: Opus 5, default
- /plan: used — this is the plan
- reads: manifest for this stage — loaded as written (03, 05); also read `install.sh`,
  `tests/control-line.sh`, `tests/i17_dune.sh` as impact surface, which the manifest does not cover
- Skills skipped (I14): `brainstorming` and `writing-plans` are denied on this hop class by the seam;
  the cascade's own GENERATE shape is the plan.
- INVARIANTS I1–I18: held. One hop, GENERATE only, spec + plan, no product code, no EXECUTE, no
  stage N+1, no enforcement layer weakened.
