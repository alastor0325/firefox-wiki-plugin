#!/usr/bin/env bash
# wiki-pre-lookup.sh
# PreToolUse hook: fast wiki check before searchfox-cli or dom/media grep.
# If wiki has relevant content, prints file list + snippets so Claude can
# invoke /firefox-wiki:lookup instead of searching code directly.
#
# Triggers on:
#   Bash   — only when command contains searchfox-cli
#   Grep   — only when path is under dom/media

set -euo pipefail

WIKI_PATH="${WIKI_PATH:-$HOME/firefox-wiki}"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
TERM=""

if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
    echo "$COMMAND" | grep -q "searchfox-cli" || exit 0

    # Extract query from: --define 'Foo', --id Foo, -q 'foo bar'
    TERM=$(echo "$COMMAND" \
        | grep -oE "(--define|--id|-q)\s+'[^']+'" \
        | head -1 \
        | sed "s/^[^ ]* *'//" \
        | sed "s/'$//" \
        || true)

    # Fallback: last bare word argument
    if [[ -z "$TERM" ]]; then
        TERM=$(echo "$COMMAND" \
            | grep -oE "(--define|--id|-q)\s+[^ ]+" \
            | head -1 \
            | awk '{print $2}' \
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

# Search wiki (max 3 files to avoid flooding context)
MATCHED_FILES=$(rg "$TERM" "$WIKI_PATH" --include="*.md" -l 2>/dev/null | head -3 || true)
[[ -z "$MATCHED_FILES" ]] && exit 0

echo "[WIKI HIT] '$TERM' found in wiki — run /firefox-wiki:lookup '$TERM' before searching code."
while IFS= read -r FILE; do
    REL="${FILE#$WIKI_PATH/}"
    SNIPPET=$(rg "$TERM" "$FILE" -m 1 --no-heading --no-line-number 2>/dev/null \
        | head -c 120 || true)
    echo "  $REL: $SNIPPET"
done <<< "$MATCHED_FILES"
