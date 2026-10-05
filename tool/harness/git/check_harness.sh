#!/bin/sh
# The always-loaded layer stays small and wired. Runs in pre-commit and CI.
#
#   - CLAUDE.md is the one-line bridge: it imports AGENTS.md, so every agent
#     reads the same file;
#   - AGENTS.md stays under the budget that keeps it read in full (Codex stops
#     at 32 KiB; Anthropic's target is 200 lines);
#   - every path AGENTS.md routes to exists;
#   - .claude/settings.json parses and names hook scripts that exist.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
fail=0

if ! grep -qx '@AGENTS.md' CLAUDE.md 2>/dev/null; then
  echo "harness: CLAUDE.md must contain the line '@AGENTS.md' (the shared instruction file)." >&2
  fail=1
fi

lines=$(wc -l < AGENTS.md | tr -d ' ')
bytes=$(wc -c < AGENTS.md | tr -d ' ')
if [ "$lines" -gt 260 ] || [ "$bytes" -gt 24000 ]; then
  echo "harness: AGENTS.md is $lines lines / $bytes bytes; budget 260 lines / 24000 bytes. Move depth to .claude/rules/ or docs/ and route to it." >&2
  fail=1
fi

# Routed paths: every `path` in backticks that looks like a repo path.
for p in $(grep -oE '`(\.claude|\.githooks|docs|tool|app|backend|schema)/[A-Za-z0-9_./-]+`' AGENTS.md | tr -d '`' | sort -u); do
  case "$p" in */) [ -d "$p" ] || { echo "harness: AGENTS.md routes to missing directory $p" >&2; fail=1; } ;;
       *) [ -e "$p" ] || { echo "harness: AGENTS.md routes to missing path $p" >&2; fail=1; } ;;
  esac
done

if [ -f .claude/settings.json ]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' || fail=1
import json, re, sys
try:
    s = json.load(open('.claude/settings.json'))
except Exception as e:
    print('harness: .claude/settings.json does not parse: %s' % e, file=sys.stderr); sys.exit(1)
missing = []
for ev, groups in (s.get('hooks') or {}).items():
    for g in groups:
        for h in g.get('hooks', []):
            for m in re.findall(r'\$CLAUDE_PROJECT_DIR/([^"\s]+)', h.get('command', '')):
                import os
                if not os.path.exists(m): missing.append(m)
if missing:
    print('harness: .claude/settings.json names missing hook files: %s' % ', '.join(missing), file=sys.stderr); sys.exit(1)
PY
  fi
fi

[ "$fail" -eq 0 ] && echo "harness: OK ($lines lines, $bytes bytes)"
exit $fail
