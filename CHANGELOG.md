# Changelog

## 1.2.3 — 2026-09-08

**The plugin was shipping a stale `/barbar`.**

- **Fix: plugin-mode `/barbar auto` had been running a four-release-old command.** `commands/` and `skills/` were symlinks into `.claude/` until 1.1.1, when the plugin loader turned out not to follow links; the real files that replaced them then froze. `commands/barbar.md` fell 27 lines behind, so a plugin-mode autopilot run had **no stage-10 adversarial auditor**, no "never ask and wait" rule, and no mandatory HALT instruction block — silently, since the file still worked. It is synced, and `T38` now asserts every shipped file is a real file and byte-identical to the `.claude/` copy the repo runs.

- **`/barbar init` proposes laws in the current format.** It was still emitting `D1 | law | check | break` pipe rows, and telling humans to sign with `CASCADE_HUMAN=1` as though the approval dialog did not exist. Proposals now come as `### D1` / `check:` / `break:` blocks with a `why:` line naming the commit or code path behind each one, and the checklist leads with the dialog — approving the agent's edit *is* the signature — with `bash tests/sign.sh` and the env var as the hand-edit paths.

- **`T33` exists.** It had a changelog entry and a `CONTROL-LINE` claim since 1.1.x but no test: nothing asserted that a hand-edited file can be signed from a GUI git client, that the refusal names the signing command, that the token is one-shot, or that the agent is denied running it. All four are now checked.

## 1.2.2 — 2026-09-07

**Laws you can read, and an ending that only fires when a hop ends.**

- **A domain law is now three plain lines instead of one long pipe row.** A heading you can read, a command that must pass, a command that must fail:

  ```
  ### D1 — a user's balance MUST NOT go negative
  check:  pytest tests/inv/test_D1.py
  break:  INV_MUTANT=D1 pytest tests/inv/test_D1.py
  ```

  The old `D1 | law | check | break` form still parses, so repos already using it keep working with no edit. Both go through one reader, `tests/lib/laws.py` — previously six files each had their own regex for law syntax, which is how a placeholder line once slipped through as a real law and halted autopilot. `envelope.md` also drops its implementation notes (they moved to `USAGE.md`) for a table of the four states a law can be in — GREEN, RED, THEATER, UNPROVEN — and what to do about each.

- **Fix: the agent printed a hop-edge line over questions.** `AGENTS.md` asked for `STITCH NEEDED: … for stage N` at the end of *every* reply, so plain answers ended by closing a hop that was never open, with the literal letter `N` where a stage should be. The Stop hook always drew the right boundary — silent unless the envelope says a hop is running — and the prose now agrees with it: the ritual belongs to hop replies, and idle replies end normally. `T37` asserts both layers, so they cannot drift apart again.

- **Fix: `docs/cascade/skill-binding.md` went stale on upgrade** and turned the farm red, which blocked pushes until it was hand-edited. The installer now replaces it as a pack-owned file instead of preserving your copy.

- `CONTROL-LINE.md` gains the missing `T34`–`T36` rows alongside the new `T37`.

## 1.2.1 — 2026-09-07

- **Fix: CI failed on a plugin-mode repo.** Layer 2 (agent hooks, commands, skill) lives in the plugin, so a runner that has no plugin has nothing to test — but the tests treated absent as broken and failed `T1` and every hook test. They now skip with a reason naming the CI runner, while Layers 0 and 1 stay fully enforced. Where Layer 2 *is* installed — your machine, or any standalone install, including in CI — nothing skips and coverage is unchanged.


## 1.2.0 — 2026-09-06

**The audit joins autopilot, judged by someone who did not write the code.**

- `AUTOPILOT: 05b a, 05b b, 10 audit` — stage 10 can be signed onto the list. Its GENERATE hop dispatches an *independent* reviewer (a fresh subagent, briefed to be hostile to narrative: "if you did not open the file, it is not IMPLEMENTED") to find each FR/NFR/D#'s artifact and test; the rows go in unchanged and `tests/audit.sh` decides. Its EXECUTE hop punches DIRTY rows — real fixes only, never by editing a row or deleting a test — up to three rounds, then halts.
- **Stage 11 and merge can never be signed.** `autopilot.py` rejects a list containing them: READY is the human's signature, merge is the human's act.
- A signed initiative now costs two signatures — the list and READY — instead of two per slice (T36).


## 1.1.5 — 2026-09-06

- **Fix: a plugin-mode repo could never reach `BARBAR n/n`.** The farm's tests looked for the hooks, commands and skill inside the repo, but plugin mode keeps Layer 2 in the plugin — so `/barbar merge` was unreachable in exactly the setup the docs recommend. `install.sh` records `plugin_root` in the manifest and the tests resolve Layer 2 from it (T35).
- **Fix: a product's own `AGENTS.md` never received the cascade rules.** The installer kept an existing file, so the agent read the product's rules and not the hop law. The rules are now appended below whatever is already there (T35).
- **Version drift is announced** at session start with the exact refresh command, and `install.sh --check` names it (T34, 1.1.4).


## 1.1.4 — 2026-09-06

- **Version drift is announced.** A plugin update refreshes only the machine-wide half; a repo's `tests/`, `.githooks/` and commands come from `install.sh`. When they diverge, the session-start hook now says so and prints the exact refresh command, and `install.sh --check .` names it too. Three separate "the fix didn't work" reports traced to this (T34).


## 1.1.3 — 2026-09-06

- **Every halt is actionable.** A halt must carry `BOTTLENECK` / `WHAT TO DO` (copy-pasteable) / `IF YOU DISAGREE` / `RESUME WITH` / `DONE SO FAR`. The Stop hook sends back a halt lacking that block, so a run never ends with a reason you cannot act on (T28).
- **The loop's refusal explains itself.** An undecided law names the envelope line, the two commands to write, the signing command and the waiver alternative. A law whose commands are already named is ordinary hop work — the loop runs it and the agent writes the test (T18).


## 1.1.2 — 2026-09-06

- **Fix: a human editing by hand could not commit from an IDE.** The only signature was an environment variable, which a GUI git client cannot pass, so a hand-edited envelope was blocked in a loop. A signing command now mints the same one-shot token for the human-owned files you changed; commit from any client afterwards. The agent is denied running it (reading and linting stay allowed) and the block messages name it (T33).
- **Fix: quoted text is never a command.** A multi-line commit message mentioning a guarded command tripped the ship guard; quoted spans are blanked before command-position matching (T15).


## 1.1.1 — 2026-09-05

- **Fix: `/barbar` was unknown in plugin-mode repos.** The plugin root shipped `commands/` and `skills/` as symlinks (the loader does not follow them) and plugin-mode install removed the repo's `.claude/commands` — so such a repo had no `/barbar` at all. Both are real directories now, and plugin mode keeps the repo's commands (the plugin's own remain reachable as `/bdd:barbar`). T31 pins both.
- **Note:** `claude plugin update` refreshes only the machine-wide half. Re-run the plugin's `install.sh` in each repo to update its scripts; `install.sh --check .` reports the version mismatch.


## 1.1.0 — 2026-09-05

Seamless delivery and two bugs found by the first real user.

- **Plugin.** `claude plugin install bdd@bdd`; hooks, commands and the skill machine-wide; the agent offers the repo-side install on the first feature prompt (T31).
- **Approve-to-sign.** The permission dialog is the human signature for hop edges, laws, `<EDIT>` content and law tests; one-shot tokens pre-commit accepts once (T30).
- **First-knowledge discovery.** `/barbar init` proposes laws and audit rows; hooks nudge until a law is in force (T29).
- **Fix: a template placeholder is not a law.** Fresh installs shipped an unprovable D1 that halted autopilot at the first EXECUTE (T18).
- **Fix: a hook's GIT_DIR never reaches the farm.** The pre-push farm's throwaway repos inherited GIT_DIR and flipped a real product to `core.bare=true` and re-pointed its worktree HEAD (T32).
- Worktree-safe installer, bytecode never staged, plugin-mode install strips prior project hooks, docs rewritten for three readers.
- Versions: `VERSION`, `plugin.json` and `marketplace.json` are tied by T31 — the plugin updater compares them.


## 1.0.0 — 2026-09-02

First production-oriented release. Every control lives at the lowest layer that can enforce it (I18), and each layer is pinned by a behavioral test (T1–T22).

- **Plugin.** `claude plugin install bdd@bdd`: hooks, commands and the skill machine-wide; the agent offers the repo-side install on the first feature prompt (T31). **Approve-to-sign:** the permission dialog is the human signature for hop edges, laws, `<EDIT>` content and law tests (T30). **First-knowledge discovery:** `/barbar init` proposes laws and audit rows; hooks nudge until a law is in force (T29).
- **Layers.** CI + branch protection; git hooks (`.githooks/`) for any agent; Claude Code hooks (`.claude/hooks/`: hop_guard, bash_guard, stop_guard, preserve, seam); rules (`AGENTS.md` + shims).
- **Commands are scripts.** `tests/loop.sh` (LOOP k/n), `tests/barbar.sh` (BARBAR k/n, merge gate), `tests/dsharp_strength.sh` (DSHARP k/n), `tests/audit.sh` (AUDIT k/n). The agent never types a score.
- **Human-owned lines.** `CURRENT_HOP/STAGE/SLICE` and every D# line are rejected by pre-commit and hop_guard; humans commit hop edges with `CASCADE_HUMAN=1`, which the agent is denied.
- **Red twin.** A D# is in force only with a validator and a command that must fail; THEATER and UNPROVEN refuse merge, UNPROVEN blocks the loop.
- **Stage 10 computed.** `audit.sh` scores rows against the tree; prose verdicts are ignored. Stage 11 READY counts only inside `<EDIT>` (human-signed).
- **Fail visibly.** A crashing guard returns `ask`, never allow. `install.sh --check` reports drift. Idempotent install: a re-run replaces pack-owned paths, nests nothing, drops stale files (T23).
- **Autopilot (opt-in).** A human-signed `AUTOPILOT:` list lets the agent advance hop edges itself — only the next listed edge, spec doc before EXECUTE, `loop.sh` n/n before the next slice; 10/11, READY and merge stay human (T27). `/barbar auto` runs the list overnight on Claude Code; the Stop hook continues until done, HALT, or a cap (T28). Measured: stress run 8, 4/4.
- **Stress-tested.** `evals/spike/stress.sh`: two features of rising difficulty, a law-contradicting trap, an audit hop, the ship gate. Findings became T14b, T25 (existing law tests are human-owned), T26 (no exception carved into a law; no new test under an existing D# except the file its law names). Run 5: 7/7 strict.
- **Measured.** `evals/spike/`: fresh container, Phase 1 from zero, then a real agent through seven probes — recorded in `evals/probes/` — Phase 1 22/22, PROBES 7/7 on `2ee3c9f`.
