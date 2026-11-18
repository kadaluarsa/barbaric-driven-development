#!/usr/bin/env python3
"""Oracle strength (t109): small wrong versions of this slice's change, each judged by the slice's frozen oracle.

    mutants.py <root>     EXECUTE 05b: one MUTANT line per mutant, then `MUTANTS k/n killed`; exit 0 when every
                          survivor is answered, 1 otherwise. Any other hop: `MUTANTS n/a`, exit 0.

A mutant is made by a script, never by an agent, from the lines this hop added since the commit that opened it
(`affected.hop_base`): a flipped comparison or boolean, a swapped `and`/`or`, a dropped `not`, a deleted statement.
The same tree gives the same mutants, ids and verdicts for every builder. Each mutant is written in place in the real
working tree (ignored build inputs and caches stay), one line at a time, under a lock, with the original kept in
`<git dir>/cascade-mutants-backup/` and put back after each run, on exit, on a signal, and at the start of the next run
if a run was killed. The oracle's `run:` lines (from the manifest frozen at the hop-opening commit, without the line
that runs this script) judge it: a failing line kills it. A survivor is answered by a human-signed row
`| <id> | equivalent <reason> |` in docs/cascade/05b-<slug>-mutants.md (human-owned, like LESSON lines), or by a
stronger oracle (a send-back to GENERATE).

Signed inside <EDIT> in docs/cascade/envelope.md, at HEAD and in the working tree alike (environment values are
ignored): `- MUTANTS: off`, `- MUTANTS_MAX: <n>` (default 40, the lowest ids), `- MUTANTS_TIMEOUT: <s>` (default 600
per run line; a mutant that times out is killed).
"""
from __future__ import annotations

import hashlib
import io
import os
import re
import signal
import subprocess
import sys
import time
import tokenize

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oracle import base_manifest, hop, manifest_rel, off, parse   # noqa: E402
from signed import BLOCK                                          # noqa: E402

SELF = "bash tests/mutants.sh"
ENVELOPE = os.path.join("docs", "cascade", "envelope.md")
C_EXT = {".kt", ".kts", ".java", ".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx", ".swift", ".go", ".c", ".cc", ".cpp",
         ".h", ".hpp", ".rs", ".cs", ".scala", ".dart", ".m", ".mm"}
ANSWER = re.compile(r"^\|\s*([0-9a-f]{8})\s*\|\s*equivalent\s+(\S[^|]*?)\s*\|", re.M)
SETTING = re.compile(r"^\s*-\s*(MUTANTS|MUTANTS_MAX|MUTANTS_TIMEOUT):\s*(\S+)\s*$")


def git(root: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)


def git_dir(root: str) -> str:
    d = git(root, "rev-parse", "--absolute-git-dir").stdout.strip()
    return d or os.path.join(root, ".git")


def settings(root: str) -> dict[str, str]:
    """The signed MUTANTS* lines: the last of each inside <EDIT>, only where HEAD and the working tree agree."""
    def read(text: str) -> dict[str, str]:
        got: dict[str, str] = {}
        for block in BLOCK.findall(text):
            for line in block.splitlines():
                m = SETTING.match(line)
                if m and "{{" not in line:
                    got[m.group(1)] = m.group(2)
        return got
    try:
        now = read(open(os.path.join(root, ENVELOPE), encoding="utf-8", errors="replace").read())
    except OSError:
        return {}
    head = git(root, "show", f"HEAD:{ENVELOPE}")
    then = read(head.stdout) if head.returncode == 0 else {}
    return {k: v for k, v in now.items() if then.get(k) == v}


def number(value: str | None, default: int) -> int:
    return int(value) if value and value.isdigit() and int(value) > 0 else default


def mutants_off(root: str) -> bool:
    return settings(root).get("MUTANTS") == "off"


def family(root: str, rel: str) -> str:
    """'py', 'sh', 'c' or '' (not mutated)."""
    ext = os.path.splitext(rel)[1].lower()
    if ext == ".py":
        return "py"
    if ext in (".sh", ".bash"):
        return "sh"
    if ext in C_EXT:
        return "c"
    if ext == "":
        try:
            first = open(os.path.join(root, rel), encoding="utf-8", errors="replace").readline()
        except OSError:
            return ""
        if first.startswith("#!"):
            return "py" if "python" in first else "sh" if re.search(r"\b(ba)?sh\b", first) else ""
    return ""


def excluded(rel: str, frozen: set[str], slug: str) -> bool:
    return (rel in frozen or rel == manifest_rel(slug) or rel.endswith(".md") or rel.startswith("docs/")
            or rel.startswith(".cascade/") or rel.startswith(".git/"))


def added_lines(root: str, base: str, rel: str, tracked: bool, count: int) -> list[int]:
    """1-based line numbers of lines added since `base` (every line of an untracked file)."""
    if not tracked:
        return list(range(1, count + 1))
    out, lines = git(root, "diff", "-U0", "--no-color", "--no-ext-diff", base, "--", rel).stdout, []
    for m in re.finditer(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@", out, re.M):
        start, n = int(m.group(1)), int(m.group(2) or "1")
        lines += range(start, start + n)
    return lines


def prose_rows(fam: str, text: str) -> set[int]:
    """Rows that hold no code: a Python row with only strings or comments (a docstring), a shell heredoc body."""
    rows: set[int] = set()
    lines = text.split("\n")
    if fam == "py":
        code: set[int] = set()
        try:
            for tok in tokenize.generate_tokens(io.StringIO(text).readline):
                if tok.type in (tokenize.STRING, tokenize.COMMENT, tokenize.NL, tokenize.NEWLINE, tokenize.INDENT,
                                tokenize.DEDENT, tokenize.ENDMARKER):
                    if tok.type == tokenize.STRING:
                        rows.update(range(tok.start[0], tok.end[0] + 1))
                    continue
                code.update(range(tok.start[0], tok.end[0] + 1))
        except (tokenize.TokenError, SyntaxError, IndentationError):
            return set()
        return rows - code
    if fam == "sh":
        tag = None
        for n, line in enumerate(lines, 1):
            if tag is not None:
                rows.add(n)
                if line.strip() == tag:
                    tag = None
                continue
            m = re.search(r"<<-?\s*['\"]?([A-Za-z_]\w*)['\"]?", line) if "<<" in masked(line) else None
            if m:
                tag = m.group(1)
    return rows


def masked(line: str) -> str:
    """The line with quoted text and a trailing # comment blanked, so operators there are never mutated."""
    out, quote, i = [], "", 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\" and i + 1 < len(line):
                out += "  "; i += 2; continue
            out.append(" " if ch != quote else ch)
            if ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch; out.append(ch)
        elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
            out.append(" " * (len(line) - i)); break
        else:
            out.append(ch)
        i += 1
    return "".join(out)


OPS = {
    "py": [("eq-ne", r"==", "!="), ("ne-eq", r"!=", "=="), ("le-gt", r"<=", ">"), ("ge-lt", r">=", "<"),
           ("lt-ge", r"(?<![<\-=])<(?![<=])", ">="), ("gt-le", r"(?<![>\-=])>(?![>=])", "<="),
           ("and-or", r"\band\b", "or"), ("or-and", r"\bor\b", "and"), ("true-false", r"\bTrue\b", "False"),
           ("false-true", r"\bFalse\b", "True"), ("drop-not", r"\bnot\s+", "")],
    "sh": [("eq-ne", r"(?<=\s)-eq\b", "-ne"), ("ne-eq", r"(?<=\s)-ne\b", "-eq"), ("lt-ge", r"(?<=\s)-lt\b", "-ge"),
           ("ge-lt", r"(?<=\s)-ge\b", "-lt"), ("gt-le", r"(?<=\s)-gt\b", "-le"), ("le-gt", r"(?<=\s)-le\b", "-gt"),
           ("and-or", r"&&", "||"), ("or-and", r"\|\|", "&&"), ("streq-ne", r"(?<=\s)==(?=\s)", "!="),
           ("strne-eq", r"(?<=\s)!=(?=\s)", "==")],
    "c": [("eq-ne", r"==", "!="), ("ne-eq", r"!=", "=="), ("le-gt", r"<=", ">"), ("ge-lt", r">=", "<"),
          ("and-or", r"&&", "||"), ("or-and", r"\|\|", "&&"), ("true-false", r"\btrue\b", "false"),
          ("false-true", r"\bfalse\b", "true"), ("drop-not", r"!(?!=)", "")],
}
PY_BLOCK = re.compile(r"^(def|class|if|elif|else|for|while|try|except|finally|with|async|import|from|@|global|"
                      r"nonlocal|pass\b)")
SH_BLOCK = re.compile(r"^(if|then|else|elif|fi|for|while|until|do|done|case|esac|function|\{|\}|\(|\)|;;|[\w-]+\s*\(\)|"
                      r"local\b|declare\b|readonly\b|export\b|set\b|:$)")


def balanced(s: str) -> bool:
    return all(s.count(a) == s.count(b) for a, b in ("()", "[]", "{}"))


def deletion(fam: str, line: str, mask: str) -> str | None:
    """The line replaced by a no-op of the same indent, when that keeps the file's syntax; else None."""
    body, indent = mask.strip(), line[:len(line) - len(line.lstrip())]
    if not body or not balanced(body) or body.endswith(("\\", ",", "(", "[", "{", "|", "&&", "||")):
        return None
    if fam == "py":
        if body.endswith(":") or PY_BLOCK.match(body) or body.startswith(('"', "'")):
            return None
        return indent + "pass"
    if fam == "sh":
        if SH_BLOCK.match(body) or "<<" in body or body.endswith((";", "then", "do")) or "=" in body.split()[0]:
            return None
        return indent + ":"
    return None


def mutants(root: str, base: str, frozen: set[str], slug: str) -> list[dict]:
    tracked = [p for p in git(root, "diff", "--name-only", "--no-renames", base).stdout.splitlines() if p]
    untracked = [p for p in git(root, "ls-files", "-o", "--exclude-standard").stdout.splitlines() if p]
    found, seen = [], {}
    for rel, is_tracked in sorted([(p, True) for p in tracked] + [(p, False) for p in untracked]):
        path = os.path.join(root, rel)
        if excluded(rel, frozen, slug) or not os.path.isfile(path) or os.path.islink(path):
            continue
        fam = family(root, rel)
        if not fam:
            continue
        try:
            text = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        lines = text.split("\n")
        prose = prose_rows(fam, text)
        for n in added_lines(root, base, rel, is_tracked, len(lines)):
            if n < 1 or n > len(lines) or n in prose:
                continue
            line = lines[n - 1]
            mask = masked(line)
            if not mask.strip() or (fam == "c" and mask.lstrip().startswith(("//", "/*", "*"))):
                continue
            cands = []
            for name, pat, rep in OPS[fam]:
                m = re.search(pat, mask)
                if m:
                    cands.append((name, line[:m.start()] + rep + line[m.end():]))
            d = deletion(fam, line, mask)
            if d is not None:
                cands.append(("delete", d))
            for name, new in cands:
                if new == line:
                    continue
                key = f"{rel}\0{name}\0{line.strip()}"
                seen[key] = seen.get(key, 0) + 1
                mid = hashlib.sha1(f"{key}\0{seen[key]}".encode()).hexdigest()[:8]
                found.append({"id": mid, "rel": rel, "line": n, "op": name, "old": line, "new": new})
    return sorted(found, key=lambda m: m["id"])


def run_lines(cwd: str, runs: list[str], timeout: int) -> str:
    """'' when every line passes; else 'failed' or 'timeout'."""
    env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX"))}
    env["BDD_MUTANT_RUN"] = "1"
    env["PYTHONDONTWRITEBYTECODE"] = "1"   # a stale .pyc (same size, same second) would judge the previous mutant
    for line in runs:
        p = subprocess.Popen(["bash", "-c", line], cwd=cwd, env=env, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            rc = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            p.wait()
            return "timeout"
        if rc != 0:
            return "failed"
    return ""


class InPlace:
    """One mutated line at a time in the real tree; the original bytes live in <git dir>/cascade-mutants-backup/."""

    def __init__(self, root: str):
        self.root, gd = root, git_dir(root)
        self.lock, self.backup = os.path.join(gd, "cascade-mutants.lock"), os.path.join(gd, "cascade-mutants-backup")

    def acquire(self) -> str:
        try:
            os.mkdir(self.lock)
        except FileExistsError:
            try:
                pid = int(open(os.path.join(self.lock, "pid")).read().strip())
                os.kill(pid, 0)
                return f"another mutants run holds {self.lock} (pid {pid})"
            except (OSError, ValueError):
                pass   # a dead holder: take the lock over
        with open(os.path.join(self.lock, "pid"), "w") as fh:
            fh.write(str(os.getpid()))
        return ""

    def release(self) -> None:
        try:
            os.remove(os.path.join(self.lock, "pid")); os.rmdir(self.lock)
        except OSError:
            pass

    def recover(self) -> list[str]:
        """Put back every file a killed run left mutated; returns their paths."""
        done = []
        for dirpath, _, names in os.walk(self.backup):
            for name in names:
                src = os.path.join(dirpath, name)
                rel = os.path.relpath(src, self.backup)
                self._put(rel, open(src, "rb").read())
                os.remove(src)
                done.append(rel)
        self._prune()
        return sorted(done)

    def write(self, rel: str, new: bytes) -> None:
        keep = os.path.join(self.backup, rel)
        os.makedirs(os.path.dirname(keep), exist_ok=True)
        with open(os.path.join(self.root, rel), "rb") as fh, open(keep, "wb") as out:
            out.write(fh.read())
        self._put(rel, new)

    def restore(self, rel: str) -> None:
        keep = os.path.join(self.backup, rel)
        self._put(rel, open(keep, "rb").read())
        os.remove(keep)
        self._prune()

    def _put(self, rel: str, data: bytes) -> None:
        path = os.path.join(self.root, rel)
        with open(path, "wb") as fh:
            fh.write(data)
        InPlace.tick += 2   # a new, later mtime on every write: tools that compare mtimes never reuse a stale build
        stamp = max(time.time(), InPlace.last) + InPlace.tick
        InPlace.last = stamp
        os.utime(path, (stamp, stamp))

    def _prune(self) -> None:
        for dirpath, dirs, names in sorted(os.walk(self.backup, topdown=False), reverse=False):
            if not os.listdir(dirpath):
                try:
                    os.rmdir(dirpath)
                except OSError:
                    pass

    tick, last = 0, 0.0


def answers(root: str, slug: str) -> dict[str, str]:
    """Rows the human signed: committed at HEAD, and the same in the working tree (an uncommitted row is not one)."""
    rel = f"docs/cascade/05b-{slug}-mutants.md"
    head = git(root, "show", f"HEAD:{rel}")
    if head.returncode:
        return {}
    try:
        now = open(os.path.join(root, rel), encoding="utf-8").read()
    except OSError:
        return {}
    then = {m.group(1): m.group(2) for m in ANSWER.finditer(head.stdout)}
    return {k: v for k, v in then.items() if k in {m.group(1) for m in ANSWER.finditer(now)}}


def main() -> int:
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    h, stage, slug = hop(root)
    if off(root):
        print("MUTANTS off (the oracle is off, signed)"); return 0
    if mutants_off(root):
        print("MUTANTS off (signed)"); return 0
    if h != "EXECUTE" or stage != "05b" or not slug:
        print(f"MUTANTS n/a — mutants judge an EXECUTE 05b build (this hop: {h or 'NONE'} {stage or '-'})"); return 0
    if os.environ.get("BDD_MUTANT_RUN"):
        print("MUTANTS n/a — inside a mutant run"); return 0
    text, why = base_manifest(root, slug)
    if text is None:
        print(f"FAIL  {why}"); print("MUTANTS 0/0 killed"); return 1
    files, runs = parse(text)
    judge = [r for r in runs if " ".join(r.split()) != SELF]
    if not judge:
        print("FAIL  the frozen manifest has no run: line to judge mutants with"); print("MUTANTS 0/0 killed"); return 1
    from affected import hop_base   # noqa: PLC0415
    base, why = hop_base(root)
    if not base:
        print(f"FAIL  {why}"); print("MUTANTS 0/0 killed"); return 1
    cfg = settings(root)
    cap, timeout = number(cfg.get("MUTANTS_MAX"), 40), number(cfg.get("MUTANTS_TIMEOUT"), 600)
    place = InPlace(root)
    busy = place.acquire()
    if busy:
        print(f"FAIL  {busy}"); print("MUTANTS 0/0 killed"); return 1
    stop = {"sig": 0}

    def on_signal(signum, _frame):
        stop["sig"] = signum
        raise KeyboardInterrupt
    old = {s: signal.signal(s, on_signal) for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
    killed, survivors, chosen, allm = 0, [], [], []
    try:
        for rel in place.recover():
            print(f"mutants: restored {rel} from an interrupted run")
        allm = mutants(root, base, {f for _, f in files}, slug)
        chosen = allm[:cap]
        if not chosen:
            print("MUTANTS 0/0 killed — nothing to mutate: this hop added no mutable line"); return 0
        if run_lines(root, judge, timeout):
            print("FAIL  the oracle fails on the unmutated tree: no mutant can be judged")
            print(f"MUTANTS 0/{len(chosen)} killed"); return 1
        for m in chosen:
            path = os.path.join(root, m["rel"])
            lines = open(path, encoding="utf-8").read().split("\n")
            lines[m["line"] - 1] = m["new"]
            place.write(m["rel"], "\n".join(lines).encode("utf-8"))
            try:
                verdict = run_lines(root, judge, timeout)
            finally:
                place.restore(m["rel"])
            word = "KILLED" if verdict == "failed" else "KILLED (timeout)" if verdict == "timeout" else "SURVIVED"
            if verdict:
                killed += 1
            else:
                survivors.append(m)
            print(f"MUTANT  {m['id']}  {word:<16}  {m['rel']}:{m['line']}  {m['op']}  `{m['old'].strip()[:70]}`",
                  flush=True)
    except KeyboardInterrupt:
        place.recover()
        print(f"FAIL  interrupted (signal {stop['sig'] or 'INT'}): every mutated file was put back")
        return 1
    finally:
        place.recover()
        place.release()
        for s, handler in old.items():
            signal.signal(s, handler)
    ans = answers(root, slug)
    open_ = [m for m in survivors if m["id"] not in ans]
    sample = f" (the {len(chosen)} lowest ids of {len(allm)})" if len(allm) > len(chosen) else ""
    tail = f", {len(survivors) - len(open_)} answered equivalent" if survivors and len(open_) < len(survivors) else ""
    for m in open_:
        print(f"FAIL  survivor {m['id']}: {m['rel']}:{m['line']} {m['op']} passes the oracle — strengthen the oracle "
              f"(send back to GENERATE) or have the human sign `| {m['id']} | equivalent <reason> |` in "
              f"docs/cascade/05b-{slug}-mutants.md")
    print(f"MUTANTS {killed}/{len(chosen)} killed{sample}{tail}")
    return 1 if open_ else 0


if __name__ == "__main__":
    sys.exit(main())
