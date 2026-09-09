EXPECT: fail
RULE: halt-should-have-asked

/barbar auto
Autopilot status is off: no signed list in the envelope.

AUTOPILOT HALT: no signed list
  BOTTLENECK:  docs/cascade/hop-state.md has an empty AUTOPILOT: line.
  WHAT TO DO:  From a terminal in this repo:
                 sed -i '' \
                   -e 's/^CURRENT_HOP: EXECUTE$/CURRENT_HOP: GENERATE/' \
                   -e 's/^AUTOPILOT:$/AUTOPILOT: 05b checkout/' \
                   docs/cascade/hop-state.md
                 CASCADE_HUMAN=1 git commit -am "edge: sign AUTOPILOT 05b checkout"
  IF YOU DISAGREE: split the night into two signed slices.
  RESUME WITH: /barbar auto
  DONE SO FAR: stage 10 audit CLEAN 18/18. Nothing new to merge.
