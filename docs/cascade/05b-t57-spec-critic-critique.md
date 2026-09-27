# Critique — 05b t57-spec-critic

Critic: a fresh read-only subagent with no memory of writing the spec, given the canonical brief in the
spec (§ What the slice adds, 1). Its rows below are verbatim. The author's answers are in
`## Dispositions`, added in a later commit.

## Brief

| C# | severity | finding | evidence |
|---|---|---|---|
| C1 | medium | The brief adds a condition to the autopilot GENERATE→EXECUTE edge (a green critique), but AGENTS.md rule 7 and autopilot.py's docstring list "spec doc present" as the only condition. The plan changes neither, so the written rules and the code will disagree. | `AGENTS.md:33` "only with the slice's spec doc present (GENERATE→EXECUTE)"; `tests/lib/autopilot.py:8` "if a spec doc for the slice exists"; spec PLAN step 7 names only the pipeline doc, barbar.md, 05-tech-design.md and USAGE.md |
| C2 | medium | The brief covers "every GENERATE hop of 05 / 05b", but stage 05 has no slice path to key a critique on. Autopilot also can never take a 05 edge, so the 05 half of the autopilot gate (and of AC4) is dead code. | `tests/lib/autopilot.py:27` `ALLOWED_STAGES = {"05b", "06", ...}` (no "05"); `grep -n "docs/cascade/05" docs/cascade/stages/05-tech-design.md` returns nothing, so no `05-<slice>.md` convention exists |

## Spec

| C# | severity | finding | evidence |
|---|---|---|---|
| C3 | high | The provenance check compares the rows in the working tree against the adding commit, so an author who deletes an inconvenient critic row still passes. No mutant covers row deletion. | spec `05b-t57-spec-critic.md:143-144` "compare columns 1–4 of each row at that commit against the working tree"; AC2 mutant list at `:116-118` has no `deleted` case |
| C4 | high | Rows are split into columns on `\|`, but the brief asks for evidence as runnable commands, which often contain shell pipes. The spec gives no escaping rule, so "columns 1–4", the evidence-cell check and the disposition column all mis-parse on normal evidence. | spec `:88` "Evidence is a command someone can run"; `:97-98` "the first four columns match the commit that added the file"; e.g. evidence `grep -n x f \| head` |
| C5 | medium | The stop_guard gate is weaker than claimed. On autopilot the continuation branch returns 2 before hop-state is parsed. An I10-shaped check is skipped once `stop_hook_active` is set, so it blocks only once. And `critique.sh` runs in no CI workflow, so the gate is Layer 2 only and can be bypassed. | `.claude/hooks/stop_guard.py:221-228`, `:244`, `:271-272`; `grep -rn critique .github/workflows/` returns nothing |
| C6 | medium | The plan says `critique.sh` reads CURRENT_SLICE "via tests/lib/cascade.sh", but cascade.sh has no slice reader. It has to be added, including the `CASCADE_ENVELOPE` override the autopilot pre-commit path relies on. | `grep -n "^cascade_" tests/lib/cascade.sh \| grep -i slice` returns nothing; spec `:138` |
| C7 | medium | The spec does not say what "tracked" means under the pre-commit autopilot path. If the critique is staged in the same commit as the hop-state edge, `git log --diff-filter=A` finds no adding commit, so the edge is refused. The spec also does not say whether `critique.sh` scores (or goes n/a) on EXECUTE 05b once the spec is edited. | `.githooks/pre-commit:100-106` (autopilot.py runs inside pre-commit with the edit staged but not committed); spec `:96` "exists and is tracked" vs `:143` git log; AC5 `:123` covers GENERATE only |
| C8 | low | The "after" diagram drops the stage-10 "gap found → Rebuild" branch, which suggests the audit always passes. It also leaves out the `human <question>` dispositions raised at the edge and the autopilot gate, both of which the plan adds. | spec `:57-58` `E --> G` only, vs before-diagram `:41` `E -- gap found --> F` |
| C9 | low | AC5 cites "T1–T54", but enforcement.sh reports T8–T54. It also has no T55/T56 (those slices used `tests/ac/` only), so a new `T57` skips numbers with no stated reason. | `tests/enforcement.sh:1295` `echo "PASS: I18 T8–T54 enforced"`; `grep -n "T55\|T56" tests/enforcement.sh` returns nothing |
| C10 | low | The canonical critic prompt has the critic read only the brief, envelope.md and the spec. Laws and hop state may live in hop-state.md, and AGENTS.md holds the rules, so the brief-conflict question cannot be fully answered. Nothing tells the critic to open the code the plan changes, so "will the plan work" goes unchecked. | spec `:83-86` "Read the brief line …, `envelope.md`, and the spec+plan"; `AGENTS.md:9-10` names hop-state.md and envelope.md together as truth |

## Dispositions

| C# | DISPOSITION |
|---|---|
| C1 | fixed spec AC7 + PLAN step 7: `AGENTS.md` rule 7 and the `autopilot.py` docstring name the critique condition |
| C2 | fixed scope narrowed to 05b; stage 05 moved to "Not in this slice" and Decision 1 |
| C3 | fixed provenance compares the set of C# ids too; `deleted` mutant added to AC2 |
| C4 | fixed rows split on unescaped `\|` only; critic brief says to escape; `pipes` mutant added to AC2 |
| C5 | fixed stop_guard check moved before the autopilot branch; CI step added in `control-line.yml` (AC4b); the once-per-stop limit is stated as the soft layer |
| C6 | fixed PLAN step 0 adds `cascade_slice()` honouring `CASCADE_ENVELOPE` |
| C7 | fixed critique committed before any edge commit; `n/a` on EXECUTE; shallow history fails, never passes |
| C8 | fixed after-diagram keeps the gap-found branch and shows human rows and the refusing gates |
| C9 | fixed AC5 says T8–T54; T57 numbering explained under Laws |
| C10 | fixed critic brief reads `hop-state.md`, `AGENTS.md` and every file the PLAN changes |
