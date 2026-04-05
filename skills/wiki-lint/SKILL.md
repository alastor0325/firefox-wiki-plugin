---
description: Check Firefox Knowledge Wiki integrity. Use --lightweight after writes (automatic) or --full for monthly health checks.
---

## When to invoke

- `--lightweight`: automatically after every wiki write (Hook 3). Checks only recently modified files.
- `--full`: monthly, for a comprehensive health check across the entire wiki.

## Mode detection

Parse `$ARGUMENTS`:
- Contains `--lightweight`: run lightweight mode.
- Contains `--full`: run full mode.
- Empty: default to lightweight mode.

---

## Lightweight mode

Runs automatically after each wiki write. Scopes checks to recently modified files only.

### Steps

1. Identify recently modified wiki files by reading the last entry in `$WIKI_PATH/log.md`, or by running:
   ```bash
   ls -lt ~/firefox-wiki/**/*.md | head -5
   ```

2. For each recently modified file:
   - Extract all `[[PageName]]` patterns:
     ```bash
     rg '\[\[([^\]]+)\]\]' <file> -o --no-filename
     ```
   - For each extracted `PageName`, check whether `<PageName>.md` exists anywhere under `$WIKI_PATH`:
     ```bash
     find ~/firefox-wiki/ -name "<PageName>.md"
     ```
   - If the file is not found: report a broken link error showing the link text, the file it appears in, and a suggested fix.

3. If broken links are found: print them clearly. Do not continue silently — the output must be visible so the broken link can be fixed immediately.

4. If all links are valid: print nothing. Silent success, no noise.

---

## Full mode

Comprehensive health check across the entire wiki. Run monthly.

### 1. Broken links scan

Grep all `*.md` files for `[[...]]` patterns. For each link verify the target file exists. Report all broken links grouped by source file.

### 2. INDEX.md completeness

For every `.md` file under `components/`, `relations/`, and `patterns/`: check that it appears in `INDEX.md`. Report any pages missing from the index.

### 3. Orphaned index entries

Find every entry in `INDEX.md` that does not have a corresponding file on disk. Report each.

### 4. Stale page detection

Find component and relation pages whose last-modified time is 180 or more days ago. List them as:

> Potentially stale — verify against current codebase.

### 5. Missing required sections

Scan each component page for the following required section headings:
- `Purpose`
- `Known Pitfalls`
- `Relations`
- `Bugs That Taught Us`

Report any component page missing one or more of these headings.

### 6. Oversized pages

Find any `.md` file exceeding 300 lines. Report each as a candidate for splitting.

### 7. Pattern synthesis candidates

Read all bug learning pages. Group them by component pairs mentioned. If 3 or more bugs share the same component pair and no pattern page exists for that pair, suggest:

> Consider creating a pattern page for \<A\>-\<B\> interactions (appears in bugs X, Y, Z)

### 8. Summary report

Print:

```
## Wiki Lint Report — <date>

Broken links: <n> issues
Missing from index: <n> pages
Orphaned index entries: <n>
Potentially stale: <n> pages
Missing required sections: <n>
Oversized pages: <n>
Pattern synthesis candidates: <n>

<details for each category>
```
