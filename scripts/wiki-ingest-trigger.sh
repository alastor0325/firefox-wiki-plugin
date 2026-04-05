#!/bin/bash
# PostToolUse(Bash) hook: trigger /firefox-wiki:ingest --auto after git commits
# to mozilla-central or similar Firefox repos (not the wiki repo itself).

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

echo "$COMMAND" | grep -q "git commit" || exit 0

REMOTE=$(git remote get-url origin 2>/dev/null || echo "")

# Match Firefox repos but not the wiki repo
echo "$REMOTE" | grep -qE '(mozilla-central|gecko)' || exit 0
echo "$REMOTE" | grep -q "firefox-wiki" && exit 0

claude -p '/firefox-wiki:ingest --auto' || true
