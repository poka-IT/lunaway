@AGENTS.md

Claude-specific pointers; everything binding is in AGENTS.md.

- Skills: see "Procedures, on demand" in AGENTS.md. Subagents `app-reviewer`,
  `rust-reviewer` and `security-auditor` (read-only, opus) review a change
  before it is called done.
- `.claude/settings.json` enforces the git and writing rules through hooks. A
  block message says what to do instead; never work around one. A rule that is
  wrong is changed in the same pull request, with the reason.
- Auto-memory is machine-local. Anything the team needs goes in the repository
  (harness-maintenance skill).
