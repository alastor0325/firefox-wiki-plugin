#!/bin/bash
# Logs wiki Read events to usage-log.jsonl.
# Called by PostToolUse(Read) hook. Receives hook JSON on stdin.

set -euo pipefail

# Suppress hooks in background wiki maintenance agents to avoid noise
[[ "${WIKI_SKIP_HOOKS:-}" == "1" ]] && exit 0

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

# Load shared config helpers (resolves WIKI_PATH, provides wiki_under_path).
# Defensive shim reproduces the original literal gate if the lib is missing.
WIKI_PATH="${WIKI_PATH:-$HOME/firefox-wiki}"
WIKI_CFG_LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/_wiki-config.sh"
[[ -f "$WIKI_CFG_LIB" ]] && source "$WIKI_CFG_LIB"
if ! declare -F wiki_under_path >/dev/null; then
  wiki_under_path() { case "$1" in "$WIKI_PATH"|"$WIKI_PATH"/*) return 0;; *) return 1;; esac; }
fi

if wiki_under_path "$FILE"; then
  LOG="$WIKI_PATH/usage-log.jsonl"
  if [ ! -f "$LOG" ]; then
    exit 0
  fi
  REL_FILE="${FILE#$WIKI_PATH/}"
  USER_EMAIL=$(git -C "$WIKI_PATH" config user.email 2>/dev/null || echo "unknown")
  ACTIVE_SID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
  ACTIVE=$(bash "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/_active-skill.sh" "$ACTIVE_SID" 2>/dev/null || true)
  read -r ACTIVE_IID ACTIVE_SKILL <<< "${ACTIVE:-}" || true
  ACTIVE_IID="${ACTIVE_IID:-}"
  ACTIVE_SKILL="${ACTIVE_SKILL:-}"
  # Best-effort bug id from the cwd's git branch (worktrees are named per
  # bug); WIKI_BUG_ID overrides. null when undeterminable.
  BUG_ID="${WIKI_BUG_ID:-}"
  if [[ -z "$BUG_ID" ]]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    BUG_ID=$(printf '%s' "$BRANCH" | grep -oE '[0-9]{6,}' | head -1 || true)
  fi
  jq -cn \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg user "$USER_EMAIL" \
    --arg file "$REL_FILE" \
    --arg iid "$ACTIVE_IID" \
    --arg skill "$ACTIVE_SKILL" \
    --arg bug "$BUG_ID" \
    '{date: $date, event_type: "wiki_read", user: $user, trigger: "hook", file: $file, query: null,
      bug_id: (if $bug == "" then null else ($bug|tonumber) end),
      instance_id: (if $iid == "" then null else $iid end),
      skill: (if $skill == "" then null else $skill end)}' >> "$LOG"
fi
