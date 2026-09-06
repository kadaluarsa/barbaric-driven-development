# Changelog

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
