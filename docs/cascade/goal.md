# /goal — this hop's definition of done

Read by `tests/loop.sh`. One `VALIDATOR:` per named test. Every in-force D# from
`envelope.md` must appear here, or carry a `WAIVE_DSHARP:` line with a reason — an
omitted D# is a FAIL entry, never a skip (I13). Clear this file on send-back (I9).

GOAL_STAGE: 05b
GOAL_SLICE: example
VALIDATOR: true
# VALIDATOR: pytest tests/ac/test_checkout.py
# VALIDATOR: pytest tests/inv/test_D1_balance.py
# WAIVE_DSHARP: D3 this slice does not touch refunds — approved by <name> <date>
