# /goal — this hop's definition of done

Read by `tests/loop.sh`. One `VALIDATOR:` per named test. Every in-force D# from
`envelope.md` must appear here, or carry a `WAIVE_DSHARP:` line with a reason — an
omitted D# is a FAIL entry, never a skip (I13). Clear this file on send-back (I9).

GOAL_STAGE: 05b
GOAL_SLICE: t59-scale-hardening
VALIDATOR: bash tests/ac/t59_scale_hardening.sh
VALIDATOR: bash tests/ac/t57_spec_critic.sh
VALIDATOR: bash tests/ac/t58_divergence.sh
VALIDATOR: bash tests/enforcement.sh
VALIDATOR: bash tests/lint.sh

# AC1/AC2/AC4/AC5 — tests/ac/t59_scale_hardening.sh: the fingerprint runs a constant number of git processes
#   (red twin: the old per-file one grows), changes on every edit the old one saw plus mode, flags and
#   same-second edits, never on ignored/.cascade/staged-only changes, writes nothing to .git; sign.sh signs
#   what it signed before with a constant process count (red twin: the old sign.sh grows); autopilot needs
#   docs/cascade/<stage>-<slug>.md exactly (red twin: the substring match allows the 06 collision).
# t57 and t58 stay green: autopilot.py's spec check and stop_guard.py's spec gates changed under them.
# AC3/AC3b/AC3c/AC6 — enforcement.sh T59 (with T8–T58 unchanged): every Stop-hook check that cannot finish
#   sends back with its cause (red twin: the old silent pass), scheme check incl. plugin mode, loop.sh
#   writes no receipt it cannot back; lint.sh checks CONTROL-LINE.md names T59.
# AC7 — tests/stress/ten_year.sh is opt-in (it writes 60,000 files); run once, output in the hop report.
# NO D# IN FORCE — envelope.md declares no law, so there is none to list or waive.
