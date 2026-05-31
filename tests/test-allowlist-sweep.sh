#!/usr/bin/env bash
# tests/test-allowlist-sweep.sh
# For EVERY skill in scripts/wiki-relevant-skills.txt, verify:
#   1. skill-start.sh recognizes it (writes the current-skill slot)
#   2. a subsequent wiki_read attributes to it
#   3. the skill name maps to a real installed skill (a typo'd allowlist
#      entry would silently never be tracked)
# Also verify a name NOT in the allowlist is rejected (slot unchanged).
#
# Hermetic: throwaway WIKI_PATH and HOME-state. Skill-existence check
# (#3) looks at the real ~/.claude/skills and plugin skills dirs and is
# reported as a warning (not a hard failure) when a skill can't be located
# locally — some are plugin-provided and may live elsewhere.
#
# Usage: bash tests/test-allowlist-sweep.sh

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
SKILL_START="$PLUGIN_ROOT/scripts/skill-start.sh"
ACTIVE="$PLUGIN_ROOT/scripts/_active-skill.sh"
LOG_READ="$PLUGIN_ROOT/scripts/log-wiki-read.sh"
ALLOWLIST="$PLUGIN_ROOT/scripts/wiki-relevant-skills.txt"

PASS=0; FAIL=0
ok()   { echo "PASS [$1]"; PASS=$((PASS+1)); }
bad()  { echo "FAIL [$1]: ${2:-}"; FAIL=$((FAIL+1)); }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"; mkdir -p "$HOME/.claude/state"
WIKI="$SANDBOX/firefox-wiki"; mkdir -p "$WIKI/components"
: > "$WIKI/usage-log.jsonl"
export WIKI_PATH="$WIKI"
unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID

# ~ was overridden above; capture the real user home explicitly.
REAL_HOME="$(eval echo ~"$(id -un)")"
REAL_SKILLS="$REAL_HOME/.claude/skills"

skill_exists() {  # is there an installed skill by this name (anywhere)?
    local name="$1"
    local base="${name##*:}"   # plugin-namespaced: strip "plugin:" prefix
    # Fast paths: global user skills + this plugin's own skills.
    [[ -f "$REAL_SKILLS/$name/SKILL.md" ]] && return 0
    [[ -f "$REAL_SKILLS/$base/SKILL.md" ]] && return 0
    [[ -f "$PLUGIN_ROOT/skills/$base/SKILL.md" ]] && return 0
    # Fallback: project-scoped skills live in <repo>/.claude/skills or
    # <repo>/.agents/skills. Bounded find, stop at first match.
    local hit
    hit=$(find "$REAL_HOME" -maxdepth 6 -type f -name SKILL.md \
              -path "*/skills/$base/SKILL.md" -print -quit 2>/dev/null)
    [[ -n "$hit" ]] && return 0
    return 1
}

[[ -f "$ALLOWLIST" ]] || { echo "FAIL: allowlist missing at $ALLOWLIST"; exit 1; }

n=0
while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    n=$((n+1))
    sid="sweep-$n"

    # 1. recognized → slot written
    printf '{"session_id":"%s","tool_input":{"skill":"%s","args":"123"}}' "$sid" "$skill" \
        | bash "$SKILL_START"
    got=$(bash "$ACTIVE" "$sid" | awk '{print $2}')
    [[ "$got" == "$skill" ]] && ok "$skill: slot set" \
        || bad "$skill: slot set" "current='$got'"

    # 2. wiki_read attributes to it
    printf '{"session_id":"%s","tool_input":{"file_path":"%s/components/X.md"}}' "$sid" "$WIKI" \
        | bash "$LOG_READ"
    tagged=$(jq -rc 'select(.event_type=="wiki_read")' "$WIKI/usage-log.jsonl" | tail -1 | jq -r '.skill')
    [[ "$tagged" == "$skill" ]] && ok "$skill: wiki_read attributed" \
        || bad "$skill: wiki_read attributed" "tagged='$tagged'"

    # 3. allowlist entry maps to a real installed skill (catches typos)
    if skill_exists "$skill"; then
        ok "$skill: installed skill exists"
    else
        bad "$skill: no SKILL.md found anywhere — typo in allowlist?"
    fi
done < "$ALLOWLIST"

# Non-allowlisted name is rejected (slot stays from last loop iteration).
before=$(bash "$ACTIVE" "sweep-reject" | awk '{print $2}')   # empty (fresh sid)
printf '{"session_id":"%s","tool_input":{"skill":"%s","args":""}}' "sweep-reject" "definitely-not-a-real-skill" \
    | bash "$SKILL_START"
after=$(bash "$ACTIVE" "sweep-reject" | awk '{print $2}')
[[ -z "$before" && -z "$after" ]] && ok "non-allowlisted skill rejected (no slot)" \
    || bad "non-allowlisted skill rejected" "before='$before' after='$after'"

echo ""
echo "Swept $n allowlisted skills."
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
