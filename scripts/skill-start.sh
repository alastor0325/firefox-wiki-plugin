#!/usr/bin/env bash
# skill-start.sh
# PreToolUse hook on the Skill tool. Records the invoked skill as the
# "current skill" for this session (single-slot, overwritten each time)
# and writes a session_start event to usage-log.jsonl.
#
# There is deliberately NO matching end hook: PostToolUse(Skill) fires
# when the Skill tool returns its instructions text, not when the skill's
# work finishes, so an end bracket would close before any real wiki
# consultation happens. The current-skill slot instead persists across
# turns and is overwritten by the next skill-start. See
# docs/skill-attribution.md.
#
# Filters: only acts on skills listed in wiki-relevant-skills.txt. Other
# skills get silent exit-0 so the rest of the Skill tool surface is
# untouched.

set -euo pipefail

[[ "${WIKI_SKIP_HOOKS:-}" == "1" ]] && exit 0

WIKI_PATH="${WIKI_PATH:-$HOME/firefox-wiki}"
LOG="$WIKI_PATH/usage-log.jsonl"
[[ -f "$LOG" ]] || exit 0  # wiki not initialized — silently no-op

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/_skill-lib.sh"

INPUT=$(cat)

SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // ""')
[[ -z "$SKILL" ]] && exit 0

ALLOWLIST="$PLUGIN_ROOT/scripts/wiki-relevant-skills.txt"
[[ -f "$ALLOWLIST" ]] || exit 0
grep -qxF "$SKILL" "$ALLOWLIST" 2>/dev/null || exit 0

SESSION_ID=$(skill_session_id "$INPUT")
mkdir -p "$HOME/.claude/state"
SLOT=$(current_skill_path "$SESSION_ID")

INSTANCE_ID=$(uuidgen 2>/dev/null \
    || python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null \
    || echo "fallback-$$-$(date +%s)")

ARGS=$(echo "$INPUT" | jq -c '.tool_input.args // null')
TS=$(skill_now)

# Overwrite the current-skill slot atomically (mktemp + mv). Concurrent
# sub-agents racing here just settle on a last-writer-wins value, which
# is the intended semantics for "most recent skill".
TMP=$(mktemp)
jq -cn \
    --arg id "$INSTANCE_ID" \
    --arg skill "$SKILL" \
    --arg ts "$TS" \
    --argjson args "$ARGS" \
    '{instance_id: $id, skill: $skill, args: $args, started_at: $ts}' \
    > "$TMP" && mv "$TMP" "$SLOT"

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
