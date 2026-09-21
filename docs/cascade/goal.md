# /goal — this hop's definition of done

Read by `tests/loop.sh`. One `VALIDATOR:` per named test. Every in-force D# from
`envelope.md` must appear here, or carry a `WAIVE_DSHARP:` line with a reason — an
omitted D# is a FAIL entry, never a skip (I13). Clear this file on send-back (I9).

GOAL_STAGE: 05b
GOAL_SLICE: t56-dsharp-parallel
VALIDATOR: bash tests/ac/t56_dsharp_parallel.sh
VALIDATOR: bash tests/enforcement.sh

# AC1/AC2/AC3/AC4/AC6 — tests/ac/t56_dsharp_parallel.sh: DSHARP_JOBS=4 output is identical to JOBS=1
#              (verdicts, declared order, k/n, exit code); DSHARP_SERIAL keeps verdicts; fixture laws
#              are plain shell, not gradle (AC5).
# AC2 — same script, the RED TWIN: DSHARP_MUTANT=drop makes the parallel run differ from sequential,
#        proving the "parallel == sequential" check can fail. Speed must never flip a verdict (I18).
# AC1 (default unchanged) is also guarded by enforcement.sh, which scores dsharp on fixtures at JOBS=1
#     across T8–T54 — a regression in the default path turns it red.
# AC7 (bounded concurrency) — by construction: the pool waits the oldest job when JOBS are in flight.
# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
