#!/usr/bin/env bash
# _active-skill.sh
# Print the current skill for this session as two space-separated tokens:
#
#     <instance_id> <skill>
#
# Prints nothing if no skill has been invoked yet this session (the slot
# file doesn't exist).
#
# The "current skill" is whatever skill-start.sh last wrote to the slot.
# It persists across turns until the next skill-start overwrites it, so it
# reflects the skill whose work is presently underway. See
# docs/skill-attribution.md for why this beats a start/end bracket.
#
# Arg $1 (optional): the session id, normally extracted by the caller from
# its own hook stdin (.session_id). Falls back to the env var.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/_skill-lib.sh"

SESSION_ID="${1:-}"
[[ -n "$SESSION_ID" ]] || SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"

SLOT=$(current_skill_path "$SESSION_ID")
[[ -f "$SLOT" ]] || exit 0

jq -r 'if (.skill // "") == "" then empty else "\(.instance_id) \(.skill)" end' \
    "$SLOT" 2>/dev/null || true
