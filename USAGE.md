# How to use Barbaric Driven Development properly

This is the operator's manual. `INTEGRATION.md` is how to wire it; `CONTROL-LINE.md` is the law; this is what you do every day. Read it once, then keep §3 and §9 open.

## 1. Ten-minute setup

```bash
git clone https://github.com/kadaluarsa/barbaric-driven-development.git ~/tools/bdd     # once per machine
cd /path/to/your-product && bash ~/tools/bdd/install.sh .            # all four layers, core.hooksPath, manifest
git add -A && CASCADE_HUMAN=1 git commit -m "cascade: install"
bash ~/tools/bdd/install.sh --check .                                # no drift, hooks wired, nothing gitignored
bash tests/barbar.sh                                                 # BARBAR n/n before you write a line of product
```

Then **restart your agent session in that directory.** Claude Code discovers `.claude/commands/` and `.claude/skills/` at session start; a session opened before `install.sh` ran will not list `/barbar`, `/loop` or `/audit`. Type `/` — all three should appear.

Then three things only you can do:

1. **Protect `main`** with the required checks (one `gh api` call, INTEGRATION.md §3). Until then every REFUSED is a suggestion.
2. **Fill `docs/cascade/envelope.md`** — the intake `<EDIT>` tags and at least one law (§4).
3. **Commit `.claude/`, `.githooks/`, `.cascade/`.** `install.sh --check .` tells you if `.gitignore` hides any of them.

Optional: install Superpowers (`claude plugin marketplace add obra/superpowers-marketplace`, then `claude plugin install superpowers@superpowers-marketplace`). The pack holds without it; with it, each change is also better-crafted, and the seam binds the skills per hop automatically.

## 2. The shape of every stage

```
you:    generate stage N                     ← the agent writes spec + plan, then STOPS
you:    read it. lock, cut, rewrite, or:      send back: <reason>
you:    approved, execute stage N            ← flip the hop with the key (§3); the agent builds, then STOPS
you:    read the diff + the LOOP line, or:    send back: <reason>
you:    accepted, generate stage N+1
```

One hop per reply. The agent never flips the hop, never starts N+1, never types a score. If it does any of those, the layers block it and the transcript shows `BLOCKED by cascade` — send it back.

Stages: 00 intake → 01–04 evidence and design (no code) → 05 tech design → **05b one slice at a time** (the only build hop) → 06–09 → **10 audit** → **11 PRR** → merge.

## 3. The human key

Hop state and every law line in `envelope.md` are **human-owned by mechanism**. The agent cannot change them; neither can you without the key:

```bash
# edit CURRENT_HOP / CURRENT_STAGE / CURRENT_SLICE or a D# line, then:
CASCADE_HUMAN=1 git commit -m "approved, execute stage 05b slice checkout"
```

Use the key for exactly four things: flipping the hop, declaring or changing a law, accepting a change to an existing law test (`tests/inv/*`), and signing READY. **Never put the key in an agent's prompt, a script the agent runs, or CI.** `bash_guard` denies it to the agent on Claude Code; on other agents the key is your discipline.

## 4. Laws (D#) — the ten-year asset

A law is one line, four columns, inside the `<EDIT>` block:

```
D1 | balance MUST NOT go negative | pytest tests/inv/test_D1_balance.py | INV_MUTANT=D1 pytest tests/inv/test_D1_balance.py
```

- **validator** must exit 0 when the law holds.
- **red twin** must exit non-zero — it is the PRD's "bad example" made runnable. Common patterns: an env switch the code honors in test builds, a fixture that violates the law, a mutation flag.
- Declare it before the slice that can break it. Until both commands exist and behave, the law is **UNPROVEN** and `tests/loop.sh` refuses the hop — the agent's expected work is to create exactly the test file the law names, nothing else under that D#.
- `bash tests/dsharp_strength.sh` → GREEN / RED / **THEATER** (twin passed: the test cannot fail — fix the test, not the law) / UNPROVEN.
- Cover the **failure path**: the attempt that must be rejected. The script proves the test can fail; only you can see it fails for the right reason.
- Waiver: `WAIVE_DSHARP: D3 <reason>` in `goal.md`, written by you, for one hop. Never by the agent.

Rule of thumb: money, tenancy, idempotency, conservation, retention. Three real laws move long-run correctness more than any other hour you spend.

## 5. `/goal` and `/loop`

Before an EXECUTE hop the agent writes `docs/cascade/goal.md`:

```
VALIDATOR: pytest tests/ac/test_checkout.py
VALIDATOR: pytest tests/inv/test_D1_balance.py
VALIDATOR: pytest tests/inv/test_D3_refund.py
```

Every in-force law belongs in it — an omitted one is a FAIL entry, not a skip. `/loop` is `bash tests/loop.sh`: it refuses on GENERATE, on stages 01–04 and 11, and while any law is UNPROVEN; it prints `LOOP k/n`. If the agent typed `LOOP 3/3` instead of running the script, that is a send-back.

## 6. Stage 10 and 11 — evidence, then signature

- **10:** the agent proposes rows in `docs/cascade/10-audit.md` (`| FR-1 | claim | path: x test: cmd | IMPLEMENTED |`). `bash tests/audit.sh` re-verifies every row on the tree — path exists, test green, D# GREEN — and every FR-/NFR- in `03-prd.md` and every D# needs a row. Its verdict is the only one that counts; a `CLEAN` written in prose is ignored. REFINED rows count only after **you** move them inside `<EDIT>`.
- **11:** you write READY yourself, inside `<EDIT>`:

  ```
  <EDIT>
  ## Verdict: READY
  </EDIT>
  ```
  Outside the tags it is not a signature and the gate refuses.

## 7. Merge

```bash
bash tests/barbar.sh merge
```

Runs the farm, then `dsharp_strength.sh` (all GREEN), then `audit.sh` (CLEAN), then checks READY is human-signed. Prints ALLOWED or REFUSED. It does not push. Ship path is: ALLOWED → PR → required checks green → a human merges. **Never** `--no-verify`, never push to `main`, never re-point `core.hooksPath` — each is blocked on Claude Code and is drift everywhere else.

## 8. Upgrading

```bash
cd ~/tools/bdd && git pull --ff-only && cd -                # newer pack
bash ~/tools/bdd/install.sh .                                # idempotent: replaces pack files, keeps yours
bash ~/tools/bdd/install.sh --check .                        # in CI too
```

`--check` is red for a softened hook, a deleted script, an unwired hook, a gitignored layer, or a version mismatch. Your envelope, goal, PRD, shims and settings are yours and never count as drift.

## 9. What the scores and messages mean

| You see | It means | You do |
|---|---|---|
| `LOOP k/n`, k<n | a validator or an in-force law failed | send back, or fix in the same hop; never delete a test |
| `LOOP REFUSED … GENERATE` | someone asked for a loop on a spec hop | nothing — that was correct |
| `LOOP REFUSED … not in force` | a declared law has no validator or twin | complete the law (§4) or waive it in writing |
| `DSHARP THEATER D2` | D2's twin passed — its test can't fail | fix the test; the law was never protecting anything |
| `AUDIT k/n DIRTY` | a row has no path, a red test, or a PRD item has no row | `approved, execute stage 10 punch`, then re-audit |
| `BLOCKED: GENERATE … may not write product code` | the agent tried to build on a spec hop | send back; the hop stays GENERATE |
| `BLOCKED … human-owned` | the agent tried to flip the hop, change a law, or edit a law test | send back; if the change is right, do it yourself with the key |
| `BLOCKED: direct push to main` | anyone tried to skip the gate | use the ship path (§7) |
| `BARBAR merge REFUSED` | one of the four conditions is missing — the line names it | fix that condition; never "fix" the farm with product code |
| `IGNORED .claude/hooks` from `--check` | Layer 2 isn't in the repo | un-ignore it and commit |
| `/barbar` (or `/loop`, `/audit`) not in the `/` list | the session started before the files existed, or you opened a checkout that doesn't have them (a stale `main`, a product where `install.sh` never ran) | `git pull --ff-only` in the pack, or `install.sh --check .` in a product — it prints `UNWIRED`/`MISSING` — then restart the session |
| `Unknown command: /barbar` in headless `claude -p` | project skills are not registered as slash commands headless; only `.claude/commands/` are | make sure `.claude/commands/barbar.md` exists (`install.sh` ships it); T16 checks |

## 10. Anti-patterns that defeat the pack

- Writing `CASCADE_HUMAN=1` anywhere an agent can read it.
- A law whose twin is `false` or `true` — a twin must run the real test against a real bad example.
- Approving a slice that contradicts a law "just this once." Runs 1–3 of the stress test show the agent will either stop (good) or find a way (bad); the pack blocks the second only partially. Change the law with the key, or refuse the slice.
- Editing `10-audit.md` to say CLEAN. The gate computes it; the edit is noise.
- Letting the agent "resume where it left off" after `/compact` without the reprint — the hook re-injects state, but read the first message of the new context anyway.
- Running the pack from a checkout that is behind `origin/main`. Every layer is a file in git; a stale checkout is a stale bar. `install.sh --check .` and `git status -sb` before you start.
- Treating `PROBES k/7` from one model as permanent. Re-run after a model or harness change; it takes fifteen minutes.

## 11. Autopilot — her overnight loop, with the bar kept

**To deliver a feature on autopilot, three steps — two are yours, one is the agent's:**

```bash
# 1. say what you want, in git (one paragraph per slice; the agent writes the spec from this)
cat >> docs/cascade/05b-briefs.md <<'EOF'
- multi-currency: balances per currency code; credit/debit/capture/refund take a currency; D1 holds per currency.
EOF
# 2. declare any new law (validator + red twin, UNPROVEN is fine — the agent builds them) and sign the list
#    in docs/cascade/envelope.md:   AUTOPILOT: 05b multi-currency
git add -A && CASCADE_HUMAN=1 git commit -m "brief + autopilot list"
```

3. Type **`/barbar auto`** — nothing else. The feature description is already in git; the prompt carries no intent. (`/barbar auto <text>` works too: the text is appended to the briefs file first. The list still needs your signature.)

Come back to: the edge line of the last hop, or an `AUTOPILOT HALT: <reason>`. Then you read the diff once, run `/audit`, sign READY, and merge.

**Without autopilot** the same feature is the manual loop from §2: `generate stage 05b slice multi-currency` → read → `approved, execute …` (with the key) → read the diff and `LOOP n/n` → `accepted, …`.

Off by default. To let the agent run several slices without you at each edge, sign the list in the envelope with the key:

```
AUTOPILOT: 05b checkout, 05b refunds, 05b statement
```

Then one command — **`/barbar auto`** — and the agent advances GENERATE→EXECUTE→next by itself, but only along that list, in order. Each edge is checked by the same rule in `pre-commit` and `hop_guard` (`tests/lib/autopilot.py`): a spec doc must exist before EXECUTE; `bash tests/loop.sh` must be n/n before the next slice; nothing past the list end; never stage 10 or 11; the list itself is human-owned. Laws, red twins, law tests, the computed audit, your READY signature and the merge are exactly as without autopilot.

On Claude Code the Stop hook keeps the session alive between hops until the list ends, the agent writes `AUTOPILOT HALT: <reason>` (a red law it cannot change, a blocked edge, a slice that contradicts a law), or a continuation cap trips — it cannot spin. On other agents `/barbar auto` is the same instructions without the hook: the agent's own persistence carries it.

What you give up: the diff at each edge. The stress test's run 3 (a VIP overdraft carved into "balance never negative") was caught by a human reading that diff. Under autopilot you read it once, at the end — so keep lists short, keep laws sharp, and run `bash evals/spike/stress.sh` in autopilot mode before you trust it overnight.

## 12. Reading the evidence

- `evals/probes/` — cold-agent conformance runs, transcripts included.
- `evals/stress/` — two features, a trap, an audit, a merge; five runs, what each found, a craft review of what the agent built.
- `AUDIT.md` — what is mechanism, what is prose, and where the ceiling is.

The number to watch is not a percentage. It is `DSHARP k/n` — because it goes red the moment reality disagrees with a law.
