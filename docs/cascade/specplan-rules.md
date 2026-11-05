# Spec and plan rules

🧑 **HUMAN-OWNED FILE.** `bash tests/specplan.sh` reads the limits below. The pre-commit hook blocks a change to this file unless you sign it with `bash tests/sign.sh`.

Write each new spec and plan by these ASD-STE100 principles:

- Use one term for one meaning.
- Use active voice.
- Write one requirement in one sentence.
- Write steps in execution order.
- Keep technical names, commands, paths and quoted output exact.

The check does not claim ASD-STE100 conformance. It tests only sentence length, the banned terms below and the contract fields. The critic reads for the other principles. The pack does not ship the ASD-STE100 dictionary, because ASD holds the copyright.

The limits below are proposals. The agent that wrote them could not read Issue 9, so confirm them against your copy. The banned terms are this pack's own list. They are not part of the standard.

<EDIT>
SPECPLAN_MAX_WORDS_PROCEDURE: 20
SPECPLAN_MAX_WORDS_DESCRIPTIVE: 25
SPECPLAN_BANNED: etc. | and/or | as needed | as necessary | if possible | and so on
</EDIT>

To turn the check off, add `- SPECPLAN: off` inside `<EDIT>` in `docs/cascade/envelope.md`, and sign it.
