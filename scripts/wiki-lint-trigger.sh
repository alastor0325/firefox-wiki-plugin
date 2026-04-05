#!/bin/bash
# PostToolUse(Write|Edit) hook: trigger /firefox-wiki:lint --lightweight
# after any write to the wiki directory.

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

echo "$FILE" | grep -q "firefox-wiki/" || exit 0

claude -p '/firefox-wiki:lint --lightweight' || true
