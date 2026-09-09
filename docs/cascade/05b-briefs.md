- multi-currency: <one paragraph>
- journal-transfers: <one paragraph>
- stage-reads-manifest: Every hop currently carries context for stages it is not running. A stage 08
  hop re-reads 01's problem statement and 02's JTBD in full, though it needs only the invariants and
  the stage 05 technical design — so per-hop context grows with the accepted-artifact pile rather than
  with the work. Give each stage in `product-e2e-gre-pipeline.md` an explicit `reads:` line naming the
  prior artifacts that stage actually consumes, and teach the GENERATE and EXECUTE hop shapes to load
  exactly that list and nothing else. The 22-hop floor is the method and stays; what goes is each hop
  paying for stages it is not on. Done when every stage 00–11 carries a `reads:` line, the hop shapes
  cite it, and a test asserts no stage's manifest names an artifact from a stage that has not been
  accepted yet.
- stage-template-split: `product-e2e-cascade.md` holds all twelve stages' spec templates in one 31 KB
  file, and a hop uses exactly one of them. Split the templates into `docs/cascade/stages/NN-<name>.md`
  and reduce the parent file to a dispatch index that points at the stage in play. Done when the parent
  is under 4 KB, every stage template lives in its own file, and a test asserts the index names every
  file present and no file is orphaned.
- invariant-card: Invariants I1–I18 are the part of `product-e2e-gre-pipeline.md` actually consulted
  mid-hop, but they sit inside a 32 KB document that must be loaded whole to reach them. Extract them
  to a standalone `docs/cascade/invariants.md` card of roughly 1 KB, leave a pointer behind, and have
  the hop shapes cite the card. Done when the card exists, the pipeline doc references rather than
  restates I1–I18, and `tests/loop.sh` reads the card.
