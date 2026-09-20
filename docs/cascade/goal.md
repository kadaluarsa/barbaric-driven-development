# /goal — this hop's definition of done

Read by `tests/loop.sh`. One `VALIDATOR:` per named test. Every in-force D# from
`envelope.md` must appear here, or carry a `WAIVE_DSHARP:` line with a reason — an
omitted D# is a FAIL entry, never a skip (I13). Clear this file on send-back (I9).

GOAL_STAGE: 05b
GOAL_SLICE: t55-sign-ux-docs
VALIDATOR: bash tests/ac/t55_sign_ux_docs.sh
VALIDATOR: bash tests/enforcement.sh

# AC1/AC2/AC4 — tests/ac/t55_sign_ux_docs.sh: the docs lead with the permission dialog; USAGE and
#               INTEGRATION carry the Remote/web "no local pull" note; VERSION is 1.9.3 + changelog.
# AC3 — same script, the RED TWIN: tests/sign.sh and its bash_guard denial survive this docs slice,
#        and the signing enforcement layer is unchanged. Gut the fallback and the script goes red.
# AC5 — scope (docs + VERSION + this one AC script) verified by diff review; no runtime code changed.
# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
