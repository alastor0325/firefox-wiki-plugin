#!/bin/bash
# PostToolUse(Write|Edit) hook: trigger /firefox-wiki:lint --lightweight
# after any write to the wiki directory.

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Load shared config helpers (resolves WIKI_PATH, provides wiki_under_path).
# Defensive shim reproduces the original literal gate if the lib is missing.
WIKI_PATH="${WIKI_PATH:-$HOME/firefox-wiki}"
WIKI_CFG_LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/_wiki-config.sh"
[[ -f "$WIKI_CFG_LIB" ]] && source "$WIKI_CFG_LIB"
if ! declare -F wiki_under_path >/dev/null; then
  wiki_under_path() { case "$1" in "$WIKI_PATH"|"$WIKI_PATH"/*) return 0;; *) return 1;; esac; }
fi

wiki_under_path "$FILE" || exit 0

claude -p '/firefox-wiki:lint --lightweight' || true
