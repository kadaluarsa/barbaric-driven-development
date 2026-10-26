# Regression suite — accepted slices' tests

> ⚙️ **MACHINE-READ FILE.** Read by `tests/regress.sh`, the merge gate (`bash tests/barbar.sh merge`) and CI.
> 🤖 **AGENT:** `bash tests/goal.sh reset` (start of every EXECUTE hop) and `bash tests/goal.sh carry-out` add lines
> here. You may add a line; you may never remove or change one.
> 🧑 **HUMAN:** Removing or changing a line is yours to sign (`bash tests/sign.sh`), or retire a line already removed
> on a branch with `- REGRESS_RETIRED: <line> — <reason>` in the envelope's Locked decisions.

When a slice is accepted, its tests stop running in every later hop's loop and run here instead: at the merge gate
and in CI on every pull request. Only lines starting at column 0 are read; the examples below are indented.

    REGRESS: bash tests/ac/checkout.sh                          a line run by the gate and CI
    REGRESS: xcodebuild test -scheme App -quiet # gate-only     skipped in CI (a Linux runner), run at the merge gate

Lines are grouped under `### <slice>` headings by carry-out; the headings carry no meaning to the checks. See
USAGE.md §B17.

### t77-goal-hygiene
REGRESS: bash tests/ac/t77_goal_hygiene.sh

### t78-carry-out
REGRESS: bash tests/ac/t78_carry_out.sh

### t79-zero-test-guard
REGRESS: bash tests/ac/t79_zero_test_guard.sh

### t80-carry-matching
REGRESS: bash tests/ac/t80_carry_matching.sh
