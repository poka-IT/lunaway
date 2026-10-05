# Vendored Rust skills

Six skills in this directory come from actionbook/rust-skills:

- `m05-type-driven`, `m06-error-handling`, `m07-concurrency`,
  `m10-performance`, `m15-anti-pattern`, `domain-web`.

Source: https://github.com/actionbook/rust-skills at commit
`5c40d3ad785193231b7d0dbfb8e1eb447e5edd94`, through the copy synced on the
maintainer's machine (`~/.claude/skills/`).

Licence: MIT, as declared by the upstream README ("MIT License", section
"License"), `metadata.json` (`"license": "MIT"`) and
`.claude-plugin/plugin.json` (`"license": "MIT"`) at that commit. The README
points to a LICENSE file that does not exist at that commit (HTTP 404 on
2026-10-06); the notice is therefore this file, with the copyright of the
actionbook/rust-skills authors.

Local change: the `description` of each skill starts with "Rust code only. "
so that they do not trigger on non-Rust work. Bodies are unchanged.

To update: copy the new upstream version over these directories, keep the
description prefix, and update the commit above.
