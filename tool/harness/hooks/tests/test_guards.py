#!/usr/bin/env python3
"""Regression tests for the guard regexes and the fail-open contract.

    python3 tool/harness/hooks/tests/test_guards.py

Dependency-free so it runs on any machine with a bare Python; the CI runs it
in the harness job.

Two writing quirks, both deliberate. Dashes are built with chr(), so this
file never carries one. And every git command under test is assembled from
G + "...": the guards read the raw text of a tool call, so a file that spelled
the forbidden commands out could not be written or edited through an agent.
"""

import io
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HOOKS = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(HOOKS, "..", "..", ".."))
sys.path.insert(0, HOOKS)

import bash_guard  # noqa: E402
import edit_guard  # noqa: E402
import harness_common  # noqa: E402
import post_edit  # noqa: E402

EM = chr(0x2014)
EN = chr(0x2013)
G = "git "
FAILURES = []


def check(label, got, want):
    if got != want:
        FAILURES.append("%s: got %r, want %r" % (label, got, want))


def cases(label, fn, block, allow):
    for c in block:
        check("%s should block: %s" % (label, c), bool(fn(c)), True)
    for c in allow:
        check("%s should allow: %s" % (label, c), bool(fn(c)), False)


cases(
    "destructive",
    bash_guard.destructive,
    [G + "stash", G + "stash pop", G + "checkout .", G + "checkout ./", G + "checkout -- .",
     G + "checkout HEAD -- .", G + "restore .", G + "restore -- .", G + "restore --source=HEAD .",
     G + "restore --staged .", G + "restore . && ls", G + "reset --hard", G + "reset --hard HEAD~1",
     G + "-C backend reset --hard", G + "clean -fd", G + "clean --force", G + "checkout -- app/lib/main.dart"],
    [G + "stash list", G + "stash show", G + "checkout main", G + "checkout -b clean",
     G + "checkout .github/workflows/ci.yml", G + "diff HEAD -- .", G + "clean -n", G + "clean --dry-run",
     G + "log --stat", G + "checkout main && ls .", G + "show HEAD:file", G + "restore --staged app/lib/main.dart"],
)
cases(
    "no-verify",
    bash_guard.NO_VERIFY.search,
    [G + "commit -m x --no-verify", G + "commit --no-verify -m 'x'", G + "push --no-verify",
     G + "commit -n -m x", G + "-C app commit -n -m x"],
    [G + "commit -m 'no-verify is banned'", G + "log -n 3", G + "commit -m x", G + "push origin HEAD"],
)
cases(
    "force push",
    bash_guard.FORCE_PUSH.search,
    [G + "push --force", G + "push -f origin main", G + "push origin main --force", G + "push --force origin fix/x"],
    [G + "push --force-with-lease=fix/x:abc origin fix/x", G + "push origin HEAD", G + "push -u origin fix/x", G + "push --tags"],
)
cases(
    "prod tag",
    bash_guard.PROD_TAG.search,
    [G + "push origin v1.8.0", G + "push origin v1.8.0+203", G + "push --tags", G + "push origin refs/tags/v1.8.1",
     G + "push origin main v1.8.0"],
    [G + "push origin v1.8.0-beta.1", G + "push origin fix/v1", G + "tag v1.8.0", G + "push origin main"],
)
check("prod tag ack", bool(bash_guard.PROD_TAG_ACK.search("LUNAWAY_PROD_TAG_ACK=1 " + G + "push origin v1.8.0")), True)
cases(
    "hooksPath",
    bash_guard.HOOKS_PATH.search,
    [G + "config core.hooksPath /tmp/x", G + "config --unset core.hooksPath", G + "config --local core.hooksPath .husky"],
    [G + "config core.hooksPath .githooks", G + "config --get core.hooksPath", G + "config --local core.hooksPath",
     G + "config user.name poka", G + "config -l", '"$(' + G + 'config --local core.hooksPath 2>/dev/null)"',
     G + "config --local core.hooksPath >/tmp/x"],
)
cases(
    "bare toolchain",
    bash_guard.BARE_TOOLCHAIN.search,
    ["flutter test", "dart format lib", "cd app && dart analyze", "flutter pub get; echo ok", "  dart tool/i18n_check.dart"],
    ["fvm flutter test", "fvm dart format lib", "echo 'run flutter test'", "tool/check.sh",
     "/opt/flutter/bin/flutter --version", G + "commit -m 'flutter test'", "grep -r dart lib"],
)
if os.path.isfile(os.path.join(ROOT, ".fvmrc")):
    check("heredoc is not an invocation", bash_guard.bare_toolchain("cat > x.yml <<'EOF'\n  - flutter analyze\nEOF", ROOT), "")
    check("inline python is not an invocation", bash_guard.bare_toolchain("python3 - <<'PY'\nprint('flutter test')\nPY", ROOT), "")
cases(
    "bare cargo update",
    bash_guard.CARGO_UPDATE_BARE.search,
    ["cargo update", "cd backend && cargo update", "cargo +1.99.0 update", "cargo update --verbose"],
    ["cargo update -p tokio", "cargo update --package tokio", "cargo update --workspace", "cargo update --dry-run",
     "cargo build", "echo 'never run cargo update -p'"],
)
cases(
    "database drop",
    bash_guard.DB_DROP.search,
    ["sqlx database drop -y", "sqlx database reset", "sqlx migrate revert", "psql $DATABASE_URL -c 'DROP TABLE places'",
     "psql -c \"truncate places\""],
    ["sqlx database create", "sqlx migrate run", "psql -c 'select 1'", "cargo sqlx prepare"],
)

RM = "rm "
cases(
    "computed recursive rm",
    bash_guard.RM_COMPUTED.search,
    [RM + '-rf "$tmpd"', RM + "-r $X/build", RM + "-rf build/*", RM + "-fr `pwd`/x", RM + "--recursive $(dirname x)",
     "cd /tmp && " + RM + "-Rf ./a?b"],
    [RM + "-rf /home/dev/lunaway/data/tmp/infra", RM + "file.txt", RM + "-f $FILE", RM + "-rf data/tmp/x",
     G + "rm --cached app/x.dart", "echo \"never " + RM + "-rf $x\"", "printf '%s' 'no " + RM + "-r *'"],
)
cases(
    "shell -c with rm",
    bash_guard.SHELL_C_RM.search,
    ["bash -c 'cd x; " + RM + "-rf y'", "sh -c \"" + RM + "a\"", "bash -lc 'make && " + RM + "out'"],
    ["bash -c 'echo hi'", "sh tool/setup.sh", "bash infra/provision.sh", RM + "a && bash x.sh",
     "printf '%s' \"no sh -c with " + RM + "here\"", "echo 'bash -c is banned; " + RM + "too'"],
)
cases(
    "secret print",
    bash_guard.SECRET_PRINT.search,
    ["cat ~/.config/lunaway/env", "cat .env", "head backend/.env", "cat app/android/key.properties", "xxd upload.jks"],
    ["cat .env.example", "cut -d= -f1 ~/.config/lunaway/env", "stat .env", "cat README.md", "cat app/lib/env_config.dart"],
)

check("a heredoc written by cat is text",
      bash_guard.strip_text_heredocs("cat > x.md <<'EOF'\n" + RM + "-rf $x\nEOF\necho done"), "cat > x.md <<'EOF'\necho done")
check("a heredoc fed to bash is code",
      bash_guard.strip_text_heredocs("bash <<'EOF'\n" + RM + "-rf $x\nEOF"), "bash <<'EOF'\n" + RM + "-rf $x\nEOF")
check("a command after the heredoc is still read",
      "rm -rf $y" in bash_guard.strip_text_heredocs("cat > a <<EOF\ntext\nEOF\n" + RM + "-rf $y"), True)
# Edit guard: dashes, generated files, secrets, committed migrations.
check("dash in new_string, not in old", edit_guard.introduced_dash("Edit", {"old_string": "a, b", "new_string": "a " + EM + " b"}, ""), True)
check("dash already in old_string", edit_guard.introduced_dash("Edit", {"old_string": "a " + EM + " b", "new_string": "a " + EN + " b"}, ""), False)
check("no dash", edit_guard.introduced_dash("Edit", {"old_string": "a", "new_string": "b"}, ""), False)
check("write to new file with dash", edit_guard.introduced_dash("Write", {"content": "x " + EN + " y"}, "/nonexistent/file.md"), True)
with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as tmp:
    tmp.write("old " + EM + " text\n")
check("write to file that has a dash", edit_guard.introduced_dash("Write", {"content": "x " + EN + " y"}, tmp.name), False)
os.unlink(tmp.name)
check("multiedit introduces",
      edit_guard.introduced_dash("MultiEdit", {"edits": [{"old_string": "a", "new_string": "b"},
                                                          {"old_string": "c", "new_string": "c " + EM + " d"}]}, ""), True)


def generated(rel):
    return any(p.search(rel) for p, _ in edit_guard.GENERATED)


for rel, want in [("app/lib/core/router/router.g.dart", True), ("app/lib/i18n/strings.g.dart", True),
                  ("app/lib/x.freezed.dart", True), ("app/pubspec.lock", True), ("backend/Cargo.lock", True),
                  ("backend/.sqlx/query-abc.json", True), ("schema/lunaway.graphql", True),
                  ("app/packages/lunaway_nav/rust/Cargo.lock", True),
                  ("app/packages/lunaway_nav/lib/src/rust/frb_generated.dart", True),
                  ("app/packages/lunaway_nav/rust/src/frb_generated.rs", True),
                  ("app/packages/lunaway_nav/rust/src/session.rs", False),
                  ("app/lib/main.dart", False), ("app/lib/i18n/en.i18n.json", False), ("backend/Cargo.toml", False)]:
    check("generated " + rel, generated(rel), want)
for rel, want in [(".env", True), (".env.example", False), ("app/android/key.properties", True),
                  ("app/android/app/upload.jks", True), ("app/ios/key.p8", True), ("app/lib/env.dart", False)]:
    check("secret path " + rel, bool(edit_guard.SECRETS.search(rel)), want)
check("migration path", bool(edit_guard.MIGRATION.search("backend/migrations/20261006000000_init.sql")), True)
check("not a migration", bool(edit_guard.MIGRATION.search("backend/crates/x/src/lib.rs")), False)

# Leak guard: a stand-in term, so this file never carries a real one.
TERM = "zorblax"
check("denied term found case-insensitively", edit_guard.denied_term("see " + TERM.upper() + " here", [TERM]), TERM)
check("no denied term", edit_guard.denied_term("nothing here", [TERM]), "")
check("new text of a write", edit_guard.new_text("Write", {"content": "abc"}), "abc")
check("new text of a multiedit",
      edit_guard.new_text("MultiEdit", {"edits": [{"new_string": "a"}, {"new_string": "b"}]}), "a\nb")
CHECK_LEAKS = os.path.join(ROOT, "tool", "harness", "git", "check_leaks.sh")
with tempfile.TemporaryDirectory() as repo:
    def gitl(*args):
        subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null"] + list(args), cwd=repo,
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def leaks(*args):
        p = subprocess.run(["sh", CHECK_LEAKS] + list(args), cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                           encoding="utf-8", errors="replace")
        return p.returncode

    gitl("init", "-q")
    with open(os.path.join(repo, "a.md"), "w", encoding="utf-8") as f:
        f.write("clean line\n")
    gitl("add", "a.md")
    check("leaks: no denylist, nothing to check", leaks("--cached"), 0)
    with open(os.path.join(repo, ".leak-denylist"), "w", encoding="utf-8") as f:
        f.write(TERM + "\n")
    check("leaks: clean staged lines pass", leaks("--cached"), 0)
    with open(os.path.join(repo, "a.md"), "w", encoding="utf-8") as f:
        f.write("clean line\nthe " + TERM.capitalize() + " source\n")
    gitl("add", "a.md")
    check("leaks: a staged line with the term is refused", leaks("--cached"), 1)
    with open(os.path.join(repo, "msg.txt"), "w", encoding="utf-8") as f:
        f.write("feat(x) : import " + TERM + "\n")
    check("leaks: a commit message with the term is refused", leaks("--message", os.path.join(repo, "msg.txt")), 1)
    with open(os.path.join(repo, "msg.txt"), "w", encoding="utf-8") as f:
        f.write("feat(x) : import generic feed\n")
    check("leaks: a clean commit message passes", leaks("--message", os.path.join(repo, "msg.txt")), 0)

# Post-edit routes each file to its gate.
for rel, want in [("app/lib/i18n/fr.i18n.json", "tool/i18n_check.dart"), ("tool/allowed_hosts.txt", "tool/structure_check.dart"),
                  ("AGENTS.md", "tool/harness/git/check_harness.sh"), ("backend/deny.toml", "tool/structure_rs.sh"),
                  ("app/lib/main.dart", None)]:
    check("post-edit gate for " + rel, post_edit.route(rel), want)

# The repository marker recognises this tree and nothing above it.
check("repo root found from a subdirectory", harness_common.repo_root(os.path.join(ROOT, "app", "lib")), ROOT)
check("no repo root outside", harness_common.repo_root(tempfile.gettempdir()), None)

# Fail-open smoke test: every hook exits 0 and prints nothing on garbage stdin
# and outside the repository.
for script in ["bash_guard.py", "edit_guard.py", "post_edit.py", "session_preflight.py", "agent_liveness.py"]:
    for stdin in ["", "not json", json.dumps({"tool_name": "Bash", "tool_input": {"command": G + "reset --hard"}, "cwd": tempfile.gettempdir()})]:
        p = subprocess.run([sys.executable, os.path.join(HOOKS, script)], input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           text=True, encoding="utf-8", errors="replace", cwd=tempfile.gettempdir())
        check("%s fails open on %r" % (script, stdin[:12]), (p.returncode, p.stdout.strip()), (0, ""))


def guard(script, payload):
    p = subprocess.run([sys.executable, os.path.join(HOOKS, script)], input=json.dumps(payload), stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace")
    return p.returncode, "BLOCKED" in p.stderr


# Inside the repo, the guards block with exit 2 and a reason.
check("bash_guard blocks in repo", guard("bash_guard.py", {"tool_name": "Bash", "tool_input": {"command": G + "stash"}, "cwd": ROOT}), (2, True))
check("bash_guard blocks a bare cargo update", guard("bash_guard.py", {"tool_name": "Bash", "tool_input": {"command": "cargo update"}, "cwd": ROOT}), (2, True))
check("bash_guard lets a heredoc mention cargo update",
      guard("bash_guard.py", {"tool_name": "Bash", "tool_input": {"command": "cat > x.md <<'EOF'\ncargo update\nEOF"}, "cwd": ROOT}), (0, False))
check("edit_guard blocks a generated file",
      guard("edit_guard.py", {"tool_name": "Write", "tool_input": {"file_path": os.path.join(ROOT, "schema", "lunaway.graphql"), "content": "x"}, "cwd": ROOT}),
      (2, True))
check("bash_guard lets a cat heredoc describe rm",
      guard("bash_guard.py", {"tool_name": "Bash", "tool_input": {"command": "cat > d.md <<'EOF'\nno " + RM + "-rf $x here\nEOF"}, "cwd": ROOT}),
      (0, False))
check("bash_guard blocks a computed rm after a heredoc",
      guard("bash_guard.py", {"tool_name": "Bash", "tool_input": {"command": "cat > d.md <<'EOF'\nx\nEOF\n" + RM + "-rf \"$d\""}, "cwd": ROOT}),
      (2, True))
check("edit_guard blocks a dash",
      guard("edit_guard.py", {"tool_name": "Write", "tool_input": {"file_path": os.path.join(ROOT, "docs", "new.md"), "content": "a " + EM + " b"}, "cwd": ROOT}),
      (2, True))

# The lock check refuses a pubspec.lock resolving a package from a path and a
# Cargo.lock resolving a crate from git, staged or committed.
HOSTED = "packages:\n  go_router:\n    dependency: \"direct main\"\n    description:\n      name: go_router\n      url: \"https://pub.dev\"\n    source: hosted\n    version: \"18.0.2\"\n"
LOCAL = "packages:\n  durt:\n    dependency: \"direct main\"\n    description:\n      path: \"../durt\"\n      relative: true\n    source: path\n    version: \"1.0.0\"\n"
# The app's own package, committed under app/packages/, resolves on every
# clone; a path that climbs out of it does not.
IN_REPO = "packages:\n  lunaway_nav:\n    dependency: \"direct main\"\n    description:\n      path: \"packages/lunaway_nav\"\n      relative: true\n    source: path\n    version: \"0.1.0\"\n"
VENDORED = "packages:\n  maplibre_gl_web:\n    dependency: \"direct overridden\"\n    description:\n      path: \"third_party/maplibre_gl_web\"\n      relative: true\n    source: path\n    version: \"0.27.1\"\n"
CLIMBS = "packages:\n  x:\n    dependency: \"direct main\"\n    description:\n      path: \"packages/../../x\"\n      relative: true\n    source: path\n    version: \"0.1.0\"\n"
ABSOLUTE = "packages:\n  x:\n    dependency: \"direct main\"\n    description:\n      path: \"/home/me/packages/x\"\n      relative: false\n    source: path\n    version: \"0.1.0\"\n"
CRATES = "[[package]]\nname = \"tokio\"\nversion = \"1.53.2\"\nsource = \"registry+https://github.com/rust-lang/crates.io-index\"\n"
GITDEP = "[[package]]\nname = \"x\"\nversion = \"0.1.0\"\nsource = \"git+https://example.org/x.git#abc\"\n"
CHECK_LOCK = os.path.join(ROOT, "tool", "harness", "git", "check_lock.sh")
with tempfile.TemporaryDirectory() as repo:
    os.makedirs(os.path.join(repo, "app", "packages", "lunaway_nav", "rust"))
    os.makedirs(os.path.join(repo, "backend"))

    def gitc(*args):
        subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null"] + list(args), cwd=repo, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def lock_check(arg, rel, content):
        with open(os.path.join(repo, rel), "w", encoding="utf-8") as f:
            f.write(content)
        gitc("add", rel)
        if arg != "--cached":
            gitc("commit", "-q", "-m", "lock")
        p = subprocess.run(["sh", CHECK_LOCK, arg], cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                           encoding="utf-8", errors="replace")
        return p.returncode

    gitc("init", "-q")
    check("lock: committed hosted pubspec.lock", lock_check("HEAD", "app/pubspec.lock", HOSTED), 0)
    check("lock: staged path pubspec.lock", lock_check("--cached", "app/pubspec.lock", LOCAL), 1)
    check("lock: committed path pubspec.lock", lock_check("HEAD", "app/pubspec.lock", LOCAL), 1)
    check("lock: staged hosted pubspec.lock", lock_check("--cached", "app/pubspec.lock", HOSTED), 0)
    check("lock: committed in-repo package", lock_check("HEAD", "app/pubspec.lock", IN_REPO), 0)
    check("lock: committed vendored package", lock_check("HEAD", "app/pubspec.lock", VENDORED), 0)
    check("lock: committed path climbing out", lock_check("HEAD", "app/pubspec.lock", CLIMBS), 1)
    check("lock: staged absolute path", lock_check("--cached", "app/pubspec.lock", ABSOLUTE), 1)
    check("lock: staged hosted again", lock_check("--cached", "app/pubspec.lock", HOSTED), 0)
    gitc("commit", "-q", "-m", "hosted")
    check("lock: staged registry Cargo.lock", lock_check("--cached", "backend/Cargo.lock", CRATES), 0)
    check("lock: staged git Cargo.lock", lock_check("--cached", "backend/Cargo.lock", GITDEP), 1)
    gitc("reset", "-q")
    nav = "app/packages/lunaway_nav/rust/Cargo.lock"
    check("lock: staged registry crate lock of the app", lock_check("--cached", nav, CRATES), 0)
    check("lock: committed git crate lock of the app", lock_check("HEAD", nav, GITDEP), 1)

# Every subprocess reading text names its encoding: `text=True` alone decodes
# with the platform codec (cp1252 on a French Windows), and git hands back UTF-8.
TEXT_KEYWORDS = ("text", "universal_newlines")


def decoding_calls_without_encoding(path):
    import ast

    try:
        tree = ast.parse(io.open(path, encoding="utf-8").read())
    except (SyntaxError, UnicodeDecodeError):
        return []
    found = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        names = {kw.arg for kw in node.keywords if kw.arg}
        if names & set(TEXT_KEYWORDS) and "encoding" not in names:
            found.append(node.lineno)
    return found


offenders = []
for base, _dirs, files in os.walk(os.path.join(ROOT, "tool", "harness")):
    for name in files:
        if name.endswith(".py"):
            full = os.path.join(base, name)
            offenders += ["%s:%d" % (os.path.relpath(full, ROOT), line) for line in decoding_calls_without_encoding(full)]
check("every decoding subprocess names its encoding", offenders, [])

if FAILURES:
    print("\n".join(FAILURES))
    print("%d failure(s)" % len(FAILURES))
    sys.exit(1)
print("test_guards: OK")
