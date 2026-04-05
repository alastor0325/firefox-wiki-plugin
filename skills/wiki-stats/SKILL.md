---
description: Show Firefox Knowledge Wiki usage metrics — hit rate, most-consulted pages, false confidence rate, and coverage gaps. Run monthly.
---

## When to invoke

Run once a month to measure whether the wiki is actually helping investigations.

## Steps

### 1. Locate the wiki and load the log

Determine `WIKI_PATH` (`$WIKI_PATH` or `~/firefox-wiki/`). Read `$WIKI_PATH/usage-log.jsonl`.

If the file is missing or empty, stop and say:

> No usage data yet. The wiki needs to be used for at least one month before stats are meaningful.

### 2. Parse the log

Read the JSONL file — one JSON object per line. Group entries by `event_type`:
- `wiki_read` — wiki consultation events (from lookup or add)
- `ingest` — post-investigation knowledge additions
- `add` — user-triggered fact additions
- `lint` — lint runs

### 3. Compute and display metrics

#### Hit Rate

The primary metric. Definition:
- **Numerator**: sessions that contain at least one `wiki_read` event.
- **Denominator**: total investigation sessions, estimated by counting `ingest` events (each completed investigation should produce one ingest).

Display as a monthly table:

```
| Month | Investigations | Wiki Hits | Hit Rate |
|-------|---------------|-----------|----------|
| ...   | ...           | ...       | ...      |
```

Targets: >50% at 3 months, >70% at 6 months.

#### Most Consulted Pages

Count `wiki_read` events per `file` field. Show the top 10:

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
