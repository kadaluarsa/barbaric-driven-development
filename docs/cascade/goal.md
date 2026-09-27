# /goal — this hop's definition of done

Read by `tests/loop.sh`. One `VALIDATOR:` per named test. Every in-force D# from
`envelope.md` must appear here, or carry a `WAIVE_DSHARP:` line with a reason — an
omitted D# is a FAIL entry, never a skip (I13). Clear this file on send-back (I9).

GOAL_STAGE: 05b
GOAL_SLICE: t58-divergence
VALIDATOR: bash tests/ac/t58_divergence.sh
VALIDATOR: bash tests/ac/t57_spec_critic.sh
VALIDATOR: bash tests/enforcement.sh
VALIDATOR: bash tests/lint.sh

# AC1/AC2/AC3 — tests/ac/t58_divergence.sh: a clean [diverge] fixture is DIVERGE n/n; [diverge 4] needs 4;
#   the RED TWIN — 15 mutants each turn it red; before the pick it says "waiting on your choice"; untagged
#   and EXECUTE are n/a; the documented tag form still matches doctor's brief check.
# t57 must stay green after critique.py moved its helpers into tests/lib/provenance.py.
# AC4/AC5/AC6 — enforcement.sh T58: Stop hook refuses the spec edge and accepts the decision-needed halt
#   before the pick; autopilot will not advance; Layer 2 asks/denies the pick; Layer 1 refuses an unsigned one.
# AC7 — CI step in control-line.yml; lint.sh checks CONTROL-LINE.md names T58; docs carry the rule.
# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
