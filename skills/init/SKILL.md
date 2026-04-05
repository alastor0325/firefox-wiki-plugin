---
name: init
description: Initialize the Firefox Knowledge Wiki directory structure. Run once after cloning the wiki content repo.
version: 0.1.0
---

## Steps

### 0. Print pre-flight checklist

Before doing anything, print this checklist so the user can see what will be verified:

```
Firefox Knowledge Wiki — Pre-flight checks

  [ ] Wiki content repo cloned at ~/firefox-wiki/
  [ ] jq installed
  [ ] pandoc installed
  [ ] log-wiki-read.sh hook present
```

Then run each check in order. For each item, update its status as you go:
- `[✓]` — found / satisfied
- `[✗]` — missing — see action below

### 1. Determine WIKI_PATH

Use the `$WIKI_PATH` environment variable if set; otherwise default to `~/firefox-wiki/`.

### 2. Check wiki content repo

Check whether `$WIKI_PATH/INDEX.md` exists.

If **not found**, mark `[✗]` and stop with:

```
Firefox Knowledge Wiki content not found at ~/firefox-wiki/.

Please clone the wiki repo first:

  git clone https://github.com/alastor0325/firefox-wiki ~/firefox-wiki

Note: this is a private repo. If you don't have access, contact :alwu (alwu@mozilla.com) to request it.

Once cloned, re-run /firefox-wiki:init.
```

Do not proceed further.

### 3. Check jq

Run `which jq`.

If **not found**, mark `[✗]` and ask:

```
jq is not installed. Install it now?

  brew install jq

Reply "yes" to install, or "no" to abort.
```

Wait for the user's reply:
- **yes** → run `brew install jq`, verify it succeeds, mark `[✓]`, continue
- **no** → stop. Do not proceed to the next step.

### 4. Check pandoc

Run `which pandoc`.

If **not found**, mark `[✗]` and ask:

```
pandoc is not installed. It is required for URL ingestion (/firefox-wiki:add <url>). Install it now?

  brew install pandoc

Reply "yes" to install, or "no" to abort.
```

Wait for the user's reply:
- **yes** → run `brew install pandoc`, verify it succeeds, mark `[✓]`, continue
- **no** → stop. Do not proceed to the next step.

### 5. Check hook script

Check whether `${CLAUDE_PLUGIN_ROOT}/scripts/log-wiki-read.sh` exists.

If **not found**, mark `[✗]` and warn (non-blocking — continue):

```
Warning: log-wiki-read.sh not found. Wiki read events will not be logged.
Re-install the plugin to fix: /plugin install firefox-wiki@firefox-wiki-plugin
```

### 6. Create directory structure

Run `mkdir -p` for each of the following (it is safe to run even if they already exist):

- `$WIKI_PATH/specs/`
- `$WIKI_PATH/platform/`
- `$WIKI_PATH/components/`
- `$WIKI_PATH/relations/`
- `$WIKI_PATH/patterns/`
- `$WIKI_PATH/bugs/`

### 7. Create files if they do not already exist

Never overwrite a file that is already present. Check for existence before writing each one.

**`$WIKI_PATH/usage-log.jsonl`** — create as an empty file.

**`$WIKI_PATH/log.md`** — create with this content:

```markdown
# Wiki Change Log
Append-only. One entry per ingest or significant update.
```

**`$WIKI_PATH/glossary.md`** — create only if it does not already exist (the cloned wiki repo will already have a populated glossary.md — never overwrite it). If creating from scratch, use this minimal stub:

```markdown
# Glossary

Use `/firefox-wiki:add` to populate this file with quick-reference entries as you encounter them.
```

**`$WIKI_PATH/INDEX.md`** — create with this content, substituting today's date for `(today's date)`:

```markdown
# Firefox Knowledge Wiki

Last updated: (today's date)

## How to Use This Wiki

- Claude reads this file first before any investigation or triage session
- All component names, bug numbers, and pattern names use [[wiki-links]]
- After investigations, Claude updates affected pages and appends to log.md
- Run `/firefox-wiki:stats` monthly to review usage metrics

## Components

| Component | Role | Key Relations |
|---|---|---|

## Relations

| Relation | What It Captures |
|---|---|

## Patterns

| Pattern | Summary |
|---|---|

## Specs & Platform

| File | Covers |
|---|---|

## Recent Learnings

See [[log.md]] for full history.
```

### 8. Print a status report

```
Firefox Knowledge Wiki initialized at: ~/firefox-wiki/

Directories: ✓ specs/ ✓ platform/ ✓ components/ ✓ relations/ ✓ patterns/ ✓ bugs/
Files:       ✓ INDEX.md  ✓ log.md  ✓ glossary.md  ✓ usage-log.jsonl

Next steps:
- Add knowledge:       /firefox-wiki:add <statement or URL>
- Before investigating: wiki lookup runs automatically
```
