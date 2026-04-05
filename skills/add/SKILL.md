---
name: add
description: Add a fact, explanation, or note to the Firefox Knowledge Wiki in natural language. Claude decides which page to update or create.
version: 0.1.0
---

## Steps

### 1. Read the input

Read `$ARGUMENTS`. If empty, ask the user:

> "What would you like to add to the wiki? Describe the fact, behavior, or concept."

### 2. Locate the wiki

Determine WIKI_PATH: use the `$WIKI_PATH` environment variable if set, otherwise `~/firefox-wiki/`.

Check that `$WIKI_PATH/INDEX.md` exists. If not, tell the user:

> "Wiki not initialized. Run `/firefox-wiki:init` first."

Then stop.

### 3. Read INDEX.md

Read `$WIKI_PATH/INDEX.md` to understand the current wiki structure — which components, relations, patterns, specs, and bugs are already cataloged.

### 4. Classify the input

Determine which content type best matches the input:

| Type | Criteria | Target path |
|---|---|---|
| **Component fact** | About a specific Firefox class or component | `components/<Name>.md` |
| **Interaction/protocol** | How two components relate or communicate | `relations/<A>-<B>.md` |
| **Reusable pattern** | A mechanism that appears in multiple contexts | `patterns/<name>.md` |
| **Spec/standard behavior** | Codec, container, or web spec behavior | `specs/<name>.md` or `platform/<name>.md` |
| **Bug learning** | Distilled insight from a resolved bug | `bugs/<id>-<slug>.md` |
| **Glossary entry** | Abbreviation, error code, or enum value | `glossary.md` |

### 5. Determine confidence level

If not obvious from context, ask the user:

> "What is the confidence level for this fact?
> - [High] — verified by reading source code
> - [Medium] — inferred from observed behavior or documentation
> - [Low] — extrapolated or from memory; needs future verification"

If the user's phrasing makes the confidence obvious (e.g. "I just read the code and confirmed that..." implies High; "I think..." implies Low), infer it without asking.

### 6. Determine source citation

Identify the source if available: bug number, revision hash, spec section, or colleague name. Ask if it is not clear from the input and the user has not already provided it.

### 7. Determine the target page and write the content

**If a relevant page already exists:** append to the appropriate section within that page.

**If no page exists yet:** create it using the standard template for its type (see templates below).

**If the content spans multiple pages** (e.g. a fact about how component A interacts with component B): write the full content on the relation page (`relations/<A>-<B>.md`) and add a cross-reference line in each of the component pages.

Format the new content as:

```markdown
### <Section heading if a new section is needed>
<content> [High] <!-- source: bug 2026875, 2026-04-04 -->
```

If the content fits naturally into an existing section, append without adding a new heading.

Use `[[wiki-links]]` for every component, pattern, or bug name mentioned in the content.

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

**Spec/platform page** (`specs/<name>.md` or `platform/<name>.md`):
```markdown
# <Name>

## Summary

## Key Rules

## Firefox-Specific Notes
```

**Bug learning page** (`bugs/<id>-<slug>.md`):
```markdown
# Bug <id> — <slug>

## Root Cause

## Fix Summary

## Learnings
```

### 8. Update INDEX.md if a new page was created

If a new page was created in this step, add a row for it to the appropriate table in INDEX.md.

### 9. Append to usage-log.jsonl

Append a single line to `$WIKI_PATH/usage-log.jsonl`:

```json
{"date":"<ISO 8601 timestamp>","event_type":"add","trigger":"user","file":"<relative path from WIKI_PATH>","confidence":"<High|Medium|Low>"}
```

### 10. Lint wiki-links

After writing, scan the modified file for all `[[PageName]]` references. For each one, check whether a file named `<PageName>.md` exists anywhere under `$WIKI_PATH`. Report any broken links to the user.

### 11. Push to remote

Run:

```bash
cd $WIKI_PATH && git add -A && git commit -m "wiki: add <one-line summary of what was added>" && git push
```

### 12. Confirm to the user

Print a confirmation in this format:

```
Added to `<relative file path>` with [<confidence>] tag. [[links]] verified. Pushed to remote.
```

If any broken links were found, list them after the confirmation line.
