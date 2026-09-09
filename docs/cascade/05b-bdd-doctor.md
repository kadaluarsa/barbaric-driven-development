# Stage 05b — bdd-doctor — SPEC

## User story IDs from the PRD

- **S-DR1** — As someone who installed BDD, I run one command and learn whether the pipeline is
  actually working, not merely whether its files are intact.
- **S-DR2** — As someone whose repo is half-wired, the output tells me which layer is dead and what to
  run, rather than a single red verdict.
- **S-DR3** — As a maintainer, I can trust each check because breaking it on purpose turns the run red.

## The problem, stated exactly

`bdd check` (`install.sh --check`) answers one question well: do the shipped files still match the
pack? It verifies the version line, every file's SHA against `.cascade/manifest`, that no enforcement
directory is gitignored, and that `.claude/settings.json` names the five hooks.

That is the pack's *files* being intact. It is not the pack *working*. Nothing today asks:

| Question | Checked today |
|---|---|
| Does `core.hooksPath` actually point at `.githooks`? | **no** — settings.json wiring is checked, git's is not |
| Does Layer 0 exist (a CI workflow that runs the farm)? | **no** |
| Are the D# laws in force, or UNPROVEN/THEATER? | only inside `barbar merge` |
| Is the hop state coherent — a hop open on a slice with no spec doc? | **no** |
| Does an `AUTOPILOT:` entry name a slice nobody briefed? | only when autopilot runs |
| Do the `reads:` and `stages` manifests hold? | via `lint.sh`, not surfaced as health |
| Does the farm still run end to end? | `bdd farm`, separately |

A repo can pass `bdd check` with every byte correct and still have a dead pipeline: `core.hooksPath`
unset after a fresh clone, and Layer 1 is simply gone while every file it needs sits there hashing
correctly.

## What the slice adds

`tests/doctor.sh`, run as `/bdd doctor`, `bdd doctor`, or `bash tests/doctor.sh`. It walks I18's layer
order — lowest layer that can enforce, first — and prints one line per check plus a score.

```
DOCTOR — barbaric-driven-development 1.8.0 (standalone)

  L0  CI            2 workflows, farm invoked in pack-self-check.yml
  L0  main          protected (branch protection not readable offline — see note)
  L1  hooksPath     core.hooksPath -> .githooks
  L1  git hooks     pre-commit, pre-push present and executable
  L2  agent hooks   5 wired in .claude/settings.json
  --  pack          CASCADE 1.8.0 (standalone): no drift in 47 shipped files
  --  laws          DSHARP 0/0 — no law in force (propose with /barbar init)
  --  hop state     NONE — coherent
  --  manifests     READS clean, STAGES clean
  --  farm          BARBAR 22/22

DOCTOR 10/10
```

**It composes; it does not re-implement.** `install.sh --check`, `dsharp_strength.sh`,
`reads_manifest.sh`, `stage_templates.sh` and `barbar.sh` own their verdicts and doctor reports them.
Re-deriving a verdict doctor does not own is how two sources of truth start disagreeing.

The genuinely new checks are three:

1. **`core.hooksPath`** — `git config core.hooksPath` resolves to the repo's `.githooks`. This is the
   one that survives a clone badly and is invisible to every existing check.
2. **Layer 0 presence** — at least one workflow under `.github/workflows/` invokes `tests/barbar.sh`.
   Branch protection itself is a GitHub setting and cannot be read offline; doctor says so rather than
   implying it checked.
3. **Hop-state coherence** — `hop-state.md` parses; if `CURRENT_HOP` is `GENERATE` or `EXECUTE` then
   `CURRENT_STAGE` is set, and for a 05b slice `docs/cascade/05b-<slice>.md` exists before EXECUTE;
   every `AUTOPILOT:` entry names a slice with a brief or a spec. An open hop pointing at a slice
   nobody wrote is the failure that wastes a whole session.

### A degraded repo must be diagnosed, not crashed on

Doctor runs *because* something may be wrong, so a missing file is a finding, never a stack trace. No
`.cascade/manifest` → `pack: not installed here — run bdd install .`, and the run continues. Each
check is independent; one red never skips the rest.

### `DOCTOR k/n` and nothing softer

`k` counts green checks, `n` counts checks that ran. Exit 0 only when `k == n`. A check that cannot
run in this environment is not silently green — it prints `skipped` with the reason and is excluded
from `n`, so a skip can never inflate the score. Same discipline as `BARBAR k/n` (I17).

## Files likely touched

- `tests/doctor.sh` — new
- `commands/doctor.md` and `.claude/commands/doctor.md` — the slash command, byte-identical (T38)
- `install-global.sh` — a `doctor)` case and its help line
- `install.sh` — ship `tests/doctor.sh` and the command file; add them to the manifest
- `tests/lint.sh` — syntax-check the new script (already globs `tests/*.sh`)
- `README.md` / `USAGE.md` — one line each, so the command is discoverable
- `tests/enforcement.sh` — a new `T52` proving doctor goes red when a layer dies

## Tests that must pass

- `bash tests/doctor.sh` → `DOCTOR n/n`, exit 0.
- Red twins, one per new check: `DOCTOR_MUTANT=hookspath`, `=layer0`, `=hopstate`. Each breaks that
  check in a scratch copy and the run **must** go red. A check with no twin does not count as in force.
- `bash tests/doctor.sh` in a directory with no `.cascade/manifest` exits non-zero **and prints a
  finding**, not a traceback.
- `bash tests/lint.sh`, `tests/enforcement.sh` (with the new T52) green.
- Fresh `install.sh` into a scratch repo: `bash tests/doctor.sh` runs there and names its own gaps.

## What the user can do when the slice is done

Type one command after a clone, an upgrade or a bad merge, and see which enforcement layer is dead —
instead of discovering it the next time a guard silently fails to fire.

## What the agent must not touch

- `<EDIT>` blocks; `envelope.md`; the human-owned lines of `hop-state.md`.
- `evals/` — frozen transcripts.
- The verdicts doctor reports. Doctor never re-scores `BARBAR`, `DSHARP` or `CASCADE`; if one is
  wrong, that is a bug in the owning script, not something to paper over here.
- Existing `tests/inv/*` and any test under an existing D# id.
- No check may be weakened, skipped by default, or made advisory to get `DOCTOR n/n` (I18).

## D# IDs this slice can break

None. `DSHARP 0/0` — no law is in force in this repo. Doctor *reports* law strength; it does not
define laws, and the agent may not write D# lines.

---

# Stage 05b — PLAN

## Goal

Execute lands `tests/doctor.sh` and its three red twins, exposes it as `/bdd doctor` and `bdd doctor`,
ships it through `install.sh`, and adds T52 so a dead layer is provably caught.

## In scope this execute

- [ ] `tests/doctor.sh` — layered checks, `DOCTOR k/n`, degraded-repo tolerance
- [ ] Three `DOCTOR_MUTANT` twins for the three new checks
- [ ] `commands/doctor.md` + `.claude/commands/doctor.md`, byte-identical
- [ ] `doctor)` case and help line in `install-global.sh`
- [ ] `install.sh` ships both new files
- [ ] `T52` in `tests/enforcement.sh`
- [ ] One line each in `README.md` and `USAGE.md`

## Out of scope this execute

- Querying GitHub for branch protection. Offline-honest reporting only.
- Auto-repair. Doctor diagnoses and names the command; it never installs, rewires or signs.
- Folding `bdd check` into doctor, or changing `install.sh --check`'s output.
- The `invariant-card` and `rename-build-stage` briefs.
- Making doctor a merge gate. Diagnosis first; gating is a separate decision.

## Definition of done

1. `bash tests/doctor.sh` → `DOCTOR n/n`, exit 0.
2. Each of `DOCTOR_MUTANT=hookspath|layer0|hopstate` → non-zero, naming that check.
3. Doctor in a bare directory → non-zero with a finding, no traceback.
4. `bash tests/lint.sh` and `bash tests/enforcement.sh` (incl. T52) → exit 0.
5. Fresh `install.sh` into a scratch repo → doctor runs there.
6. `commands/doctor.md` and `.claude/commands/doctor.md` byte-identical (T38).
7. No `<EDIT>` change, no `evals/` change.

## Risks / UNKNOWNs that still block

- **Doctor becomes a second source of truth.** The failure mode is doctor saying "laws fine" while
  `barbar merge` refuses. Mitigation is structural: doctor shells out and quotes, never re-derives.
- **Branch protection is unverifiable offline** and it is the strongest control in the stack. Doctor
  must not let a green line imply it checked. Wording is load-bearing here.
- **T52 is a test I add about my own script.** It belongs to a new id, so it does not touch the
  human-owned suite — but its value depends on it failing when a layer dies, which the three twins,
  not T52 alone, are there to prove.

## Ask of you

1. **Name.** `/bdd doctor` reads as a two-word command, but the pack's existing commands are single
   words (`/barbar`, `/loop`, `/audit`). This plans `/doctor` as the slash command with `bdd doctor`
   in the terminal launcher — matching how `/barbar` pairs with `bdd farm`. Say if you want the slash
   command literally named `bdd doctor`.
2. **Farm inside doctor?** Running `tests/barbar.sh` makes doctor slow (the farm is the expensive
   part). The plan includes it, with `--fast` deferring it. Say if you would rather doctor never run
   the farm.

## Invariants this hop

- PRESERVE run: no
- /goal set to: the seven DoD items above
- /model /effort: Opus 5, default
- /plan: used — this is the plan
- reads: manifest for this stage — loaded as written (03, 05); also read `install.sh`,
  `install-global.sh`, `.githooks/`, `tests/dsharp_strength.sh` as impact surface
- Skills skipped (I14): `brainstorming`, `writing-plans` — denied on this hop class by the seam.
- INVARIANTS I1–I18: held. One hop, GENERATE only, spec + plan, no product code, no EXECUTE.
