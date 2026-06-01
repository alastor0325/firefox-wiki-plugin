---
name: init
description: Initialize the Firefox Knowledge Wiki directory structure. Run once after cloning the wiki content repo.
version: 0.3.0
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
  [ ] git user.email configured
  [ ] wiki-config.json present (search tool + trigger paths)
  [ ] WIKI_PATH persisted    (only shown when WIKI_PATH is non-default)
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

### 6. Check git user.email

Run:
```bash
git config user.email
```

- **Set**: mark `[✓]` — this value will be used as `user` in all log events.
- **Not set**: mark `[✗]` and warn (non-blocking — continue):

```
Warning: git user.email is not configured. All wiki log events will be
attributed to "unknown", which will make per-person stats meaningless.

Fix with:
  git config --global user.email "you@mozilla.com"
```

### 7. Create directory structure

Run `mkdir -p` for each of the following (it is safe to run even if they already exist):

- `$WIKI_PATH/specs/`
- `$WIKI_PATH/platform/`
- `$WIKI_PATH/others/`
- `$WIKI_PATH/components/`
- `$WIKI_PATH/relations/`
- `$WIKI_PATH/patterns/`
- `$WIKI_PATH/architecture/`
- `$WIKI_PATH/triage/`
- `$WIKI_PATH/profiler/`
- `$WIKI_PATH/bugs/`

### 8. Create files if they do not already exist

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

### 9. Configure the trigger surface (`wiki-config.json`)

This file lives in the wiki repo and controls which code searches trigger the pre-lookup hook. It travels with the wiki, so a personal wiki for another subsystem (e.g. graphics) carries its own trigger paths. Defaults reproduce the original Firefox-media behavior.

**If `$WIKI_PATH/wiki-config.json` does not exist**, prompt the user (pressing Enter accepts the defaults shown):

```
Configure the wiki trigger surface (press Enter for defaults):

  Search tool that fires the pre-lookup hook [searchfox-cli]:
  Source paths to watch, space-separated [dom/media]:
```

Then write it (substituting the answers; `$TRIGGER_PATHS` is the space-separated reply):

```bash
jq -n --arg st "${SEARCH_TOOL:-searchfox-cli}" --arg tp "${TRIGGER_PATHS:-dom/media}" \
  '{schema:1, search_tool:$st,
    trigger_paths:($tp|split(" ")|map(select(length>0))),
    source_repo_pattern:"(mozilla-central|gecko|mozilla-firefox/firefox)"}' \
  > "$WIKI_PATH/wiki-config.json"
```

**If it already exists**, show the current values with `jq . "$WIKI_PATH/wiki-config.json"` and ask whether to update. Only on confirmation, merge **without clobbering** unknown keys (preserves `source_repo_pattern` and any future fields):

```bash
jq --arg st "$SEARCH_TOOL" --argjson tp "$TRIGGER_PATHS_JSON" \
   '.search_tool=$st | .trigger_paths=$tp' \
   "$WIKI_PATH/wiki-config.json" > "$WIKI_PATH/wiki-config.json.tmp" \
   && mv "$WIKI_PATH/wiki-config.json.tmp" "$WIKI_PATH/wiki-config.json"
```

Mark `[✓]` in the checklist. Changes take effect immediately (hooks read the file live).

### 10. Persist WIKI_PATH (only when it is non-default)

Skip this step entirely when the resolved `WIKI_PATH` equals `$HOME/firefox-wiki`.

Hooks read `WIKI_PATH` from the environment. Claude Code populates the hook environment from the `env` block of `~/.claude/settings.json` at startup — a shell-profile `export` is unreliable because hooks may run under a GUI/launchd-spawned process that never sourced your profile. So persist it there. Offer to do it, and on confirmation merge without clobbering existing settings:

```bash
SETTINGS="$HOME/.claude/settings.json"
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
jq --arg p "$WIKI_PATH" '.env = (.env // {}) | .env.WIKI_PATH = $p' \
   "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
```

Tell the user this **takes effect in the next Claude Code session** (the `env` block is read at startup), and print the value so they can instead `export WIKI_PATH=<path>` in the shell they launch Claude Code from if they prefer. Mark `[✓]`.

### 11. Check wiki maintenance instruction

This step ensures the wiki write-back rule is active in the user's global Claude config. It is **non-blocking** — if the user declines, continue to the status report.

The wiki maintenance paragraph to check for / add is:

```
## Wiki maintenance
After any investigation, bug fix, or code review session, write back any
non-obvious facts discovered to the Firefox Knowledge Wiki (~/.firefox-wiki/
or $WIKI_PATH) using /firefox-wiki:add. This includes: spec-component
mappings, Firefox deviations from spec, component behaviors,
threading/ownership facts, and architectural observations.

Every addition must cite a verifiable source:
- Code facts: a Searchfox permanent URL (e.g. https://searchfox.org/mozilla-central/rev/<hash>/path/to/file.cpp#42)
- Spec facts: spec name + section (e.g. "ITU-T H.265 §7.4.8", "ISO/IEC 14496-15:2022 §4.2")
- Bug facts: Bugzilla bug number (e.g. bug 2026875)

Do not add facts from memory or inference alone — only what you can directly
point to. If you cannot provide a source, do not write to the wiki.
```

**Skip check:** Before doing anything, check whether `WIKI_MAINTENANCE_SKIP=1` is present in `~/.claude/CLAUDE.md`. If so, skip this step silently and mark `[–]`.

**Detection:**

```bash
grep -q "Wiki maintenance" ~/.claude/CLAUDE.md 2>/dev/null && echo "PRESENT" || echo "ABSENT"
```

- **PRESENT** → mark `[✓]` — already configured. No action needed.
- **ABSENT** → show the following prompt:

```
Wiki maintenance instruction not found in ~/.claude/CLAUDE.md.

This tells Claude to write back facts discovered during investigations to
the wiki, with verifiable source citations. It lives in your global config
so it applies in all sessions while you evaluate it. Once proven, you can
move it to your repo's AGENTS.md and remove it from the global config.

Add it to ~/.claude/CLAUDE.md now? (yes / no / skip-always)
```

- **yes** → append the paragraph to `~/.claude/CLAUDE.md`, mark `[✓]`, continue
- **no** → mark `[–]` (skipped this time), continue
- **skip-always** → append a line `# WIKI_MAINTENANCE_SKIP=1` to `~/.claude/CLAUDE.md` so this check is suppressed in future runs, mark `[–]`, continue

Also update the pre-flight checklist in step 0 to include this item:

```
  [ ] Wiki maintenance instruction active
```

### 12. Print a status report

```
Firefox Knowledge Wiki initialized at: <WIKI_PATH>

Directories: ✓ specs/ ✓ platform/ ✓ others/ ✓ components/ ✓ relations/ ✓ patterns/ ✓ architecture/ ✓ triage/ ✓ profiler/ ✓ bugs/
Files:       ✓ INDEX.md  ✓ log.md  ✓ glossary.md  ✓ usage-log.jsonl
Config:      ✓ wiki-config.json (search_tool=<tool>, trigger_paths=<paths>)
WIKI_PATH:   <default ~/firefox-wiki | <path> — persisted to settings.json (restart to apply) | <path> — from environment>
User:        <email from git config | ✗ not set — run: git config --global user.email "you@mozilla.com">
Maintenance: <✓ active in AGENTS.md | ✓ active in ~/.claude/CLAUDE.md | – skipped>

You're ready. Just start working on bugs — the plugin will build the wiki automatically.

Optionally:
- Seed with existing knowledge:  /firefox-wiki:add <spec URL, bug id, or fact>
- Check usage after sessions:    /firefox-wiki:stats
```
