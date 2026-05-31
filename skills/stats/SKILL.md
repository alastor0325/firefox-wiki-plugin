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

Also locate `TRIAGE_DIR` (`$TRIAGE_DIR` or `~/firefox-triage/`). Read `$TRIAGE_DIR/decisions-log.jsonl` if it exists — it's optional; if missing, the per-pattern correction rate section below is skipped.

If `usage-log.jsonl` is missing or empty, stop and say:

> No usage data yet. The wiki needs to be used for at least one month before stats are meaningful.

### 2. Parse the log

Read the JSONL file — one JSON object per line. Skip any line that is not valid JSON (malformed entries — lint will repair them on next run). Group entries by `event_type`:

For each metric below, if the required fields are absent on an event, skip that event and note the count of skipped entries at the end of the report. Never crash or omit a metric entirely because of missing fields — show `n/a (N events missing required fields)` instead.
- `pre_lookup` — pre-hook intercept events (searchfox-cli or dom/media grep attempted)
- `wiki_read` — wiki page reads (from lookup skill or hook)
- `ingest` — post-investigation bug knowledge additions
- `url-ingest` / `pdf-ingest` — spec/platform ingests (from add or init)
- `add` — user-triggered natural-language fact additions
- `session_start` / `session_end` — skill invocation brackets written by the wiki plugin's PreToolUse/PostToolUse hooks on the Skill tool. Each has `instance_id`, `skill`, `claude_session`. Wiki events fired during a skill instance inherit the same `instance_id` + `skill` fields.

### 3. Compute and display metrics

#### Hit Rate

The primary metric. Measured from `pre_lookup` events — these are logged by the pre-hook every time Claude attempts a searchfox-cli or dom/media grep, capturing exactly when the wiki was consulted vs when code was searched directly.

- **Denominator**: count of `pre_lookup` events (each represents one code search attempt).
- **Numerator**: count of `pre_lookup` events where `wiki_hit: true`.

If no `pre_lookup` events exist yet (plugin freshly installed), fall back to the old method: denominator = `ingest` event count, numerator = `ingest` events where `hypothesis_from_wiki = true` or matching `wiki_read` by `bug_id`. Label this fallback clearly as "estimated (no pre_lookup data)".

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

#### Per-Skill Coverage

The unbiased "is the wiki being consulted where it should be?" metric.
Uses `session_start` / `session_end` events emitted by the wiki-plugin's
PreToolUse/PostToolUse hooks on the Skill tool. Each session_start has
an `instance_id`, a `skill` name, and a `claude_session`. Wiki events
(`wiki_read`, `pre_lookup`) emitted during a skill instance inherit
that `instance_id`.

For each tracked skill in `wiki-relevant-skills.txt`:

- **Instances**: count of `session_start` events with that `skill`.
- **Consulted**: of those instances, count how many have at least one
  `wiki_read` or `pre_lookup` event with the same `instance_id`.
- **Coverage**: `Consulted / Instances`.

Display:

```
| Skill                    | Instances | Consulted | Coverage |
|--------------------------|-----------|-----------|----------|
| /bug-start               |   ...     |   ...     |   ...    |
| /firefox-implementation  |   ...     |   ...     |   ...    |
| /triage                  |   ...     |   ...     |   ...    |
| /review-patch            |   ...     |   ...     |   ...    |
| /analyze-profile         |   ...     |   ...     |   ...    |
```

Mark any row with Instances < 5 as `(low signal)` — a 100% rate over
2 instances is not a meaningful statistic.

A low coverage rate on a skill with high instance count means the
skill is doing code-touching work without consulting the wiki at all
— either the wiki has nothing useful on that topic (real coverage
gap) or the skill isn't wired to look up the wiki (workflow gap).

Targets per skill: >50% at 3 months of use, >70% at 6 months. Skills
below 30% after a month of use → flag for review.

#### Per-Skill Hit Rate

The "when the skill consults the wiki, does it find something?" metric.
Pre-existing Hit Rate but broken out per skill so you can see which
skills' consultations are productive vs unproductive.

For each tracked skill:

- **Consultations**: count of `pre_lookup` events with that `skill` tag.
- **Hits**: of those, count where `wiki_hit: true`.
- **Hit Rate**: `Hits / Consultations`.

Display:

```
| Skill                    | Consultations | Hits | Hit Rate |
|--------------------------|---------------|------|----------|
| /bug-start               |     ...       | ...  |   ...    |
| /firefox-implementation  |     ...       | ...  |   ...    |
| /triage                  |     ...       | ...  |   ...    |
```

Same `(low signal)` marker for Consultations < 10.

Low hit rate on a high-volume skill = wiki content is missing for the
topics that skill cares about → coverage gap. Pair with the
Coverage table above:

- **High Coverage + High Hit Rate** → wiki is working for this skill.
- **High Coverage + Low Hit Rate** → skill is consulting but not
  finding anything → write more pages on this skill's topics.
- **Low Coverage + High Hit Rate** → wiki has the right content but
  the skill isn't being routed to it → check lookup heuristics or
  skill wiring.
- **Low Coverage + Low Hit Rate** → wiki is not in this skill's
  workflow at all → bigger architectural question.

#### Per-Pattern Correction Rate (triage-apply-feedback)

The "is this wiki pattern actually helping triage?" metric. Joins
`~/firefox-wiki/usage-log.jsonl` (wiki reads tagged with `skill: triage`)
with `~/firefox-triage/decisions-log.jsonl` (corrections written by
`/triage-apply-feedback`). If the file doesn't exist, skip this
section entirely.

For each `wiki_read` event with `skill: triage` (or any other tracked
skill that loads patterns at session start):

- Read the `instance_id` and the `file` (e.g. `triage/chrome-ua-assume-firefox.md`).
- Find the `session_start` event with the same `instance_id` to get the
  bug_id(s) being processed (from `args`).
- Look in `decisions-log.jsonl` for `apply-feedback` events with any of
  those bug_ids. If one or more exist, the pattern was present in a
  session that ended in a correction.

Aggregate by wiki page file:

```
| Pattern page                        | Sessions present | Corrected | Correction Rate |
|-------------------------------------|------------------|-----------|-----------------|
| triage/chrome-ua-assume-firefox.md  |         12       |     1     |       8%        |
| triage/ai-advised-pref-changes.md   |         18       |     7     |      39%        |   ← red flag
| triage/wrong-component-graphics-routing.md |    9      |     0     |       0%        |
```

High correction rate (>25% with N≥8) on a pattern means: when /triage
sees this pattern, the human ends up correcting the resulting draft
more often than not. Candidates for re-verification via
`/firefox-wiki:verify` or rewrite via `/firefox-wiki:add`.

Low correction rate is the desired state — the pattern is helping
land correct decisions.

#### Attribution caveats

Wiki events (`wiki_read`, `pre_lookup`) carry an
`attribution_confidence` field set by `_active-skill.sh` at the moment
they fire. It reflects how trustworthy the `skill` / `instance_id`
tags are, given that background sub-agents share the parent's
session_id (so a single stack can hold genuinely-parallel instances):

- **`certain`** — exactly one skill instance was active. Both `skill`
  and `instance_id` are reliable. Use everywhere.
- **`skill-certain`** — multiple instances active but all the *same*
  skill (e.g. /triage fanning out parallel /bug-start sub-agents). The
  `skill` tag is reliable; the `instance_id` is best-effort (the stack
  top, which may not be the true owner). **Include in per-skill
  Coverage and Hit Rate** (skill is what those measure), but **exclude
  from any per-instance join** (e.g. the hypothesis_from_wiki
  bug-correlation, which should use args/bug_id matching instead).
- **`ambiguous`** — multiple instances of *different* skills active
  concurrently. Neither tag is trustworthy. **Exclude from all
  per-skill metrics.** Count these and show the total in a footer so
  the reader knows the denominator excluded them.
- **`null`** (field absent or empty) — no skill was active when the
  event fired (e.g. ad-hoc wiki browsing outside any tracked skill).
  Group under `(no active skill)`.

When computing the per-skill tables above, treat `certain` and
`skill-certain` events as attributable to their `skill`; drop
`ambiguous` and `null`. Report the dropped counts in a one-line
footer.

### 4. Closing recommendation

Print exactly one recommendation based on the results:

- Hit rate on track: "Wiki is working well. Keep ingesting after each investigation."
- Hit rate low: "Wiki lookup is not being triggered. Check that /firefox-wiki:lookup is integrated into your bug-start workflow."
- False confidence high: "Wiki content may be misleading investigations. Run /firefox-wiki:lint --full and review stale pages."
- Ingest coverage low: "Many investigations are not being ingested. Check that Hook 1 (git commit) is firing correctly."
- Per-skill coverage uneven: "Skill X has <30% wiki coverage over N≥10 instances → check whether the wiki has content for X's topics, or whether X's workflow needs to call /firefox-wiki:lookup."
- Per-skill hit rate uneven: "Skill X has <20% hit rate over N≥10 consultations → the wiki is missing pages on X's topics; consider running /firefox-wiki:add for recurring symptoms."

Apply whichever condition is most urgent. If multiple apply, print multiple recommendations.
