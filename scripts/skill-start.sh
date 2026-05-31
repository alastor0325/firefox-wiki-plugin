#!/usr/bin/env bash
# skill-start.sh
# PreToolUse hook on the Skill tool. Generates a UUID instance_id, pushes
# it onto a per-session skill stack, and writes a session_start event to
# usage-log.jsonl. Subsequent wiki events (pre_lookup, wiki_read) within
# this skill's run get tagged with the same instance_id via _active-skill.sh.
#
# Filters: only acts on skills listed in wiki-relevant-skills.txt. Other
# skills get silent exit-0 so the rest of the Skill tool surface is
# untouched.

set -euo pipefail

# Suppress hooks in background wiki maintenance agents to avoid noise
[[ "${WIKI_SKIP_HOOKS:-}" == "1" ]] && exit 0

WIKI_PATH="${WIKI_PATH:-$HOME/firefox-wiki}"
LOG="$WIKI_PATH/usage-log.jsonl"
[[ -f "$LOG" ]] || exit 0  # wiki not initialized — silently no-op

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/_stack-lib.sh"

INPUT=$(cat)

SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // ""')
[[ -z "$SKILL" ]] && exit 0

ALLOWLIST="$PLUGIN_ROOT/scripts/wiki-relevant-skills.txt"
[[ -f "$ALLOWLIST" ]] || exit 0
grep -qxF "$SKILL" "$ALLOWLIST" 2>/dev/null || exit 0

SESSION_ID=$(stack_session_id "$INPUT")
mkdir -p "$HOME/.claude/state"
STACK=$(stack_path "$SESSION_ID")

INSTANCE_ID=$(uuidgen 2>/dev/null \
    || python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null \
    || echo "fallback-$$-$(date +%s)")

ARGS=$(echo "$INPUT" | jq -c '.tool_input.args // null')
TS=$(stack_now)

# Push onto the stack under lock (parallel sub-agents may share it).
stack_lock "$STACK"
trap 'stack_unlock "$STACK"' EXIT
[[ -f "$STACK" ]] || echo "[]" > "$STACK"
TMP=$(mktemp)
if jq --arg id "$INSTANCE_ID" \
      --arg skill "$SKILL" \
      --arg ts "$TS" \
      --argjson args "$ARGS" \
      '. + [{instance_id: $id, skill: $skill, args: $args, started_at: $ts}]' \
      "$STACK" > "$TMP" 2>/dev/null; then
    mv "$TMP" "$STACK"
else
    # Corrupt stack (e.g. an interrupted concurrent write) — reset to just
    # this entry rather than losing the hook entirely.
    rm -f "$TMP"
    jq -cn --arg id "$INSTANCE_ID" --arg skill "$SKILL" --arg ts "$TS" --argjson args "$ARGS" \
        '[{instance_id: $id, skill: $skill, args: $args, started_at: $ts}]' > "$STACK"
fi
stack_unlock "$STACK"
trap - EXIT

USER_EMAIL=$(git -C "$WIKI_PATH" config user.email 2>/dev/null || echo "unknown")
jq -cn \
    --arg date "$TS" \
    --arg user "$USER_EMAIL" \
    --arg sid "$SESSION_ID" \
    --arg iid "$INSTANCE_ID" \
    --arg skill "$SKILL" \
    --argjson args "$ARGS" \
    '{date: $date, event_type: "session_start", user: $user,
      claude_session: $sid, instance_id: $iid, skill: $skill, args: $args}' \
    >> "$LOG"

exit 0
