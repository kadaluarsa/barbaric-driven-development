# Audit — will an agent actually follow this?

> **Status:** this is the pre-I18 audit, kept as the record. Findings §1, §3, §4 are fixed and the fix for each is a red test (T13, T14, and `score_hops.py --tree`). §2 is fixed by `tests/loop.sh`. §5 is now scoreable with `--tree`. See **After I18** at the bottom for the current enforcement-class table.

Scope: does this pack produce the behavior in the [verify/CI talk](https://www.youtube.com/watch?v=Cmoh-yR-usA&t=2466s) — explicit repo rules, evals, hard CI, loop until n/n, gated auto-merge, don't trust chat, verify before continuing.

Method: read every file, run every test, then try to break each control the way an agent would break it. Reproductions below are copy-pasteable.

Farm state at audit time: `BARBAR 17/17`, `i17_dune.sh` T0–T7 green, `control-line.sh` green.

## Verdict

Split the question, because the pack answers one half well and the other half not at all.

| Question | Confidence |
|---|---|
| Does the pack **encode** the talk's levers? | **High.** I15–I17 are written down, cross-referenced in three files, and `control-line.sh` fails if any of that wording is deleted. |
| Can the pack **lose** the control line by accident? | **Low risk.** That is what the greps buy, and they buy it honestly. |
| Will a coding agent **obey** it on a real product? | **Low.** Every product-side control is self-reported by the agent. Nothing reads the tree. |

The pack is a regression test on its own prose. It is not yet a regression test on agent behavior.

Its own law is `I17 — chat is not evidence`. Applied to itself, most of T1–T7 are still chat.

## Enforcement class per lever

**MACHINE** = a red test fires whatever the agent says. **STATIC** = a hand-written fixture is scored; the fixture never changes, so agent drift cannot move it. **SELF-REPORTED** = the agent prints the claim and nothing checks it. **PROMPT** = words only.

| T# | Talk lever | Class | Confidence |
|----|-----------|-------|-----------|
| T1 | Skill hard-stops one-shots | PROMPT (grep for `Hard stop` in SKILL.md) | Low — Claude Code only; no skill mechanism on other agents |
| T2 | Evals | STATIC (12 frozen fixtures, regex-scored) | Low — see §1, the suite can vanish silently |
| T3 | Hard CI | **MACHINE** | **High** — real, and the strongest thing here |
| T4 | Loop until n/n | MACHINE for `/barbar`; SELF-REPORTED for `/loop` | Split — see §2 |
| T5 | Auto-merge on green | SELF-REPORTED (greps agent-written markdown) | Low — see §3 |
| T6 | Don't trust chat | SELF-REPORTED (regex for the word `path:`) | Low — see §4 |
| T7 | Verify before continuing | STATIC | Low — fixture, not behavior |

One of seven is machine-enforced.

## Findings

### 1. The whole hop-eval suite can disappear and the farm still prints n/n — CRITICAL

`tests/barbar.sh` reads the scorer through process substitution:

```
done < <(python3 "$ROOT/tests/score_hops.py" "$ROOT/evals/hops")
```

`set -euo pipefail` does not see failures inside `< <(...)`. If the scorer crashes, or `python3` is absent, the loop reads zero lines, zero hop checks are counted, and `k == n` still holds.

Reproduction — scorer keeps the strings `i17_dune.sh` greps for, but exits non-zero:

```bash
cp tests/score_hops.py /tmp/s.bak
printf 'import sys\n# oneshot-not-barbar implemented-needs-evidence\nraise SystemExit(3)\n' > tests/score_hops.py
bash tests/i17_dune.sh | grep T2      # PASS  T2
bash tests/barbar.sh; echo "rc=$?"    # BARBAR 5/5, rc=0
cp /tmp/s.bak tests/score_hops.py
```

`BARBAR 5/5`, exit 0, T2 green, twelve evals never ran. This is precisely the failure the pack warns about in the loop constitution — a green suite that no longer asserts the law. `n` is computed from what ran, so a suite that runs nothing is perfect.

Fix: capture the scorer's exit code (write to a temp file, check `$?`, `fail` on non-zero) and assert a floor — `HOPS k/n` must be present and `n` must be ≥ the number of `evals/hops/*.md` files on disk.

### 2. `/loop` has no implementation

`/barbar` is a script. `/loop` is a convention. `LOOP k/n` is a line the agent prints. Nothing verifies that the printed validators ran, that `k` is real, or that the in-force D# were in `/goal` — the rule "an in-force D# omitted from `/goal` is FAIL, not skip" is enforced only by the agent choosing to fail itself.

So the pack's headline verify loop is exactly the thing the pack says not to trust. On a product repo this is partly rescued by real D# tests being real CI checks — but that rescue lives in the product repo and is out of scope here, which the README does say.

### 3. The merge gate reads files the agent writes, and skips its own preconditions

`merge_gate()` checks two things: `10-audit.md` matches `Audit verdict: CLEAN`, `11-prr.md` matches `Verdict: READY`. That is the entire gate.

Reproduction — two files, six lines, no product:

```bash
mkdir -p /tmp/spoof/docs/cascade
printf '# 10\n\n## Audit verdict: CLEAN\n' > /tmp/spoof/docs/cascade/10-audit.md
printf '# 11\n\n## Verdict: READY\n'      > /tmp/spoof/docs/cascade/11-prr.md
BARBAR_ROOT=/tmp/spoof bash tests/barbar.sh merge   # ALLOWED, rc=0
```

Two gaps beyond spoofability:

- **The merge path never runs the farm.** `SKILL.md` and `CONTROL-LINE.md` both say merge is legal only if "BARBAR is n/n AND in-force D# are green." `tests/barbar.sh merge` short-circuits to `merge_gate` before any eval runs. `bash tests/barbar.sh merge` returns ALLOWED on a tree whose farm is red. The docs claim a four-part gate; the code implements two parts.
- **ALLOWED is advisory.** Nothing wires this to branch protection or a required check. The README is honest that it "does not `git push`" — but that also means an agent that ignores the REFUSED line faces no obstacle.

Fix: make `merge` run `run` first and refuse on `k<n`; state in the gate output that D# verification is unimplemented rather than deferring it to a parenthetical.

### 4. Tree evidence is a regex for the word "path:"

`score_hops.py`:

```python
claimed  = bool(re.search(r"\bIMPLEMENTED\b", body))
evidence = bool(re.search(r"(path:|test:|tests/)", body))
```

No filesystem check, no test execution, and the search is **document-wide, not per row** — one `path:` anywhere clears every IMPLEMENTED row in the report.

Reproduction:

```
| FR-1 | login    | path: app/DoesNotExist.kt test: test:ac:nope | IMPLEMENTED |
| FR-2 | payments | trust me                                     | IMPLEMENTED |
| FR-3 | refunds  | trust me                                     | IMPLEMENTED |
```

→ `PASS  expect=pass actual=pass  (implemented-needs-evidence)`. A non-existent file and two bare assertions clear T6, the "don't trust chat" lever.

Fix: score per row, and resolve each `path:` against the tree (`os.path.exists`) when scoring a real hop rather than a fixture.

### 5. Static fixtures cannot detect drift

`evals/hops/` holds 12 committed files that the pack authored and that never change. They test the regexes in `score_hops.py`. They are a good scorer unit test and a bad agent eval — the talk's evals watch what the model actually did.

Nothing in the repo ingests a real transcript. The gap between "our fixtures score correctly" and "our agent behaved" is unmeasured.

Fix: a directory the human drops real hop reports into, scored by the same rules. Then T2 is about behavior.

### 6. Regex fragility (lower severity)

- `oneshot-not-barbar` matches `based on .+ using ` — fires on ordinary prose like "based on the 05 spec using TDD". False positive on a legal hop.
- `no-nplus1` second branch is unreachable: the first `if` already catches `Starting GENERATE stage \d+`, and the inner guard re-tests `Starting GENERATE`.
- `barbar-not-product` returns `pass` on sight of `/barbar merge`, delegating to another rule — correct, but only because the `EXECUTE REPORT` check happens to be ordered first.
- `/tmp/barbar-pack.out` and `/tmp/barbar-i17.out` are fixed paths. Concurrent runs collide; on a shared runner this is a symlink target. Use `mktemp`.
- `.github/workflows/control-line.yml` has no `permissions:` block and no `timeout-minutes`. Add `permissions: contents: read`.

## Portability — "any coding agent"

The audit question assumes an agent that reads the pack. Today nothing routes it there.

| Present | File |
|---|---|
| no | `AGENTS.md` — Codex, Amp, Jules, Zed, recent Cursor, Gemini CLI |
| no | `CLAUDE.md` |
| no | `.cursor/rules/` |
| no | `.github/copilot-instructions.md` |
| no | `GEMINI.md`, `CONVENTIONS.md`, `.windsurf/rules/` |

The pack ships a Claude Code skill and two long docs, and the README's install step is "copy both files into the product repo (or hand them to the coding agent)." That is a manual paste per session, per agent. `.claude/skills/barbar/SKILL.md` is the only auto-loading artifact and it loads on exactly one agent.

Also worth naming: the conductor binds ~20 Claude Code slash commands (`/loop`, `/goal`, `/diff`, `/branch`, `/rewind`, `/compact`, `/effort`, `/background`, `/btw`). On any other agent those are prose. The intent survives; the mechanism does not.

See [`INTEGRATION.md`](INTEGRATION.md) for the fix, including conformance probes that measure per-agent compliance instead of assuming it.

## What would raise confidence

Ranked by how much each moves the "will an agent obey" number:

1. Fix §1. A suite that goes green when it runs nothing invalidates T2 and T4 at once.
2. Fix §3. Make `merge` run the farm; the docs already promise this.
3. Fix §4. Resolve `path:` against the tree — this is the one line that turns T6 from chat into evidence.
4. Ship `AGENTS.md` + shims (INTEGRATION.md) so the rules load without a paste.
5. Add conformance probes and score real transcripts, so T1/T7 stop being fixtures.

1–3 are small, local, and testable. They take the pack from one machine-enforced lever to four.

## One-line answer

**The pack cannot lose its own control line — high confidence. It cannot yet make an agent follow it — low confidence, one of seven levers machine-enforced, and the farm has a hole that lets the eval suite silently not run.**

## After I18

Same seven levers, re-scored after the enforcement layers landed. **MACHINE** now means a real deny, not a grep.

| T# | Lever | Before | After | Enforced by |
|----|-------|--------|-------|-------------|
| T1 | Skill hard-stop | PROMPT | **MACHINE** on Claude Code, PROMPT elsewhere | `hop_guard.py` denies the Write; git `pre-commit` denies the commit everywhere |
| T2 | Evals | STATIC | STATIC + **MACHINE** | fixtures still score the scorer; `score_hops.py --tree` scores a real report against the tree; T14 makes a dead scorer red |
| T3 | Hard CI | MACHINE | MACHINE | unchanged, plus `permissions:` and `timeout-minutes` |
| T4 | Loop until n/n | SELF-REPORTED for `/loop` | **MACHINE** | `tests/loop.sh` emits `LOOP k/n`, exits non-zero, refuses on GENERATE, fails an omitted D# (T12, T13) |
| T5 | Auto-merge gate | SELF-REPORTED | **MACHINE** | `barbar.sh merge` runs the farm and executes every in-force D# validator before reading 10/11 (T14, `dsharp-red-product`) |
| T6 | Don't trust chat | SELF-REPORTED | **MACHINE** with `--tree` | per-row evidence; `path:` resolved on the filesystem |
| T7 | Verify before next | STATIC | **MACHINE** | `pre-commit` (T8), `hop_guard.py` (T15), `stop_guard.py` blocks a hop that has no edge line |

Seven of seven have a machine layer on Claude Code; five of seven on any agent that commits through git. The two that remain prompt-only off Claude Code — the skill hard-stop and the hop-edge line — are exactly what `PROBES k/7` in INTEGRATION.md measures.

Still honest about limits: git hooks can be bypassed with `--no-verify` (denied by `bash_guard.py` on Claude Code; CI is the backstop elsewhere), `10-audit.md` is still a file the agent can write (but merge now also needs green D# validators, which it cannot write its way past), and Layer 2 exists for one agent today.

### Measured (2026-09-02)

The scorecard above was judgment. `evals/spike/` replaced it with a run: a fresh `node:22-bookworm` container, `install.sh` from zero, Phase 1 **17/17** with no agent, then `claude-code 2.1.258` / `sonnet` headless with `--dangerously-skip-permissions` through all seven probes — **PROBES 7/7**, scored from the tree and the tool-call stream. The Stop hook fired live on P3 (the agent first ended without the edge line and was blocked), and `preserve.py` re-injected the control line on `--continue` in P7. Four installer/farm bugs surfaced only in the container; all are fixed with tests. Transcripts: `evals/probes/`.

### Measured — v1.0.0 (2026-09-02, `2ee3c9f`)

Re-run after the production pass (human-owned hop lines and D# laws, red twin, computed stage 10, human-signed READY, seam hook, fail-visible guards, drift check, idempotent install): Phase 1 **22/22** from zero as root in a fresh image and as a non-root user in a reused container; **PROBES 7/7** on `claude-code 2.1.258` / `sonnet`, one uninterrupted run on a product built once by `install.sh`. The run before it scored 6/7 — the miss was an installer bug (`cp -R` nesting on re-install), not the agent; it is fixed and pinned by T23. Farm 24/24, T1–T26, lint clean, bash 3.2 safe.

What still routes through a human: the quality of the red twins (a THEATER check proves a validator *can* fail, not that it fails for the right reasons), and Layer 2 exists for one agent. Everything else that used to be chat is now a script with an exit code.
