---
name: harness-check
description: "Audit the Lunaway agent harness for drift: context weight, rules restated instead of routed, broken routes, dead content, stale ratchets, hook health, CI parity with tool/check.sh, toolchain pins."
disable-model-invocation: true
---

Audit the harness of this repository and report drift. Do not fix anything
unless asked.

1. **Context weight.** Byte and line count of `AGENTS.md`, `CLAUDE.md`, every
   `.claude/rules/*.md` and every `CLAUDE.local.md`. Budgets: `AGENTS.md`
   260 lines / 24 KB (the wiring check refuses more), `CLAUDE.md` under 20
   lines, a rules file under 8 KB. Over budget is not automatically wrong:
   say which section should move to a rules file, a skill or `docs/`.

2. **Restatement.** For every `.claude/rules/*.md`, skill and doc, check it
   does not restate a law `AGENTS.md` already states in full; for
   `AGENTS.md`, check every rule names its gate or its depth file. A rule
   stated twice is drift.

3. **Routes.** Every path in backticks in `AGENTS.md`, in the rules and in
   `docs/harness.md` exists (`check_harness.sh` covers `AGENTS.md`; do the
   rest). Every skill listed under "Procedures" exists and every skill on
   disk is listed. Every `paths:` glob of a rules file matches at least one
   file, or names a directory the architecture plans.

4. **Dead content.** In the always-loaded files, anything describing a thing
   retired: a finished migration, a dated state, a passed deadline, a tool no
   longer used, a version that moved. Quote the line.

5. **Ratchets and residue.** `tool/structure_ratchet.json` must be `{}`; any
   entry is a regression to report with the file.
   `sh tool/harness/git/check_dashes.sh --all` must answer none.
   `fvm dart tool/i18n_check.dart` must report no unused key.

6. **Gates and hooks.** `tool/check.sh --quick` is green.
   `python3 tool/harness/hooks/tests/test_guards.py` and
   `python3 tool/harness/hooks/tests/test_agent_liveness.py` pass. Each hook
   exits 0 with no output on empty stdin and outside the repository.
   `.claude/settings.json` names only files that exist. `git config
   core.hooksPath` answers `.githooks` in this clone.

7. **Pins.** `.fvmrc` matches the Flutter the CI installs;
   `backend/rust-toolchain.toml` matches the Rust the CI installs;
   `backend/deny.toml` and `backend/.cargo/audit.toml` ignore the same
   advisories (`tool/structure_rs.sh` checks it).

8. **Tree hygiene.** `git worktree list`: report worktrees inside the
   repository or marked prunable. Report any tracked file at the root that is
   a report, a plan or a scratch note rather than code or documentation, and
   confirm `plan/` is ignored (`git check-ignore plan/PLAN.md`).

9. **CI.** The jobs of `.github/workflows/ci.yml` run the same commands as
   `tool/check.sh`; report any command present in one and not the other.

End with a short verdict table and the single highest-value fix.
