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

# Load shared config helpers — the search tool and trigger paths are
# configurable via $WIKI_PATH/wiki-config.json or env. Defensive: if the lib is
# missing, define shims reproducing the original hardcoded behavior so a broken
# install never breaks Bash/Grep tool calls.
WIKI_CFG_LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/_wiki-config.sh"
[[ -f "$WIKI_CFG_LIB" ]] && source "$WIKI_CFG_LIB"
if ! declare -F wiki_cfg >/dev/null; then
    wiki_cfg() { printf '%s' "$3"; }
    # shellcheck disable=SC2086
    wiki_cfg_list() { printf '%s\n' $3; }
fi

LOG="$WIKI_PATH/usage-log.jsonl"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
TERM=""

if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
    SEARCH_TOOL=$(wiki_cfg search_tool WIKI_SEARCH_TOOL searchfox-cli)
    echo "$COMMAND" | grep -qF "$SEARCH_TOOL" || exit 0

    # Extract query from: --define 'Foo', --id Foo, -q 'foo bar' (quoted or
    # unquoted), plus the symbol/call-graph/layout queries searchfox-cli
    # supports — those searches benefit from a wiki check just as much.
    TERM=$(echo "$COMMAND" \
        | grep -oE "(--define|--id|--symbol|--calls-from|--calls-to|--field-layout|-q)\s+'[^']+'" \
        | head -1 \
        | sed "s/^[^ ]* *'//" \
        | sed "s/'$//" \
        || true)

    if [[ -z "$TERM" ]]; then
        TERM=$(echo "$COMMAND" \
            | grep -oE "(--define|--id|--symbol|--calls-from|--calls-to|--field-layout|-q)\s+[^ ]+" \
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
    # Fire only when the grep path is under one of the configured trigger paths
    # (default: dom/media). Substring match preserves the prior behavior where
    # "dom/media" matched "dom/media/mediasink".
    MATCHED_TRIGGER=0
    while IFS= read -r tp; do
        [[ -z "$tp" ]] && continue
        if echo "$GREP_PATH" | grep -qF "$tp"; then MATCHED_TRIGGER=1; break; fi
    done <<< "$(wiki_cfg_list trigger_paths WIKI_TRIGGER_PATHS "dom/media")"
    [[ "$MATCHED_TRIGGER" -eq 1 ]] || exit 0

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

# Best-effort bug id, for measurability (joins wiki use -> bug outcome in
# stats). The cwd here is the Firefox tree being searched; its worktree
# branch is named per bug. WIKI_BUG_ID overrides. null when undeterminable.
BUG_ID="${WIKI_BUG_ID:-}"
if [[ -z "$BUG_ID" ]]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    BUG_ID=$(printf '%s' "$BRANCH" | grep -oE '[0-9]{6,}' | head -1 || true)
fi

# Build a bounded set of candidate terms (additive expansion of $TERM):
#   (a) split Class::Method / ns::Foo into their identifier components
#   (b) add glossary synonyms from the precomputed aliases.txt (cheap fixed
#       -string lookup; parsing glossary.md on every hook call is too slow)
# Hard-capped at 5 candidates to keep this PreToolUse hook fast. When
# aliases.txt is absent the set is just ("$TERM") — identical to before.
ALIASES_FILE="$WIKI_PATH/aliases.txt"
CANDIDATES="$TERM"

if [[ "$TERM" == *"::"* ]]; then
    PARTS=$(printf '%s' "$TERM" | tr ':' '\n' \
        | grep -E '^[A-Za-z][A-Za-z0-9_]*$' || true)
    CANDIDATES=$(printf '%s\n%s\n' "$CANDIDATES" "$PARTS")
fi

if [[ -f "$ALIASES_FILE" ]]; then
    SYNS=""
    while IFS= read -r c; do
        [[ -z "$c" ]] && continue
        S=$(grep -iF -- "$c"$'\t' "$ALIASES_FILE" 2>/dev/null \
            | head -3 | cut -f2 || true)
        SYNS=$(printf '%s\n%s\n' "$SYNS" "$S")
    done <<< "$CANDIDATES"
    CANDIDATES=$(printf '%s\n%s\n' "$CANDIDATES" "$SYNS")
fi

# de-dup (preserving order, $TERM first), drop blanks, cap at 5
CANDIDATES=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | awk '!seen[$0]++' | head -5)

# Search wiki for each candidate (content via grep -ril, filename via
# find -iname); accumulate, stop early once 3 distinct files match.
MATCHED_FILES=""
while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    HITS=$( { grep -ril "$t" "$WIKI_PATH" --include="*.md" 2>/dev/null; \
              find "$WIKI_PATH" -iname "*${t}*.md" 2>/dev/null; } \
            | grep -v '^$' || true )
    MATCHED_FILES=$(printf '%s\n%s\n' "$MATCHED_FILES" "$HITS" \
        | grep -v '^$' | sort -u || true)
    CNT=$(printf '%s\n' "$MATCHED_FILES" | grep -c . || true)
    [[ "${CNT:-0}" -ge 3 ]] && break
done <<< "$CANDIDATES"
MATCHED_FILES=$(printf '%s\n' "$MATCHED_FILES" | grep -v '^$' | sort -u | head -3 || true)

# Tag this pre_lookup with the session's current skill (if any) so we can
# attribute it. Pass the session id from this hook's own stdin so the
# right per-session slot is consulted.
ACTIVE_SID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
ACTIVE=$(bash "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/_active-skill.sh" "$ACTIVE_SID" 2>/dev/null || true)
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
            --arg bug "$BUG_ID" \
            '{date: $date, event_type: "pre_lookup", user: $user, trigger: "hook", term: $term, tool: $tool, wiki_hit: false,
              instance_id: (if $iid == "" then null else $iid end),
              skill: (if $skill == "" then null else $skill end),
              bug_id: (if $bug == "" then null else ($bug|tonumber) end)}' >> "$LOG"
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
        --arg bug "$BUG_ID" \
        '{date: $date, event_type: "pre_lookup", user: $user, trigger: "hook", term: $term, tool: $tool, wiki_hit: true, matched_files: $files,
          instance_id: (if $iid == "" then null else $iid end),
          skill: (if $skill == "" then null else $skill end),
          bug_id: (if $bug == "" then null else ($bug|tonumber) end)}' >> "$LOG"
fi

echo "[WIKI HIT] '$TERM' found in wiki — run /firefox-wiki:lookup '$TERM' before searching code."
while IFS= read -r FILE; do
    REL="${FILE#$WIKI_PATH/}"
    SNIPPET=$(grep -im 1 "$TERM" "$FILE" 2>/dev/null | head -c 120 || true)
    echo "  $REL: $SNIPPET"
done <<< "$MATCHED_FILES"
