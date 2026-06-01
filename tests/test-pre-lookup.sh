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

run_env() {
    local extra_env="$1"    # extra "KEY=val KEY2=val2" passed to the hook
    local desc="$2"
    local input="$3"
    local expect_hit="$4"   # "hit" or "miss"
    local expect_term="$5"  # expected extracted term (checked only on hit)

    # shellcheck disable=SC2086  # intentional split of "KEY=val KEY2=val2"
    output=$(echo "$input" | env $extra_env WIKI_PATH="$WIKI_PATH" WIKI_SKIP_HOOKS="" bash "$SCRIPT" 2>&1 || true)

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

run() { run_env "" "$1" "$2" "$3" "$4"; }

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

# --- Broadened searchfox-cli flag coverage (#3) ---

run "--symbol extracts term" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --symbol '\''AudioSink'\''"}}' \
    hit "AudioSink"

run "--calls-to with qualified name splits to class" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --calls-to '\''AudioSink::Shutdown'\''"}}' \
    hit "AudioSink::Shutdown"

run "--field-layout extracts term" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --field-layout AudioSink"}}' \
    hit "AudioSink"

# --- Qualified-name splitting (#2), no alias file required ---

run "Class::Method splits and matches class" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --id '\''AudioSink::Shutdown'\''"}}' \
    hit "AudioSink::Shutdown"

# --- Alias expansion (#2), with a temporary aliases.txt ---
# Save any real aliases.txt, install a known test mapping, restore after.
ALIASES="$WIKI_PATH/aliases.txt"
ALIASES_BAK=""
if [[ -f "$ALIASES" ]]; then ALIASES_BAK="$(mktemp)"; cp "$ALIASES" "$ALIASES_BAK"; fi
printf 'ASNK\tAudioSink\nAudioSink\tASNK\n' > "$ALIASES"

run "alias ASNK expands to AudioSink" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --id ASNK"}}' \
    hit "ASNK"

if [[ -n "$ALIASES_BAK" ]]; then mv "$ALIASES_BAK" "$ALIASES"; else rm -f "$ALIASES"; fi

# --- Configurable trigger surface (Tier 2), with a temporary wiki-config.json ---
# Save any real config, test default/file/env, restore after.
CFG="$WIKI_PATH/wiki-config.json"
CFG_BAK=""
if [[ -f "$CFG" ]]; then CFG_BAK="$(mktemp)"; cp "$CFG" "$CFG_BAK"; fi
rm -f "$CFG"

# (a) default (no config): dom/media triggers, gfx/layers does not
run "default trigger: dom/media grep hits" \
    '{"tool_name":"Grep","tool_input":{"pattern":"AudioSink","path":"dom/media"}}' \
    hit "AudioSink"
run "default trigger: gfx/layers grep ignored" \
    '{"tool_name":"Grep","tool_input":{"pattern":"AudioSink","path":"gfx/layers"}}' \
    miss ""

# (b) file config: trigger on gfx/layers instead of dom/media
printf '{"schema":1,"search_tool":"searchfox-cli","trigger_paths":["gfx/layers"]}\n' > "$CFG"
run "file config: gfx/layers grep hits" \
    '{"tool_name":"Grep","tool_input":{"pattern":"AudioSink","path":"gfx/layers/Foo"}}' \
    hit "AudioSink"
run "file config: dom/media grep now misses" \
    '{"tool_name":"Grep","tool_input":{"pattern":"AudioSink","path":"dom/media"}}' \
    miss ""
rm -f "$CFG"

# (c) env overrides win (no config file present)
run_env "WIKI_TRIGGER_PATHS=gfx/layers" "env trigger override: gfx/layers grep hits" \
    '{"tool_name":"Grep","tool_input":{"pattern":"AudioSink","path":"gfx/layers/Foo"}}' \
    hit "AudioSink"
run_env "WIKI_SEARCH_TOOL=mytool" "env search-tool override: mytool command hits" \
    '{"tool_name":"Bash","tool_input":{"command":"mytool --id AudioSink"}}' \
    hit "AudioSink"
run_env "WIKI_SEARCH_TOOL=mytool" "env search-tool override: searchfox-cli now ignored" \
    '{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --id AudioSink"}}' \
    miss ""

if [[ -n "$CFG_BAK" ]]; then mv "$CFG_BAK" "$CFG"; else rm -f "$CFG"; fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
