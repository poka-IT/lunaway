#!/usr/bin/env python3
"""Tests for the commit message gate (.githooks/commit-msg).
Run: python3 tool/harness/hooks/tests/test_commit_msg.py

The gate exists because git keeps comment lines when it opens no editor: on
2026-10-08 a merge committed with `git commit --no-edit` stored its
`# Conflicts:` block as a body, and the gate, which dropped comments only
from what it read, let it through.

Dependency-free so it runs on any contributor machine with a bare python.
"""

import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
HOOK = os.path.join(ROOT, ".githooks", "commit-msg")

FAILURES = []


def run(message):
    """Runs the gate on a message file; returns (exit code, file afterwards)."""
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as fh:
        fh.write(message)
        path = fh.name
    try:
        done = subprocess.run(["sh", HOOK, path], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
        with open(path, encoding="utf-8") as fh:
            return done.returncode, fh.read()
    finally:
        os.unlink(path)


def check(label, got, want):
    if got != want:
        FAILURES.append("%s: got %r, want %r" % (label, got, want))


code, _ = run("fix(carte) : cible élargie au doigt\n")
check("a one-line subject passes", code, 0)

code, stored = run("chore(carte) : fusion du parcours au clavier\n\n# Conflicts:\n#\tapp/lib/x.dart\n")
check("a merge with its conflicts block passes", code, 0)
check("the conflicts block is not stored", stored, "chore(carte) : fusion du parcours au clavier\n")

code, _ = run("fix(carte) : cible élargie\n\nParce que le doigt couvre 9 mm.\n")
check("a body is refused", code, 1)

code, _ = run("fix(carte) : cible élargie\n\nCo-" + "Authored-By: someone <a@b.c>\n")
check("a trailer is refused", code, 1)

code, _ = run('Revert "fix(carte) : cible élargie"\n\nThis reverts commit 0123456.\n')
check("git's own revert body passes", code, 0)

code, _ = run("Merge branch 'feat/x'\n")
check("git's default merge subject passes", code, 0)

code, _ = run("cible élargie au doigt\n")
check("a subject without a type is refused", code, 1)

if FAILURES:
    print("\n".join(FAILURES))
    sys.exit(1)
print("OK")
