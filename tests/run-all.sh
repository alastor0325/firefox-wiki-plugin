#!/usr/bin/env bash
# tests/run-all.sh — run every plugin test and aggregate pass/fail.
# Usage: bash tests/run-all.sh
#
# Each test is self-contained and dependency-free (bash + jq + python3).
# A custom $WIKI_PATH is honored by the tests that need a populated wiki.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
FAILED=0

run() {
  local name="$1"; shift
  echo "=============================================================="
  echo ">>> $name"
  echo "=============================================================="
  if "$@"; then
    echo "--- $name: OK"
  else
    echo "--- $name: FAILED"
    FAILED=$((FAILED+1))
  fi
  echo
}

run "test-wiki-config.sh"        bash    "$DIR/test-wiki-config.sh"
run "test-pre-lookup.sh"         bash    "$DIR/test-pre-lookup.sh"
run "test-triggers.sh"           bash    "$DIR/test-triggers.sh"
run "test-skill-attribution.sh"  bash    "$DIR/test-skill-attribution.sh"
run "test-allowlist-sweep.sh"    bash    "$DIR/test-allowlist-sweep.sh"
run "test-wiki-stats.py"         python3 "$DIR/test-wiki-stats.py"

echo "=============================================================="
if [[ "$FAILED" -eq 0 ]]; then
  echo "ALL SUITES PASSED"
else
  echo "$FAILED SUITE(S) FAILED"
fi
exit "$FAILED"
