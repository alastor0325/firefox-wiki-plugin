#!/usr/bin/env bash
# tests/test-triggers.sh
# Regression tests for the PostToolUse trigger/log hooks:
#   log-wiki-read.sh, wiki-lint-trigger.sh, wiki-ingest-trigger.sh
# Covers bug_id derivation, WIKI_PATH gating, and the ingest self-exclusion
# (incl. the pwd -P canonicalization that handles macOS /var symlinks).
#
# Usage: bash tests/test-triggers.sh   (dependency-free; uses mktemp + a claude stub)

set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
check() {
  local desc="$1" cond="$2" detail="${3:-}"
  if [[ "$cond" == "0" ]]; then echo "PASS [$desc]"; PASS=$((PASS+1))
  else echo "FAIL [$desc]${detail:+: $detail}"; FAIL=$((FAIL+1)); fi
}

TMP=$(mktemp -d)
# Stub `claude` so trigger hooks don't really invoke it; record each call.
mkdir -p "$TMP/bin"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/claude-calls.log"\n' "$TMP" > "$TMP/bin/claude"
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"
: > "$TMP/claude-calls.log"

# ───────────────────────── log-wiki-read.sh ─────────────────────────
W="$TMP/wiki"; mkdir -p "$W/components"; : > "$W/usage-log.jsonl"
LWR="$DIR/scripts/log-wiki-read.sh"

# (a) in-wiki file + WIKI_BUG_ID -> one event, numeric bug_id, relative path
echo "{\"tool_input\":{\"file_path\":\"$W/components/AudioSink.md\"}}" \
  | WIKI_PATH="$W" WIKI_BUG_ID=2042862 bash "$LWR"
line=$(tail -1 "$W/usage-log.jsonl")
check "log-wiki-read: logs event for in-wiki file" \
  "$([[ $(wc -l < "$W/usage-log.jsonl") -eq 1 ]] && echo 0 || echo 1)"
check "log-wiki-read: bug_id from WIKI_BUG_ID (numeric)" \
  "$(echo "$line" | jq -e '.bug_id == 2042862' >/dev/null 2>&1 && echo 0 || echo 1)" "$line"
check "log-wiki-read: file path stripped to WIKI_PATH-relative" \
  "$(echo "$line" | jq -e '.file == "components/AudioSink.md"' >/dev/null 2>&1 && echo 0 || echo 1)" "$line"

# (b) out-of-wiki file -> no new event (gating)
before=$(wc -l < "$W/usage-log.jsonl")
echo "{\"tool_input\":{\"file_path\":\"/somewhere/else/x.md\"}}" | WIKI_PATH="$W" bash "$LWR"
check "log-wiki-read: gates out non-wiki file" \
  "$([[ "$before" == "$(wc -l < "$W/usage-log.jsonl")" ]] && echo 0 || echo 1)"

# (c) bug_id derived from git branch name when no env override
R="$TMP/src1"; mkdir -p "$R"; git -C "$R" init -q
git -C "$R" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
git -C "$R" checkout -q -b bug-2050000-fix
: > "$W/usage-log.jsonl"
( cd "$R" && echo "{\"tool_input\":{\"file_path\":\"$W/components/AudioSink.md\"}}" | WIKI_PATH="$W" bash "$LWR" )
line=$(tail -1 "$W/usage-log.jsonl")
check "log-wiki-read: bug_id derived from branch name" \
  "$(echo "$line" | jq -e '.bug_id == 2050000' >/dev/null 2>&1 && echo 0 || echo 1)" "$line"

# (d) bug_id null when undeterminable (branch has no digits, no env)
R2="$TMP/src2"; mkdir -p "$R2"; git -C "$R2" init -q
git -C "$R2" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
git -C "$R2" checkout -q -b main
: > "$W/usage-log.jsonl"
( cd "$R2" && echo "{\"tool_input\":{\"file_path\":\"$W/components/AudioSink.md\"}}" | WIKI_PATH="$W" bash "$LWR" )
line=$(tail -1 "$W/usage-log.jsonl")
check "log-wiki-read: bug_id null when undeterminable" \
  "$(echo "$line" | jq -e '.bug_id == null' >/dev/null 2>&1 && echo 0 || echo 1)" "$line"

# ───────────────────────── wiki-lint-trigger.sh ─────────────────────────
LINT="$DIR/scripts/wiki-lint-trigger.sh"
: > "$TMP/claude-calls.log"
echo "{\"tool_input\":{\"file_path\":\"$W/components/AudioSink.md\"}}" | WIKI_PATH="$W" bash "$LINT"
check "lint-trigger: fires for in-wiki write" \
  "$(grep -q 'lint --lightweight' "$TMP/claude-calls.log" && echo 0 || echo 1)"
: > "$TMP/claude-calls.log"
echo "{\"tool_input\":{\"file_path\":\"/outside/x.md\"}}" | WIKI_PATH="$W" bash "$LINT"
check "lint-trigger: skips out-of-wiki write" \
  "$([[ ! -s "$TMP/claude-calls.log" ]] && echo 0 || echo 1)"

# ───────────────────────── wiki-ingest-trigger.sh ─────────────────────────
ING="$DIR/scripts/wiki-ingest-trigger.sh"
WG="$TMP/the-wiki"; mkdir -p "$WG"; git -C "$WG" init -q
git -C "$WG" remote add origin https://github.com/mozilla-firefox/firefox.git
SRC="$TMP/the-src"; mkdir -p "$SRC"; git -C "$SRC" init -q
git -C "$SRC" remote add origin https://github.com/mozilla-firefox/firefox.git
COMMIT='{"tool_input":{"command":"git commit -m wip"}}'
NONCOMMIT='{"tool_input":{"command":"git status"}}'

: > "$TMP/claude-calls.log"
( cd "$SRC" && echo "$NONCOMMIT" | WIKI_PATH="$WG" bash "$ING" )
check "ingest-trigger: ignores non-commit command" \
  "$([[ ! -s "$TMP/claude-calls.log" ]] && echo 0 || echo 1)"

: > "$TMP/claude-calls.log"
( cd "$SRC" && echo "$COMMIT" | WIKI_PATH="$WG" bash "$ING" )
check "ingest-trigger: fires for source-repo commit" \
  "$(grep -q 'ingest --auto' "$TMP/claude-calls.log" && echo 0 || echo 1)"

: > "$TMP/claude-calls.log"
( cd "$WG" && echo "$COMMIT" | WIKI_PATH="$WG" bash "$ING" )
check "ingest-trigger: self-excludes commit in the wiki repo (pwd -P)" \
  "$([[ ! -s "$TMP/claude-calls.log" ]] && echo 0 || echo 1)"

: > "$TMP/claude-calls.log"
( cd "$SRC" && echo "$COMMIT" | WIKI_PATH="$WG" WIKI_SOURCE_REPO_PATTERN='no-such-repo' bash "$ING" )
check "ingest-trigger: respects WIKI_SOURCE_REPO_PATTERN miss" \
  "$([[ ! -s "$TMP/claude-calls.log" ]] && echo 0 || echo 1)"

rm -rf "$TMP"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
