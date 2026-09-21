# /goal — this hop's definition of done

Read by `tests/loop.sh`. One `VALIDATOR:` per named test. Every in-force D# from
`envelope.md` must appear here, or carry a `WAIVE_DSHARP:` line with a reason — an
omitted D# is a FAIL entry, never a skip (I13). Clear this file on send-back (I9).

GOAL_STAGE: 05b
GOAL_SLICE: t58-enforcement-cache
VALIDATOR: bash tests/ac/t58_enforcement_cache.sh
VALIDATOR: bash tests/enforcement.sh

# AC1/AC2/AC3/AC4/AC5 — tests/ac/t58_enforcement_cache.sh: unchanged tree is served from cache; a changed
#              tree (or no cache, or ENFORCEMENT_NO_CACHE=1) re-runs; a failing run clears the cache.
# AC2 — same script, the RED TWIN: ENF_CACHE_MUTANT=stale serves a stale cache on a fingerprint mismatch
#        and is caught — proving the invalidation has teeth. Speed must never serve a stale green (I18).
# AC6 (cache-miss output unchanged) — enforcement.sh here runs as a full miss (the tree changed this hop),
#     so a green T8–T54 proves the 47 cases and their output are untouched by the gate.
# AC7 — VERSION 1.9.5 coupled to plugin.json + marketplace.json (T31), checked by enforcement.sh.
# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
