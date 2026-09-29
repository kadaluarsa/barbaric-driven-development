# /goal — this hop's definition of done

Read by `tests/loop.sh`. One `VALIDATOR:` per named test. Every in-force D# from
`envelope.md` must appear here, or carry a `WAIVE_DSHARP:` line with a reason — an
omitted D# is a FAIL entry, never a skip (I13). Clear this file on send-back (I9).

GOAL_STAGE: 05b
GOAL_SLICE: t60-install-health-multi-break
VALIDATOR: bash tests/ac/t60_install_health.sh
VALIDATOR: bash tests/ac/t59_scale_hardening.sh
VALIDATOR: bash tests/ac/t57_spec_critic.sh
VALIDATOR: bash tests/ac/t58_divergence.sh
VALIDATOR: bash tests/enforcement.sh
VALIDATOR: bash tests/lint.sh

# AC1/AC2/AC3/AC4m/AC5 — tests/ac/t60_install_health.sh: blank templates and the leaked-state warnings, T52 in a
#   product, the AGENTS.md block refresh, the settings-merge matcher, the two-break rule — each with a red twin.
# AC4/AC6 — enforcement.sh T60: startup warning through the real preserve.py, heading-style laws guarded at both
#   layers (TODO law, pre-t60 and missing laws.py) — red twins at each layer. T15 unedited.
# t57/t58/t59 stay green: autopilot/critique/diverge, the Stop hook and the fingerprint sit next to this change.
# AC7/AC8 — the 2.0.0 -> 2.1.1 upgrade and the product smoke are run by hand and pasted into the hop report.
# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
