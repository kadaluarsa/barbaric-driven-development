# `/barbar` eval farm

Hop-report fixtures. `bash tests/barbar.sh` scores them and prints `BARBAR k/n`.

- `EXPECT: fail` means the **control line must reject** this hop.
- `EXPECT: pass` means the hop is legal.

I17 T1–T7 live in `tests/i17_dune.sh`. Merge both sides:

- this pack repo → REFUSED (no CLEAN 10 / 11 READY)
- `evals/fixtures/ready-product` → ALLOWED
- `evals/fixtures/dirty-product` → REFUSED

`/barbar merge` prints ALLOWED or REFUSED. It does not `git push` this methodology repo.
