- multi-currency: <one paragraph>
- journal-transfers: <one paragraph>
- stage-reads-manifest: Every hop currently carries context for stages it is not running. A stage 08
  hop re-reads 01's problem statement and 02's JTBD in full, though it needs only the invariants and
  the stage 05 technical design — so per-hop context grows with the accepted-artifact pile rather than
  with the work. Give each stage in `product-e2e-gre-pipeline.md` an explicit `reads:` line naming the
  prior artifacts that stage actually consumes, and teach the GENERATE and EXECUTE hop shapes to load
  exactly that list and nothing else. The 22-hop floor is the method and stays; what goes is each hop
  paying for stages it is not on. Done when every stage 00–11 carries a `reads:` line, the hop shapes
  cite it, and a test asserts no stage's manifest names an artifact from a stage that has not been
  accepted yet.
- t52-environment-independent: `T52` asserts `DOCTOR n/n` in the pack's own checkout, which is a fact
  about the machine running it rather than about the code. CI checks out a fresh clone, `core.hooksPath`
  is unset there — it is git config and does not travel with a tree — so doctor correctly reports Layer 1
  dead, and T52 fails. It passed locally only because this machine had `core.hooksPath` set from an
  earlier install, and it could never have passed in CI. The failure is real but it is the test's, not
  doctor's: a test that depends on ambient configuration asserts nothing about the thing it names, and
  the fix is not to make doctor lenient about a genuinely dead layer. Replace the ambient-health
  assertion with a constructed positive control — a scratch repo with `core.hooksPath` set, where that
  check must be green — keeping every behavioural assertion T52 already makes (the three red twins, a
  skip never counted as green, branch protection never claimed as checked, a bare repo diagnosed rather
  than crashed on, one command file byte-identical in both trees). Done when `bash tests/enforcement.sh`
  passes both with `core.hooksPath` set and with it unset, proving the test no longer reads the
  environment it runs in.
- bdd-doctor: `bdd check` (`install.sh --check`) answers one question — do the shipped files still match
  the pack: version, per-file SHA, nothing gitignored, hooks wired. That is the pack's *files* being
  intact, which is not the same as the pack *working*. Nothing today asks whether the laws are in force,
  whether the hop state is coherent (a hop open on a slice whose spec doc does not exist, an `AUTOPILOT:`
  entry naming a slice nobody briefed), whether `core.hooksPath` actually points at `.githooks`, whether
  Layer 0 exists at all, or whether the farm still runs end to end. A repo can pass `bdd check` with
  every byte correct and still have a dead pipeline. Add `/bdd doctor` — `tests/doctor.sh`, plus a
  `doctor` case in the `bdd` launcher and a command file — that runs the checks in I18's layer order
  (Layer 0 CI, Layer 1 git hooks + `core.hooksPath`, Layer 2 agent hooks, pack integrity via
  `install.sh --check`, laws via `dsharp_strength.sh`, hop-state coherence, the `reads:`/`stages`
  manifests, then the farm) and prints one line per layer plus `DOCTOR k/n`, exiting non-zero unless
  k=n. It composes existing scripts wherever one exists and never re-implements their verdicts; the new
  checking is the hop-state coherence and the Layer 0/`hooksPath` probes. Done when `bash
  tests/doctor.sh` prints `DOCTOR n/n` in this repo, a red twin proves each new check can fail
  (`DOCTOR_MUTANT=<check>` breaks one and the run must go red), `bdd doctor` and the command file reach
  it, and a fresh `install.sh` into a scratch repo yields a tree where doctor runs and names its own
  gaps rather than crashing.
- stage-template-split: `product-e2e-cascade.md` holds all twelve stages' spec templates in one 31 KB
  file, and a hop uses exactly one of them. Split the templates into `docs/cascade/stages/NN-<name>.md`
  and reduce the parent file to a dispatch index that points at the stage in play. Done when the parent
  is under 4 KB, every stage template lives in its own file, and a test asserts the index names every
  file present and no file is orphaned.
- invariant-card: Invariants I1–I18 are the part of `product-e2e-gre-pipeline.md` actually consulted
  mid-hop, but they sit inside a 32 KB document that must be loaded whole to reach them. Extract them
  to a standalone `docs/cascade/invariants.md` card of roughly 1 KB, leave a pointer behind, and have
  the hop shapes cite the card. Done when the card exists, the pipeline doc references rather than
  restates I1–I18, and `tests/loop.sh` reads the card.
