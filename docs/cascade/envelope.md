# Cascade envelope

The memory of this product's cascade. It lives in git; chat is a cache of it.
You own everything in this file. The agent proposes changes and you approve them —
in the permission dialog, or by editing here and running `bash tests/sign.sh`.

## Where are we?

CURRENT_HOP: NONE
CURRENT_STAGE:
CURRENT_SLICE:

<EDIT>
AUTOPILOT:
</EDIT>

`AUTOPILOT:` is the overnight list — `05b checkout, 05b refunds, 10 audit`. Empty means you take every
hop edge yourself. Stage 11 and the merge can never be listed. See USAGE.md §B3.

## Laws

A law is something your product must never do. Give each one a check that **passes** and a break that
**fails** — the break is the bug the law forbids, made runnable, so a test that can't fail is caught.

Copy this shape (delete the example, keep the `<EDIT>` tags):

<EDIT>
### D1 — {{a user's balance MUST NOT go negative}}
check:  {{pytest tests/inv/test_D1.py}}
break:  {{INV_MUTANT=D1 pytest tests/inv/test_D1.py}}
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
