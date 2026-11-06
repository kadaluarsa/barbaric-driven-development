#!/usr/bin/env python3
"""PreToolUse(Bash) — deny the shell escapes around the ship gate (I15).

Patterns are anchored to command position and heredoc bodies are stripped, so
prose that *mentions* a forbidden command (docs, commit messages, echo) does not
trip the guard. Only running it does.
"""
from __future__ import annotations

NAME = "bash_guard.py"

import json
import os
import subprocess
import re
import shlex
import sys

HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?")
SPLIT = re.compile(r"[;&|\n]+")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from _common import already_handled, ask, guarded, log
except Exception as _exc:   # a guard that cannot load must not let the call through
    decision = "deny" if os.environ.get("BDD_HOOK_HOST") == "codex" or os.environ.get("PLUGIN_ROOT") else "ask"
    json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
               "permissionDecisionReason": f"cascade guard {NAME} could not load _common.py ({_exc!r}); "
                                           "refusing to fail open — a human must decide."}}, sys.stdout)
    raise SystemExit(0)

ACTOR = NAME[:-3]

RULES = (
    (re.compile(r"^git\s+push\b(?!.*--dry-run).*\b(main|master)\b"),
     "direct push to main. Ship path is CLEAN 10 + 11 READY -> /barbar merge -> PR -> required checks."),
    (re.compile(r"^git\s+push\b.*\s(-f|--force|--force-with-lease)\b"),
     "force push. Rewriting shared history destroys the evidence trail (I2)."),
    (re.compile(r"^gh\s+pr\s+merge\b"),
     "auto-merge. Merge needs CLEAN stage 10 + READY stage 11 + green D# and a human (I15)."),
    (re.compile(r"^git\s+(commit|push|merge)\b.*--no-verify\b"),
     "--no-verify bypasses the cascade pre-commit/pre-push hooks. That is the bar, not a nuisance."),
    (re.compile(r"(?i)^git\s+config\b.*(--unset\b.*core\.hooksPath|core\.hooksPath\s+(?!\.githooks(\s|$))\S)"),
     "re-pointing core.hooksPath disables the cascade git hooks (I18). Reading it, or setting .githooks, is fine."),
)
HUMAN_KEY = re.compile(r"(^|[\s;&|(]|\benv\s+|\bexport\s+)CASCADE_HUMAN=")   # setting the key is always a write
# The signature ledger is the human's. *Writing* it mints a signature; reading it does not, and denying a
# read the human can do in any editor buys nothing while teaching people the guard is noise — which is how a
# guard stops being obeyed. (This rule refused `ls`, `cat` and even a `grep` for the filename.) Writes are
# denied here; the Write/Edit tools are sealed out of the git dir by hop_guard (T46).
TOKEN = re.compile(r"cascade-(?:human-ok|sign-pending)")
READ_ONLY = re.compile(r"^(?:cat|bat|less|more|head|tail|wc|ls|stat|file|find|grep|rg|egrep|fgrep|sort|uniq"
                       r"|cut|awk|diff|cmp|shasum|sha256sum|md5|md5sum|xxd|od|test|echo|printf|\[)\b")
REDIR = re.compile(r"(?<![0-9<>])>{1,2}(?!&)")
INPLACE = re.compile(r"(?:^|\s)(?:-i(?:\.\w*)?|--in-place)\b")
# Signing is the human's act. Deny *running* the signer (command position); reading or syntax-checking it is fine.
SIGN = re.compile(r"^(?:(?:bash|sh|zsh)\s+(?!-)\S*)?\.?/?tests/sign\.sh\b|^bdd\s+sign\b")
ON_MAIN = re.compile(r"^git\s+(checkout|switch)\s+(main|master)\b")
MERGE = re.compile(r"^git\s+merge\b")


def strip_heredocs(cmd: str) -> str:
    out, lines, i = [], cmd.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = HEREDOC.search(line)
        if m:
            term = m.group(1)
            i += 1
            while i < len(lines) and lines[i].strip() != term:
                i += 1
        i += 1
    return "\n".join(out)


QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"", re.S)


def strip_quoted(cmd: str) -> str:
    """Blank out quoted spans (multi-line included) — a commit message that mentions `git push origin main`
    or the signer is text, not a command. Only unquoted command position can offend."""
    return QUOTED.sub(lambda m: '""', cmd)


MESSAGE = re.compile(r"(?:^|\s)(?:-m|--message)(?:=|\s+)(?:'[^']*'|\"(?:\\.|[^\"\\])*\"|\S+)")
QUOTE_CHARS = re.compile(r"['\"]")


def arg_view(cmd: str) -> str:
    """Quotes group an argument; they do not change what it is. `printf x > ".git/cascade-human-ok"` writes
    the ledger exactly as the bare form does, and `git commit "--no-verify"` still skips every hook — so the
    path and flag checks read the command with its quote characters removed. Blanking every quoted span
    (which is what stopped the guard firing on prose) also blinded it to quoted arguments: one pair of quotes
    turned every denial into an allow (T51). A commit message is the one quoted span that really is prose, so
    -m/--message values are dropped first. Text inside an `echo` still cannot pose as a command, because the
    command-position rules are anchored at the start of a simple command."""
    return QUOTE_CHARS.sub("", MESSAGE.sub(" ", strip_heredocs(cmd)))


def simple_commands(cmd: str) -> list[str]:
    parts = []
    for raw in SPLIT.split(arg_view(cmd)):
        s = raw.strip().lstrip("({ ").strip()
        s = re.sub(r"^(sudo|time|env|nohup|exec)\s+", "", s)
        s = re.sub(r"^(\w+=\S*\s+)+", "", s)
        if s:
            parts.append(s)
    return parts


GIT_CONFIG_ENV = re.compile(r"^\s*(?:(?:export|env)\s+|\w+=\S*\s+)*GIT_CONFIG_(?:COUNT|PARAMETERS)=")
GIT_VALUE_GLOBALS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--exec-path", "--super-prefix"}
COMMIT_VALUE_SHORT = set("mFCct")
COMMIT_VALUE_LONG = {"--message", "--file", "--author", "--date", "--reuse-message", "--reedit-message", "--fixup",
                     "--squash", "--template", "--trailer", "--cleanup", "--pathspec-from-file"}
HOOKS_OFF = "skipping the git hooks disables the cascade pre-commit/pre-push checks (I18). That is the bar, not a nuisance."


def command_tokens(cmd: str) -> list[list[str]]:
    """Each simple command as shell words, split with the quotes respected (t96): `-m "a -n b"` is one value,
    and `git commit "-n"` is the flag. Unbalanced quotes fall back to whitespace, which can only over-read."""
    text = strip_heredocs(cmd)
    try:
        lexer = shlex.shlex(text, posix=True, punctuation_chars=";&|()")
        lexer.whitespace_split = True
        lexer.commenters = ""
        words = list(lexer)
    except ValueError:
        words = text.split()
    out, cur = [], []
    for w in words:
        if w and not w.strip(";&|()"):
            out.append(cur); cur = []
        else:
            cur.append(w)
    out.append(cur)
    return [c for c in out if c]


def git_bypass(tokens: list[str]) -> tuple[str | None, str | None]:
    """(why this skips the hooks, `git <sub> ...` with its global options removed) for one simple command."""
    i = 0
    while i < len(tokens) and (tokens[i] in ("sudo", "time", "env", "nohup", "exec")
                               or re.match(r"^\w+=", tokens[i])):
        i += 1
    if i >= len(tokens) or tokens[i] != "git":
        return None, None
    i += 1
    while i < len(tokens) and tokens[i].startswith("-"):
        flag = tokens[i]
        name, eq, value = flag.partition("=")
        if flag in GIT_VALUE_GLOBALS or name in GIT_VALUE_GLOBALS:
            if not eq and i + 1 < len(tokens):
                value = tokens[i + 1]
                i += 1
            if name in ("-c", "--config-env") and value.lower().startswith("core.hookspath"):
                return HOOKS_OFF, None
        i += 1
    if i >= len(tokens):
        return None, None
    sub, args = tokens[i], tokens[i + 1:]
    plain = "git " + " ".join([sub] + args)
    no_verify = lambda a: len(a) >= 9 and "--no-verify".startswith(a)   # git takes a unique prefix: --no-veri
    if sub in ("commit", "push", "merge") and any(no_verify(a) for a in args):
        return HOOKS_OFF, plain
    if sub == "commit":
        j = 0
        while j < len(args):
            a = args[j]
            if a == "--":
                break
            if a.startswith("--"):
                if a in COMMIT_VALUE_LONG:
                    j += 1
            elif a.startswith("-"):
                for pos, ch in enumerate(a[1:]):
                    if ch == "n":
                        return HOOKS_OFF, plain
                    if ch in COMMIT_VALUE_SHORT:
                        if pos == len(a) - 2:
                            j += 1
                        break
            j += 1
    return None, plain


def offending(cmd: str) -> str | None:
    for raw in SPLIT.split(strip_quoted(strip_heredocs(cmd))):
        if GIT_CONFIG_ENV.search(raw):
            return HOOKS_OFF
    for tokens in command_tokens(cmd):
        why, plain = git_bypass(tokens)
        if why:
            return why
        if plain and plain != "git " + " ".join(tokens[tokens.index("git") + 1:]):
            for pat, rule_why in RULES:   # global options removed: `git -C . push origin main` is that push
                if pat.search(plain):
                    return rule_why
    on_main = False
    # Setting the human key (outside quoted text) is denied; merely mentioning it is not.
    # Checked on the raw segments: simple_commands() strips leading VAR=value assignments.
    for raw in SPLIT.split(strip_quoted(strip_heredocs(cmd))):
        if HUMAN_KEY.search(raw):
            return "CASCADE_HUMAN is the human's stitch key. The agent never sets it (I15)."
    for s in simple_commands(cmd):
        if TOKEN.search(s) and (REDIR.search(s) or INPLACE.search(s) or not READ_ONLY.match(s)):
            return ("the signature ledger is the human's (I15). Reading it is fine; writing, moving or "
                    "deleting it is minting a signature.")
        if SIGN.search(s):
            return "signing is the human's act — they run `bash tests/sign.sh` (or `bdd sign`) themselves (I15)."
        for pat, why in RULES:
            if pat.search(s):
                return why
        if ON_MAIN.search(s):
            on_main = True
        elif on_main and MERGE.search(s):
            return "merging into main from the shell (I15)."
    return None


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    if ev.get("tool_name") != "Bash":
        return 0
    if already_handled(ev, ev.get("cwd") or os.getcwd(), NAME):
        return 0
    cmd = (ev.get("tool_input") or {}).get("command", "")
    why = offending(cmd)
    if why:
        log(ev.get("cwd") or os.getcwd(), ACTOR, "DENY", f"`{cmd[:80]}` — {why[:140]}")
        json.dump(
            {"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": f"BLOCKED by cascade ship guard: {why}",
            }},
            sys.stdout,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(guarded(main, NAME))
