---
description: Check the BDD pipeline is working — executes `bash tests/doctor.sh` and reports DOCTOR k/n
template: Run `bash tests/doctor.sh` and report its output verbatim. Doctor walks the enforcement layers in I18 order. Never write `DOCTOR k/n` yourself. For every RED line, name the dead layer and the fix command the script printed. Never fix anything yourself — doctor diagnoses, the human repairs. A `skipped` line is not a pass and not a failure. This is not a hop. Do not print the invariant block or an edge line unless a hop was already open.
