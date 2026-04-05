---
name: verify
description: Periodically verify that facts in the Firefox Knowledge Wiki are still correct by re-reading cited sources. Flags stale or unverifiable claims for human review.
version: 0.1.0
user-invocable: false
---

## Purpose

The verify skill is the correctness layer on top of lint. Where lint checks structure and staleness signals, verify re-reads actual sources and asks: "does this code / spec still support this claim?"

It is slow and judgment-heavy — run it based on per-directory intervals, not after every write.

## Verify intervals

Per-page intervals stored as `verify-last` in `$WIKI_PATH/lint-log.json`.

| Directory | Verify interval | Rationale |
|---|---|---|
| `components/` | 30 days | Code changes most actively |
| `relations/` | 90 days | Changes when components change |
| `patterns/` | 180 days | Abstract concepts, stable |
| `specs/` | 365 days | Specs rarely change behavior |
| `bugs/` | Never | Historical record |

## When to invoke

- When nudged by `ingest` or `add` (pages overdue)
- After a large refactor that touched many components
- After suspecting agent-written facts may be wrong

## Mode detection

Parse `$ARGUMENTS`:
- Contains `--force`: ignore `verify-last` intervals — verify every page
- Contains a page path (e.g. `components/AudioSink.md`): verify that single page only
- Empty: verify all pages that are due based on `verify-last`

---

## Step 1 — Determine pages due for verification

Read `$WIKI_PATH/lint-log.json`:
```bash
cat $WIKI_PATH/lint-log.json 2>/dev/null || echo "{}"
```

For each `.md` file under `components/`, `relations/`, `patterns/`, `specs/`:
```
TODAY = current date
verify-last = lint-log[page]["verify-last"] or "1970-01-01" if absent
interval = lookup from table above

if (TODAY - verify-last) >= interval:
    → page is DUE
else:
    → skip
```

Print the due list before proceeding:
```
Pages due for verification: <n>
  components/: <n>
  relations/:  <n>
  patterns/:   <n>
  specs/:      <n>
```

---

## Step 2 — Extract verifiable facts from each due page

For each due page, read it and extract all fact lines that have a citation.

A **verifiable fact** is a line that:
- Contains a concrete claim (class name, method name, field name, behavioral assertion)
- Has at least one of:
  - A Searchfox permanent URL
  - A spec name + section reference (e.g. `§7.4.8`)
  - An official vendor doc URL (`learn.microsoft.com`, `developer.apple.com`, etc.)
  - A bug number (`bug XXXXXXX`)

Skip lines with only `[High/Medium/Low]` confidence tags and no URL/spec/bug — these cannot be mechanically re-verified.

Group extracted facts by page. For each fact record:
```
{
  "page": "components/AudioSink.md",
  "line": 12,
  "claim": "<the fact text>",
  "source_type": "searchfox|spec|vendor|bug",
  "source": "<the citation>"
}
```

---

## Step 3 — Verify each fact via gecko-navigator agent

For each due page, spawn a single `gecko-navigator` agent with all facts from that page bundled into one prompt. Do not spawn one agent per fact — batch by page to limit agent overhead.

Agent prompt template:
```
You are verifying facts in the Firefox Knowledge Wiki. For each fact below,
re-read the cited source and determine whether the current codebase / spec
still supports the claim.

IMPORTANT: Do NOT read any file under ~/firefox-wiki/ or $WIKI_PATH.
Verify exclusively from primary sources:
- Firefox source code: use searchfox-cli or MCP tools (preferred — no local
  path needed); if reading local files, restrict to the Firefox repo root
  (detect via `git rev-parse --show-toplevel` from any Firefox working directory,
  or from the $MOZ_SRC environment variable)
- Spec facts: fetch the authoritative spec URL via WebFetch
- Vendor doc facts: fetch the official vendor URL via WebFetch

Reading the wiki to verify the wiki is circular and not permitted.

Page: <page path>

Facts to verify:
<for each fact>
  Line <n>: "<claim>"
  Source: <citation>
</for each fact>

For each fact, respond with one of:
- CONFIRMED: source still supports the claim — quote the relevant line/section
- STALE: source no longer supports the claim — explain what changed
- UNCERTAIN: source is ambiguous or cannot be read — explain why

Do not guess. If you cannot read the source, say UNCERTAIN.
Cite the exact Searchfox URL or spec section you read for each verdict.
```

Collect all agent responses.

---

## Step 4 — Build verification report

Create or overwrite `$WIKI_PATH/verify-report.md`:

```markdown
# Wiki Verification Report — <date>

Pages verified: <n>
Facts checked: <n>
  Confirmed:  <n>
  Stale:      <n>
  Uncertain:  <n>

---

## Stale facts

<for each STALE verdict>
### <page path> line <n>
**Claim:** <fact text>
**Source:** <citation>
**Finding:** <agent explanation of what changed>
**Action:** Update or remove this fact via `/firefox-wiki:wiki-add`

</for each>

---

## Uncertain facts

<for each UNCERTAIN verdict>
### <page path> line <n>
**Claim:** <fact text>
**Source:** <citation>
**Finding:** <agent explanation>
**Action:** Manual review needed

</for each>

---

## Confirmed facts

<count only — no details needed>
<n> facts verified correct.
```

Save the report, then invoke `auto-update-my-md` to commit it:
```bash
cd $WIKI_PATH && git add verify-report.md
```

---

## Step 5 — Update lint-log.json

For every page that was verified (regardless of verdict), update `verify-last` in `lint-log.json`:

```bash
jq --arg page "components/AudioSink.md" \
   --arg date "<TODAY>" \
   '.[$page]["verify-last"] = $date' \
   $WIKI_PATH/lint-log.json > /tmp/lint-log-new.json \
   && mv /tmp/lint-log-new.json $WIKI_PATH/lint-log.json
```

Commit both `lint-log.json` and `verify-report.md` together:
```bash
cd $WIKI_PATH && git add lint-log.json verify-report.md \
  && git commit -m "wiki: verify run $(date +%Y-%m-%d) — <n> stale, <n> uncertain" \
  && git push
```

---

## Step 6 — Present findings

Print a summary to the user:

```
Wiki Verification — <date>

Pages verified:  <n>
Facts checked:   <n>
  Confirmed:     <n>
  Stale:         <n>  ← need correction
  Uncertain:     <n>  ← need manual review

Report saved to: ~/firefox-wiki/verify-report.md

To fix stale facts:
  /firefox-wiki:wiki-add <corrected fact with source>

To suppress a false positive, add <!-- verify-ignore --> to the fact line.
```

If there are no stale or uncertain facts:
```
All <n> verified facts confirmed correct. Wiki is accurate as of <date>.
```
