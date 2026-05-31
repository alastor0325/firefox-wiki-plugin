#!/usr/bin/env bash
# _active-skill.sh
# Print the innermost active skill's attribution as three space-separated
# tokens on stdout:
#
#     <instance_id> <skill> <confidence>
#
# confidence is one of:
#   certain        — exactly one skill instance on the stack; instance_id
#                    and skill are both unambiguous.
#   skill-certain  — more than one instance on the stack but ALL share the
#                    same skill name (e.g. /triage fanning out parallel
#                    /bug-start sub-agents). The skill is reliable; the
#                    specific instance_id is the stack top and may not be
#                    the true owner, so treat instance_id as best-effort.
#   ambiguous      — more than one instance with DIFFERENT skill names are
#                    concurrently active. Neither skill nor instance can be
#                    trusted; consumers should record the event but exclude
#                    it from per-skill metrics.
#
# Prints nothing if no skill is active.
#
# Background sub-agents share the parent's session_id (verified 2026-05-31),
# so a single stack file can hold genuinely-parallel instances. The
# confidence token is how we stay honest about that. See
# docs/skill-attribution.md.
#
# Arg $1 (optional): the session id, normally extracted by the caller from
# its own hook stdin (.session_id). Falls back to the env var.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/_stack-lib.sh"

SESSION_ID="${1:-}"
[[ -n "$SESSION_ID" ]] || SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"

STACK=$(stack_path "$SESSION_ID")
[[ -f "$STACK" ]] || exit 0

jq -r '
    if length == 0 then empty
    else
        (.[-1]) as $top
        | (map(.skill) | unique) as $skills
        | (if length == 1 then "certain"
           elif ($skills | length) == 1 then "skill-certain"
           else "ambiguous" end) as $conf
        | "\($top.instance_id) \($top.skill) \($conf)"
    end
' "$STACK" 2>/dev/null || true
