#!/usr/bin/env bash
# tests/test-wiki-config.sh
# Unit tests for scripts/_wiki-config.sh (wiki_cfg, wiki_cfg_list, wiki_under_path).
#
# Usage: bash tests/test-wiki-config.sh
# Dependency-free; uses a throwaway wiki under mktemp.

set -uo pipefail

LIB="$(dirname "$0")/../scripts/_wiki-config.sh"
PASS=0
FAIL=0

check() {
    local desc="$1" cond="$2" detail="${3:-}"
    if [[ "$cond" == "0" ]]; then
        echo "PASS [$desc]"; PASS=$((PASS+1))
    else
        echo "FAIL [$desc]${detail:+: $detail}"; FAIL=$((FAIL+1))
    fi
}

# --- Trailing-slash stripping ---------------------------------------------
TMP=$(mktemp -d)
out=$( WIKI_PATH="$TMP/my-wiki/" bash -c 'source "$1"; printf "%s" "$WIKI_PATH"' _ "$LIB" )
check "trailing slash stripped from WIKI_PATH" "$([[ "$out" == "$TMP/my-wiki" ]] && echo 0 || echo 1)" "$out"

# --- wiki_cfg precedence: default < file < env ----------------------------
mkdir -p "$TMP/my-wiki"

# default (no file, no env)
out=$( WIKI_PATH="$TMP/my-wiki" bash -c 'source "$1"; wiki_cfg search_tool WIKI_SEARCH_TOOL searchfox-cli' _ "$LIB" )
check "wiki_cfg default" "$([[ "$out" == "searchfox-cli" ]] && echo 0 || echo 1)" "$out"

# file beats default
echo '{"schema":1,"search_tool":"mytool","trigger_paths":["gfx/layers"]}' > "$TMP/my-wiki/wiki-config.json"
out=$( WIKI_PATH="$TMP/my-wiki" bash -c 'source "$1"; wiki_cfg search_tool WIKI_SEARCH_TOOL searchfox-cli' _ "$LIB" )
check "wiki_cfg file beats default" "$([[ "$out" == "mytool" ]] && echo 0 || echo 1)" "$out"

# env beats file
out=$( WIKI_PATH="$TMP/my-wiki" WIKI_SEARCH_TOOL=envtool bash -c 'source "$1"; wiki_cfg search_tool WIKI_SEARCH_TOOL searchfox-cli' _ "$LIB" )
check "wiki_cfg env beats file" "$([[ "$out" == "envtool" ]] && echo 0 || echo 1)" "$out"

# --- wiki_cfg_list --------------------------------------------------------
# default split
out=$( WIKI_PATH="$TMP/empty" bash -c 'source "$1"; wiki_cfg_list trigger_paths WIKI_TRIGGER_PATHS "dom/media a/b" | tr "\n" ","' _ "$LIB" )
check "wiki_cfg_list default split" "$([[ "$out" == "dom/media,a/b," ]] && echo 0 || echo 1)" "$out"

# json array from file
out=$( WIKI_PATH="$TMP/my-wiki" bash -c 'source "$1"; wiki_cfg_list trigger_paths WIKI_TRIGGER_PATHS "dom/media" | tr "\n" ","' _ "$LIB" )
check "wiki_cfg_list json array" "$([[ "$out" == "gfx/layers," ]] && echo 0 || echo 1)" "$out"

# env split beats file
out=$( WIKI_PATH="$TMP/my-wiki" WIKI_TRIGGER_PATHS="x/y z/w" bash -c 'source "$1"; wiki_cfg_list trigger_paths WIKI_TRIGGER_PATHS "dom/media" | tr "\n" ","' _ "$LIB" )
check "wiki_cfg_list env beats file" "$([[ "$out" == "x/y,z/w," ]] && echo 0 || echo 1)" "$out"

# --- wiki_under_path boundary cases ---------------------------------------
run_under() { WIKI_PATH="$TMP/my-wiki" bash -c 'source "$1"; wiki_under_path "$2"' _ "$LIB" "$2"; echo $?; }

check "under_path: child file"      "$(run_under _ "$TMP/my-wiki/components/A.md")"
check "under_path: exact dir"       "$(run_under _ "$TMP/my-wiki")"
check "under_path: sibling backup"  "$([[ "$(run_under _ "$TMP/my-wiki-backup/A.md")" == "1" ]] && echo 0 || echo 1)"
check "under_path: outside"         "$([[ "$(run_under _ "/etc/passwd")" == "1" ]] && echo 0 || echo 1)"
check "under_path: empty"           "$([[ "$(run_under _ "")" == "1" ]] && echo 0 || echo 1)"

rm -rf "$TMP"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
