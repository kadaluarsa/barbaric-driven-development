---
description: Check that the BDD pipeline is working, not just installed — `bash tests/doctor.sh` — and report DOCTOR k/n. Diagnosis only; never repairs, never signs.
---
Run `bash tests/doctor.sh $ARGUMENTS` and report its output verbatim. The verdict is the script's; never write `DOCTOR k/n` yourself (I18).

Doctor walks the enforcement layers in I18 order and quotes the scripts that own each verdict — `install.sh --check`, `dsharp_strength.sh`, `reads_manifest.sh`, `stage_templates.sh`, `barbar.sh`. It never re-derives one of those verdicts, and neither do you: if a line disagrees with what `bash tests/barbar.sh` or `bash tests/barbar.sh merge` says, that is a bug to report, not a number to reconcile in prose.

For every RED line, name the layer that is dead and the command the script printed to fix it. Do not run those commands: doctor diagnoses, the human repairs. In particular never run `bash tests/sign.sh`, never set `CASCADE_HUMAN=1`, and never edit `.claude/settings.json`, `.githooks/`, `core.hooksPath` or the envelope to turn a line green — a layer weakened to make doctor pass is the defect doctor exists to find (I18).

A `skipped` line is not a pass and not a failure: it is a check that could not run here, excluded from the score. Say so rather than counting it either way. Branch protection is always skipped — it is a GitHub setting, not readable from the tree — so tell the human to verify it themselves (INTEGRATION.md, Layer 0).

`DOCTOR_FAST=1` defers the farm; the score then covers everything but end-to-end. Say which one you ran.

This is not a hop. Do not print the invariant block or an edge line unless a hop was already open.
