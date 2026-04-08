#!/usr/bin/env bash
# tests/test-pre-lookup.sh
# Regression tests for scripts/wiki-pre-lookup.sh
#
# Usage: bash tests/test-pre-lookup.sh
#
# Requires: a populated ~/firefox-wiki/ (AudioSink.md and MFCDMProxy.md must exist)

set -euo pipefail

SCRIPT="$(dirname "$0")/../scripts/wiki-pre-lookup.sh"
WIKI_PATH="${WIKI_PATH:-$HOME/firefox-wiki}"
PASS=0
FAIL=0

run() {
    local desc="$1"
    local input="$2"
    local expect_hit="$3"   # "hit" or "miss"
    local expect_term="$4"  # expected extracted term (checked only on hit)

    output=$(echo "$input" | WIKI_PATH="$WIKI_PATH" WIKI_SKIP_HOOKS="" bash "$SCRIPT" 2>&1 || true)

    if [[ "$expect_hit" == "hit" ]]; then
        if echo "$output" | grep -q "\[WIKI HIT\]"; then
            if [[ -n "$expect_term" ]] && ! echo "$output" | grep -q "'$expect_term'"; then
                echo "FAIL [$desc]: hit but wrong term — expected '$expect_term'"
                echo "     output: $output"
                FAIL=$((FAIL+1))
            else
                echo "PASS [$desc]"
                PASS=$((PASS+1))
            fi
        else
            echo "FAIL [$desc]: expected hit, got miss"
            echo "     output: $output"
            FAIL=$((FAIL+1))
        fi
    else
        if echo "$output" | grep -q "\[WIKI HIT\]"; then
            echo "FAIL [$desc]: expected miss, got hit"
            echo "     output: $output"
            FAIL=$((FAIL+1))
        else
            echo "PASS [$desc]"
            PASS=$((PASS+1))
        fi
    fi
}

# --- Bash/searchfox-cli tests ---

run "quoted --define" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --define '\''AudioSink'\''"}}' \
    hit "AudioSink"

run "quoted --id" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --id AudioSink -l 50"}}' \
    hit "AudioSink"

run "bare CamelCase arg (new)" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --cpp AudioSink"}}' \
    hit "AudioSink"

run "case-insensitive content match (new)" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --define audiosink"}}' \
    hit "audiosink"

run "filename match via find (new)" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --cpp MFCDMProxy"}}' \
    hit "MFCDMProxy"

run "non-searchfox bash command ignored" \
    '{"tool_name":"Bash","tool_input":{"command":"git log --oneline -5"}}' \
    miss ""

run "unknown term produces miss" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --define ThisClassDoesNotExistAnywhere"}}' \
    miss ""

# --- Grep tool tests ---

run "Grep under dom/media hits wiki" \
    '{"tool_name":"Grep","tool_input":{"pattern":"AudioSink","path":"dom/media"}}' \
    hit "AudioSink"

run "Grep under dom/media with regex metacharacters stripped" \
    '{"tool_name":"Grep","tool_input":{"pattern":"AudioSink.*Open","path":"dom/media/mediasink"}}' \
    hit "AudioSink"

run "Grep outside dom/media ignored" \
    '{"tool_name":"Grep","tool_input":{"pattern":"AudioSink","path":"toolkit/components"}}' \
    miss ""

run "Read tool ignored" \
    '{"tool_name":"Read","tool_input":{"file_path":"dom/media/AudioSink.cpp"}}' \
    miss ""

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
