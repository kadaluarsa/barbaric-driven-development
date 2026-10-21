# Stage 05b — t74-inv-new-file-skip — CRITIQUE

Written by a fresh read-only critic subagent with the pipeline's critic brief; rows committed verbatim
before any answer.

## Brief

| C# | severity | finding | evidence |
|---|---|---|---|
| C1 | high | The brief targets the right bug, and I reproduced it at HEAD: adding `tests/inv/mutants/D99.patch` exits 1 with empty stderr. But the reuse check only recognises files named `^test_D<N>`. Once the line is set -e safe, a new file for an existing declared law lands if its name doesn't start with `test_D`. Today that commit is blocked, though silently and by accident. So the fix loosens Layer 1 against rule 5 ("you may not … add under an existing one"), while the brief claims "the policy on existing files does not change (I18)". The brief never decides whether such files are allowed. | `AGENTS.md:50` "you may not change, delete, or add under an existing one"; `.githooks/pre-commit:76-77`; scratch repo with D1 declared and line 76 patched with `\|\| true`: `echo y > tests/inv/D1_vip.sh; git add -A; git commit -qm t` gives rc=0 (unpatched hook: rc=1, empty stderr) |
| C2 | medium | "Downstream repos pick it up by re-running `install.sh`" is only true for the hook. `install.sh` overwrites `.githooks`, but it never refreshes an AGENTS.md that already carries the cascade rules. So the new rule-5 sentence never reaches an installed repo. The plan's U1 and CHANGELOG entry repeat this claim. | `install.sh:116` `if grep -q 'Barbaric Driven Development' "$DST/AGENTS.md"; then echo "  = AGENTS.md (already carries the cascade rules)"`; `install.sh:63` `copy .githooks`; spec `05b-t74-inv-new-file-skip.md:139` |

## Spec

| C# | severity | finding | evidence |
|---|---|---|---|
| C3 | high | The new AGENTS.md sentence says the twin file can have "any name", and the hook will skip every name that doesn't start with `test_D`. That lets an agent commit `tests/inv/conftest.py`, which changes the verdict of an existing pytest law without touching its file. The canonical law form is exactly `pytest tests/inv/test_D1.py`. Today that commit is blocked (silently); after t74 it lands. No AC or trade-off row covers this. | `docs/cascade/envelope.md:56` `check:  {{pytest tests/inv/test_D1.py}}`; scratch: failing `test_D1.py` gives pytest exit 1; adding a conftest whose `pytest_collection_modifyitems` skips every item gives exit 0 ("1 skipped"); patched hook: `echo y > tests/inv/conftest.py; git add -A; git commit -qm t` gives rc=0 |
| C4 | medium | The spec defers word-splitting as "a separate defect", but this fix turns that defect into a bypass. `tests/inv/test_D1 vip.sh` splits into `tests/inv/test_D1`, which passes because D1's law text contains `test_D1`, and `vip.sh`, which today is the silent exit. With `\|\| true`, `vip.sh` is skipped and a new test under declared D1 commits. | spec `:127-128`; `.githooks/pre-commit:75,84`; patched scratch: `echo y > "tests/inv/test_D1 vip.sh"; git add -A; git commit -qm t` gives rc=0 (unpatched: rc=1, empty stderr) |
| C5 | medium | S-IN3 ("policy unchanged") has no AC that would catch a change. AC1 uses D99, which is undeclared, so no AC covers a file without the `test_D` prefix under declared D1 (C1). No AC covers a new file in a subfolder that reuses the law's basename either: `tests/inv/sub/test_D1.sh` already lands today. | spec `:11-13,93-97`; scratch (unpatched): `mkdir -p tests/inv/sub; echo y > tests/inv/sub/test_D1.sh; git add -A; git commit -qm t` gives rc=0 |
| C6 | low | AC4's mutation ("a copy of the hook without the `\|\| true`") is ambiguous. The hook has five other `\|\| true` sites, so a naive sed that strips them all also changes the `law=` and MDR lines. The spec should pin the mutation to line 76. | `grep -n '\|\| true' .githooks/pre-commit` gives lines 71, 82, 89, 107, 122; spec `:98` |
| C7 | low | The brief asks that hop_guard's copy of the check be verified for the same skip. The spec only asserts in prose that it is "already safe", and no AC exercises a Write of a new non-`test_D` file (or `conftest.py`) through hop_guard. T25 only covers `test_D10.py`. | spec `:39,85-86`; `tests/enforcement.sh:379-380` (only `tests/inv/test_D10.py`) |
| C8 | low | S-IN2 promises the hook "never exits 1 in silence", but the slice fixes one line. There is no ERR trap or catch-all message, and the cleanup trap preserves the exit code and prints nothing. The story is a general guarantee backed by one AC input. | spec `:10`; `.githooks/pre-commit:12-13` `cleanup() { local rc=$?; … return "$rc"; }` |
| C9 | low | In the After diagram every found id goes to "BLOCKED". It leaves out the two paths that commit: an undeclared id (AC2's `test_D99.sh`) and a file the law names itself (`pre-commit:83-84`). The diagram therefore disagrees with AC2. It also doesn't show the new skip applying to non-test files such as `conftest.py` (C3). | spec `:61` `C -->\|yes\| E[declared law names another test? BLOCKED …]` vs spec `:95` AC2 "`tests/inv/test_D99.sh` … commits" |
| C10 | low | The plan's T-range update only covers CONTROL-LINE.md. The suite's own header and final PASS line also carry ranges (already stale or drifting), and `tests/lint.sh` doesn't check `tests/enforcement.sh`, so they will rot without anyone noticing. | `tests/enforcement.sh:2` "T8–T66"; `tests/enforcement.sh:1678` "PASS: I18 T8–T67 enforced"; `tests/lint.sh:63` checks only `README.md CONTROL-LINE.md AUDIT.md` |

## Dispositions

| C# | DISPOSITION |
|---|---|
| C1 | fixed — the spec no longer adds a bare `|| true`: §1 makes every new tests/inv file carry a D# id and blocks a declared id unless that law names the exact path, so `D1_vip.sh` is BLOCKED with a message (S-IN3, the problem table, AC2); the brief's "policy does not change" is kept as "never looser than today". |
| C2 | fixed — §4 and the plan say `install.sh` keeps an existing AGENTS.md: the hook is refreshed, the AGENTS.md sentence must be merged by hand, and the hook's BLOCKED text carries the same rule meanwhile (U1, CHANGELOG). |
| C3 | fixed — id-less new files (`conftest.py`) are BLOCKED with the reason, not skipped; a human signs one (AC3); AGENTS.md no longer says "any name"; a trade-off row records why id-less files stay the human's. |
| C4 | fixed — §1 reads added paths one per line from `git diff -z`, never word-split; AC2 adds `tests/inv/test_D1 vip.sh` (BLOCKED). |
| C5 | fixed — AC2 now covers a non-`test_D` file under declared D1, `conftest.py`, the space case and `sub/test_D1.sh`; matching is by exact path (U2 names the deliberate tightening for the subfolder copy). |
| C6 | fixed — AC5(a) pins the mutation to line 76's exact extraction text, leaving every other `|| true` alone. |
| C7 | fixed — §3 gives hop_guard.py the same rule, and AC6 drives it with `Write` of `conftest.py`, `D1_vip.sh` and `mutants/D99.patch`. |
| C8 | fixed — §2 adds an ERR trap so any unexpected failure prints its line and exit code; S-IN2 is now backed by it and AC4, and U3 notes where ERR does not fire. |
| C9 | fixed — the after diagram shows every path: no id, undeclared id, declared and named, declared and not named, existing-file change, and the ERR trap. |
| C10 | fixed — the plan updates `tests/enforcement.sh`'s header and final ranges and has `tests/lint.sh` check them with the other T-ranges. |
