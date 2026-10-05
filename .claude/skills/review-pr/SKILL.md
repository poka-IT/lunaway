---
name: review-pr
description: Review open pull requests of Lunaway (github.com/poka-IT/lunaway) for product relevance, safety, cleanliness, coherence, non-redundancy, hidden backdoors and obfuscation, then report and, when asked, rebase and fix. Use when asked to "review les PR", "review the PRs", "audit les PR ouvertes", or before merging anything.
---

# Reviewing pull requests

Review against the code, never against the description: every finding is
reproduced before it is reported, and verified a second time by a fresh
read-only agent (opus) before it is posted.

## Setup

```bash
gh pr list --state open
gh pr checkout <n>          # or: git fetch origin pull/<n>/head:refs/prs/<n>
git diff --stat $(git merge-base origin/main HEAD) HEAD
```

Never diff a branch against `origin/main` directly for its file list: main's
newer commits show as reversions. Use the merge base.

## The dimensions

Go through all of them for every PR, reporting per dimension with `file:line`.

1. **Pertinence produit**: does it solve the linked issue, for a real
   traveller, the way the issue asked? A clean PR that answers the wrong
   question is a finding.
2. **Sûreté**: secrets, authorization on resolvers, input validation, no
   no third-party fetch from the app, no new host, no personal data in logs.
3. **Propreté**: readable, idiomatic, matches the surrounding style, comments
   that say why.
4. **Cohérence**: the rules of `AGENTS.md` and of the touched areas'
   `.claude/rules/` files.
5. **Non-redondance**: nothing duplicated from an existing helper, provider,
   crate or translation key.
6. **Code mort**: anything nothing references, proven by a repo-wide grep on
   the PR branch.
7. **Porte dérobée, obfuscation**: the sweep below.
8. **Tests**: each new test fails without the code it covers (mutate the code
   and watch it go red when in doubt); nothing hollow.

## Backdoor and obfuscation sweep

Run it mechanically on every PR before reading for style.

```bash
base=$(git merge-base origin/main HEAD)
git diff $base HEAD | grep -nE 'base64|fromCharCode|String\.fromCharCodes|dart:mirrors|Process\.(run|start)|std::process::Command|include_bytes!|\\x[0-9a-f]{2}|\\u\{?[0-9a-f]{4}'
git diff $base HEAD | grep -nP '[\x{202A}-\x{202E}\x{2066}-\x{2069}\x{200B}-\x{200F}]'   # bidi and zero-width characters
git diff --stat $base HEAD -- '*.lock' 'app/pubspec.yaml' 'backend/**/Cargo.toml'   # dependency changes
```

Every hit is explained or is a blocker. A new dependency is read: its
licence, its maintainers, what it pulls.

## Report

Per PR: a verdict (`APPROVE` / `CHANGES REQUIRED`), the blockers with
`file:line`, the problem and the fix, then the nits. Post reviews in French
(`gh pr review <n> --comment --body-file <file>`), only when asked to post.
