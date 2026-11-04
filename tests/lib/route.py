#!/usr/bin/env python3
"""Route a prompt to a bdd-work craft workflow (t91) — by rules, not by a model.

    route.py "<prompt>"     prints  <route>\\t<matched words>
    route.py --eval <tsv>   scores a labeled file (<route>\\t<prompt>, # comments): per-route k/n, then ROUTE EVAL k/n (pct%)
                            exit 0 iff >= 85% overall and every ambiguous row is predicted ambiguous

Routes: investigation, bug-fix, feature, refactor, verification, ambiguous. Precedence follows bdd-work's own
"Resolve overlapping intent" (skills/bdd-work/SKILL.md): a check of a result is verification; any other question is
investigation (a question about a failure is not a fix); a requested fix is bug-fix; feature and refactor together
are a tie (ambiguous); then feature; then refactor; nothing matched is ambiguous. The route is advice: the seam prints
it, nothing refuses on it.
"""
from __future__ import annotations

import re
import sys

VERIFY = [r"\bverify\b", r"\bcheck (whether|that|if)\b", r"\bdouble-check\b", r"\bconfirm\b", r"\bmake sure\b",
          r"\bvalidate\b", r"\brun the tests\b", r"^(is|are)\b.*\b(green|passing)\b", r"\bdoes\b.*\bpass\b",
          r"\bstill pass\b"]
QUESTION_START = r"^(why|how|what|where|which|who|explain|can you walk|how come)\b"   # do/is/can… count only with a "?"
BUG = [r"\bfix(es|ed)?\b", r"\bbugs?\b", r"\bbroken\b", r"\bcrash(es|ed|ing)?\b", r"\berrors?\b",
       r"\bfail(s|ed|ing)?\b", r"\bregression\b", r"\bwrong\b", r"\bnot working\b", r"\bdoesn'?t work\b",
       r"\bflaky\b", r"\bthrows\b", r"\bgoes blank\b", r"\bnegative\b", r"\blogged out\b", r"\bred on\b",
       r"\bget it green\b", r"\bsort it out\b"]
FEATURE = [r"\badd\b", r"\bbuild\b", r"\bimplement\b", r"\bcreate\b", r"\bsupport\b", r"\bintroduce\b", r"\bnew\b",
           r"\benable\b", r"\ballow\b", r"\bmake it possible\b", r"\bshould be able to\b", r"\bi'?d like\b"]
REFACTOR = [r"\brefactor\b", r"\brename\b", r"\bextract\b", r"\brestructure\b", r"\breorgani[sz]e\b",
            r"\bclean up\b", r"\btidy\b", r"\bsplit\b", r"\bbreak\b.*\binto\b", r"\bsimplify\b", r"\bdedupe\b",
            r"\bpull\b.*\binto\b", r"\bmove\b"]


def _hits(pats: list[str], text: str) -> list[str]:
    out = []
    for p in pats:
        m = re.search(p, text)
        if m:
            out.append(m.group(0))
    return out


def classify(prompt: str) -> tuple[str, list[str]]:
    text = " ".join(prompt.lower().split())
    if not text:
        return "ambiguous", []
    v = _hits(VERIFY, text)
    if v:
        return "verification", v
    if text.endswith("?") or re.match(QUESTION_START, text):
        return "investigation", [text.split()[0]]
    b = _hits(BUG, text)
    if b:
        return "bug-fix", b
    f, r = _hits(FEATURE, text), _hits(REFACTOR, text)
    if f and r:
        return "ambiguous", f + r
    if f:
        return "feature", f
    if r:
        return "refactor", r
    return "ambiguous", []


ROUTES = ("investigation", "bug-fix", "verification", "feature", "refactor", "ambiguous")


def evaluate(path: str) -> int:
    rows = []
    for line in open(path, encoding="utf-8"):
        if not line.strip() or line.startswith("#") or "\t" not in line:
            continue
        want, prompt = line.rstrip("\n").split("\t", 1)
        rows.append((want.strip(), prompt))
    per = {r: [0, 0] for r in ROUTES}
    for want, prompt in rows:
        got, _ = classify(prompt)
        per.setdefault(want, [0, 0])
        per[want][1] += 1
        per[want][0] += int(got == want)
    for r in ROUTES:
        if per[r][1]:
            print(f"{r} {per[r][0]}/{per[r][1]}")
    k = sum(v[0] for v in per.values()); n = sum(v[1] for v in per.values())
    pct = round(100 * k / n) if n else 0
    print(f"ROUTE EVAL {k}/{n} ({pct}%)")
    amb_ok = per["ambiguous"][0] == per["ambiguous"][1]
    return 0 if n and k / n >= 0.85 and amb_ok else 1


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--eval":
        return evaluate(sys.argv[2])
    if len(sys.argv) >= 2:
        route, words = classify(" ".join(sys.argv[1:]))
        print(f"{route}\t{', '.join(words)}")
        return 0
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
