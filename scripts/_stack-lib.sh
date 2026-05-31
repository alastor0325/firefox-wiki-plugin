#!/usr/bin/env bash
# _stack-lib.sh
# Shared helpers for the skill-attribution stack used by skill-start.sh,
# skill-end.sh, _active-skill.sh, and the wiki event hooks.
#
# Source this file; do not execute it directly.

# Derive the Claude session id used to name the per-session stack file.
#
# Order of preference (most authoritative first):
#   1. .session_id from the hook stdin payload (passed as $1) — this is
#      guaranteed present in every hook invocation and is correct even
#      inside background sub-agents (they report the root session id).
#   2. $CLAUDE_CODE_SESSION_ID env var.
#   3. $CLAUDE_SESSION_ID env var (older Claude Code naming, just in case).
#   4. literal "unknown".
#
# NOTE: background sub-agents share the parent's session_id AND
# transcript_path (verified 2026-05-31 via parallel hook-input probe),
# so neither field disambiguates concurrent agents. The stack therefore
# can be shared across truly-parallel skill instances; _active-skill.sh
# reports an attribution confidence so consumers can exclude ambiguous
# events. See docs/skill-attribution.md.
stack_session_id() {
    local input="${1:-}"
    local sid=""
    if [[ -n "$input" ]]; then
        sid=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null || true)
    fi
    [[ -n "$sid" ]] || sid="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"
    printf '%s' "$sid"
}

# Path to the stack file for a given session id.
stack_path() {
    printf '%s' "$HOME/.claude/state/skill-stack-${1}.json"
}

# Acquire a coarse lock on the stack file via atomic mkdir. Spins up to
# ~2s (40 * 0.05s) then proceeds anyway — losing the lock is better than
# hanging a tool call. Safe across parallel sub-agents sharing one stack.
stack_lock() {
    local stack="$1"
    local lockdir="${stack}.lock"
    local i=0
    while ! mkdir "$lockdir" 2>/dev/null; do
        i=$((i + 1))
        if [[ $i -ge 40 ]]; then
            # Stale lock? Break in and take it.
            rm -rf "$lockdir" 2>/dev/null || true
            mkdir "$lockdir" 2>/dev/null || true
            break
        fi
        sleep 0.05
    done
}

stack_unlock() {
    rm -rf "${1}.lock" 2>/dev/null || true
}

# ISO-8601 UTC, millisecond precision when available, second precision
# otherwise. macOS `date` lacks %N, so prefer python.
stack_now() {
    local ts
    ts=$(python3 -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00","Z"))' 2>/dev/null \
        || date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null \
        || date -u +%Y-%m-%dT%H:%M:%SZ)
    case "$ts" in
        *".3NZ"|*"%3NZ") ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) ;;
    esac
    printf '%s' "$ts"
}
