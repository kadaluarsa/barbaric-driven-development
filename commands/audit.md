---
description: Score stage 10 from the tree — `bash tests/audit.sh` — and report AUDIT k/n. Evidence only; never edits product code.
---
Run `bash tests/audit.sh $ARGUMENTS` and report its output verbatim. The verdict is the script's; never write "CLEAN" yourself (I7, I18). If it is DIRTY, list the non-IMPLEMENTED rows as the punch list and stop. Do not fix rows by editing product code inside this command — that is an `approved, execute stage 10 punch` hop.
