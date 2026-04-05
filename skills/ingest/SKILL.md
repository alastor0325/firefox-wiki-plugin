---
name: ingest
description: Extract and store knowledge from a Firefox bug investigation into the wiki. Run after landing a patch. Supports --auto flag for non-interactive hook-triggered operation.
version: 0.1.0
user-invocable: false
---

## Content policy — sensitivity rules

Apply these rules before writing anything to the wiki:

**Never include:**
- PoC / testcase code that triggers a crash or exploit
- Precise race timing sequences or heap layout details that aid exploitation
- Crash addresses or stack frames with symbol offsets
- Bug numbers of security bugs that are still restricted on Bugzilla

**Security bug rule** — when the bug has a `sec-*` keyword or is still restricted:

1. Do **not** create a `bugs/<id>.md` page for it
2. Do **not** include the bug number in any page content
3. Do **not** describe the vulnerability root cause, the pre-fix condition, or the fix itself
4. Do **not** write "must do X" or "must not do Y" invariants derived from the bug — these describe the pre-fix state and are no longer true once the fix lands
5. Write **only** neutral, always-true structural facts: component role, ownership model, what thread it runs on, what it communicates with. Ask: "Is this fact true right now in the codebase, regardless of any bug?" If no, omit it.
6. If no neutral structural facts can be extracted, do **not** create or update any page
7. Cite as `<!-- source: sec bug, <YYYY-MM-DD> -->` with no bug number

For non-security bugs, the full `bugs/<id>.md` page and explicit bug number citations are appropriate.

---

When this skill is invoked, follow the protocol below exactly. First, detect the operating mode:

- If `$ARGUMENTS` contains `--auto`: run in **auto mode** (non-interactive, never prompts, make best-effort decisions at every step).
- Otherwise: run in **interactive mode** (ask clarifying questions when needed, show proposed changes before writing).

---

## Step 0 — Guard (auto mode only)

In auto mode, verify this is a Firefox repository commit before doing anything else:

Run `git remote get-url origin` in the current working directory.

If the remote URL does not contain any of `mozilla-central`, `firefox`, or `gecko`, exit silently. This commit is not in the Firefox repository and no ingest is needed.

---

## Step 1 — EXTRACT

Determine the bug ID:

- In interactive mode: ask "Which bug ID should I ingest? (or provide the path to an investigation file)"
- In auto mode: parse the most recent git commit message for a `Bug XXXXXXX` pattern. If no bug ID is found, exit silently.

Gather source material:

1. If `~/firefox-bug-investigation/bug-{id}-investigation.md` exists, read it.
2. If not, run `git log -1 --stat` and `git show HEAD` to understand what changed and use that as the source.

From the source material, extract the following:

- **Components involved**: class names, file names (e.g. `MediaFormatReader`, `AudioSink`)
- **Root cause mechanism**: the "why" — what invariant was violated or what interaction failed
- **Cross-component interactions**: how component A affects component B under condition C
- **Invariants discovered**: rules that must hold (e.g. "mWaitingPromise MUST be resolved whenever...")
- **Bug learning**: the distilled lesson worth remembering
- **Patches**: commit hashes and one-line descriptions

In interactive mode, print the full extraction summary and give the user a chance to review it before continuing. In auto mode, proceed directly to Step 2.

---

## Step 2 — DIFF AGAINST WIKI

Determine `WIKI_PATH`: use the `$WIKI_PATH` environment variable if set, otherwise default to `~/firefox-wiki/`. Verify that `INDEX.md` exists inside it.

For each component identified in Step 1:

- Read the existing component page at `components/<Name>.md` if it exists.
- Check whether the wiki already contains what was learned. If yes, mark it as "already known — skip".
- If no page exists yet, mark it as "new page needed".

For each cross-component interaction:

- Check whether a relation page exists (e.g. `relations/MFR-MDSM.md`).
- Same logic: already known → skip, new → create.

In interactive mode, show a diff summary ("Will create X, update Y, skip Z — proceed?") and wait for explicit confirmation before writing anything.

In auto mode, proceed without confirmation.

---

## Step 3 — WRITE

For each item marked as "create" or "update", write or modify the file as described below.

**Component page** (`components/<Name>.md`):

- If new: create with the following sections: Purpose, Key State (table), Key Methods (list), Known Pitfalls, Relations (links), Bugs That Taught Us (links).
- If existing: add to the Known Pitfalls section, or update Key State / Key Methods as appropriate.
- Tag all new content `[High]` (it comes from a verified investigation).
- Add a source comment on the same line as each new entry: `<!-- source: bug {id}, {date} -->`

**Relation page** (`relations/<A>-<B>.md`):

- If new: create with the following sections: Overview, Protocol description, Invariants, Failure Modes (table with bug links), Key Code Locations.
- If existing: add a row to the Failure Modes table, or update Protocol / Invariants as appropriate.
- Use `[[wiki-links]]` for all component references throughout.

**Bug learning page** (`bugs/{id}-{slug}.md`):

- Create one per bug — **except** for security bugs (see Content policy above). For sec bugs, write only to component/relation pages.
- Sections: One-Line Summary, Root Causes (numbered list, each with its lesson), Regression Source (if known), Components Involved (all as `[[links]]`), Patches (hash + one-line description).

**Pattern page** (`patterns/<name>.md`):

- Create only if the same mechanism appeared in 2 or more bugs, OR if the mechanism is complex enough to warrant its own page.
- Sections: What This Is, The State Machine (ASCII diagram if applicable), States and Transitions (table), Invariants, Bugs Where This Mattered.

Wiki-link rules that apply to all content:

- Link the first mention of each component, pattern, or bug per section using `[[PageName]]`.
- Do not link subsequent mentions of the same target within the same section.
- Do not create links to pages that do not exist yet, unless that page is being created in this same ingest run.

---

## Step 4 — LOG

Append the following block to `log.md`:

```markdown
## {date} — Bug {id}: {title}

**Context**: Landed patches {hashes}.
**Pages created**: [[page1]], [[page2]]
**Pages updated**: [[page3]], [[page4]]
**Key insight**: {1-2 sentence summary of the most important thing learned}

---
```

Append a single JSON object (one line) to `usage-log.jsonl`:

```json
{"date": "<ISO timestamp>", "event_type": "ingest", "user": "<git -C $WIKI_PATH config user.email>", "trigger": "<hook|user>", "bug_id": <number>, "pages_created": ["bugs/...", "patterns/..."], "pages_updated": ["components/...", "relations/..."], "hypothesis_from_wiki": <true|false>, "hypothesis_text": "<if applicable>", "hypothesis_correct": null}
```

To populate `hypothesis_from_wiki` and `hypothesis_text`: scan `usage-log.jsonl` for a prior `wiki_read` event whose `bug_id` matches this bug ID. If such an event is found, set `hypothesis_from_wiki: true` and copy the hypothesis text from that event. Otherwise set `hypothesis_from_wiki: false` and `hypothesis_text: ""`.

---

## Step 5 — INDEX UPDATE

Open `INDEX.md`. For each new page created in Step 3:

- Add a row to the appropriate table (Components, Relations, Patterns, or Specs & Platform).
- Component row format: `| [[Name]] | <one-line role> | [[Relation1]], [[Relation2]] |`
- Relation row format: `| [[Name]] | <what it captures> |`

Update the "Last updated" date at the top of `INDEX.md` to today's date.

---

## Step 6 — VERIFY

For every file created or modified during this ingest:

- Read the file back.
- Find all `[[...]]` patterns.
- For each wiki-link target, check that a file with that name exists somewhere under `WIKI_PATH`.
- Collect any targets with no corresponding file as broken links.

In interactive mode: report broken links to the user and offer to fix them before finishing.

In auto mode: append a warning entry to `log.md` listing each broken link, then continue without blocking.

---

## Step 7 — PUSH

Run:

```bash
cd $WIKI_PATH && git add -A && git commit -m "wiki: ingest bug {id} — {one-line summary}" && git push
```

In auto mode: run silently, do not print git output unless it fails.

---

## Step 8 — VERIFY NUDGE

After pushing, check `lint-log.json` for pages overdue for correctness verification.

Verify intervals by directory:
- `components/`: 30 days
- `relations/`: 90 days
- `patterns/`: 180 days
- `specs/`: 365 days
- `bugs/`: never

```bash
TODAY=$(date +%Y-%m-%d)
cat $WIKI_PATH/lint-log.json 2>/dev/null | jq -r '
  to_entries[] |
  select(.value["verify-last"] == null or
    (now - (.value["verify-last"] | strptime("%Y-%m-%d") | mktime)) > (
      if (.key | startswith("components/")) then 30
      elif (.key | startswith("relations/")) then 90
      elif (.key | startswith("patterns/")) then 180
      elif (.key | startswith("specs/")) then 365
      else 99999 end * 86400
    )
  ) | .key'
```

If any pages are returned, print (in both auto and interactive mode):

```
Note: <n> page(s) are overdue for correctness verification:
  components/: <n>  (interval: 30 days)
  relations/:  <n>  (interval: 90 days)
  ...
Run /firefox-wiki:wiki-verify to check them.
```

If nothing is overdue: print nothing.

---

## Final Output (interactive mode only)

After all steps are complete, print:

```
Ingest complete — Bug {id}

Created: {list}
Updated: {list}
Skipped (already known): {list}
Broken links: {list or "none"}

Key insight logged: {one sentence}
Pushed to remote.
```
