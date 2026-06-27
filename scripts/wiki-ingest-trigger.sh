#!/bin/bash
# PostToolUse(Bash) hook: trigger /firefox-wiki:ingest --auto after a commit is
# created/finalized in a Firefox repo (not the wiki repo itself).
#
# Matches `git commit` AND the jj equivalents (`jj commit` / `jj describe`): the
# Firefox patch workflow is jj-based (colocated jj+git), so commits are made
# through jj and a `git commit`-only gate silently stops firing the moment the
# workflow switches to jj. `jj new` is intentionally NOT matched — it opens an
# empty change (nothing to ingest yet). ingest --auto parses the *latest commit
# message* for the bug id and skips already-known facts, so re-firing across a jj
# patch stack (multiple describe/commit calls) is idempotent — redundant at worst.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

echo "$COMMAND" | grep -qE 'git commit|jj (commit|describe)' || exit 0

# Load shared config helpers (resolves WIKI_PATH, provides wiki_cfg). Defensive
# shim reproduces the original hardcoded source pattern if the lib is missing.
WIKI_PATH="${WIKI_PATH:-$HOME/firefox-wiki}"
WIKI_CFG_LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/_wiki-config.sh"
[[ -f "$WIKI_CFG_LIB" ]] && source "$WIKI_CFG_LIB"
if ! declare -F wiki_cfg >/dev/null; then wiki_cfg() { printf '%s' "$3"; }; fi

REMOTE=$(git remote get-url origin 2>/dev/null || echo "")

# Match source repos to ingest from (configurable; default = Firefox repos).
SRC_PATTERN=$(wiki_cfg source_repo_pattern WIKI_SOURCE_REPO_PATTERN '(mozilla-central|gecko|mozilla-firefox/firefox)')
echo "$REMOTE" | grep -qE "$SRC_PATTERN" 2>/dev/null || exit 0

# Never ingest commits made in the wiki repo itself — compare the repo toplevel
# to the resolved WIKI_PATH (robust to however the wiki remote is named).
# Canonicalize both with `pwd -P`: `git rev-parse --show-toplevel` returns a
# physical path, but $WIKI_PATH may contain symlinks (e.g. macOS /var).
REPO_TOP=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$REPO_TOP" ]]; then
    REPO_TOP=$(cd "$REPO_TOP" 2>/dev/null && pwd -P || printf '%s' "${REPO_TOP%/}")
    WIKI_TOP=$(cd "$WIKI_PATH" 2>/dev/null && pwd -P || printf '%s' "$WIKI_PATH")
    [[ "$REPO_TOP" == "$WIKI_TOP" ]] && exit 0
fi

claude -p '/firefox-wiki:ingest --auto' || true
