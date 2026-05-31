#!/bin/bash
# Logs wiki Read events to usage-log.jsonl.
# Called by PostToolUse(Read) hook. Receives hook JSON on stdin.

set -euo pipefail

# Suppress hooks in background wiki maintenance agents to avoid noise
[[ "${WIKI_SKIP_HOOKS:-}" == "1" ]] && exit 0

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
  ACTIVE_SID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
  ACTIVE=$(bash "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/scripts/_active-skill.sh" "$ACTIVE_SID" 2>/dev/null || true)
  read -r ACTIVE_IID ACTIVE_SKILL <<< "${ACTIVE:-}" || true
  ACTIVE_IID="${ACTIVE_IID:-}"
  ACTIVE_SKILL="${ACTIVE_SKILL:-}"
  jq -cn \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg user "$USER_EMAIL" \
    --arg file "$REL_FILE" \
    --arg iid "$ACTIVE_IID" \
    --arg skill "$ACTIVE_SKILL" \
    '{date: $date, event_type: "wiki_read", user: $user, trigger: "hook", file: $file, query: null, bug_id: null,
      instance_id: (if $iid == "" then null else $iid end),
      skill: (if $skill == "" then null else $skill end)}' >> "$LOG"
fi
