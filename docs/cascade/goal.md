# /goal — this hop's definition of done

Read by `tests/loop.sh`. One `VALIDATOR:` per named test. Every in-force D# from
`envelope.md` must appear here, or carry a `WAIVE_DSHARP:` line with a reason — an
omitted D# is a FAIL entry, never a skip (I13). Clear this file on send-back (I9).

GOAL_STAGE: 05b
GOAL_SLICE: t57-spec-critic
VALIDATOR: bash tests/ac/t57_spec_critic.sh
VALIDATOR: bash tests/enforcement.sh
VALIDATOR: bash tests/lint.sh

# AC1/AC2/AC5/AC6 — tests/ac/t57_spec_critic.sh: a clean fixture is CRITIQUE n/n; the RED TWIN — each of
#   eleven CRITIQUE mutants (missing, undispositioned, rewritten, deleted, pipes, nodiagram, overcap,
#   noevidence, vague, together, uncommitted) turns it red; EXECUTE 05b and GENERATE 06 are n/a.
# AC3/AC4 — enforcement.sh T57: the Stop hook and autopilot refuse a red critique, pass a green one,
#   and stage 06 is untouched. AC4b (CI) — control-line.yml runs tests/critique.sh with full history.
# AC7 — docs agree with code: lint.sh checks CONTROL-LINE.md names T57; AGENTS.md rule 7, autopilot.py,
#   the pipeline's Spec critic brief, barbar.md (both copies) and USAGE.md carry the condition.
# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
