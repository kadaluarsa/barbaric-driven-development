# Docker spike — the pack from zero, then a real agent

Two phases. Phase 1 needs no auth and proves every layer works on a machine with none of your setup. Phase 2 drives Claude Code headless through the seven conformance probes from `INTEGRATION.md` and scores them from the tree and the tool-call stream — never from what the agent says about itself.

## Phase 1 — every layer, no agent (deterministic)

```bash
docker build -f evals/spike/Dockerfile -t bdd-spike .
docker run --rm bdd-spike bash /opt/phase1.sh        # PHASE1 17/17
```

Builds a fresh ledger product in `/work/demo`, runs `install.sh`, then walks it through: GENERATE-hop product write (blocked), `<EDIT>` change (blocked), EXECUTE write (allowed), `/loop` on GENERATE (refused), omitted D# (FAIL entry), push to main (blocked), merge before 10/11 (REFUSED), merge after CLEAN 10 + READY 11 with green D# (ALLOWED), merge after a D1 regression (REFUSED).

## Phase 2 — a real agent, cold (needs your auth inside the container)

```bash
docker run -d --name bdd-p2 bdd-spike bash -c 'bash /opt/phase1.sh >/tmp/p1.log 2>&1; chown -R node:node /work; tail -f /dev/null'
docker exec -u node -it bdd-p2 claude auth login        # you do this; credentials stay in the container
docker exec -u node bdd-p2 bash -c 'cd /work/demo && PROBE_MODEL=sonnet bash /opt/probes.sh'
docker cp bdd-p2:/work/probes ./probes-out               # PROBES.md + every transcript
```

Runs as the non-root `node` user because headless Claude refuses `--dangerously-skip-permissions` as root. That flag is deliberate: it removes every safeguard *except* the pack's own layers, so a PASS means the layers held, not the permission prompt.

Each probe resets the repo to a known hop state, runs one `claude -p`, then checks `git status`, `goal.md`, and the `stream-json` tool calls. `P*.tools.txt` also records whether the Stop hook fired (`STOP_HOOK_FIRED`) and whether `preserve.py` re-injected the control line on `--continue` (`PRESERVE_FIRED`).

## Stress (rising difficulty + a trap)

`stress.sh` adds two features and one law-violating slice through real agent hops and scores quality preservation — see `evals/stress/`.

## Results

| Phase | Result |
|---|---|
| Phase 1, fresh container, no agent | **22/22** (v1.0.0; was 17/17 before the human-owned-lines, red-twin, computed-audit and signed-READY scenarios were added) |
| Phase 2, `claude-code 2.1.258` / `sonnet`, headless, one clean run | **PROBES 7/7** on v1.0.0 (`2ee3c9f`), and 7/7 on the pre-1.0 pack |

Recorded runs with transcripts: `evals/probes/`. Bugs the spike found and fixed on the way: a READY product could never merge (`7d6c715`), the farm's self-test was not hermetic (`89e1c38`), the installer put the skill where Claude Code does not load it and shipped no user-invocable `/barbar` (`c3d9794`, `4636975`, `703b3e6`, `01c2af0`), `phase1.sh` used fixed `/tmp` paths so a root run broke a later user run (`9d10158`), the install manifest flagged product-owned templates as drift (`8d03a39`), and `install.sh` was not idempotent — a re-run nested every shipped directory (`2ee3c9f`, T23). None were visible from host tests alone.
