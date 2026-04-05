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
  jq -n \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg file "$FILE" \
    '{date: $date, event_type: "wiki_read", trigger: "hook", file: $file}' >> "$LOG"
fi
