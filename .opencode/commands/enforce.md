---
description: Run the enforcement test suite — executes `bash tests/enforcement.sh` to verify I18 T8–T61
agent: general
subagent: true
template: Run `bash tests/enforcement.sh` and report its output verbatim. The suite scores every enforcement test T8–T61. The final line must say `PASS: I18 T8–T61 enforced` for a clean bill. If any test FAILs, list the failing test IDs and their error messages — do not try to fix them from here.
