---
name: harness-maintenance
description: Where a new piece of knowledge belongs in Lunaway, and how to record it. Use when asked to update your memory, to update the rules or CLAUDE.md, to remember something, to record a decision, or when you finish work a future agent must know about. Covers the split between auto-memory, AGENTS.md, .claude/rules, docs, skills and gates, and the anti-patterns that rot a harness.
---

# Recording what you learned

Before writing anything anywhere, answer one question:

> **Who needs this, and when?**

The answer picks the destination. A rule that binds everyone stuck in one
machine's memory is invisible to the team; a one-off detail promoted to the
always-loaded file taxes every session forever.

## The decision table

| who needs it | when | destination |
|---|---|---|
| every agent, every session | always | one line in `AGENTS.md`, under the right heading, naming the gate that holds it |
| every agent touching one area | when they open a file there | `.claude/rules/<area>.md` (path-scoped) plus its row in the `AGENTS.md` table |
| every agent, for one kind of task | on demand | a skill: `.claude/skills/<name>/SKILL.md`, listed under "Procedures" |
| whoever operates CI, releases, signing | on demand | `docs/` |
| a machine, not a reader | every time | a gate (`tool/*_check.dart`, `tool/structure_rs.sh`), a hook (`tool/harness/hooks/`), a git hook, a CI job; the prose shrinks to one line |
| only you, only on this machine | while working here | auto-memory (`~/.claude/projects/<repo>/memory/`) |

**The test for auto-memory:** would this still be true and useful on another
machine, or for another agent? If yes, it does not belong in memory. Memory
is the right home for a local build quirk, a path that exists only here. It
is the wrong home for anything about the product, the rules, or how we work.

**If a rule can be checked by a script, it becomes a gate.** Enforcement
beats documentation: the dash ban and the destructive-git ban are hooks
because agents kept violating them while the rule sat in a file they had
read. `docs/harness.md` says how to add a rule to `structure_check`, a regex
to the bash guard, or a step to the preflight.

**Never Sonnet for a review or an audit; opus is the floor.** Pass `model`
explicitly when spawning an agent.

**Never restate, route.** `AGENTS.md` names a rule and points at the file
that holds its depth; a second copy diverges silently.

**`plan/` is local.** The roadmap and research notes live in the gitignored
`plan/` on the maintainer's machine. A decision that binds the code moves
from there into `AGENTS.md`, a rules file or `docs/` when it is implemented.

## "Update your memory"

1. `ls ~/.claude/projects/<repo>/memory/` and read `MEMORY.md`; update the
   file that already covers the subject rather than creating a near-duplicate.
2. Ask the promotion question. If the fact is team-wide, write it to the repo
   (this table), commit it, and keep at most a one-line pointer in memory.
   Say which destination you chose.
3. Delete what is now false: a fixed bug, a shipped plan, an expired gate.
4. Keep `MEMORY.md` exact: one line per memory, no orphan in either direction.
5. Convert relative dates to absolute.
6. Never write a secret, not even truncated.

## "Update the rules"

- `AGENTS.md` for the map and the one-line laws. It stays under the budget
  `check_harness.sh` holds (260 lines, 24 KB); depth moves out.
- `.claude/rules/<area>.md` for an area convention, with `paths:`.
- A skill for a procedure with steps, a trigger and an end state.
- A gate when the rule is mechanical.

Every harness change goes through a pull request like code, and
`tool/check.sh --quick` must stay green (it runs the hook tests and the
wiring check).

## Anti-patterns, each seen in a sibling repo

- A 26 KB instruction file loaded every turn, half of it procedures used in
  one session out of ten. That is what this harness replaced.
- A rule that contradicts itself (a rule that bans a pattern and uses it in
  its own example). A rule file is code: read it whole after editing.
- A dated status in an always-loaded file ("the map is being migrated").
  Always-loaded context must survive without maintenance.
- Planning artefacts committed at the root and never updated. Working state
  lives in the issue tracker and the pull request; a plan file goes stale
  (here it stays in the gitignored `plan/`).
- A retired thing left with a tombstone. Delete it; git history keeps it.
- Team knowledge in one machine's auto-memory.
