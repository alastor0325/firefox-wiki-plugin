---
name: lookup
description: Look up prior knowledge in the Firefox Knowledge Wiki before starting an investigation or triage. Returns synthesized context with citations.
version: 0.1.0
user-invocable: false
---

## When to invoke

Invoke at the start of every investigation or triage session, and any time a new component is encountered mid-investigation.

## Steps

### 1. Locate the wiki

Determine `WIKI_PATH`: use `$WIKI_PATH` if set, otherwise `~/firefox-wiki/`.

Check whether `$WIKI_PATH/INDEX.md` exists. If it does not, stop and say:

> Wiki not initialized — run /firefox-wiki:init

### 2. Determine the query

Parse `$ARGUMENTS`:
- If non-empty: use the arguments as the query text.
- If empty: infer the query from the current conversation — what bug, component, or symptom is being discussed?

### 3. Scan INDEX.md

Read `$WIKI_PATH/INDEX.md`. Scan the component, relation, and pattern tables for entries relevant to the query. Note which page files are referenced.

### 4. Grep the wiki for key terms

First, check whether the current conversation context contains a hook pre-lookup
result — a message starting with `Wiki hit for '<term>':`. If found, extract the
file paths listed there and skip the grep below; those paths are already the rg
results and can be used directly in step 5.

If no hook output is present, extract key terms from the query:
- Component names (C++ class names, method names, field names)
- Bug numbers (e.g. `1234567`)
- Error codes or HRESULT values
- Symptom keywords (stall, freeze, seek, encode, decrypt, etc.)

For each extracted term, run:

```bash
rg "<term>" ~/firefox-wiki/ --include="*.md" -l
```

Collect the union of files identified by the INDEX.md scan and by grep results.

### 5. Read the most relevant files

Read at most 4 files to keep context bounded. Priority order:

1. Relation page
2. Pattern page
3. Component page
4. Bug page

If a component page references another page via a `[[PageName]]` link that has not already been read, follow that link one level and read the target file as well (counts toward the 4-file limit).

If the query contains an error code or abbreviation, also read `$WIKI_PATH/glossary.md` (counts toward the limit).

### 6. Synthesize a response

Write the answer in this format:

```
## Wiki Context: <query summary>

**<Key finding 1>** — from [[PageName]]
<1-2 sentences of the relevant fact>

**<Key finding 2>** — from [[PageName]]
<1-2 sentences>

**Known failure modes** (if any):
- <mode> — [[bug-page]]

**Invariants to keep in mind**:
- <invariant>
```

If nothing relevant was found, say so explicitly:

> No prior wiki content for this query.

Then suggest: "After the investigation, add findings with `/firefox-wiki:add`."

### 7. Log read events

Append one JSON line to `$WIKI_PATH/usage-log.jsonl` for each file actually read:

Resolve the user field first:
```bash
WIKI_USER=$(git -C $WIKI_PATH config user.email 2>/dev/null || echo "unknown")
```

```json
{"date":"<ISO 8601 datetime>","event_type":"wiki_read","user":"<WIKI_USER>","trigger":"agent","file":"<path relative to WIKI_PATH>","query":"<query text>","bug_id":<number or null>}
```
