# Changelog

## 1.7.0 — 2026-09-09

**An audit of the pack, and the hole it found in the signing system.**

An end-to-end review turned up six defects, three of them introduced in the previous day's releases. Then an adversarial pass over the signing system found something worse than all six.

- **Fix (security): the signature ledger was writable by the agent.** Every defence around a signature guarded the *shell* — `bash_guard` denies `CASCADE_HUMAN=` and denies running `tests/sign.sh`. None of them sees a file write. On an `EXECUTE` hop the agent could write `<sha256> docs/cascade/envelope.md` straight into `$GIT_DIR/cascade-human-ok` with the Write tool, and `pre-commit` would honour it as the human's signature — approve-to-sign, the whole point of the pack, routed around in one call. Verified live before the fix. The git dir is now sealed against the agent on every hop: ledger, pending list, hooks and refs. Ordinary product writes are untouched. `T46`.

- **Fix: a Layer 1 guard was failing open.** `echo "$staged" | grep -qx` under `set -o pipefail` returns 141 once `grep` exits at the first match and the writer takes SIGPIPE — so on a commit with a large enough staged list, the human-ownership check on the envelope **did not run at all**. Reproduced: a commit flipping `CURRENT_HOP` walked straight through. All three pipelines into `grep -q` are gone, and scratch files clean up from an `EXIT` trap so a failing `rm` can never abort a commit whose checks passed (the T45 class). `T47`.

- **The push gate is fast again.** Sealing and testing cost time: the meta-suite went 255s → 420s, taking a push to seven minutes. A gate that slow is one people bypass with `--no-verify`, and a bar routed around protects nothing. `pre-push` now runs a 7s gate that defers only the pack's own meta-suite to CI, labels its score `(fast: … not a full farm)`, and keeps lint, the hop scorer and the merge fixtures local. `barbar merge` unsets fast mode and CI never sets it. `T48`.

- **One home for the hook helpers.** Five copies of "where does hop state live", four of the logger, three of the dedupe, two crash wrappers — the same defect consolidated in 1.2.2 (six law parsers, until a placeholder counted as a law), reintroduced by hand in the same session that shipped the fix. `seam.py` carried the proof it was copy-paste: `if "seam.py" == "preserve.py"`, a comparison that is always false, inside a dedupe key. `.claude/hooks/_common.py` is now the single definition, and all six hooks fail safely in the way their event requires — a crashing PreToolUse guard asks rather than letting the call through, and `sign_ok` says so loudly, because a silent failure there looks exactly like a signature that did not work. `T49`.

- **`bash_guard` stopped denying reads.** It matched the ledger's filename anywhere in a command, so `ls`, `cat` and even a `grep` for the name were refused — three false positives in one session. A guard that fires on harmless things is one people learn to route around. Writes are still denied, and the Write/Edit path is sealed by `T46`.

- **The punch-round cap is real.** "At most **3** punch rounds" was prose, asserted by grepping the command file for literal markdown — reformatting broke the test, ignoring the instruction did not. Four DIRTY stage-10 rounds on one slice are now refused with the remaining rows named; a CLEAN audit resets the count. An agent grinding at DIRTY rows all night looks like progress every round.

- **The meta-suite runs in 113s instead of 470s**, with nothing dropped. Three tests ran a full farm — which runs `enforcement.sh` — *inside* a test of `enforcement.sh`, about 70s each, to assert something the outer run was already proving; they use the fast gate now. And `T32` nested the entire suite inside itself (208s) to prove that an inherited `GIT_DIR` never reaches a throwaway repo.

- **Fix: `T32` could not fail on this machine, and never could.** It corrupted a victim repo through an inherited `GIT_DIR` and asserted the corruption did not happen — but modern git ignores `GIT_DIR` for `init`, so the assertion passed whether or not the scripts unset anything. The suite printed the reason as a footnote on every run: *"this git does not redirect init/symbolic-ref via GIT_DIR"*. It now puts a `git` shim on `PATH` and observes the environment the scripts actually hand to git, which fails for the right reason and names the leaked path.

- **Tests that asserted wording now assert behavior.** `i17_dune.sh` — the suite certifying this pack's public claims — was 0% behavioral: `T4` grepped `barbar.sh` for the string `exit 1` rather than running the farm, and `T5`/`T6`/`T7` asserted fixture files existed without ever scoring them. Five of the eight now run something; `T0`/`T1`/`T3` stay presence checks on purpose and are labelled as such. In `enforcement.sh`, the skill-binding and send-back greps became behavioral, two redundant ones were deleted, and `T43`'s eleven assertions about conversational conduct — which no script can observe — became two scored eval fixtures plus the checks that are genuinely mechanical.

## 1.6.0 — 2026-09-09

**Hop state moves out of the envelope.**

The envelope held two things with completely different lifetimes: hop state, which turns over three or four times per slice, and your laws, which change maybe twice a year. Sharing a file meant `git log docs/cascade/envelope.md` buried "we added D3" under fifty "moved to EXECUTE" — the most valuable record BDD produces, and the hardest to read.

- **`docs/cascade/hop-state.md`** now holds `CURRENT_HOP` / `CURRENT_STAGE` / `CURRENT_SLICE` and the `AUTOPILOT:` list. `envelope.md` keeps the laws, the locked decisions and the accepted artifacts. Both are human-owned; both are protected at Layer 1 and Layer 2 exactly as before — an agent flipping the hop in the new file is refused by `pre-commit` the same way, and `T44` fails if that guard is removed.

- **Nothing breaks in an existing repo.** Every reader — six scripts, five hooks, `pre-commit` — resolves hop state to `hop-state.md` when it exists and falls back to `envelope.md` when it does not. A repo installed before the split keeps working untouched, and `install.sh` deliberately **does not** create the new file where the envelope still carries `CURRENT_HOP`: doing so would silently reset a running hop to `NONE`. It prints how to split by hand, between hops, when you want to.

- To split an existing repo: move the four lines into `docs/cascade/hop-state.md` while no hop is open, and sign that commit with `bash tests/sign.sh`. Splitting the pack's own envelope needed exactly that signature — the guard refused the agent, correctly, and `T44` now proves it refuses in the new file too.

- **Fix: the git hooks broke inside a worktree.** `pre-commit` wrote its scratch file to `$ROOT/.git/…`, which is a *file* in a worktree, so every protected-line check errored with `Not a directory` before reporting. It already resolved the real git dir two lines above and simply wasn't using it. `T45`, found by this release's own commit being refused from a worktree.

## 1.5.1 — 2026-09-08

**Two more places that made you type instead of choose.**

- **`/barbar init` walks the laws one at a time.** It used to end with "copy the ones you accept into the envelope" — a block of six proposals to hand-sort, which is how a law nobody read ends up halting a run at 3am. Each candidate is now its own question: *sign it*, *sign it and build the test*, or *skip*, with the option text saying what the `check` will run and what the `break` will disable. Signing goes through the dialog as always. It closes by reporting `dsharp_strength.sh`, so you see what is actually in force rather than what you meant to sign. This is the path from `DSHARP 0/0` to a real floor, and it is now a few clicks.

- **The accept edge offers the verdict.** *Accept*, *send back* with a one-line reason, or *show me the diff first* — instead of a line of prose you answer by typing. Silence is never read as acceptance.

- **A send-back now leaves a trace, which changes I11's status.** It was the one invariant with nothing at all behind it: a send-back happened in chat, and nothing downstream knew a hop had been rejected. The reason is now written into the slice's brief and recorded in `.cascade/decisions.log`, and the fix is told to start from a clean tree rather than stack patches. Still not *enforced* — no hook can see whether you actually rewound — but it is observable, and the loop receipt (I10) already stops stacked work from reusing the old evidence. `CONTROL-LINE.md` records the new status honestly rather than upgrading it to green.

## 1.5.0 — 2026-09-08

**A halt that could have been a click.**

`/barbar auto` with an unsigned list used to print a procedure — a four-line `sed`, a commit with the stitch key, a slice name to retype that the agent already knew — for something that is not a procedure at all. It is a *decision*: which slice to build next. The agent was handing the human homework instead of asking a question.

- **The unsigned-list path now asks.** In an interactive session, `/barbar auto` reads `docs/cascade/05b-briefs.md`, offers the slices that have no work yet as options in the permission UI's own picker, and — once you choose — makes the envelope edit itself so the approval dialog carries your signature. No `sed`, no `CASCADE_HUMAN=1`, no retyping. If the current hop is a CLEAN stage 10 it says so in the question: the choice is "what next", not "something is broken".

- **Halts in general prefer a question.** When the blocker is a decision a human must make — which slice, which reading of an ambiguous brief, whether to drop an out-of-scope row — and someone is at the keyboard, the agent asks and carries on. A halt is for things a human must go and *do*. Halts that remain keep the five-field block, with `WHAT TO DO` held to the shortest real path.

- **Headless is unchanged.** With nobody at the keyboard there is nobody to ask, so an unattended run still halts with the two lines named. `T43` pins both directions.

## 1.4.2 — 2026-09-08

- **Fix: 1.4.0's I10 gate blocked stage 10.** The new "no accept without evidence" check demanded a `tests/loop.sh` receipt from *every* EXECUTE hop — but stage 10 is judged by `tests/audit.sh`, as `autopilot.py` already knew. A finished audit hop was refused for lacking evidence that stage does not produce. The check now asks each stage for its own review command, and the refusal names the right one. Found in a real repo within an hour of shipping 1.4.0.

- **Fix: running the farm dirtied the repo.** The 1.3.0 decision log wrote into two eval fixtures whose `.cascade/` was tracked, so every `tests/barbar.sh` left modified files behind — and a `git add -A` release commit swept them in. They are untracked and ignored now.

- **Fix: plugin-mode `install.sh` deleted the pack's own Layer 2.** Run inside the pack repo, it removed `.claude/hooks/*.py` and the skill source — correct in a product, where the plugin supplies them, and destructive here, where those files *are* what gets packaged. Every later release would have shipped a plugin with no `hop_guard`, no `stop_guard`, no signing dialog; standalone installs would have had nothing to copy; and the pack could no longer test itself. It now refuses when the target is the source, and still strips them in a real product. `T42`, with the destructive commit reverted before it reached any remote.

## 1.4.1 — 2026-09-08

**A number in prose is a claim, and nothing was checking it.**

- **README caught up with five releases.** It still described autopilot before the halt block, the run log and the budget existed, and pointed at "tests T1–T36" when the suite was at T41. It now covers the loop receipt (an agent cannot ask you to accept a hop it never ran), `.cascade/decisions.log`, `BDD_AUTOPILOT_MINUTES`, and links the invariant coverage map.

- **Fix: 1.4.0's invariant coverage map never landed.** The edit was anchored on a T-range that had already moved, so the replace was a silent no-op — the map and the `T41` row were reported as written and were not there. Both are in now, and the edit that added them asserts its anchor instead of trusting it.

- **`lint.sh` now fails on a stale test-range claim.** Every `T8–Tn` written in `README.md`, `CONTROL-LINE.md` or `AUDIT.md` must end at the suite's real last test, and `CONTROL-LINE.md` must carry a row for it. This is the same defect class as a stale shipped file (`T38`): documentation that reads as true. `T1–T7` is left alone — that is the separate I17 suite and is correct as written.

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
