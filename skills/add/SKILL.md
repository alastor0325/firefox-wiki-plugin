---
name: add
description: Add a fact, explanation, or note to the Firefox Knowledge Wiki in natural language. Claude decides which page to update or create.
version: 0.2.0
---

## Step 1 — Detect input type

Read `$ARGUMENTS`. If empty, ask the user:

> "What would you like to add to the wiki? Describe the fact, behavior, or concept, or provide a spec URL."

Classify the input:

| Pattern | Route |
|---|---|
| Starts with `http://` or `https://` | → **Spec ingest path** (see below) |
| Starts with `bug ` followed by digits | → **Bug ingest path**: invoke the `firefox-wiki:ingest` skill with the bug ID |
| Anything else | → **Fact path** (existing behavior) |

---

## URL ingest path

### S1 — Check prerequisites

Run:
```bash
which pandoc || echo "NOT FOUND"
which curl || echo "NOT FOUND"
```

If either is missing, tell the user which tool is absent and offer to install it:

```
<tool> is required for URL ingestion. Would you like me to install it now?

  brew install <tool>

Reply "yes" to install, or install manually and re-run the command.
```

Wait for the user's reply. If yes, run the install command and continue. If no, stop.

### S2 — Fetch and convert

```bash
SPEC_URL="<the URL from $ARGUMENTS>"
SPEC_MD="/tmp/wiki-spec-ingest.md"

# Capture response headers for staleness tracking
curl -sI "$SPEC_URL" > /tmp/wiki-spec-headers.txt

# Fetch and convert to markdown in one pipeline
curl -sL --max-time 120 "$SPEC_URL" \
  | pandoc -f html -t markdown --strip-comments --wrap=none \
  > "$SPEC_MD"
```

Extract staleness metadata from the headers:
```bash
ETAG=$(grep -i "^etag:" /tmp/wiki-spec-headers.txt | tr -d '\r' | awk '{print $2}')
LAST_MOD=$(grep -i "^last-modified:" /tmp/wiki-spec-headers.txt | tr -d '\r' | cut -d' ' -f2-)
FETCH_DATE=$(date +%Y-%m-%d)
```

### S3 — Map sections

Scan headings to understand structure:
```bash
grep "^#" "$SPEC_MD" | head -60
```

Identify the **major sections** (top-level `#` or `##` headings that represent distinct concepts). Ignore navigation boilerplate: table of contents, site headers/footers, breadcrumbs, "see also" sidebars, cookie banners, and repeated navigation links.

Use judgment about what counts as a section worth storing — a section should represent a self-contained concept, not a one-line stub or pure navigation entry.

### S4 — Create pages

Determine `WIKI_PATH` (use `$WIKI_PATH` env var, otherwise `~/firefox-wiki/`).

Determine the target directory based on the source:
- Formal spec (w3.org, whatwg.org, ietf.org, iso.org, itu.int) → `specs/`
- Reference docs, MDN, blog posts, postmortems, internal wikis → `platform/`
- When in doubt, use `specs/`

For each major section:

1. **Extract the section content** from the markdown file — from its heading to the next same-level heading.

2. **Distill it**: do not copy the source verbatim. Write a structured summary covering:
   - What this section defines or explains
   - Key rules, states, or algorithm steps relevant to a Firefox implementer
   - Any normative requirements or behavioral constraints

   Omit: cross-reference links (`§4.8.x`), navigation content, cookie/legal banners, content that doesn't add implementation value.

3. **Create or update** `$WIKI_PATH/<target-dir>/<slug>.md` using this template:

```markdown
# <Section title>

<!-- source-url: <URL> -->
<!-- source-fetched: <FETCH_DATE> -->
<!-- source-etag: <ETAG> -->
<!-- source-last-modified: <LAST_MOD> -->

## Summary

<1-3 sentence overview>

## Key Rules

<numbered list of important rules or behaviors>

## States / Attributes

<table if the section defines states, attributes, or error codes — omit section if not applicable>

## Firefox-Specific Notes

<leave empty — filled in as implementation experience accumulates>
```

4. If a page for this section **already exists**: update the content sections but preserve any existing `## Firefox-Specific Notes`. Update the `source-fetched` and `source-etag` metadata comments.

### S5 — Update INDEX.md

Add a row for each new spec page created to the `## Specs & Platform` table in INDEX.md:
```
| [[<slug>]] | <one-line description of what it covers> |
```

Update the "Last updated" date.

### S6 — Log and push

Append to `usage-log.jsonl`:
```json
{"date":"<ISO timestamp>","event_type":"spec-ingest","trigger":"user","url":"<SPEC_URL>","pages_created":[...],"pages_updated":[...]}
```

Run:
```bash
cd $WIKI_PATH && git add -A && git commit -m "wiki: ingest spec <domain/path>" && git push
```

### S7 — Confirm

Print:
```
Spec ingested: <URL>

Created: <list of new pages>
Updated: <list of updated pages>

Re-run `/firefox-wiki:add <URL>` to refresh when the spec updates.
Staleness will be flagged automatically by `/firefox-wiki:lint --full`.
```

---

## Bug ingest path

Extract the bug ID from `$ARGUMENTS` (strip the `bug ` prefix). Invoke the `firefox-wiki:ingest` skill passing the bug ID.

---

## Fact path

### 1. Locate the wiki

Check that `$WIKI_PATH/INDEX.md` exists. If not, tell the user:
> "Wiki not initialized. Run `/firefox-wiki:init` first."

### 2. Read INDEX.md

Read `$WIKI_PATH/INDEX.md` to understand current wiki structure.

### 3. Classify the fact

| Type | Criteria | Target path |
|---|---|---|
| **Component fact** | About a specific Firefox class or component | `components/<Name>.md` |
| **Interaction/protocol** | How two components relate or communicate | `relations/<A>-<B>.md` |
| **Reusable pattern** | A mechanism that appears in multiple contexts | `patterns/<name>.md` |
| **Spec/standard behavior** | Codec, container, or web spec behavior | `specs/<name>.md` or `platform/<name>.md` |
| **Bug learning** | Distilled insight from a resolved bug | `bugs/<id>-<slug>.md` |
| **Glossary entry** | Abbreviation, error code, or enum value | `glossary.md` |

### 4. Determine confidence level

If not obvious from context, ask the user:
> - [High] — verified by reading source code
> - [Medium] — inferred from observed behavior or documentation
> - [Low] — extrapolated or from memory; needs future verification

### 5. Determine source citation

Identify the source if available: bug number, revision hash, spec section, or colleague name.

### 6. Write the content

**If a relevant page already exists:** append to the appropriate section.

**If no page exists yet:** create using the standard template for its type.

Format new content as:
```markdown
<content> [High] <!-- source: bug 2026875, 2026-04-04 -->
```

Use `[[wiki-links]]` for every component, pattern, or bug name mentioned.

#### Page templates

**Component page** (`components/<Name>.md`):
```markdown
# <Name>

## Overview

## Key Behaviors

## Known Quirks

## Relations
```

**Relation page** (`relations/<A>-<B>.md`):
```markdown
# <A> ↔ <B>

## Overview

## Protocol / Interaction

## Edge Cases
```

**Pattern page** (`patterns/<name>.md`):
```markdown
# <Name> Pattern

## Summary

## Where Used

## Implementation Notes
```

**Bug learning page** (`bugs/<id>-<slug>.md`):
```markdown
# Bug <id> — <slug>

## Root Cause

## Fix Summary

## Learnings
```

### 7. Update INDEX.md if a new page was created

### 8. Append to usage-log.jsonl

```json
{"date":"<ISO 8601 timestamp>","event_type":"add","trigger":"user","file":"<relative path from WIKI_PATH>","confidence":"<High|Medium|Low>"}
```

### 9. Lint wiki-links

Scan modified files for `[[PageName]]` references. Report any broken links.

### 10. Push to remote

```bash
cd $WIKI_PATH && git add -A && git commit -m "wiki: add <one-line summary>" && git push
```

### 11. Confirm

```
Added to `<relative file path>` with [<confidence>] tag. [[links]] verified. Pushed to remote.
```
