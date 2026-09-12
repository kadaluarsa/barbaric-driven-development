# /goal — this hop's definition of done

Read by `tests/loop.sh`. One `VALIDATOR:` per named test. Every in-force D# from
`envelope.md` must appear here, or carry a `WAIVE_DSHARP:` line with a reason — an
omitted D# is a FAIL entry, never a skip (I13). Clear this file on send-back (I9).

GOAL_STAGE: 05b
GOAL_SLICE: t53-bdd-disable
VALIDATOR: bash tests/ac/t53_disable.sh
VALIDATOR: bash tests/enforcement.sh

# AC1/AC3/AC4/AC5/AC6 — tests/ac/t53_disable.sh (round-trip, DISABLED surfaces, gitignore, idempotence)
# AC2  — T53 in tests/enforcement.sh: a disabled repo leaves Layer 0 untouched and still cannot merge.
#        This is the slice's red twin. T53_MUTANT=layer0 must turn it red.
# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
