#!/usr/bin/env bash
# tests/test-skill-attribution.sh
# End-to-end tests for the "current skill" attribution model:
#   scripts/skill-start.sh, scripts/_active-skill.sh,
#   scripts/log-wiki-read.sh (skill tagging path).
#
# Usage: bash tests/test-skill-attribution.sh
#
# Hermetic: uses a throwaway WIKI_PATH and a throwaway state dir (HOME is
# pointed at a tempdir) so it never touches the real wiki or ~/.claude.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

SKILL_START="$PLUGIN_ROOT/scripts/skill-start.sh"
ACTIVE="$PLUGIN_ROOT/scripts/_active-skill.sh"
LOG_READ="$PLUGIN_ROOT/scripts/log-wiki-read.sh"

PASS=0
FAIL=0
ok()   { echo "PASS [$1]"; PASS=$((PASS+1)); }
bad()  { echo "FAIL [$1]: $2"; FAIL=$((FAIL+1)); }

# --- Hermetic sandbox ---------------------------------------------------
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"        # state dir lives under $HOME/.claude/state
mkdir -p "$HOME/.claude/state"
WIKI="$SANDBOX/firefox-wiki"       # path must contain "firefox-wiki/" for log-wiki-read
mkdir -p "$WIKI/components"
LOG="$WIKI/usage-log.jsonl"
: > "$LOG"
export WIKI_PATH="$WIKI"
unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID

SID="sess-A"
start_skill() {  # start_skill <skill> [args] [session_id]
    local skill="$1" args="${2:-null}" sid="${3:-$SID}"
    local argjson
    if [[ "$args" == "null" ]]; then argjson=null; else argjson="\"$args\""; fi
    printf '{"session_id":"%s","tool_input":{"skill":"%s","args":%s}}' "$sid" "$skill" "$argjson" \
        | bash "$SKILL_START"
}
read_wiki() {  # read_wiki <relpath> [session_id]
    local rel="$1" sid="${2:-$SID}"
    printf '{"session_id":"%s","tool_input":{"file_path":"%s/%s"}}' "$sid" "$WIKI" "$rel" \
        | bash "$LOG_READ"
}
last_read_skill() {  # echo the skill tag of the most recent wiki_read event
    jq -rc 'select(.event_type=="wiki_read")' "$LOG" | tail -1 | jq -r '.skill // "null"'
}
last_read_iid() {
    jq -rc 'select(.event_type=="wiki_read")' "$LOG" | tail -1 | jq -r '.instance_id // "null"'
}

# --- 1. allowlisted skill sets the current slot -------------------------
start_skill bug-start 2042862
got=$(bash "$ACTIVE" "$SID" | awk '{print $2}')
[[ "$got" == "bug-start" ]] && ok "allowlisted skill becomes current" \
    || bad "allowlisted skill becomes current" "current=$got"

# session_start event was logged
n=$(jq -rc 'select(.event_type=="session_start" and .skill=="bug-start")' "$LOG" | wc -l | tr -d ' ')
[[ "$n" == "1" ]] && ok "session_start logged" || bad "session_start logged" "count=$n"

# --- 2. wiki_read inherits the current skill + instance_id --------------
slot_iid=$(bash "$ACTIVE" "$SID" | awk '{print $1}')
read_wiki components/AutoplayPolicy.md
[[ "$(last_read_skill)" == "bug-start" ]] && ok "wiki_read inherits current skill" \
    || bad "wiki_read inherits current skill" "got=$(last_read_skill)"
[[ "$(last_read_iid)" == "$slot_iid" ]] && ok "wiki_read inherits instance_id" \
    || bad "wiki_read inherits instance_id" "got=$(last_read_iid) want=$slot_iid"

# --- 3. a second skill overwrites the slot (sequential) -----------------
start_skill review
got=$(bash "$ACTIVE" "$SID" | awk '{print $2}')
[[ "$got" == "review" ]] && ok "second skill overwrites slot" \
    || bad "second skill overwrites slot" "current=$got"
read_wiki components/AutoplayPolicy.md
[[ "$(last_read_skill)" == "review" ]] && ok "wiki_read now attributes to review" \
    || bad "wiki_read now attributes to review" "got=$(last_read_skill)"

# --- 4. non-allowlisted skill does NOT change the slot ------------------
start_skill some-random-skill
got=$(bash "$ACTIVE" "$SID" | awk '{print $2}')
[[ "$got" == "review" ]] && ok "non-allowlisted skill leaves slot unchanged" \
    || bad "non-allowlisted skill leaves slot unchanged" "current=$got"

# --- 5. no current skill before any skill-start → skill:null ------------
SID2="sess-B"
read_wiki components/AutoplayPolicy.md "$SID2"
[[ "$(last_read_skill)" == "null" ]] && ok "no skill active → skill:null" \
    || bad "no skill active → skill:null" "got=$(last_read_skill)"

# --- 6. session isolation: sess-B unaffected by sess-A ------------------
start_skill analyze-profile "" "$SID2"
got_b=$(bash "$ACTIVE" "$SID2" | awk '{print $2}')
got_a=$(bash "$ACTIVE" "$SID" | awk '{print $2}')
[[ "$got_b" == "analyze-profile" && "$got_a" == "review" ]] \
    && ok "sessions are isolated" \
    || bad "sessions are isolated" "A=$got_a B=$got_b"

# --- 7. no session_end events are ever written --------------------------
n=$(jq -rc 'select(.event_type=="session_end")' "$LOG" | wc -l | tr -d ' ')
[[ "$n" == "0" ]] && ok "no session_end events (current-skill model)" \
    || bad "no session_end events" "count=$n"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
