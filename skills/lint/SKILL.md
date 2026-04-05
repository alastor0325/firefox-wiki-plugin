---
name: lint
description: Check Firefox Knowledge Wiki integrity. Use --lightweight after writes (automatic) or --full to run all due accuracy checks based on per-page lint intervals.
version: 0.6.0
user-invocable: false
---

## Lint state: lint-log.json

All lint state is stored in a single file at `$WIKI_PATH/lint-log.json`. Pages are never modified by the lint skill — all metadata stays in this file.

### Format

```json
{
  "components/AudioSink.md": {
    "lint-last": "2026-04-05",
    "lint-source-rev": "abc123def"
  },
  "specs/MSE_W3C/overview.md": {
    "lint-last": "2026-01-10"
  }
}
```

- `lint-last` — ISO 8601 date of last successful lint pass for this page
- `lint-source-rev` — git hash of the Firefox tree at last lint (components/relations only)

Pages absent from `lint-log.json` are treated as never-linted and are always due.

### Reading and writing

Read the full log at the start of any full/force lint run:
```bash
cat $WIKI_PATH/lint-log.json 2>/dev/null || echo "{}"
```

After all checks complete, write the updated log in one atomic operation and commit:
```bash
# build updated JSON in memory, then write
echo '<updated-json>' > $WIKI_PATH/lint-log.json
cd $WIKI_PATH && git add lint-log.json && git commit -m "wiki: lint run $(date +%Y-%m-%d)"
```

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

- `--lightweight`: runs automatically after every wiki write (triggered by the PostToolUse hook on Write/Edit). Checks only recently modified files for broken links.
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
LINT_LOG = parsed lint-log.json
lint-last = LINT_LOG[page]["lint-last"] or "1970-01-01" if absent
interval = lookup from table above (by directory)

if (TODAY - lint-last) >= interval:
    → page is DUE — run checks
else:
    → page is CURRENT — skip
```

For `components/` and `relations/` pages that are due, additionally run the source-change check:

```bash
FIREFOX_ROOT=${MOZ_SRC:-$(git rev-parse --show-toplevel 2>/dev/null)}
CURRENT_REV=$(git -C $FIREFOX_ROOT rev-parse HEAD)
lint-source-rev = LINT_LOG[page]["lint-source-rev"] (empty if absent)

git -C $FIREFOX_ROOT log <lint-source-rev>..<CURRENT_REV> --oneline -- dom/media/ 2>/dev/null
```

If the log is **empty** (no commits to `dom/media/` since last lint): mark page as **source-unchanged** — skip accuracy checks, run structural checks only. Record `lint-last = TODAY` in `lint-log.json` but leave `lint-source-rev` unchanged.

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
   ls "$FIREFOX_ROOT/<path>" 2>/dev/null && echo "EXISTS" || echo "MISSING"
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

## Auto-fix pass

After all checks complete, automatically fix all mechanical issues before updating lint-log.json. Do not ask for confirmation — apply all fixes silently and include a count in the summary report.

### Fix 1: Spec-internal terms in spec pages

In all files under `specs/`, `platform/`, `others/`: find `[[PageName]]` links where the target does not exist anywhere under `$WIKI_PATH`. These are W3C/spec-defined terms (e.g. `[[append state]]`, `[[buffer full flag]]`) that were incorrectly marked as wiki-links during ingestion.

For each such broken link in a spec page: replace `[[PageName]]` with plain text `PageName` (strip the brackets).

```bash
# For each spec file with broken links, use sed to strip [[...]] for unresolved targets
sed -i 's/\[\[<broken-term>\]\]/<broken-term>/g' <spec-file>
```

Apply only to files under `specs/`, `platform/`, `others/` — never strip links in `components/`, `relations/`, `patterns/`, or `bugs/`.

### Fix 2: Bug link format

In all wiki files: find `[[bug XXXXXXX]]` patterns. For each, look up the matching bug page under `bugs/`:

```bash
find $WIKI_PATH/bugs -name "<XXXXXXX>-*.md" | head -1
```

- If found: replace `[[bug XXXXXXX]]` with `[[bugs/XXXXXXX-slug]]` (using the actual filename without `.md`)
- If not found: leave as-is — report as unresolvable in the summary

### Fix 3: Dead references to deleted pages

In `components/` and `relations/` pages: find `[[PageName]]` links where:
- The target does not exist anywhere under `$WIKI_PATH`
- The target is a relation or pattern page (contains `-` suggesting a relation, or matches a known deleted page)

For each such dead reference: replace `[[PageName]]` with plain text `PageName`.

Do **not** auto-remove references to missing component pages — those may need to be created, not removed. Only remove references to pages that were explicitly relation/pattern pages (identified by naming convention: `A-B` format for relations).

---

## After checks: update lint-log.json

After all pages have been checked, update `lint-log.json` in one pass:

For each page that was checked (due, not skipped):
- Set `lint-last` to TODAY
- For components/relations that ran accuracy checks: set `lint-source-rev` to `CURRENT_REV`
- For components/relations that were source-unchanged: leave `lint-source-rev` as-is

Build the updated JSON using `jq`:
```bash
jq --arg page "components/AudioSink.md" \
   --arg date "2026-04-05" \
   --arg rev "abc123def" \
   '.[$page] = {"lint-last": $date, "lint-source-rev": $rev}' \
   $WIKI_PATH/lint-log.json > /tmp/lint-log-new.json \
   && mv /tmp/lint-log-new.json $WIKI_PATH/lint-log.json
```

Repeat for each checked page, then commit once:
```bash
cd $WIKI_PATH && git add lint-log.json && git commit -m "wiki: lint run $(date +%Y-%m-%d)"
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
