#!/usr/bin/env bash
# _wiki-config.sh — shared config helpers for the wiki hooks. SOURCED, not run.
#
# Precedence for every setting: env var > $WIKI_PATH/wiki-config.json > default.
# The built-in defaults equal the previously-hardcoded values, so when neither
# an env override nor a config file is present the hooks behave exactly as
# before. bash 3.2 safe: no mapfile, no associative arrays; the env layer uses
# indirect expansion ${!name}.

WIKI_PATH="${WIKI_PATH:-$HOME/firefox-wiki}"
WIKI_PATH="${WIKI_PATH%/}"                 # strip any trailing slash
WIKI_CONFIG_FILE="$WIKI_PATH/wiki-config.json"

# wiki_cfg <json_key> <ENV_VAR_NAME> <default> -> echoes a scalar value.
wiki_cfg() {
    local key="$1" envname="$2" default="$3" val=""
    val="${!envname:-}"
    if [[ -n "$val" ]]; then printf '%s' "$val"; return 0; fi
    if [[ -f "$WIKI_CONFIG_FILE" ]]; then
        val=$(jq -r --arg k "$key" '.[$k] // empty' "$WIKI_CONFIG_FILE" 2>/dev/null || true)
        if [[ -n "$val" ]]; then printf '%s' "$val"; return 0; fi
    fi
    printf '%s' "$default"
}

# wiki_cfg_list <json_key> <ENV_VAR_NAME> <default-space-separated>
# -> echoes the list one item per line. The env var is space-separated.
wiki_cfg_list() {
    local key="$1" envname="$2" default="$3" val=""
    val="${!envname:-}"
    if [[ -n "$val" ]]; then
        # shellcheck disable=SC2086  # intentional split of space-separated env
        printf '%s\n' $val
        return 0
    fi
    if [[ -f "$WIKI_CONFIG_FILE" ]]; then
        val=$(jq -r --arg k "$key" '.[$k][]? // empty' "$WIKI_CONFIG_FILE" 2>/dev/null || true)
        if [[ -n "$val" ]]; then printf '%s\n' "$val"; return 0; fi
    fi
    # shellcheck disable=SC2086  # intentional split of the space-separated default
    printf '%s\n' $default
}

# wiki_under_path <abs_file_path> -> 0 if the file is under the resolved
# WIKI_PATH (boundary match, so firefox-wiki-backup does NOT match firefox-wiki).
wiki_under_path() {
    local f="$1"
    [[ -n "$f" ]] || return 1
    case "$f" in
        "$WIKI_PATH"|"$WIKI_PATH"/*) return 0 ;;
        *) return 1 ;;
    esac
}
