# Law shards

Laws (D#) may live here instead of in `docs/cascade/envelope.md`, one file per module: `core.md` for `:core`,
`app.md` for `:app`. The name is yours; `README.md` is never read as a shard.

- **Same format.** `### D7 — <MUST / MUST NOT>` with `check:`, `break:`, `reason:`, `path:`, `tier:`, or the legacy
  one-liner, inside an `<EDIT>` block — exactly as in the envelope.
- **One set.** `tests/lib/laws.py` reads the envelope, then every `docs/cascade/laws/*.md` in filename order.
  `DSHARP k/n`, the merge gate, `/goal` and stage 10 see one set of laws, split or not.
- **Unique ids.** One id in two places — two shards, a shard and the envelope — is FATAL: `dsharp_strength.sh`,
  `loop.sh` and `audit.sh` all refuse until one of them gets a new id.
- **You sign every change.** Adding, editing, moving or removing a law in a shard is a D# change, guarded like the
  envelope's: approve it in the dialog, or run `bash tests/sign.sh` (a new or removed shard included) and commit.
  Renaming a shard counts as removing it.
- **Decisions stay in the envelope.** `DSHARP_GRADLE_HARNESS`, `AFFECTED_SHARED_MODULES` and the other locked
  decisions are read only from `envelope.md`; `tests/lint.sh` flags one written here.
- **Retire, don't delete.** A law that is superseded or whose behaviour is gone gets a signed `retired:` line
  (USAGE.md §B14); it stops being scored, keeps its id, and stays readable here.
- **List each shard** in the envelope's `## Law shards` section, inside `<EDIT>`. `tests/lint.sh` checks it.
- **A hop reads only what it needs.** The prompt hook names the shards a slice's spec names (or, before the spec
  exists, every shard with its id range); on an EXECUTE hop, `bash tests/affected.sh --shards` lists the shards the
  diff reaches.
