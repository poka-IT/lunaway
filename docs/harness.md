# The agent harness

How Lunaway keeps any agent, and any contributor driving one, from making the
mistakes that matter: a lost working tree, a secret in git, an app that
calls a third party directly, a stale API contract, a hollow test. Three layers; put
new knowledge in the right one, the wrong layer is how a harness rots.

| layer | what belongs there | cost |
|---|---|---|
| **always loaded** | `AGENTS.md` (the map and the laws, one line each), `CLAUDE.md` (imports it, plus Claude pointers) | full text, every turn |
| **on demand** | `.claude/rules/*.md` (area conventions, loaded by Claude when a matching file is opened, read by others from the routing table), `docs/` (architecture, operations), `.claude/skills/*/SKILL.md` (procedures with steps) | a description at rest, full text when used |
| **mechanical** | `tool/*.dart` and `tool/structure_rs.sh` gates, `.githooks/`, `tool/harness/hooks/` (agent hooks), `.claude/settings.json` (deny rules), the CI jobs | zero context |

Two rules carry most of it. **If a rule can be checked by a script, it is a
gate, and the prose shrinks to one line naming the gate.** And **a retired
thing gets deleted**, not left with a note; git history keeps it.

## The pieces

| file | role |
|---|---|
| `AGENTS.md` | the shared instruction file (agents.md standard: Codex, Cursor, Copilot, OpenCode, Gemini via `.gemini/settings.json`, Claude via `CLAUDE.md`) |
| `CLAUDE.md` | `@AGENTS.md` plus Claude-only pointers |
| `.claude/rules/` | path-scoped conventions: Riverpod, screens, translations, Dart tests, Rust, SQL, GraphQL, data sources |
| `.claude/skills/` | procedures (pre-pr-audit, review-pr, ci-green, job-watching, db-migration, graphql-schema-change, data-source, harness-maintenance, harness-check) and six vendored Rust skills (`RUST_SKILLS_PROVENANCE.md`) |
| `.claude/agents/` | read-only reviewers: `app-reviewer`, `rust-reviewer`, `security-auditor` |
| `.claude/settings.json` | deny rules on secrets; hooks: bash guard, edit guard, post-edit gates, session preflight, agent liveness |
| `tool/harness/hooks/` | the hook scripts (Python, fail open, tested by `tests/`) |
| `tool/harness/git/` | shell checks shared by the git hooks, `tool/check.sh` and CI: dashes, secrets, lockfiles, harness wiring; `tool/harness/vendored.txt` lists the third-party files committed as published, which the dash check and the pre-commit formatting skip |
| `.githooks/` | pre-commit (dashes, secrets, locks, wiring, formatting, Dart and Rust structure gates), commit-msg (subject convention), pre-push (prod tag, analyses); each chains to a machine-local hook of the same name |
| `tool/structure_check.dart` | app invariants with remediation messages; `tool/allowed_hosts.txt`, `tool/structure_ratchet.json` |
| `tool/i18n_check.dart` | translation gate |
| `tool/structure_rs.sh` | backend invariants: pure domain crate, advisory parity |
| `tool/check.sh` | the whole gate, what the CI runs |
| `tool/setup.sh` | clone bootstrap |
| `opencode.json` | OpenCode permission denies (same git and secret rules) |
| `.github/workflows/ci.yml` | `harness`, `app`, `backend` jobs |

## What is enforced where

| rule | agent hook | git hook | CI |
|---|---|---|---|
| destructive git, `--no-verify`, forced push | bash guard | | |
| production tag push | bash guard | pre-push | |
| bare `flutter`/`dart` with fvm installed | bash guard | | pinned version |
| bare `cargo update`, dropping a database | bash guard | | |
| recursive `rm` on a computed path, `sh -c` scripts that remove files, printing a secret file | bash guard (heredoc bodies written by `cat`/`tee` are text and skipped) | | |
| em dash / en dash | edit guard | pre-commit (added lines), commit-msg | `harness` (whole tree) |
| generated files edited by hand | edit guard | | `app` (codegen freshness), `backend` (schema drift test) |
| committed migration edited | edit guard | | |
| secrets read or written | deny rules, edit guard | pre-commit | `harness` |
| lockfile resolving from a path or git | | pre-commit | `harness` |
| formatting | | pre-commit (rewrites) | `app`, `backend` |
| translations (parity, parameters, unused keys) | post-edit | pre-commit | `app` |
| app structure (legacy providers, print, hosts) | post-edit (data files) | pre-commit | `app` |
| backend structure (pure domain, advisory parity) | post-edit (deny files) | pre-commit | `backend` |
| `AGENTS.md` wiring and size | post-edit | pre-commit | `harness` |
| hook regressions | | | `harness` |
| analysis (`dart analyze --fatal-infos`, clippy `-D warnings`) | | pre-push | `app`, `backend` |
| dependency licences, sources, advisories | | | `backend` (cargo deny) |
| the app's guidance crate (`app/packages/lunaway_nav/rust`: fmt, clippy for the host and for WebAssembly, cargo deny with `backend/deny.toml`, tests) | edit guard (its lockfile and bridge are generated) | | `nav-crate` |
| the crate's WebAssembly build (`app/web/lunaway_nav/`, gitignored, built from source by `app/packages/lunaway_nav/tool/build_web.sh` before every web build) and the web release that serves it | | | `web` |
| one engine everywhere: the shared vectors (`app/integration_test/fixtures/engine_trace.dart`) answered by the macOS library and by each platform's build | | | `app` (host side); `integration_test/engine_vectors_test.dart` on a device or in a browser |
| tests | | | `app`, `backend` |
| commit message | | commit-msg | |
| background agent left unwatched | agent liveness (Stop) | | |

A local hook can be skipped by a human who insists (`--no-verify` outside an
agent, `LUNAWAY_SKIP_ANALYZE=1`); the CI cannot. Local hooks give fast
feedback, the server holds the line.

## Budgets

`tool/harness/git/check_harness.sh` refuses `AGENTS.md` above 260 lines or
24 000 bytes (Codex stops reading project docs at 32 KiB; Anthropic's target
is 200 lines). A rule file stays under 8 KB; a skill body over 500 lines is a
sign that reference material should move to its own file next to `SKILL.md`.

## Adding to the harness

- **A new app invariant a grep can hold**: a rule in `tool/structure_check.dart`
  with a `why` and a `fix` message (the error is the instruction). One line in
  `AGENTS.md` names the rule.
- **A new backend invariant**: a block in `tool/structure_rs.sh`, same shape.
- **A new shell mistake**: a regex in `tool/harness/hooks/bash_guard.py`, with
  block and allow cases in `tests/test_guards.py`. The command text of a tool
  call is what the guard reads, so a test that spells a forbidden command out
  cannot itself be written through an agent; assemble the string
  (`G + "stash"`). A heredoc carries text, not commands: the guards that would
  misfire on documentation exempt it.
- **A new procedure**: a skill under `.claude/skills/<name>/SKILL.md`, listed
  in `AGENTS.md` under "Procedures". Its description says when to use it.
- **A new area convention**: a `.claude/rules/<area>.md` with `paths:`
  frontmatter and a row in the "Read before touching" table.
- **A setup step**: in `tool/harness/hooks/session_preflight.py` and
  `tool/setup.sh`, never in prose asking a human.

## Testing the harness by hand

```bash
python3 tool/harness/hooks/tests/test_guards.py
python3 tool/harness/hooks/tests/test_agent_liveness.py
echo '{"tool_name":"Bash","tool_input":{"command":"cargo update"},"cwd":"'$PWD'"}' \
  | python3 tool/harness/hooks/bash_guard.py; echo "exit $?"      # 2, with the reason
sh tool/harness/git/check_harness.sh
tool/check.sh --quick
```

## Deliberately out of the gates

- `flutter analyze`: it does not load analyzer plugins, so riverpod_lint
  findings never show there (measured on 2026-10-05). Every gate runs
  `dart analyze` instead. If riverpod_lint ever slows analysis badly as the
  tree grows, it is removed from `app/analysis_options.yaml` and the Riverpod
  rules are held by the reviewer agent alone; that change says so here.
- The depth limit of the GraphQL schema is not tested yet: async-graphql
  leaves introspection out of the depth count and the schema has no nested
  type. The complexity limit is tested; the depth test arrives with the first
  nested type.
