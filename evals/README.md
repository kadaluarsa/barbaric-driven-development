# `/barbar` eval farm

Hop-report fixtures. `bash tests/barbar.sh` scores them and prints `BARBAR k/n`.

- `EXPECT: fail` means the **control line must reject** this hop.
- `EXPECT: pass` means the hop is legal.

I17 T1–T7 live in `tests/i17_dune.sh`. Merge both sides:

- this pack repo → REFUSED (no CLEAN 10 / 11 READY)
- `evals/fixtures/ready-product` → ALLOWED
- `evals/fixtures/dirty-product` → REFUSED
- `evals/fixtures/dsharp-red-product` → REFUSED (CLEAN 10 + READY 11, but an in-force D# validator fails)

`merge` runs the farm first (T14). I18 T8–T15 live in `tests/enforcement.sh` and exercise the git hooks, `tests/loop.sh`, and `.claude/hooks/` in throwaway repos.

`/barbar merge` prints ALLOWED or REFUSED. It does not `git push` this methodology repo.
