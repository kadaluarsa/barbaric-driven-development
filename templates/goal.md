# /goal — this hop's definition of done

Read by `tests/loop.sh`. One `VALIDATOR:` per named test. Every in-force D# from
`envelope.md` must appear here, or carry a `WAIVE_DSHARP:` line with a reason — an
omitted D# is a FAIL entry, never a skip (I13). Clear this file on send-back (I9).

Empty until an EXECUTE hop sets it: `tests/loop.sh` refuses a goal with no `VALIDATOR:` line.
The shape, for when it is set (each line starts at column one, without the `#`):

#   GOAL_STAGE: 05b
#   GOAL_SLICE: <slice>
#   VALIDATOR: bash tests/ac/<slice>.sh
