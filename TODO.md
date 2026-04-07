# Firefox Wiki Plugin — TODO

Items discovered during development and usage. Add new items here rather than fixing immediately.

---

## Stats & Metrics

- [ ] **Filter maintenance ingests from coverage metrics** — `stats` skill counts all 25 ingest events, including ones triggered by verify/lint/maintenance agents. Only ingest events with a real numeric Bugzilla `bug_id` should count toward ingest coverage and false confidence rate.

- [ ] **False confidence rate is blind** — `hypothesis_from_wiki` and `hypothesis_correct` fields are never populated. No real bug investigations have been run through the wiki yet. Stats can report hit rate but cannot measure whether wiki hits actually help. Needs real investigation data before this metric is meaningful.

- [x] **`hypothesis_from_wiki` auto-detection** — Ingest skill now scans the last 8 hours of `pre_lookup` events for `wiki_hit: true` to set `hypothesis_from_wiki` automatically. No engineer action needed.

- [x] **`hypothesis_correct` auto-backfill** — Verify skill now backfills `hypothesis_correct` in matching ingest events after each verify run: `stale_fixed == 0` → true, `stale_fixed > 0` → false. Data grows naturally without any manual review.

- [ ] **`verify-report.md` appearing in most-consulted pages** — Verify agents read `verify-report.md` during maintenance, polluting the most-consulted list. Filter files outside `$WIKI_PATH` content directories (i.e. exclude `verify-report.md`, `lint-log.json`, `usage-log.jsonl`) from wiki_read consultation counts in stats.

---

## Confidence Scoring

- [ ] **Implement confidence scoring system** — See debate in session 2026-04-06. Two jobs: (1) maintenance scheduling — low confidence pages are always due for verify; (2) runtime — lookup skill surfaces confidence level so Claude treats low-confidence facts as leads to verify, not ground truth.

- [ ] **Track verify coverage, not just pass/fail** — "High confidence after verify" is misleading when the verify agent only sampled 12 of 30 facts. Track `facts_checked` / `facts_estimated_total` alongside `verify-last` in lint-log.json. A page with 40% coverage should not be marked the same as one with 100% coverage.

- [ ] **Auto-downgrade confidence on code change** — Pages should not silently stay high-confidence after Firefox has accumulated new commits past the verified rev. Use `lint-source-rev` (already tracked in lint-log.json) to auto-lower confidence when the Firefox tree has moved significantly, without waiting for the full interval.

---

## Wiki Structure

- [ ] **`others/` and `platform/` directories are empty** — No content has been placed there yet. `platform/` is intended for platform-specific knowledge (Windows WMF quirks, macOS AudioToolbox, Android GeckoView). Consider populating from existing component pages that have platform-specific sections.

- [ ] **`architecture/` directory added but not in `init` skill** — The new `architecture/` directory (for end-to-end pipeline walkthroughs like `MediaPipeline.md`) was added to lint and verify interval tables but not to the `init` skill's directory creation step. Update `skills/init/SKILL.md` to create `architecture/` on first run.

---

## Hooks & Logging

- [ ] **`add` skill should always log to usage-log** — If pages are created via direct Write (bypassing `:add`), no event is logged. Currently relies on manual backfill. Consider adding a lint check that detects wiki pages without a corresponding `add` or `ingest` event.

- [ ] **`verify` events not logged to usage-log** — Verify runs update `lint-log.json` but write no event to `usage-log.jsonl`. A `verify` event type would enable: how often verify runs, which pages are verified most, how many facts corrected over time. Low priority until false confidence rate is measurable.

---

## Skills

- [ ] **`init` skill missing `architecture/` directory** — See wiki structure note above.

- [ ] **Plugin version 0.5.0 requires restart to take effect** — Skills are cached at session startup; `/reload-plugins` does not re-read SKILL.md from disk. Document this clearly in README so users know to restart Claude Code after plugin updates.
