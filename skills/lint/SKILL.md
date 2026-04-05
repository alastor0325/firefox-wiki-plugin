---
name: lint
description: Check Firefox Knowledge Wiki integrity. Use --lightweight after writes (automatic) or --full to run all due accuracy checks based on per-page lint intervals.
version: 0.3.0
---

## Lint metadata

Every wiki page carries two metadata comments that drive interval-based linting:

```
<!-- lint-last: 2026-04-05 -->
<!-- lint-source-rev: abc123def -->
```

- `lint-last` — date of last successful lint for this page (ISO 8601)
- `lint-source-rev` — git hash of the Firefox tree at the time of last lint (components/relations only; omitted for specs/patterns/bugs)

These are written by the lint skill after each page passes its checks. Pages without these comments are treated as never-linted (lint immediately).

## Lint intervals by content type

| Directory | Interval | Source-change check |
|---|---|---|
| `components/` | 14 days | Yes — skip if no Firefox commits since `lint-source-rev` |
| `relations/` | 14 days | Yes — skip if no Firefox commits since `lint-source-rev` |
| `patterns/` | 90 days | No |
| `specs/` | 180 days | No — use ETag/MD5 instead |
| `platform/` | 180 days | No — use ETag/MD5 instead |
| `others/` | 180 days | No |
| `bugs/` | Never | Historical record — never re-lint |

## When to invoke

- `--lightweight`: automatically after every wiki write (Hook 3). Checks only recently modified files for broken links.
- `--full`: run all checks that are due based on per-page intervals. Pages not yet past their interval are skipped.
- `--force`: like `--full` but ignores intervals — checks every page regardless of `lint-last`.

## Mode detection

Parse `$ARGUMENTS`:
- Contains `--lightweight`: run lightweight mode.
- Contains `--force`: run full mode with interval checking disabled.
- Contains `--full`: run full mode with interval checking enabled.
- Empty: default to lightweight mode.

---

## Lightweight mode

Runs automatically after each wiki write. Fast — structural checks only on recently modified files.

### Steps

1. Identify recently modified wiki files:
   ```bash
   git -C $WIKI_PATH diff --name-only HEAD~1 HEAD 2>/dev/null || ls -lt $WIKI_PATH/**/*.md | head -5
   ```

2. For each recently modified file:
   - Extract all `[[PageName]]` patterns:
     ```bash
     rg '\[\[([^\]]+)\]\]' <file> -o --no-filename
     ```
   - For each `PageName`, check whether `<PageName>.md` exists anywhere under `$WIKI_PATH`:
     ```bash
     find $WIKI_PATH -name "<PageName>.md"
     ```
   - If not found: report a broken link error with the link text, source file, and a suggested fix.

3. If broken links found: print them clearly.

4. If all valid: silent success — print nothing.

---

## Full mode

Runs all checks that are due. For each page, first determine whether it needs linting:

### Due check (per page)

```
TODAY = current date
lint-last = read from page metadata (or epoch if absent)
interval = lookup from table above (by directory)

if (TODAY - lint-last) >= interval:
    → page is DUE — run checks
else:
    → page is CURRENT — skip
```

For `components/` and `relations/` pages that are due, additionally run the source-change check:

```bash
# Get Firefox repo root
FIREFOX_ROOT=$(git -C ~/firefox rev-parse --show-toplevel 2>/dev/null || echo ~/firefox)

# Get current HEAD
CURRENT_REV=$(git -C $FIREFOX_ROOT rev-parse HEAD)

# Check if any relevant files changed since lint-source-rev
git -C $FIREFOX_ROOT log <lint-source-rev>..<CURRENT_REV> --oneline -- dom/media/ 2>/dev/null
```

If the log is **empty** (no commits to `dom/media/` since last lint): mark page as **source-unchanged** and skip accuracy checks (only run structural checks). Update `lint-last` to today without updating `lint-source-rev`.

If the log is **non-empty** or `lint-source-rev` is absent: run all checks for this page.

---

### Check 1: Broken links scan

Grep all due `*.md` files for `[[...]]` patterns. For each link verify the target file exists. Report all broken links grouped by source file.

### Check 2: INDEX.md completeness

For every `.md` file under `components/`, `relations/`, and `patterns/`: check that it appears in `INDEX.md`. Report any pages missing from the index.

### Check 3: Orphaned index entries

Find every entry in `INDEX.md` that does not have a corresponding file on disk. Report each.

### Check 4: Missing required sections

Scan each due component page for required section headings:
- `## Overview` or `## Purpose`
- `## Relations`

Report any component page missing these headings.

### Check 5: Oversized pages

Find any due `.md` file exceeding 300 lines. Report as a candidate for splitting.

### Check 6: Spec staleness check (specs/ platform/ others/ only)

For each due spec page with a `<!-- source-url: <url> -->` comment:

1. Extract URL and stored ETag/Last-Modified/MD5:
   ```bash
   grep "source-url\|source-etag\|source-last-modified\|source-md5" <file>
   ```

2. For **remote URLs**: fetch current headers only:
   ```bash
   curl -sI --max-time 10 "<url>"
   ```
   Compare current `etag` or `last-modified` against stored value.

   For **local PDFs** (`file://`): compute current MD5:
   ```bash
   md5 "<local-path>"
   ```
   Compare against stored `source-md5`.

3. Verdict:
   - **Unchanged**: mark current.
   - **Changed**: flag as stale — "spec updated since last ingest. Re-run `/firefox-wiki:add <url>` to refresh."
   - **Unreachable / file missing**: mark "unverified — check manually".

### Check 7: Dead Searchfox links (components/ relations/ only)

For each due page, find all `searchfox.org/mozilla-central/rev/<hash>/...` URLs:

1. Extract `<path>` from URL.

2. Check file existence in current Firefox tree:
   ```bash
   ls $FIREFOX_ROOT/<path> 2>/dev/null && echo "EXISTS" || echo "MISSING"
   ```

3. If file exists, check symbol from surrounding sentence:
   ```bash
   searchfox-cli --id '<symbol>' --cpp -l 5
   ```

4. Verdict:
   - **File missing**: dead link — "file no longer exists at `<path>`"
   - **Symbol missing**: potentially stale — "symbol `<name>` not found in current tree"
   - **OK**: current

### Check 8: Missing citations (components/ relations/ patterns/ only)

For each due page, scan for fact lines without a source citation.

A **fact line**: non-empty, not a heading, not a table delimiter, not inside a code block, contains a class/method/field name or behavioral assertion.

A **citation**: `<!-- source: ... -->` comment, `[High/Medium/Low]` tag, Searchfox URL, or spec section reference (`§`) on the same line.

Flag uncited fact lines as:
> `components/Foo.md:42` — uncited claim: "<line text>"

Limit to first 20 uncited lines per file. Advisory only — do not fail lint.

### Check 9: Symbol existence check (components/ only)

For each due component page, extract the primary class name from the page title (`# ClassName`).

```bash
searchfox-cli --define '<ClassName>' --cpp -l 1
```

If not found:
> `components/<Name>.md` — class `<Name>` not found in current tree. Page may describe a removed or renamed component.

### Check 10: Pattern synthesis candidates

Read all bug pages. Group by component pairs mentioned. If 3+ bugs share the same component pair and no pattern page exists, suggest:
> Consider creating a pattern page for `<A>`-`<B>` interactions (appears in bugs X, Y, Z)

---

## After checks: update lint metadata

For each page that was checked (due and not skipped):

1. If all checks passed (or only advisory issues): update metadata comments in the page:
   ```
   <!-- lint-last: <TODAY> -->
   <!-- lint-source-rev: <CURRENT_REV> -->   ← components/relations only
   ```

2. Commit the metadata updates:
   ```bash
   cd $WIKI_PATH && git add -A && git commit -m "wiki: lint metadata update $(date +%Y-%m-%d)"
   ```

---

## Summary report

```
## Wiki Lint Report — <date> (<--full|--force>)

Pages checked:              <n> of <total> (remainder not yet due)

Broken links:               <n> issues
Missing from index:         <n> pages
Orphaned index entries:     <n>
Missing required sections:  <n>
Oversized pages:            <n>
Stale specs:                <n> (spec updated upstream)
Dead Searchfox links:       <n> (file/symbol missing in current tree)
Uncited claims:             <n> lines  (advisory)
Missing class definitions:  <n> components
Pattern synthesis:          <n> candidates

Next due:
  components/  — <date of next component page due>
  specs/       — <date of next spec page due>

<details for each category>
```
