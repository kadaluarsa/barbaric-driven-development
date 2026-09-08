# Changelog

## 1.4.0 — 2026-09-08

**Counting the pack's own invariants, and closing the one that mattered.**

BDD declares 18 invariants (I1–I18). Fifteen were enforced by a hook, a script or a gate. Three — I10, I11, I12 — appeared in no enforcement code at all: they were prose asking the agent to behave, which is the exact thing this pack exists to replace.

- **I10 is now mechanical.** *"Execute may not ask for accept without the review command for that hop."* `autopilot.py` gated the *advance* on `tests/loop.sh`, but an interactive hop could print `STITCH NEEDED: accept execute for stage 05b` having never run it — and the human was asked to accept work with no evidence behind it. `loop.sh` now writes a receipt when it reaches n/n, naming the hop and fingerprinting the working tree; the Stop hook refuses the accept edge unless a receipt matches **this hop and this code**. A missing receipt, a receipt from another stage, or any edit made after the loop passed all fail, with the command that produces the evidence named in the refusal. A failing loop deletes the receipt. `T41`, mutation-checked.

- **I11 and I12 are documented as unenforced, with the reason.** I11 (send-back → rewind, don't stack fixes on a dirty tree) has no machine signal: a send-back happens in chat, so a hook cannot see one. I12 is half-covered — hop state, locks and plan are protected lines already, but a tangent editing a legitimately-writable file is indistinguishable from the hop's own work. Claiming otherwise would be the theater the pack forbids.

- **`CONTROL-LINE.md` gains an invariant coverage map** — every I# against the layer that enforces it and the T# that proves it, including the two entries that say "nothing" out loud.

## 1.3.1 — 2026-09-08

- **Fix: explaining a halt triggered one.** The Stop hook matched `AUTOPILOT HALT` anywhere in a reply, so documenting the halt format — in a code fence, in a changelog entry, in an answer to "what does a halt look like" — stopped a session that had no hop running and demanded an instruction block for a halt nobody issued. It happened while writing the 1.3.0 release notes. Code fences and inline code spans are now read as quotation; a halt anywhere else on a line still counts, including appended to an edge line. Same bug class as `T15`, where a commit message naming a guarded command was parsed as the command. Covered by four cases in `T40`.

## 1.3.0 — 2026-09-08

**The morning after an unattended run.**

Three ideas taken from [IronCurtain](https://github.com/provos/ironcurtain), which sandboxes untrusted agents at runtime. Its threat model is not this pack's — it distrusts the agent, BDD distrusts the code — but three of its mechanisms transfer cleanly.

- **A run log.** Git records what succeeded. It does not record what was denied, what you signed, which law went red at 3am, or why autopilot stopped — that lived in terminal scrollback and then it was gone. Every layer now appends one line to `.cascade/decisions.log`:

  ```
  2026-09-08T03:14:22Z  hop_guard   DENY    src/Ledger.kt — product path on a GENERATE hop (stage 05b)
  2026-09-08T03:19:08Z  sign_ok     SIGNED  docs/cascade/envelope.md sha=4f2a… — approved in the permission dialog
  2026-09-08T03:22:10Z  dsharp      THEATER D3 refund is idempotent — break passed, so the check cannot fail
  2026-09-08T03:22:11Z  stop_guard  HALT    AUTOPILOT HALT: D3 is THEATER
  ```

  Read it with `python3 tests/lib/decisions.py . --tail 40`; the last dozen lines are also injected at session start. It is a record, never a gate — **no verdict depends on it**, and `T40` asserts that deleting it changes nothing. It is gitignored on install, and `.cascade/` is no longer a product path, so a run can never dirty the tree it is auditing.

- **A law is checked the moment it is signed.** Approving a law in the dialog used to prove nothing: it could sit UNPROVEN or THEATER until the next `/barbar auto` halted on it. Signing the envelope now runs `dsharp_strength.sh` immediately and says `DSHARP 2/3 — signed, but not yet protecting you`, naming which law and why. Their pipeline verifies a policy before deployment; this is the same discipline, one layer up.

- **A wall-clock budget.** The hop cap (`4 × slices + 4`) counts continuations, which is a poor proxy for cost — a slice stuck on a build error can burn a night inside it. `BDD_AUTOPILOT_MINUTES=90 /barbar auto` stops at 90 minutes with committed work intact and the reason logged. Unset means no ceiling, as before.

Not taken: the sandbox and the MITM proxy. They are the right answer to their threat model, but absorbing them would make BDD a runtime with a container and a proxy to maintain. Its durability comes from being plain bash and git files with no service to keep alive. Run IronCurtain *around* BDD rather than rebuilding it inside.

## 1.2.4 — 2026-09-08

**A second machine ran with no commit gates and nothing said so.**

- **`core.hooksPath` is git config, not a file, so it never travels with the repo.** Clone a cascade repo onto another machine and `.githooks/` is right there on disk with git not calling it: no commit gate, no push gate, no error, nothing visibly different from a working repo. Session start now says `LAYER 1 IS OFF` with the one-line fix, and goes quiet once the clone is wired. `T39`.

- **Fix: friendly-format laws were invisible at session start.** `preserve.py` kept its own pipe-format parser through 1.2.2, so a repo using the `### D1` / `check:` / `break:` form began every resumed session with `Domain laws: (none declared)` — the agent starting blind to laws that were in force. It reads through `tests/lib/laws.py` now, and `hop_guard.py` takes its protected-line pattern from there too. The 1.2.2 note claiming every parser was consolidated was wrong; these two were left behind.

- **The re-injected control line stops demanding a hop edge on every reply**, matching the `AGENTS.md` fix in 1.2.2. It was the reason the ritual kept reappearing over plain questions even after the prose was corrected.

- **`/barbar init` is explicitly safe to re-run** — second machine, second pass months later. It writes one file and overwrites it, never the envelope, and now skips laws already in force instead of re-proposing them.

- **README: a mermaid diagram of who does what.** Three amber boxes are the human — approve the edge, clear a halt, sign READY — and everything else is the pack. Plus what to do on a fresh clone.

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
