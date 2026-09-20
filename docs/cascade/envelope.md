# Cascade envelope

Your product's laws and the decisions behind them. It lives in git; chat is a cache of it.
You own everything in this file. The agent proposes changes and you approve them — in the permission
dialog, or by editing here and running `bash tests/sign.sh`.

Where the cascade is *right now* — the hop, the slice, the overnight list — lives in
[`hop-state.md`](hop-state.md), so that this file's history stays a record of decisions rather than
of movement.

## Laws

A law is something your product must never do. Give each one a check that **passes** and a break that
**fails** — the break is the bug the law forbids, made runnable, so a test that can't fail is caught.

Copy this shape (delete the example, keep the `<EDIT>` tags):

<EDIT>
### D1 — a tree that is not CLEAN stage 10 and human-signed READY stage 11 with every D# GREEN MUST NOT be allowed to merge
check:  BARBAR_ROOT=evals/fixtures/ready-product bash tests/barbar.sh gate
break:  BARBAR_ROOT=evals/fixtures/dirty-product bash tests/barbar.sh gate

### D2 — a READY verdict the human did not sign MUST NOT count as READY
check:  python3 -B tests/lib/signed.py evals/fixtures/ready-product/docs/cascade/11-prr.md 'Verdict:\s*READY( WITH WAIVERS)?'
break:  python3 -B tests/lib/signed.py evals/fixtures/unsigned-ready-product/docs/cascade/11-prr.md 'Verdict:\s*READY( WITH WAIVERS)?'

### D3 — a law that cannot fail MUST NOT count as in force
check:  bash tests/dsharp_strength.sh --root evals/fixtures/ready-product
break:  bash tests/dsharp_strength.sh --root evals/fixtures/theater-product

### D4 — a typed verdict MUST NOT stand in for a computed one
check:  bash tests/audit.sh --root evals/fixtures/ready-product
break:  bash tests/audit.sh --root evals/fixtures/prose-clean-product

### D5 — standing BDD down MUST NOT reach Layer 0
check:  bash tests/ac/t53_disable.sh
break:  BDD_DISABLE_MUTANT=layer0 bash tests/ac/t53_disable.sh

### D6 — the agent MUST NOT be able to mint its own signature
check:  printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"bash tests/sign.sh"}}' "$PWD" | python3 -B .claude/hooks/bash_guard.py | grep -q '"permissionDecision": "deny"'
break:  BDD_GUARD_MUTANT=seal printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"bash tests/sign.sh"}}' "$PWD" | python3 -B .claude/hooks/bash_guard.py | grep -q '"permissionDecision": "deny"'
</EDIT>

`bash tests/dsharp_strength.sh` scores every law:

| | meaning | what to do |
|---|---|---|
| GREEN | check passes, break fails | nothing — the law is in force |
| RED | check failed | the law is broken; fix the product |
| THEATER | break passed | the test can't fail — fix the test, not the law |
| UNPROVEN | check or break missing | write it, or `WAIVE_DSHARP: D1 <reason>` in `goal.md` for one hop |

Don't know what your laws are? Run `/barbar init` — it reads the repo and proposes them for you to sign.

## Locked decisions
<EDIT>
- {{decision}} — locked {{date}}
</EDIT>

## Accepted artifacts
<EDIT>
- {{path}} — stage {{N}} — {{date}}
</EDIT>
