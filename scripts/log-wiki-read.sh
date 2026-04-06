#!/bin/bash
# Logs wiki Read events to usage-log.jsonl.
# Called by PostToolUse(Read) hook. Receives hook JSON on stdin.

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

if echo "$FILE" | grep -q "firefox-wiki/"; then
  LOG="${WIKI_PATH:-$HOME/firefox-wiki}/usage-log.jsonl"
  if [ ! -f "$LOG" ]; then
    exit 0
  fi
  WIKI_PATH_RESOLVED="${WIKI_PATH:-$HOME/firefox-wiki}"
  REL_FILE="${FILE#$WIKI_PATH_RESOLVED/}"
  USER_EMAIL=$(git -C "$WIKI_PATH_RESOLVED" config user.email 2>/dev/null || echo "unknown")
  jq -cn \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg user "$USER_EMAIL" \
    --arg file "$REL_FILE" \
    '{date: $date, event_type: "wiki_read", user: $user, trigger: "hook", file: $file, query: null, bug_id: null}' >> "$LOG"
fi
