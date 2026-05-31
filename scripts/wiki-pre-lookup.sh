#!/usr/bin/env bash
# wiki-pre-lookup.sh
# PreToolUse hook: fast wiki check before searchfox-cli or dom/media grep.
# If wiki has relevant content, prints file list + snippets so Claude can
# invoke /firefox-wiki:lookup instead of searching code directly.
# Logs hit/miss to usage-log.jsonl for hit rate tracking.
#
# Triggers on:
#   Bash   — only when command contains searchfox-cli
#   Grep   — only when path is under dom/media

set -euo pipefail

# Suppress hooks in background wiki maintenance agents to avoid noise
[[ "${WIKI_SKIP_HOOKS:-}" == "1" ]] && exit 0

WIKI_PATH="${WIKI_PATH:-$HOME/firefox-wiki}"
LOG="$WIKI_PATH/usage-log.jsonl"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
TERM=""

if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
    echo "$COMMAND" | grep -q "searchfox-cli" || exit 0

    # Extract query from: --define 'Foo', --id Foo, -q 'foo bar' (quoted or unquoted)
    TERM=$(echo "$COMMAND" \
        | grep -oE "(--define|--id|-q)\s+'[^']+'" \
        | head -1 \
        | sed "s/^[^ ]* *'//" \
        | sed "s/'$//" \
        || true)

    if [[ -z "$TERM" ]]; then
        TERM=$(echo "$COMMAND" \
            | grep -oE "(--define|--id|-q)\s+[^ ]+" \
            | head -1 \
            | awk '{print $2}' \
            || true)
    fi

    # Fallback: last CamelCase or MixedCase identifier in the command
    # Catches bare args like: searchfox-cli --cpp AudioSink
    if [[ -z "$TERM" ]]; then
        TERM=$(echo "$COMMAND" \
            | grep -oE '\b[A-Z][A-Za-z0-9]{3,}\b' \
            | tail -1 \
            || true)
    fi

elif [[ "$TOOL_NAME" == "Grep" ]]; then
    GREP_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // ""')
    echo "$GREP_PATH" | grep -q "dom/media" || exit 0

    # Strip regex metacharacters, take first meaningful word
    TERM=$(echo "$INPUT" \
        | jq -r '.tool_input.pattern // ""' \
        | sed 's/[.*+?^${}()|[\]\\]//g' \
        | grep -oE '[A-Za-z][A-Za-z0-9_]{3,}' \
        | head -1 \
        || true)
else
    exit 0
fi

[[ -z "$TERM" || ! -f "$WIKI_PATH/INDEX.md" ]] && exit 0

USER_EMAIL=$(git -C "$WIKI_PATH" config user.email 2>/dev/null || echo "unknown")
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Search wiki:
# 1. Case-insensitive content search (grep -ril)
# 2. Case-insensitive filename match (find -iname)
# Combine results, deduplicate, limit to 3 files
CONTENT_MATCHES=$(grep -ril "$TERM" "$WIKI_PATH" --include="*.md" 2>/dev/null || true)
FILENAME_MATCHES=$(find "$WIKI_PATH" -iname "*${TERM}*.md" 2>/dev/null || true)
MATCHED_FILES=$(printf '%s\n%s\n' "$CONTENT_MATCHES" "$FILENAME_MATCHES" \
    | grep -v '^$' \
    | sort -u \
    | head -3 \
    || true)

# Tag this pre_lookup with the session's current skill (if any) so we can
# attribute it. Pass the session id from this hook's own stdin so the
# right per-session slot is consulted.
ACTIVE_SID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
ACTIVE=$(bash "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/scripts/_active-skill.sh" "$ACTIVE_SID" 2>/dev/null || true)
read -r ACTIVE_IID ACTIVE_SKILL <<< "${ACTIVE:-}" || true
ACTIVE_IID="${ACTIVE_IID:-}"
ACTIVE_SKILL="${ACTIVE_SKILL:-}"

if [[ -z "$MATCHED_FILES" ]]; then
    if [[ -f "$LOG" ]]; then
        jq -cn \
            --arg date "$DATE" \
            --arg user "$USER_EMAIL" \
            --arg term "$TERM" \
            --arg tool "$TOOL_NAME" \
            --arg iid "$ACTIVE_IID" \
            --arg skill "$ACTIVE_SKILL" \
            '{date: $date, event_type: "pre_lookup", user: $user, trigger: "hook", term: $term, tool: $tool, wiki_hit: false,
              instance_id: (if $iid == "" then null else $iid end),
              skill: (if $skill == "" then null else $skill end)}' >> "$LOG"
    fi
    exit 0
fi

# Hit: log and print context for Claude
if [[ -f "$LOG" ]]; then
    MATCHED_JSON=$(echo "$MATCHED_FILES" | awk -v wp="$WIKI_PATH/" '{gsub(wp,"",$0); printf "\"%s\",", $0}' | sed 's/,$//')
    jq -cn \
        --arg date "$DATE" \
        --arg user "$USER_EMAIL" \
        --arg term "$TERM" \
        --arg tool "$TOOL_NAME" \
        --argjson files "[$MATCHED_JSON]" \
        --arg iid "$ACTIVE_IID" \
        --arg skill "$ACTIVE_SKILL" \
        '{date: $date, event_type: "pre_lookup", user: $user, trigger: "hook", term: $term, tool: $tool, wiki_hit: true, matched_files: $files,
          instance_id: (if $iid == "" then null else $iid end),
          skill: (if $skill == "" then null else $skill end)}' >> "$LOG"
fi

echo "[WIKI HIT] '$TERM' found in wiki — run /firefox-wiki:lookup '$TERM' before searching code."
while IFS= read -r FILE; do
    REL="${FILE#$WIKI_PATH/}"
    SNIPPET=$(grep -im 1 "$TERM" "$FILE" 2>/dev/null | head -c 120 || true)
    echo "  $REL: $SNIPPET"
done <<< "$MATCHED_FILES"
