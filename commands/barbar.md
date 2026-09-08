---
description: /barbar — score the farm; /barbar merge — the gate; /barbar auto — run the human-signed AUTOPILOT list of slices overnight, advancing only while every law holds.
---
- Arguments exactly `merge` → run `bash tests/barbar.sh merge`, report verbatim, stop. Never push or merge yourself.
- Arguments exactly `init` → **first-knowledge discovery** (below): scan the repo and *propose* laws and audit rows for the human to sign. Never write `docs/cascade/envelope.md` or `10-audit.md` yourself.
- Arguments starting with `auto` → **autopilot** (below). Any text after `auto` is a brief: append it to `docs/cascade/05b-briefs.md` (create it if missing) and commit it before starting — briefs live in git, not in chat.
- Anything else → run `bash tests/barbar.sh`, report verbatim, stop. Print the `BARBAR k/n` line the script emitted — never compose it (I18). Do not GENERATE, EXECUTE, stitch, or "fix" a red farm with product code.

## `/barbar auto` — her overnight loop, with the bar kept

Run `python3 tests/lib/autopilot.py --status .`.

**If it prints `off` — ask, do not instruct.** An unsigned list is a decision the human has not made yet, not a
procedure they need to follow. In an interactive session, use the **AskUserQuestion** tool to put the choice in
front of them instead of printing commands to retype:

- Read `docs/cascade/05b-briefs.md` and the last few commits. Offer, as options, the briefs that have no slice
  built yet — one option per candidate slice, the header naming the slice, the description saying in one line
  what it would build and roughly how long the run is. Two to four options; "Other" is added for you, and a
  human who wants something else will type it there.
- If the current hop is a finished stage 10 (`tests/audit.sh` is CLEAN), say so in the question — the choice is
  "what next", not "something is broken".
- When they pick: **you** make the edit — `CURRENT_HOP`, `CURRENT_STAGE`, `CURRENT_SLICE` and the `AUTOPILOT:`
  line — and let the permission dialog carry their signature. Never print a `sed`, never tell them to set the
  stitch key, never ask them to retype a slice name you already know. Then continue the run.
- Only halt if they decline, if no brief exists to offer (ask them what to build — one question, not a
  procedure), or if the session is non-interactive: with no human at the keyboard there is nobody to ask, so
  fall back to `AUTOPILOT HALT: no signed list` with the two lines named.

**If it prints `done`**, print the invariant block and `AUTOPILOT HALT: list complete — STITCH NEEDED: accept execute for stage N, or send back.` and stop. Offer the same picker for the next slice if the human wants to keep going.

Otherwise it names the next signed edge. Repeat until `done` or a HALT:

1. **GENERATE the slice** (spec + plan only, into `docs/cascade/`), commit it, print the invariant block and `STITCH NEEDED: review spec+plan for stage N`.
2. **Advance**: edit `CURRENT_HOP/STAGE/SLICE` in `docs/cascade/envelope.md` to exactly what `--status` says and commit. The hooks allow only that edge; if they BLOCK, stop with `AUTOPILOT HALT: <the hook's reason>`.
3. **EXECUTE the slice** (for a `10 audit` entry, follow the stage-10 section above instead): write `goal.md` with the AC tests and every in-force D#, build, `bash tests/loop.sh` until it prints `LOOP n/n`, `git diff`, commit, print the invariant block and `STITCH NEEDED: accept execute for stage N, or send back.`
4. **Advance** again (the hooks re-run `tests/loop.sh` against this hop before allowing it).

**Read the log before guessing.** `.cascade/decisions.log` holds one line per decision every layer made — denials, signatures, law verdicts, halts. When a run stopped and the reason is not obvious, read it (`python3 tests/lib/decisions.py . --tail 40`) rather than reconstructing from chat. It is a record, never a gate: nothing passes or fails because of it.

**Bound an unattended run.** `BDD_AUTOPILOT_MINUTES=90 /barbar auto` stops at 90 minutes with committed work intact; unset means no ceiling. The hop cap (`4 × slices + 4`) still applies.

**Never ask and wait mid-run.** Autopilot resolves what is mechanical (build errors, failing tests, missing validators or twins, wiring). If you need a *decision* a human owns — a scope question, an ambiguous brief, a hypothesis that changes what to build — do not pause for an answer: state your recommended default in the hop report and end the run with `AUTOPILOT HALT: decision needed — <the question>`. A halted run is resumable; a hanging one is not.

### Stage 10 on the list (`AUTOPILOT: … , 10 audit`)

The audit is a *computed* gate — `bash tests/audit.sh` is the judge — so it may be pre-signed. Two hops:

**GENERATE 10 — adversarially, not as the author.** You wrote this code; do not grade your own homework. Dispatch a **fresh subagent** with no memory of building it and this brief: *"You are an independent auditor. Read the accepted specs in `docs/cascade/` and the repository. For every FR/NFR in the PRD and every D# in the envelope, find the artifact and the test that proves it. Be hostile to narrative: if you did not open the file, it is not IMPLEMENTED. Report one row per item as `| ID | claim | path: X test: CMD | STATUS |`."* Write its rows into `docs/cascade/10-audit.md` unchanged — including the ones that make your own work look incomplete. Then run `bash tests/audit.sh` and report its verdict verbatim; the script, not the subagent, decides.

**EXECUTE 10 — the punch list.** For each row the script scored MISSING / DRIFTED / VIOLATED: fix it if it is buildable within the accepted spec (a missing test, a wrong path, an unwired call), then re-run `bash tests/audit.sh`. At most **3** punch rounds; if it is still DIRTY, HALT with the remaining rows. Never make a row pass by editing the row, deleting a test, or narrowing a claim — that is falsifying evidence. A row that is genuinely out of scope is a `drop <ID>` decision for the human: HALT and say so.

When the audit is CLEAN and the list is done, halt with `AUTOPILOT HALT: list complete — AUDIT n/n CLEAN. Stage 11 READY and the merge are yours.` and say exactly how to sign.

**Never put `11` or a merge on the list.** `autopilot.py` refuses them: READY is the human's signature and merge is the human's act.

**Prefer a question to a halt.** A halt is for things a human must go and do. If what you actually need is a
*decision* — which slice, which of two readings of a brief, whether to drop an out-of-scope row — and a human
is at the keyboard, use **AskUserQuestion** and carry on with their answer. A halt that could have been a
click is a stalled night.

**Every HALT must be actionable.** A halt with no instruction is a stalled product. Always end with exactly this shape, filled in:

```
AUTOPILOT HALT: <one-line reason>
  BOTTLENECK:  <what is actually blocking, naming the file/law/command>
  WHAT TO DO:  <the exact commands or edits a human runs — copy-pasteable>
  IF YOU DISAGREE: <the alternative, e.g. "drop FR-3 from the brief and re-run">
  RESUME WITH: /barbar auto
  DONE SO FAR: <slices completed, commits, what is safe to merge>
```

Never halt with only a reason. Keep `WHAT TO DO` to the shortest real path — one command, or one
sentence for the human to say. If the fix needs a signature, lead with the cheap path — the human tells you what they want, you make the edit, and they approve the dialog; that approval *is* the signature. Offer the hand-edit paths (`bash tests/sign.sh` from any git client, or `CASCADE_HUMAN=1 git commit` from a terminal) as the alternative, not the instruction. Never print a multi-step hand-edit when one sentence from the human would do. If a law's text is signed and its validator/twin commands are named but the test files do not exist, that is not a halt — build them in this hop.

HALT immediately — do not work around — when: `tests/loop.sh` cannot reach n/n inside the slice; a law is RED, THEATER or UNPROVEN and only a human can change it; a hook BLOCKS an edge; the slice contradicts a law (a law admits no exceptions — say so, do not implement); anything needs `CASCADE_HUMAN`. Write `AUTOPILOT HALT: <reason>` as the last line so the Stop hook lets the session end. Stages 10, 11 and merge are never yours.

## `/barbar init` — first-knowledge discovery (proposals, not laws)

**Re-running is safe and expected** — a second machine, a second pass months later. This writes one file and overwrites it; it never touches the envelope, so no signed law can be lost. Read the envelope first and **do not re-propose a law already in force**: say `D1–D3 already in force, skipped` and propose only what is new. If every law you would propose is already signed, say so and stop rather than padding the file.

Read, do not write product code: `git log --oneline -60`, `README*`, `docs/`, the PRD if any, the test tree, CI config, and the main source directories (names, public APIs, feature flags, entitlement/paywall/auth checks, money, tenancy, export/persistence paths). Then write **`docs/cascade/proposals.md`** — only that file — with:

1. **Candidate laws**, 3–6, in the envelope's format — a heading, a command that must pass, a command that must fail — each with a real validator this repo's test framework could run and a red-twin idea (an env switch, a fixture, a mutant):

   ```
   ### D1 — <MUST / MUST NOT, one sentence>
   check:  <command that passes while the law holds>
   break:  <command that fails once the law is broken>
   why:    <the commit or code path that made you propose this>
   ```

   The `why:` line is for the human reading the proposal; only `check:` and `break:` carry into the envelope. Prefer physics the product cannot afford to break: money, entitlement, data loss, aspect/duration/fps guarantees, tenancy, idempotency.
2. **Proposed stage-10 rows** for features that already exist: `| FR-n | <claim from the log> | path: <file> test: <cmd or "none found"> | IMPLEMENTED or MISSING |` — only cite a test that actually exists; otherwise say `test: none found` and status MISSING.
3. **A one-line PRD skeleton** (`FR-1 …`) if `docs/cascade/03-prd.md` is absent.

End with exactly this checklist for the human, then stop:
- copy the laws you accept into the `<EDIT>` D# block of `docs/cascade/envelope.md` — delete the rest. Ask the agent to make the edit and approve the dialog it raises: that approval is your signature. Editing the file yourself works too; sign it with `bash tests/sign.sh` before committing, or commit from a terminal with `CASCADE_HUMAN=1 git commit`.
- create the validators/twins you accepted (or approve an EXECUTE hop to build them) until `bash tests/dsharp_strength.sh` is all GREEN
- move accepted rows into `docs/cascade/10-audit.md` and run `bash tests/audit.sh`

Proposals are drafts. A law is in force only when a human signs it and its twin fails.
