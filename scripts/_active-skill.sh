#!/usr/bin/env bash
# Print the innermost active skill's instance_id + skill name as
# space-separated tokens on stdout, or nothing if no skill is active.
#
# Consumed by wiki-pre-lookup.sh and log-wiki-read.sh so they can tag
# their events with the skill instance that owns the current tool call.
#
# Stack file is per-Claude-session, lives in ~/.claude/state/, and is
# pushed/popped by skill-start.sh / skill-end.sh.

set -euo pipefail

SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
STACK="$HOME/.claude/state/skill-stack-$SESSION_ID.json"
[[ -f "$STACK" ]] || exit 0

jq -r '. | if length == 0 then empty else .[-1] | "\(.instance_id) \(.skill)" end' \
    "$STACK" 2>/dev/null || true
