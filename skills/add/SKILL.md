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
| Starts with `http://` or `https://` | → **URL ingest path** |
| Local path ending in `.pdf` | → **PDF ingest path** |
| Starts with `bug ` followed by digits | → **Bug ingest path**: invoke the `firefox-wiki:ingest` skill with the bug ID |
| Anything else | → **Fact path** (existing behavior) |

---

## Content policy — distillation only

**Never copy spec text verbatim into the wiki.** Always distill: extract the intent, rules, and facts and rewrite them in your own words.

This applies to all sources but is especially critical for:

| Spec type | Examples | Reason |
|---|---|---|
| **Public specs** | WHATWG, W3C, IETF RFC, Khronos | Best practice — keep wiki concise |
| **Private/paid specs** | ISO, IEC, ITU-T (H.264, HEVC, MPEG-*, AAC) | Legal — verbatim reproduction is prohibited |

When ingesting a private spec, add a notice at the top of each created page:

```markdown
> **Note**: This page contains distilled facts from a private/paid specification
> (ISO/IEC/ITU-T). No verbatim spec text is reproduced here.
```

---

## URL ingest path

### S1 — Check prerequisites

Run:
```bash
which pandoc || echo "NOT FOUND"
which curl || echo "NOT FOUND"
```

If either is missing, offer to install it:

```
<tool> is required for URL ingestion. Would you like me to install it now?

  brew install <tool>

Reply "yes" to install, or "no" to abort.
```

Wait for reply. If yes, run the install and verify it succeeds before continuing. If no, stop.

### S2 — Classify the URL and derive spec group

Determine target directory and ingest strategy based on the domain:

| Domain pattern | Directory | Strategy |
|---|---|---|
| whatwg.org, w3.org, ietf.org, iso.org, itu.int, khronos.org | `specs/` | **Section-based**: one wiki page per major section |
| microsoft.com, docs.microsoft.com, learn.microsoft.com, developer.apple.com | `platform/` | **Single page**: one wiki page for the whole resource |
| Everything else (MDN, blogs, postmortems, wikis, etc.) | `others/` | **Single page**: one wiki page for the whole resource |

For `specs/` sources, also derive a **spec group** subfolder from the URL path:

- Take the last meaningful path segment (filename without extension, or last directory name)
- Slugify: lowercase, replace spaces and `/` with `-`, strip `.html`/`.txt`/`.pdf`
- Examples:
  - `html.spec.whatwg.org/multipage/media.html` → `specs/html-media/`
  - `w3.org/TR/webcodecs/` → `specs/webcodecs/`
  - `w3.org/TR/webaudio/` → `specs/webaudio/`
  - `ietf.org/rfc/rfc6381.txt` → `specs/rfc6381/`
  - `w3.org/TR/media-source/` → `specs/media-source/`

All section pages from a single spec ingest go into the same subfolder.

### S3 — Fetch and convert

```bash
SRC_URL="<the URL from $ARGUMENTS>"
SRC_MD="/tmp/wiki-url-ingest.md"

curl -sI "$SRC_URL" > /tmp/wiki-url-headers.txt
curl -sL --max-time 120 "$SRC_URL" \
  | pandoc -f html -t markdown --strip-comments --wrap=none \
  > "$SRC_MD"

ETAG=$(grep -i "^etag:" /tmp/wiki-url-headers.txt | tr -d '\r' | awk '{print $2}')
LAST_MOD=$(grep -i "^last-modified:" /tmp/wiki-url-headers.txt | tr -d '\r' | cut -d' ' -f2-)
FETCH_DATE=$(date +%Y-%m-%d)
```

### S4a — Section-based ingest (specs only)

Scan headings:
```bash
grep "^#" "$SRC_MD" | head -60
```

Identify major sections — `##` level headings that each represent a self-contained concept. Ignore navigation boilerplate (TOC, breadcrumbs, site headers/footers, cookie banners).

For each major section:

1. Extract content from its heading to the next same-level heading.
2. Distill into a structured summary — do not copy verbatim. Cover:
   - What this section defines
   - Key normative rules, states, algorithm steps
   - Omit: `§x.y` cross-references, implementor notes irrelevant to Firefox, pure navigation
3. Create or update `$WIKI_PATH/specs/<spec-group>/<slug>.md` (create the subfolder if needed):

```markdown
# <Section title>

<!-- source-url: <SRC_URL>#<anchor> -->
<!-- source-fetched: <FETCH_DATE> -->
<!-- source-etag: <ETAG> -->
<!-- source-last-modified: <LAST_MOD> -->

## Summary

## Key Rules

## States / Attributes

## Firefox-Specific Notes
```

If the page already exists: update content sections, preserve `## Firefox-Specific Notes`, refresh the metadata comments.

### S4b — Single-page ingest (platform/ and others/)

Distill the entire converted markdown into one wiki page. Cover:
- What this resource is and why it matters
- Key facts, behaviors, or constraints relevant to Firefox engineers
- Omit navigation, legal boilerplate, marketing content

Create or update `$WIKI_PATH/<platform|others>/<slug>.md`:

```markdown
# <Resource title>

<!-- source-url: <SRC_URL> -->
<!-- source-fetched: <FETCH_DATE> -->
<!-- source-etag: <ETAG> -->
<!-- source-last-modified: <LAST_MOD> -->

## Summary

## Key Points

## Firefox-Specific Notes
```

If the page already exists: update content, preserve `## Firefox-Specific Notes`, refresh metadata.

### S5 — Update INDEX.md

Add a row for each new page to the `## Specs & Platform` table:
```
| [[<slug>]] | <one-line description> |
```

Update the "Last updated" date.

### S6 — Log and push

Append to `usage-log.jsonl`:
```json
{"date":"<ISO timestamp>","event_type":"url-ingest","trigger":"user","url":"<SRC_URL>","directory":"<specs|platform|others>","pages_created":[...],"pages_updated":[...]}
```

Prepend an entry to `log.md` (after the `---` separator, before any prior entries):
```markdown
## <YYYY-MM-DD> — Ingest <domain/path>

Pages created: <list of relative paths>
Pages updated: <list, or "none">
Source: <SRC_URL>
```

```bash
cd $WIKI_PATH && git add -A && git commit -m "wiki: ingest <domain/path>" && git push
```

### S7 — Confirm

```
Ingested: <URL>  →  <specs|platform|others>/

Created: <list>
Updated: <list>

Re-run `/firefox-wiki:add <URL>` to refresh.
Staleness flagged automatically by `/firefox-wiki:lint --full`.
```

---

## PDF ingest path

### P1 — Classify the PDF

Determine whether the PDF is a public or private spec:

| Indicators | Classification |
|---|---|
| Filename/title contains ISO, IEC, ITU-T, MPEG, H.264, H.265, HEVC, AAC, MPEG-4 | **Private** — distill only, add notice |
| IETF RFC, W3C, WHATWG, Khronos, public domain | **Public** — distill only (best practice) |
| Internal doc, postmortem, design doc | **Private** — distill only |

Determine target directory and spec group:
- Formal standards (ISO, IEC, ITU-T, IETF, W3C, Khronos) → `specs/<spec-group>/` where spec group is derived from the filename (e.g. `h264-spec.pdf` → `specs/h264/`, `rfc6381.pdf` → `specs/rfc6381/`)
- Platform/vendor docs (Microsoft, Apple internal PDFs) → `platform/`
- Everything else → `others/`

### P2 — Read the PDF

Use the Read tool with the `pages` parameter. For large PDFs (>10 pages):

1. First read pages 1-3 to identify the document title, structure, and table of contents.
2. Map the major sections from the TOC.
3. Read each major section in chunks (up to 20 pages per call).

```
Read tool: file_path="<path>", pages="1-3"   # TOC / structure
Read tool: file_path="<path>", pages="4-20"  # first section
... and so on
```

### P3 — Determine ingest strategy

- If the PDF is a **spec with clear sections** (most ISO/ITU/IETF docs): section-based, one wiki page per major section — same as URL spec ingest (S4a).
- If the PDF is a **single-topic document** (design doc, postmortem, short reference): single page — same as URL single-page ingest (S4b).

### P4 — Create pages

Follow the same distillation rules as URL ingest (S4a or S4b). For private specs, prepend the notice to each page:

```markdown
> **Note**: This page contains distilled facts from a private/paid specification
> (ISO/IEC/ITU-T). No verbatim spec text is reproduced here.
```

Use this metadata block (no ETag — local file):

```markdown
<!-- source-url: file://<absolute-path> -->
<!-- source-fetched: <FETCH_DATE> -->
<!-- source-md5: <md5 of the file> -->
```

Compute the MD5:
```bash
md5 "<path>"   # macOS
```

### P5 — Update INDEX.md, log, and push

Same as URL ingest steps S5 and S6 (including the `log.md` entry). Commit message: `wiki: ingest <filename>`.

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

### 8. Update logs

Append to `usage-log.jsonl`:
```json
{"date":"<ISO 8601 timestamp>","event_type":"add","trigger":"user","file":"<relative path from WIKI_PATH>","confidence":"<High|Medium|Low>"}
```

Prepend an entry to `log.md` (after the `---` separator, before any prior entries):
```markdown
## <YYYY-MM-DD> — <one-line summary of what was added>

File: `<relative path>`
Confidence: <High|Medium|Low>
Source: <bug number, spec section, or colleague name>
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
