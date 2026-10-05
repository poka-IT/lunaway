#!/usr/bin/env python3
"""PreToolUse(Bash): the shell mistakes that cost this project real time or data.

1. Destructive git: stash, checkout/restore of the tree, reset --hard, clean.
   Inspect with log/show/diff, or ask.
2. Disarming the gates: --no-verify, moving core.hooksPath, force pushes
   (--force-with-lease on a contributor branch is allowed).
3. A production tag push (vX.Y.Z without a pre-release suffix) publishes a
   release; it is refused unless LUNAWAY_PROD_TAG_ACK=1 is on that command.
4. A bare `flutter` or `dart` while the repo pins a version through fvm and
   fvm is installed: the wrong SDK reformats files and changes the lint set.
5. A bare `cargo update`: it re-resolves every crate of the lockfile at once.
   Update one crate with `cargo update -p <crate>`.
6. Dropping data: `sqlx database drop|reset`, or DROP/TRUNCATE sent through
   psql, refused unless LUNAWAY_DB_RESET_ACK=1 is on that command.

Fails open on anything unexpected. Regexes are exercised by tests/test_guards.py.
"""

import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from harness_common import allow, block, read_payload, repo_root
except Exception:
    sys.exit(0)

# Global git options may sit between `git` and the subcommand (`-C dir`,
# `-c k=v`, `--no-pager`); the subcommand anchor holds behind them.
GIT_OPTS = r"(?:-[A-Za-z]\s+\S+\s+|-{1,2}[^\s]+\s+)*"
GIT = r"\bgit\s+" + GIT_OPTS

DESTRUCTIVE = [
    (GIT + r"stash\b(?!\s+(?:list|show))", "git stash"),
    (GIT + r"(?:checkout|restore)\b[^\n|;&]*\s\.(?:/)?(?:\s|$)", "git checkout/restore ."),
    (GIT + r"(?:checkout|restore)\b[^\n|;&]*\s--\s+(?!\.)\S", "git checkout/restore -- <path> (discards the working tree)"),
    (GIT + r"reset\s+(?:[^\n|;&]*\s)?--hard\b", "git reset --hard"),
    (GIT + r"clean\b[^\n|;&]*\s(?:-\w*[fdx]|--force\b)", "git clean"),
]

NO_VERIFY = re.compile(GIT + r"(?:commit|push|merge)\b[^\n|;&]*\s(?:--no-verify|-n)(?:\s|$)")
# A read (`--get`, `-l`, or the key alone, possibly followed by a redirection
# or a closing `)` of a command substitution) passes; a write passes only when
# the value is `.githooks`; `--unset` never passes.
HOOKS_PATH = re.compile(
    GIT
    + r"config\b[^\n|;&]*(?:--unset(?:-all)?\s+core\.hooksPath\b"
    + r"|\bcore\.hooksPath\s+(?!\.githooks(?:\s|$))(?![0-9]*[<>]|\))[^\s|;&])"
)
FORCE_PUSH = re.compile(GIT + r"push\b[^\n|;&]*\s(?:--force|-f)(?:\s|$)")
PROD_TAG = re.compile(
    GIT + r"push\b[^\n|;&]*\s(?:v[0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?|--tags|refs/tags/v[0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?)(?:\s|$)"
)
PROD_TAG_ACK = re.compile(r"\bLUNAWAY_PROD_TAG_ACK=1\b")
# A bare toolchain call in command position: `flutter test`, `dart format`,
# `cd x && dart ...`. Not `fvm flutter`, not a path (`/opt/flutter/bin/flutter`)
# and not a word inside a string or an option.
BARE_TOOLCHAIN = re.compile(
    r"(?:^\s*|[;&|(`]\s*|\bthen\s+|\belse\s+|\bdo\s+|\bxargs\s+)(?:env\s+\w+=\S+\s+)*(flutter|dart)\s"
)
# `cargo update` passes with a target (-p/--package), with --workspace (it
# touches the workspace members only) and as a dry run.
CARGO_UPDATE_BARE = re.compile(
    r"\bcargo\s+(?:\+\S+\s+)?update\b(?![^\n|;&]*\s(?:-p|--package|--workspace|-w|--dry-run)\b)"
)
DB_DROP = re.compile(
    r"\bsqlx\s+(?:database\s+(?:drop|reset)|migrate\s+revert)\b"
    r"|\bpsql\b[^\n|;&]*\b(?:DROP\s+(?:DATABASE|SCHEMA|TABLE)|TRUNCATE)\b",
    re.IGNORECASE,
)
DB_ACK = re.compile(r"\bLUNAWAY_DB_RESET_ACK=1\b")
# A recursive removal whose target is computed (a variable, a command
# substitution, a glob) cannot be reviewed before it runs: an empty variable
# turns `rm -rf "$dir/"` into a removal of the wrong tree. Refused on
# 2026-10-06 by the maintainer; literal paths only.
# Both rules match a word in command position only (start of a line, after
# ; & | ( or a backtick, after then/do/else/xargs/exec/sudo/env), so the
# same words inside a quoted message or a printf string are not commands.
CMD_POS = r"(?:^|[;&|(`\n])\s*(?:(?:then|do|else|xargs|exec|sudo|nohup|env(?:\s+\w+=\S+)*)\s+)*(?:/\S*/)?"
RM_COMPUTED = re.compile(CMD_POS + r"rm\s+(?:-[A-Za-z]*[rR][A-Za-z]*|--recursive)\b[^\n|;&]*[$*?`]", re.MULTILINE)
# A shell -c script hides its commands from every check; with rm inside it is
# refused outright (same incident).
SHELL_C_RM = re.compile(CMD_POS + r"(?:bash|sh|zsh|dash)\s+-[A-Za-z]*c\b[\s\S]*\brm\s", re.MULTILINE)
# Printing a file that holds secrets puts them in the transcript.
SECRET_PRINT = re.compile(
    r"\b(?:cat|less|more|head|tail|bat|xxd|strings|od)\b[^\n|;&]*"
    r"(?:(?<![\w.])\.env(?!\.example)\b|key\.properties|\.config/lunaway/|\.(?:jks|keystore|p8|p12|pem)\b)"
)


def destructive(cmd):
    for pattern, label in DESTRUCTIVE:
        if re.search(pattern, cmd):
            return label
    return ""


def bare_toolchain(cmd, root):
    if not root or not os.path.isfile(os.path.join(root, ".fvmrc")):
        return ""
    if not shutil.which("fvm"):
        return ""
    # A command that writes a file (heredoc, inline script) is not a toolchain
    # invocation, whatever the text it writes says.
    if "<<" in cmd or re.match(r"\s*python3?\s+-", cmd):
        return ""
    m = BARE_TOOLCHAIN.search(cmd)
    return m.group(1) if m else ""


def writes_text(cmd):
    """A heredoc or inline script carries text, not commands to judge."""
    return "<<" in cmd or bool(re.match(r"\s*python3?\s+-", cmd))


HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
TEXT_SINK = re.compile(r"^\s*(?:cat|tee)\b")


def strip_text_heredocs(cmd):
    """`cmd` without the bodies of heredocs written to a file by cat or tee:
    those bodies are text, not commands. A heredoc fed to a shell or an
    interpreter (`bash <<EOF`, `python3 - <<EOF`) is code and is kept."""
    lines = cmd.split("\n")
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = HEREDOC.search(line)
        if m and TEXT_SINK.match(re.split(r"&&|\|\||;|\|", line[: m.start()])[-1]):
            i += 1
            while i < len(lines) and lines[i].strip() != m.group(2):
                i += 1
        i += 1
    return "\n".join(out)


def main():
    payload = read_payload()
    if not payload or payload.get("tool_name") != "Bash":
        return allow()
    cmd = (payload.get("tool_input") or {}).get("command") or ""
    root = repo_root(payload.get("cwd") or os.getcwd())
    if not root:
        return allow()

    hit = destructive(cmd)
    if hit:
        return block(
            "BLOCKED by the harness: %s discards work in the tree. Inspect with git log / show / "
            "diff, or ask the maintainer to run it. (AGENTS.md, Git)" % hit
        )
    if NO_VERIFY.search(cmd):
        return block(
            "BLOCKED by the harness: --no-verify disarms the tracked git hooks, and the CI replays "
            "the same checks, so the failure only moves to the pipeline. Fix what the hook reports."
        )
    if HOOKS_PATH.search(cmd):
        return block("BLOCKED by the harness: core.hooksPath stays `.githooks` (tool/setup.sh sets it).")
    if FORCE_PUSH.search(cmd):
        return block(
            "BLOCKED by the harness: never --force / -f a push. On a contributor branch you rebased, "
            "use --force-with-lease=<branch>:<sha you fetched>; main is never rewritten."
        )
    if PROD_TAG.search(cmd) and not PROD_TAG_ACK.search(cmd):
        return block(
            "BLOCKED by the harness: pushing a production tag (vX.Y.Z without a pre-release suffix) "
            "publishes a release. That is a maintainer decision: prefix the command with "
            "LUNAWAY_PROD_TAG_ACK=1 if that is what was asked."
        )
    tool = bare_toolchain(cmd, root)
    if tool:
        return block(
            "BLOCKED by the harness: this repo pins Flutter through .fvmrc and fvm is installed; "
            "run `fvm %s ...` so the pinned SDK formats and analyses (a bare `%s` uses whatever is on PATH)."
            % (tool, tool)
        )
    code = strip_text_heredocs(cmd)
    if SHELL_C_RM.search(code):
        return block(
            "BLOCKED by the harness: a `sh -c`/`bash -c` script that removes files cannot be reviewed before "
            "it runs. Run the commands directly, or write the routine to a script file in the repository and "
            "run that file."
        )
    if RM_COMPUTED.search(code):
        return block(
            "BLOCKED by the harness: a recursive rm on a variable, a command substitution or a glob. Use a "
            "fixed scratch directory (data/tmp/, gitignored) and remove literal paths only, one at a time."
        )
    if SECRET_PRINT.search(code):
        return block(
            "BLOCKED by the harness: this prints a file that holds secrets into the transcript. Show "
            "permissions (`stat`) or key names (`cut -d= -f1 <file>`) instead."
        )
    if not writes_text(cmd) and CARGO_UPDATE_BARE.search(cmd):
        return block(
            "BLOCKED by the harness: a bare `cargo update` re-resolves every crate of Cargo.lock at once, "
            "which turns one bump into an unreviewable diff. Update the crate you need: "
            "`cargo update -p <crate>` (AGENTS.md, Rust)."
        )
    if not writes_text(cmd) and DB_DROP.search(cmd) and not DB_ACK.search(cmd):
        return block(
            "BLOCKED by the harness: this drops or empties a database. On the local dev database, "
            "prefix the command with LUNAWAY_DB_RESET_ACK=1; anywhere else, ask the maintainer."
        )
    return allow()


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        pass
    sys.exit(0)
