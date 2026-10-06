#!/usr/bin/env python3
"""PreToolUse(Edit|Write|MultiEdit|NotebookEdit): what an edit must never do.

1. Introduce an em dash (U+2014) or en dash (U+2013). Only INTRODUCED dashes
   are refused: an edit whose old text already carries one, or a write to a
   file that already has one, passes, so a file with old dashes can still be
   edited (fix them while there).
2. Edit generated output by hand: Dart codegen, lockfiles, the sqlx offline
   cache, the exported GraphQL schema. Regenerate instead.
3. Write key material: .env, key.properties, keystores, Apple keys.
4. Modify a migration that is already committed: sqlx checksums every applied
   migration, so an edited one breaks every database it ran on.

Fails open on anything unexpected. The two dash code points are built with
chr() so this file never carries one itself.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from harness_common import allow, block, denylist, git, ignored, read_payload, relative, repo_root
except Exception:
    sys.exit(0)

DASHES = re.compile("[" + chr(0x2014) + chr(0x2013) + "]")
SKIP_SUFFIXES = (".lock", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".pdf", ".ico", ".woff", ".woff2", ".ttf", ".zip")

GENERATED = [
    (re.compile(r"^app/lib/i18n/strings.*\.g\.dart$"), "edit app/lib/i18n/<locale>.i18n.json, then run `fvm dart run slang` in app/"),
    (re.compile(r"\.g\.dart$"), "run `fvm dart run build_runner build` in app/ instead of editing the output"),
    (re.compile(r"\.freezed\.dart$"), "run `fvm dart run build_runner build` in app/ instead of editing the output"),
    (re.compile(r"\.graphql\.dart$"), "run `fvm dart run build_runner build` in app/ instead of editing the output"),
    (re.compile(r"^app/pubspec\.lock$"), "run `fvm flutter pub get` (or `pub add`/`pub upgrade <pkg>`) in app/"),
    (re.compile(r"^backend/Cargo\.lock$"), "let cargo write it (`cargo update -p <crate>`, `cargo build`)"),
    (re.compile(r"^app/packages/[^/]+/rust/Cargo\.lock$"), "let cargo write it (`cargo update -p <crate>`, `cargo build`)"),
    (re.compile(r"^app/packages/lunaway_nav/(lib/src/rust/|rust/src/frb_generated\.rs$)"),
     "edit rust/src/api/, then run app/packages/lunaway_nav/tool/generate.sh"),
    (re.compile(r"^backend/\.sqlx/"), "run `cargo sqlx prepare --workspace` in backend/"),
    (re.compile(r"^schema/lunaway\.graphql$"), "run `cargo run -p lunaway-api --bin export-schema` in backend/"),
]
SECRETS = re.compile(r"(^|/)(\.env|key\.properties|[^/]*\.(jks|keystore|p8|p12|pem|mobileprovision))$")
MIGRATION = re.compile(r"^backend/migrations/[^/]+\.sql$")


def file_has_dash(path):
    try:
        if not path or not os.path.isfile(path):
            return False
        if os.path.getsize(path) > 4 * 1024 * 1024:
            return True
        with open(path, encoding="utf-8", errors="ignore") as f:
            return bool(DASHES.search(f.read()))
    except Exception:
        return True


def introduced_dash(tool, tool_input, path):
    if tool == "Edit":
        new, old = tool_input.get("new_string") or "", tool_input.get("old_string") or ""
        return bool(DASHES.search(new)) and not DASHES.search(old)
    if tool == "MultiEdit":
        for e in tool_input.get("edits") or []:
            if DASHES.search(e.get("new_string") or "") and not DASHES.search(e.get("old_string") or ""):
                return True
        return False
    if tool == "Write":
        return bool(DASHES.search(tool_input.get("content") or "")) and not file_has_dash(path)
    if tool == "NotebookEdit":
        return bool(DASHES.search(tool_input.get("new_source") or ""))
    return False


def new_text(tool, tool_input):
    """The text an edit writes."""
    if tool == "Edit":
        return tool_input.get("new_string") or ""
    if tool == "MultiEdit":
        return "\n".join(e.get("new_string") or "" for e in tool_input.get("edits") or [])
    if tool == "Write":
        return tool_input.get("content") or ""
    if tool == "NotebookEdit":
        return tool_input.get("new_source") or ""
    return ""


def denied_term(text, terms):
    low = text.lower()
    for t in terms:
        if t in low:
            return t
    return ""


def committed(rel, root):
    rc, _ = git(["cat-file", "-e", "HEAD:" + rel], root)
    return rc == 0


def main():
    payload = read_payload()
    if not payload:
        return allow()
    tool = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    root = repo_root(payload.get("cwd") or os.getcwd())
    if not root:
        return allow()
    rel = relative(path, root)
    if rel is None:
        return allow()

    if SECRETS.search(rel) and not rel.endswith(".env.example"):
        return block("BLOCKED by the harness: %s is key material and is never written through an agent." % rel)
    for pattern, fix in GENERATED:
        if pattern.search(rel):
            return block("BLOCKED by the harness: %s is generated; %s." % (rel, fix))
    if MIGRATION.search(rel) and committed(rel, root):
        return block(
            "BLOCKED by the harness: %s is a committed migration; sqlx checksums it, so editing it breaks "
            "every database it already ran on. Add a new migration instead (db-migration skill)." % rel
        )
    terms = denylist(root)
    if terms and not ignored(rel, root):
        term = denied_term(new_text(tool, tool_input), terms)
        if term:
            return block(
                "BLOCKED by the harness: this edit writes a term listed in .leak-denylist into %s, a "
                "tracked file. That name must never appear in this repository; use the generic name "
                "(see .claude/rules/data-sources.md)." % rel
            )
    if not rel.lower().endswith(SKIP_SUFFIXES) and introduced_dash(tool, tool_input, path):
        return block(
            "BLOCKED by the harness: this edit introduces an em dash or en dash. Use a comma, a colon, "
            "a period, parentheses, or reword (AGENTS.md, Writing)."
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
