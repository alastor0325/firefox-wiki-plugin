#!/usr/bin/env bash
# tests/test-scaffold.sh
# Guards the "fresh personal wiki" path (the thing /firefox-wiki:init Step 2 now
# supports): a brand-new $WIKI_PATH with NO cloned content and NO derived caches
# (index.json / aliases.txt) is a fully working wiki — the pre-lookup hook runs
# cleanly against it, MISSING on the empty wiki and HITTING once a page is added.
#
# Hermetic: builds a throwaway wiki in a temp dir; never touches ~/firefox-wiki.
# Usage: bash tests/test-scaffold.sh

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$PLUGIN_ROOT/scripts/wiki-pre-lookup.sh"
PASS=0; FAIL=0
ok()  { echo "PASS [$1]"; PASS=$((PASS+1)); }
bad() { echo "FAIL [$1]: $2"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
WIKI="$TMP/my-wiki"

# --- Reproduce exactly what /firefox-wiki:init Steps 7-9 scaffold for a fresh,
#     never-cloned personal wiki (deliberately NO index.json / aliases.txt). ---
mkdir -p "$WIKI"/{specs,platform,others,components,relations,patterns,architecture,triage,profiler,bugs}
: > "$WIKI/usage-log.jsonl"
printf '# Wiki Change Log\nAppend-only.\n' > "$WIKI/log.md"
printf '# Glossary\n\nUse /firefox-wiki:add to populate.\n' > "$WIKI/glossary.md"
printf '# Firefox Knowledge Wiki\n\n## Components\n\n| Component | Role |\n|---|---|\n' > "$WIKI/INDEX.md"
jq -n '{schema:1, search_tool:"searchfox-cli", trigger_paths:["dom/media"],
        source_repo_pattern:"(mozilla-central|gecko)"}' > "$WIKI/wiki-config.json"

# 1) Scaffold has the files the runtime needs — and no derived caches yet.
if [[ -f "$WIKI/INDEX.md" && -f "$WIKI/wiki-config.json" && -f "$WIKI/usage-log.jsonl" ]]; then
  ok "scaffold creates INDEX.md + wiki-config.json + usage-log.jsonl"
else
  bad "scaffold creates the core files" "a core file is missing"
fi
if [[ ! -e "$WIKI/index.json" && ! -e "$WIKI/aliases.txt" ]]; then
  ok "fresh wiki has no derived caches (index.json/aliases.txt)"
else
  bad "fresh wiki has no derived caches" "a cache unexpectedly exists"
fi

run_hook() { echo "$1" | env WIKI_PATH="$WIKI" WIKI_SKIP_HOOKS="" bash "$HOOK" 2>&1 || true; }
SF='{"tool_name":"Bash","tool_input":{"command":"searchfox-cli --define AudioSink"},"session_id":"s1"}'

# 2) Empty fresh wiki -> clean MISS, logged as wiki_hit:false (missing caches must
#    not crash or block the code search).
out="$(run_hook "$SF")"
if echo "$out" | grep -q '\[WIKI HIT\]'; then
  bad "empty wiki misses cleanly" "unexpected hit: $out"
else
  ok "empty wiki misses cleanly (no [WIKI HIT])"
fi
if tail -1 "$WIKI/usage-log.jsonl" | grep -q '"wiki_hit":false'; then
  ok "miss is logged (wiki_hit:false)"
else
  bad "miss is logged" "no wiki_hit:false line in usage-log.jsonl"
fi

# 3) Add a page (as /firefox-wiki:add would) -> HIT, logged as wiki_hit:true.
printf '# AudioSink\n\nAudioSink renders audio on the MDSM task queue.\n' > "$WIKI/components/AudioSink.md"
out="$(run_hook "$SF")"
if echo "$out" | grep -q '\[WIKI HIT\]'; then
  ok "populated wiki hits ([WIKI HIT] for AudioSink)"
else
  bad "populated wiki hits" "no hit: $out"
fi
if tail -1 "$WIKI/usage-log.jsonl" | grep -q '"wiki_hit":true'; then
  ok "hit is logged (wiki_hit:true)"
else
  bad "hit is logged" "no wiki_hit:true line in usage-log.jsonl"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
