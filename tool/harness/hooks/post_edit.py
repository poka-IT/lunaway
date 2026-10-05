#!/usr/bin/env python3
"""PostToolUse(Edit|Write|MultiEdit): run the gate that the edited file feeds,
and hand its verdict back to the model while the edit is fresh.

  app/lib/i18n/*.i18n.json                    -> tool/i18n_check.dart
  tool/allowed_hosts.txt, tool/structure_*    -> tool/structure_check.dart
  AGENTS.md, CLAUDE.md, .claude/settings.json -> tool/harness/git/check_harness.sh
  backend/deny.toml, backend/.cargo/audit.toml, tool/structure_rs.sh
                                              -> tool/structure_rs.sh

Exit 2 on a PostToolUse hook does not undo anything; it feeds stderr to the
model as something to fix now. Silent when the gate passes. Fails open.
"""

import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from harness_common import allow, read_payload, relative, repo_root
except Exception:
    sys.exit(0)


def dart(root):
    if shutil.which("fvm") and os.path.isfile(os.path.join(root, ".fvmrc")):
        return ["fvm", "dart"]
    if shutil.which("dart"):
        return ["dart"]
    return None


def run(cmd, root):
    try:
        p = subprocess.run(cmd, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                           encoding="utf-8", errors="replace", timeout=120)
    except Exception:
        return 0, ""
    return p.returncode, p.stdout or ""


def route(rel):
    """The gate script an edited file feeds, or None. Pure, so it is tested
    on machines without the toolchain the gate needs."""
    if rel.startswith("app/lib/i18n/") and rel.endswith(".i18n.json"):
        return "tool/i18n_check.dart"
    if rel in ("tool/allowed_hosts.txt", "tool/structure_ratchet.json", "tool/structure_check.dart"):
        return "tool/structure_check.dart"
    if rel in ("AGENTS.md", "CLAUDE.md", ".claude/settings.json"):
        return "tool/harness/git/check_harness.sh"
    if rel in ("backend/deny.toml", "backend/.cargo/audit.toml", "tool/structure_rs.sh"):
        return "tool/structure_rs.sh"
    return None


def gate_for(rel, root):
    script = route(rel)
    if not script:
        return None
    if script.endswith(".dart"):
        d = dart(root)
        return d + [script] if d else None
    return ["sh", script]


def main():
    payload = read_payload()
    if not payload:
        return allow()
    path = (payload.get("tool_input") or {}).get("file_path") or ""
    root = repo_root(payload.get("cwd") or os.getcwd())
    rel = relative(path, root)
    if not root or rel is None:
        return allow()

    gate = gate_for(rel, root)
    if not gate or not os.path.isfile(os.path.join(root, gate[-1])):
        return allow()

    code, out = run(gate, root)
    if code != 0:
        sys.stderr.write("The gate for %s fails after this edit; fix it before moving on:\n%s\n" % (rel, out.strip()))
        sys.exit(2)
    return allow()


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        pass
    sys.exit(0)
