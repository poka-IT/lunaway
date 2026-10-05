"""Shared helpers for the Claude Code hooks of this repository.

Every guard is scoped to THIS repository (a directory carrying AGENTS.md,
backend/Cargo.toml and an app/pubspec.yaml named `lunaway`) and fails OPEN
everywhere else: an unexpected payload, a missing file or a parse error lets
the tool call through. A guard that breaks unrelated work costs more than the
defect it catches.

Exit codes follow the Claude Code contract: 0 allows, 2 blocks with the reason
on stderr. Cursor reads the same settings file and honours the same codes.
"""

import json
import os
import re
import subprocess
import sys

PACKAGE_NAME = "lunaway"


def read_payload():
    """The hook JSON on stdin, or None when it cannot be read."""
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            return None
        return json.loads(raw)
    except Exception:
        return None


def _package_name(root):
    try:
        with open(os.path.join(root, "app", "pubspec.yaml"), encoding="utf-8") as f:
            for line in f:
                m = re.match(r"^name:\s*(\S+)", line)
                if m:
                    return m.group(1)
    except Exception:
        return None
    return None


def is_root(path):
    return (
        os.path.isfile(os.path.join(path, "AGENTS.md"))
        and os.path.isfile(os.path.join(path, "backend", "Cargo.toml"))
        and _package_name(path) == PACKAGE_NAME
    )


def repo_root(start):
    """Walk up from `start` to the root of this repository, or None."""
    try:
        cur = os.path.abspath(start or os.getcwd())
    except Exception:
        return None
    for _ in range(40):
        if is_root(cur):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return None
        cur = parent
    return None


def relative(path, root):
    """`path` relative to `root`, or None when it lies outside."""
    if not path or not root:
        return None
    try:
        p = path if os.path.isabs(path) else os.path.join(root, path)
        rel = os.path.relpath(os.path.abspath(p), root)
    except Exception:
        return None
    return None if rel.startswith("..") else rel.replace(os.sep, "/")


def git(args, cwd, timeout=15):
    """(returncode, stdout) of a git command; (1, "") when it cannot run."""
    try:
        p = subprocess.run(["git"] + list(args), cwd=cwd, timeout=timeout, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        return p.returncode, (p.stdout or "").strip()
    except Exception:
        return 1, ""


def denylist(root):
    """Lower-case terms from the untracked `.leak-denylist` (one per line),
    which must never enter a tracked file or a commit message. Empty when the
    file is absent (a fresh clone, the CI)."""
    try:
        with open(os.path.join(root, ".leak-denylist"), encoding="utf-8") as f:
            return [l.strip().lower() for l in f if l.strip()]
    except Exception:
        return []


def ignored(rel, root):
    """True when git ignores `rel` (plan/, data/ ...): denied terms may live there."""
    rc, _ = git(["check-ignore", "-q", rel], root)
    return rc == 0


def block(message):
    sys.stderr.write(message.rstrip() + "\n")
    sys.exit(2)


def allow():
    sys.exit(0)
