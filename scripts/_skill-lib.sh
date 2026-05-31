#!/usr/bin/env bash
# _skill-lib.sh
# Shared helpers for skill attribution. Sourced by skill-start.sh,
# _active-skill.sh, and the wiki event hooks. Do not execute directly.
#
# Attribution model: "current skill" single slot, NOT a start/end bracket.
# PostToolUse(Skill) fires when the Skill tool returns its instructions
# text (~immediately), NOT when the skill's multi-turn work finishes, so
# an end-event bracket would close before any real wiki consultation
# happens. Instead, skill-start.sh overwrites a single slot file that
# persists across turns; wiki events attribute to whatever skill is
# currently in the slot. See docs/skill-attribution.md.

# Derive the Claude session id used to name the per-session slot file.
# Prefer the hook stdin's .session_id (passed as $1) — guaranteed present
# and correct even inside background sub-agents (they report the root
# session id). Fall back to env vars, then "unknown".
skill_session_id() {
    local input="${1:-}"
    local sid=""
    if [[ -n "$input" ]]; then
        sid=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null || true)
    fi
    [[ -n "$sid" ]] || sid="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"
    printf '%s' "$sid"
}

# Path to the current-skill slot file for a given session id.
current_skill_path() {
    printf '%s' "$HOME/.claude/state/current-skill-${1}.json"
}

# ISO-8601 UTC, millisecond precision when available (python), second
# precision otherwise. macOS `date` lacks %N.
skill_now() {
    local ts
    ts=$(python3 -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00","Z"))' 2>/dev/null \
        || date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null \
        || date -u +%Y-%m-%dT%H:%M:%SZ)
    case "$ts" in
        *".3NZ"|*"%3NZ") ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) ;;
    esac
    printf '%s' "$ts"
}
