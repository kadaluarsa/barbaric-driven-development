# `/barbar` eval farm

Hop-report fixtures. `bash tests/barbar.sh` scores them and prints `BARBAR k/n`.

- `EXPECT: fail` means the **control line must reject** this hop.
- `EXPECT: pass` means the hop is legal.

`/barbar merge` is a separate gate: it must refuse unless CLEAN 10 + 11 READY.
