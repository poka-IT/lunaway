#!/usr/bin/env python3
"""SessionStart: converge the clone, then say only what the agent must do.

Runs at every session start (Claude Code, and Cursor through the same
settings file). Nothing here is asked of a human: what a script can do is
done, silently and idempotently; what it cannot do becomes one line addressed
to the agent.

  - activates the tracked git hooks (core.hooksPath = .githooks);
  - checks the pinned Flutter is installed under fvm;
  - checks the pinned Rust toolchain and the cargo tools the gates call;
  - refreshes origin at most every 30 minutes and reports how far the local
    default branch lags, since every branch starts from origin's;
  - reports stray git worktrees left inside the repository.

Silent on a converged clone. Fails open: any error exits 0 with no output.
"""

import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from harness_common import git, read_payload, repo_root
except Exception:
    sys.exit(0)

FETCH_INTERVAL = 30 * 60
CARGO_TOOLS = (("cargo-nextest", "cargo install cargo-nextest --locked"),
               ("cargo-deny", "cargo install cargo-deny --locked"))


def run(cmd, cwd, timeout=15):
    try:
        p = subprocess.run(cmd, cwd=cwd, timeout=timeout, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                           encoding="utf-8", errors="replace")
        return p.returncode, (p.stdout or "").strip()
    except Exception:
        return 1, ""


def state_file(root, name):
    rc, common = git(["rev-parse", "--git-common-dir"], root)
    base = common if os.path.isabs(common) else os.path.join(root, common or ".git")
    d = os.path.join(base, "lunaway-harness")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, name)


def fresh(path, interval):
    try:
        return time.time() - os.path.getmtime(path) < interval
    except OSError:
        return False


def pinned(path, pattern):
    try:
        with open(path, encoding="utf-8") as f:
            m = re.search(pattern, f.read())
            return m.group(1) if m else None
    except Exception:
        return None


def main():
    payload = read_payload() or {}
    root = repo_root(payload.get("cwd") or os.getcwd())
    if not root:
        return
    todo = []

    rc, hooks_path = git(["config", "--local", "core.hooksPath"], root)
    if hooks_path != ".githooks" and os.path.isdir(os.path.join(root, ".githooks")):
        git(["config", "core.hooksPath", ".githooks"], root)

    flutter = pinned(os.path.join(root, ".fvmrc"), r'"flutter"\s*:\s*"([^"]+)"')
    if flutter:
        rc, out = run(["fvm", "list"], root)
        if rc != 0 and not out:
            todo.append(
                "fvm is not installed; this repo pins Flutter %s. Install fvm (https://fvm.app), then `fvm install`, "
                "and run every flutter/dart command as `fvm flutter` / `fvm dart`." % flutter
            )
        elif flutter not in out:
            todo.append("Flutter %s (.fvmrc) is not installed under fvm: run `fvm install` before building or testing." % flutter)

    rust = pinned(os.path.join(root, "backend", "rust-toolchain.toml"), r'channel\s*=\s*"([^"]+)"')
    if rust:
        rc, out = run(["rustup", "toolchain", "list"], root)
        if rc != 0 and not out:
            todo.append("rustup is not installed; the backend pins Rust %s (https://rustup.rs)." % rust)
        elif not any(line.startswith(rust) for line in out.splitlines()):
            todo.append(
                "Rust %s (backend/rust-toolchain.toml) is not installed: "
                "`rustup toolchain install %s --profile minimal -c rustfmt -c clippy`." % (rust, rust)
            )
    for tool, install in CARGO_TOOLS:
        if not shutil.which(tool):
            todo.append("%s is missing; tool/check.sh needs it: `%s`." % (tool, install))

    rc, branch = git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], root)
    default = branch.split("/", 1)[1] if rc == 0 and "/" in branch else "main"
    stamp = state_file(root, "fetch")
    if not fresh(stamp, FETCH_INTERVAL):
        rc, _ = git(["fetch", "--quiet", "origin", default], root, timeout=20)
        if rc == 0:
            try:
                open(stamp, "w").close()
            except Exception:
                pass
    rc, behind = git(["rev-list", "--count", "%s..origin/%s" % (default, default)], root)
    if rc == 0 and behind.isdigit() and int(behind) > 0:
        todo.append(
            "local `%s` is %s commit(s) behind origin/%s: start any new branch from origin/%s "
            "(`git fetch origin && git switch -c <branch> origin/%s`), and fast-forward %s when you are on it."
            % (default, behind, default, default, default, default)
        )

    rc, wt = git(["worktree", "list", "--porcelain"], root)
    if rc == 0:
        paths = [l.split(" ", 1)[1] for l in wt.splitlines() if l.startswith("worktree ")]
        stray = [p for p in paths if p != root and p.startswith(root + os.sep)]
        if stray:
            todo.append(
                "git worktrees live inside the repository (%s): remove the ones you own once merged "
                "(`git worktree remove <path>`)." % ", ".join(stray)
            )

    if todo:
        print("Harness preflight (lunaway): do these before the task you were given.")
        for t in todo:
            print("- " + t)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
