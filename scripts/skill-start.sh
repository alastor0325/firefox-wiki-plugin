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

INPUT=$(cat)

# One-shot probe: capture the raw hook stdin the first time we run, so we
# can see what fields Claude Code's harness passes (transcript_path, cwd,
# agent_id, etc.). Auto-disables after the first write.
PROBE_FILE="$HOME/.claude/state/hook-input-sample.json"
if [[ ! -f "$PROBE_FILE" ]]; then
    mkdir -p "$(dirname "$PROBE_FILE")"
    printf '%s\n' "$INPUT" > "$PROBE_FILE"
fi

SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // ""')
[[ -z "$SKILL" ]] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
ALLOWLIST="$PLUGIN_ROOT/scripts/wiki-relevant-skills.txt"
[[ -f "$ALLOWLIST" ]] || exit 0
grep -qxF "$SKILL" "$ALLOWLIST" 2>/dev/null || exit 0

SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"
STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR"
STACK="$STATE_DIR/skill-stack-$SESSION_ID.json"

# Generate a unique instance_id for this skill invocation.
INSTANCE_ID=$(uuidgen 2>/dev/null \
    || python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null \
    || echo "fallback-$$-$(date +%s)")

ARGS=$(echo "$INPUT" | jq -c '.tool_input.args // null')

# ISO-8601 UTC. Prefer ms precision via python (cross-platform), then
# fall back to GNU date %3N, then plain second precision.
TS=$(python3 -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00","Z"))' 2>/dev/null \
    || date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null \
    || date -u +%Y-%m-%dT%H:%M:%SZ)
# Guard against macOS-style literal "3N" leaking through if %N is unsupported.
case "$TS" in
    *".3NZ"|*"%3NZ") TS=$(date -u +%Y-%m-%dT%H:%M:%SZ) ;;
esac

# Push onto the stack (initialize empty if missing).
[[ -f "$STACK" ]] || echo "[]" > "$STACK"
TMP=$(mktemp)
jq --arg id "$INSTANCE_ID" \
   --arg skill "$SKILL" \
   --arg ts "$TS" \
   --argjson args "$ARGS" \
   '. + [{instance_id: $id, skill: $skill, args: $args, started_at: $ts}]' \
   "$STACK" > "$TMP" && mv "$TMP" "$STACK"

# Append session-start event.
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
