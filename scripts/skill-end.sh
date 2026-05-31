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

INPUT=$(cat)
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // ""')
[[ -z "$SKILL" ]] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
ALLOWLIST="$PLUGIN_ROOT/scripts/wiki-relevant-skills.txt"
[[ -f "$ALLOWLIST" ]] || exit 0
grep -qxF "$SKILL" "$ALLOWLIST" 2>/dev/null || exit 0

SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"
STACK="$HOME/.claude/state/skill-stack-$SESSION_ID.json"
[[ -f "$STACK" ]] || exit 0

TS=$(python3 -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00","Z"))' 2>/dev/null \
    || date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null \
    || date -u +%Y-%m-%dT%H:%M:%SZ)
case "$TS" in
    *".3NZ"|*"%3NZ") TS=$(date -u +%Y-%m-%dT%H:%M:%SZ) ;;
esac

# Find the rightmost matching entry and pull it out.
INSTANCE_ID=$(jq -r --arg skill "$SKILL" '
    [range(0; length) | select(.[].skill == $skill)] as $hits
    | if ($hits | length) == 0 then ""
      else . as $a | $a[$hits[-1]].instance_id
      end
' "$STACK" 2>/dev/null || echo "")

# Defensive: if the cleverer query failed, try the simpler fallback —
# strip the last element if it matches the skill we're closing.
if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "null" ]]; then
    INSTANCE_ID=$(jq -r --arg skill "$SKILL" '
        if length == 0 then ""
        elif .[-1].skill == $skill then .[-1].instance_id
        else "" end
    ' "$STACK")
fi

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "null" ]]; then
    exit 0
fi

# Drop the matched entry from the stack (only the rightmost occurrence
# of that instance_id, but instance_ids are unique so this is fine).
TMP=$(mktemp)
jq --arg id "$INSTANCE_ID" \
   '. | map(select(.instance_id != $id))' \
   "$STACK" > "$TMP" && mv "$TMP" "$STACK"

# Clean up empty stack file.
if [[ "$(jq 'length' "$STACK" 2>/dev/null)" == "0" ]]; then
    rm -f "$STACK"
fi

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
