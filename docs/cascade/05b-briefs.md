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
- t53-bdd-disable: There is no way to stand the pipeline down. Debugging something unrelated inside a
  BDD repo means hand-unsetting `core.hooksPath` and hand-stripping the `hooks` key out of
  `.claude/settings.json`, then remembering to put both back — and a half-restored repo reports as
  `UNWIRED` drift, which reads like damage rather than like a switch someone left flipped. Add
  `bdd disable [repo]` and `bdd enable [repo]`: disable stands down Layer 1 (git hooks) and Layer 2
  (agent hooks), stashing the exact prior state under `.cascade/disabled/` so enable restores it
  byte-for-byte; it never touches Layer 0, so CI stays red and the merge gate still refuses. Every
  status surface — `bdd status`, `bdd doctor`, `install.sh --check`, the `seam.py` prompt banner —
  leads with `BDD DISABLED` so a forgotten disable cannot masquerade as a green pipeline. Done when
  disable/enable round-trip `core.hooksPath` and `.claude/settings.json` exactly, `.cascade/disabled/`
  is gitignored so a disable can never be committed, `install.sh --check` distinguishes DISABLED from
  DRIFT, and a red twin proves Layer 0 survives: with the repo disabled, the CI workflow is unchanged
  and `bash tests/barbar.sh merge` still REFUSES.
- t57-spec-critic: The human is the only critic of a spec+plan before it is built, and a human who lacks
  the expertise misses exactly the gaps that matter; the first independent reviewer (the stage-10
  auditor) arrives after the code exists, when a gap costs a rebuild instead of an edit. On every
  GENERATE hop of 05 / 05b, after the spec+plan are drafted, dispatch a fresh subagent with no memory of
  writing them. It first challenges the **brief** (is this the right problem; does it conflict with the
  envelope), then the spec+plan, and writes `docs/cascade/<stage>-<slice>-critique.md`: at most 10 rows,
  severity-ranked, `| C# | severity | finding | evidence | DISPOSITION |`, kept verbatim. Evidence is a
  runnable command or a quoted `path:` line; a row with neither is marked `UNEVIDENCED` so the human sees
  which findings rest on the critic's word. The author fills every DISPOSITION: `fixed <where>`,
  `rejected <reason>`, or `human <question>` (raised at the edge). Every spec also carries a
  `## Before vs after` section with a mermaid diagram and a plain-language `## Benefits and trade-offs`
  table, so a non-specialist can judge the change; the critic checks the diagram matches the plan. The
  critic is advisory — it never passes or fails a spec; `tests/critique.sh` checks only that the critique
  exists, its rows keep their shape, every row is dispositioned, and the two spec sections are present.
  The stop hook and the autopilot GENERATE→EXECUTE edge refuse while it is red. Done when `bash
  tests/critique.sh` passes on a critiqued slice, a red twin (`CRITIQUE_MUTANT=missing|undispositioned|rewritten|nodiagram`)
  makes each case go red, the GENERATE edge is refused without a green critique, and stages 01–04 / 11
  are untouched.
- t58-divergence: The design is the agent's first idea — stage 05 asks for one stack and one rejected
  alternative — so the human never sees options they did not know to ask for. Opt-in per slice: a brief
  tagged `[diverge]` makes its GENERATE hop dispatch N subagents (default 3, `DIVERGE_N`) before the
  spec, one always the boring baseline (so "prefer boring technology" survives as the default to beat),
  the others each under a different forbidden pattern or single priority. Each writes one entry in
  `docs/cascade/05b-<slice>-candidates.md` with `approach`, `constraint`, `gives up`, `regret when`,
  `failure modes` and `falsifier` (a cheap command or experiment that would prove it wrong); the t57
  critic ranks them, advisory only. The human signs the pick as a `CHOSEN: <C#> — <reason>` line inside
  `<EDIT>`; autopilot always stops for that choice with a halt naming the candidates and their
  falsifiers. `tests/diverge.sh` checks ≥N candidates, every field filled, distinct `constraint`s, and
  no two `approach` texts near-duplicate (token-overlap threshold) — it guarantees distinct text, not
  real novelty, and the spec says so. Done when `bash tests/diverge.sh` passes on a tagged slice, a red
  twin (`DIVERGE_MUTANT=clone|missing-falsifier|no-baseline`) makes each case go red, an untagged slice
  runs GENERATE exactly as today with `bash tests/enforcement.sh` green, and autopilot stops rather than
  chooses on a `[diverge]` slice.
- t59-scale-hardening: A stress test on a synthetic ten-year repo (60,060 tracked files, 10,000 spec docs,
  150 laws, 3,000 audit rows) showed the per-action layers stay flat (hooks under 100ms, a 10-file commit
  195ms), but three things grow with the repo, and two of them turn a check off without saying so.
  `cascade_worktree_sha` forks one `git hash-object` per file: 235s at 60k files, so `loop.sh` took 217s
  with a single `true` validator. The Stop hook runs that same fingerprint under a 120s timeout and
  treats a timeout as "cannot verify, let it through" (`stop_guard.py:229–234`), so past roughly 30k files
  the I10 "tree changed after the loop passed" check silently stops running; the stage-10 branch does the
  same under 900s around a full `audit.sh` (`stop_guard.py:203–208`). `sign.sh` forks one `grep` per doc
  to find `<EDIT>` blocks: 38s per signature, where one `git grep` takes 61ms. And autopilot accepts a
  slice's spec doc by substring match (`tests/lib/autopilot.py:83`), so after years of slugs an old
  `05b-login-rate-limit.md` satisfies a new slice `login`. Make the fingerprint cost scale with what
  changed, not with the size of the repo (git's own index and stat cache); make a check that cannot
  finish say so and refuse, never pass; find `<EDIT>` files in one process; match the spec doc exactly.
  Verdicts must not change on any tree the current code can check in time (I18). Done when the
  fingerprint stays under 1s on the 60k-file fixture and still changes on a one-byte edit, a timed-out
  Stop-hook check refuses the edge with a message naming the cause and the command to run by hand,
  `sign.sh` finds the same `<EDIT>` files as today, a slug that is only a substring of an older spec
  name no longer counts as its spec, and `bash tests/enforcement.sh` stays green.
