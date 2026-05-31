#!/usr/bin/env bash
# skill-end.sh
# PostToolUse hook on the Skill tool. Pops the innermost matching skill
# from the per-session stack and writes a session_end event paired with
# the session_start by instance_id.
#
# Matching strategy: find the rightmost (innermost) stack entry with the
# same skill name. Tolerates LIFO nesting (skill A invokes Skill tool
# with B → B starts → B ends → A still on stack).

set -euo pipefail

[[ "${WIKI_SKIP_HOOKS:-}" == "1" ]] && exit 0

WIKI_PATH="${WIKI_PATH:-$HOME/firefox-wiki}"
LOG="$WIKI_PATH/usage-log.jsonl"
[[ -f "$LOG" ]] || exit 0

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
STACK=$(stack_path "$SESSION_ID")
[[ -f "$STACK" ]] || exit 0

TS=$(stack_now)

stack_lock "$STACK"
trap 'stack_unlock "$STACK"' EXIT

# Find the rightmost matching entry's instance_id.
INSTANCE_ID=$(jq -r --arg skill "$SKILL" '
    [range(0; length) | select(.[].skill == $skill)] as $hits
    | if ($hits | length) == 0 then ""
      else . as $a | $a[$hits[-1]].instance_id
      end
' "$STACK" 2>/dev/null || echo "")

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "null" ]]; then
    INSTANCE_ID=$(jq -r --arg skill "$SKILL" '
        if length == 0 then ""
        elif .[-1].skill == $skill then .[-1].instance_id
        else "" end
    ' "$STACK" 2>/dev/null || echo "")
fi

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "null" ]]; then
    stack_unlock "$STACK"
    trap - EXIT
    exit 0
fi

# Drop the matched entry (instance_ids are unique).
TMP=$(mktemp)
if jq --arg id "$INSTANCE_ID" 'map(select(.instance_id != $id))' "$STACK" > "$TMP" 2>/dev/null; then
    mv "$TMP" "$STACK"
else
    rm -f "$TMP"
fi

if [[ "$(jq 'length' "$STACK" 2>/dev/null || echo 0)" == "0" ]]; then
    rm -f "$STACK"
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
    '{date: $date, event_type: "session_end", user: $user,
      claude_session: $sid, instance_id: $iid, skill: $skill}' \
    >> "$LOG"

exit 0
