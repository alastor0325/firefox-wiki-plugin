---
name: stats
description: Show Firefox Knowledge Wiki usage metrics — hit rate, most-consulted pages, false confidence rate, and coverage gaps. Run monthly.
version: 0.1.0
---

## When to invoke

Run once a month to measure whether the wiki is actually helping investigations.

## Steps

### 1. Locate the wiki and load the log

Determine `WIKI_PATH` (`$WIKI_PATH` or `~/firefox-wiki/`). Read `$WIKI_PATH/usage-log.jsonl`.

If the file is missing or empty, stop and say:

> No usage data yet. The wiki needs to be used for at least one month before stats are meaningful.

### 2. Parse the log

Read the JSONL file — one JSON object per line. Skip any line that is not valid JSON (malformed entries — lint will repair them on next run). Group entries by `event_type`:

For each metric below, if the required fields are absent on an event, skip that event and note the count of skipped entries at the end of the report. Never crash or omit a metric entirely because of missing fields — show `n/a (N events missing required fields)` instead.
- `wiki_read` — wiki consultation events (from lookup)
- `ingest` — post-investigation bug knowledge additions
- `url-ingest` / `pdf-ingest` — spec/platform ingests (from add or init)
- `add` — user-triggered natural-language fact additions

### 3. Compute and display metrics

#### Hit Rate

The primary metric. Definition:
- **Denominator**: count of `ingest` events (one per completed bug investigation).
- **Numerator**: count of `ingest` events where `hypothesis_from_wiki = true`, OR where a `wiki_read` event exists with the same `bug_id` in the log (whichever is broader — use the union).

If a `wiki_read` event has `bug_id: null`, it cannot be correlated; count it only if its timestamp falls within 24 hours before an `ingest` event with no prior `wiki_read` match.

If the log contains events with a `user` field, compute hit rate per user and show both tables: one per-user, then a team aggregate row. Events without a `user` field are grouped under `(unknown)`.

```
| Month | User              | Investigations | Wiki Hits | Hit Rate |
|-------|-------------------|----------------|-----------|----------|
| ...   | alwu@mozilla.com  | ...            | ...       | ...      |
| ...   | (team total)      | ...            | ...       | ...      |
```

If no events have a `user` field, fall back to the single-column table:

```
| Month | Investigations | Wiki Hits | Hit Rate |
|-------|---------------|-----------|----------|
| ...   | ...           | ...       | ...      |
```

Targets: >50% at 3 months, >70% at 6 months.

#### Most Consulted Pages

Count `wiki_read` events per `file` field. If `user` data is present, also show a per-user breakdown for the top 5 pages. Show the top 10 overall:

```
| Page | Reads | Last Read |
|------|-------|-----------|
| ...  | ...   | ...       |
```

Note: these are the highest-value pages — keep them current.

#### Never Consulted Pages

List all `.md` files in `$WIKI_PATH` that have zero `wiki_read` entries in the log. Display as:

> These pages have never been read — consider removing or improving them.

#### Ingest Coverage

Ratio: `ingest` event count / total investigation count (same denominator as hit rate).

Should approach 1.0. If below 0.7, print:

> Warning: many investigations are not being ingested.

#### False Confidence Rate

Compute:
- Numerator: entries where `hypothesis_from_wiki = true` AND `hypothesis_correct = false`
- Denominator: all entries where `hypothesis_from_wiki = true`

If any entries have `hypothesis_from_wiki = true` and `hypothesis_correct = null`, list their bug IDs and prompt:

> Please fill in hypothesis_correct for these bugs to complete the measurement.

Target: false confidence rate below 10%.

#### Add Events

Count user-triggered `add` events by month. Shows how actively the engineer contributes knowledge outside of automated ingest.

#### Coverage Gaps

- Read `ingest` events. Extract component names from the `pages_updated` field.
- Cross-reference with the component table in `INDEX.md`.
- Components appearing in ingests but absent from INDEX.md → missing documentation.
- Components in INDEX.md with no `wiki_read` events in the log → potentially unused pages.

List both categories.

### 4. Closing recommendation

Print exactly one recommendation based on the results:

- Hit rate on track: "Wiki is working well. Keep ingesting after each investigation."
- Hit rate low: "Wiki lookup is not being triggered. Check that /firefox-wiki:lookup is integrated into your bug-start workflow."
- False confidence high: "Wiki content may be misleading investigations. Run /firefox-wiki:lint --full and review stale pages."
- Ingest coverage low: "Many investigations are not being ingested. Check that Hook 1 (git commit) is firing correctly."

Apply whichever condition is most urgent. If multiple apply, print multiple recommendations.
