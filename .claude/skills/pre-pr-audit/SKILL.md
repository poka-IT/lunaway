---
name: pre-pr-audit
description: Full multi-agent audit of a branch before a pull request is opened. Use when asked for "an audit", "audit par sub-agent", or before sending any PR. Fans out one read-only reviewer per dimension (security, performance, non-regression, clean code, redundancy, coherence, pertinence) and reports findings with file:line and a blocking verdict.
---

# Pre-PR audit

Before any pull request, everything done on the branch is audited by
sub-agents, one per dimension (or grouped sensibly), in parallel, each
read-only. Say explicitly that a complete sub-agent audit is being run, then
run it.

Inputs for every reviewer: `git diff origin/main...HEAD` (three dots: the
merge base, so main's newer commits do not show as reversions), the list of
changed files, and the rules of `AGENTS.md` plus the `.claude/rules/` files of
the touched areas. The repository's own reviewers carry the checklists:
`app-reviewer` for Dart, `rust-reviewer` for Rust, `security-auditor` for
anything crossing a trust boundary.

Model floor: opus for every reviewer (an audit that misses a defect costs
more than the tokens it saves).

## Dimensions

- **Security**: no leaked secret; authorization on every new resolver; input
  validated at the boundary; the app never fetching a data source
  directly (`.claude/rules/data-sources.md`); no new host outside
  `tool/allowed_hosts.txt`; no personal data (precise location, keys) in a
  log; no weakened guard.
- **Optimisation**: no repeated query where one batched call exists
  (DataLoader), sane algorithms and data structures, spatial queries backed
  by an index.
- **Performance**: no jank (heavy work off the UI thread, lists built
  lazily, map markers through the clustered source), bounded memory, bounded
  GraphQL queries.
- **Non-regression**: behaviour preserved at every call site;
  `tool/check.sh` green; the committed schema matches the code.
- **Clean code**: readable, idiomatic, matches the surrounding style;
  comments say why; English in code; no dashes.
- **Non-redundancy**: no logic duplicated from an existing helper, provider,
  service or crate; no second translation key for something already keyed;
  grep the whole branch, tests included, before calling anything dead.
- **Coherence**: fits the architecture (domain crate pure, resolvers thin,
  Riverpod codegen, three layouts, slang, source provenance on every value).
- **Pertinence**: the change solves the stated problem for a real traveller,
  the way the issue asked; nothing out of scope.

## Verify before reporting

Every finding is reproduced on the branch: read the actual file, not the
hunk; open the package source (`~/.pub-cache`, `~/.cargo/registry`) for a
claim about a dependency. A finding that does not survive verification is
retracted explicitly.

## Report

Grouped by dimension, each finding with `file:line`, the concrete failure it
causes and the fix, and a verdict: **blocking** or **nice-to-have**. Then fix
the blocking ones on the branch, rerun `tool/check.sh`, and only then open
the pull request (title and description in French).
