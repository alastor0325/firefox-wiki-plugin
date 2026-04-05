# firefox-wiki-plugin

A Claude Code plugin that gives Claude a persistent memory of Firefox media subsystem knowledge — so it stops redoing the same code archaeology every investigation and builds on what it already knows.

Without this plugin, Claude re-searches the same components, re-reads the same files, and re-derives the same facts every session. With it, knowledge accumulates: every investigation adds to the wiki, and every future investigation starts from what was already learned.

> **The wiki content is maintained in a shared private repo.** You need access to get the accumulated knowledge — without it you start from an empty wiki and lose the team's prior learnings. Request access from :alwu (alwu@mozilla.com) before installing.

## What you get automatically

Once installed, no ongoing effort is required.

**Before every code search** — when Claude is about to run `searchfox-cli` or grep under `dom/media`, a hook scans the wiki first. If it finds relevant prior knowledge, Claude reads it and may skip the code search entirely.

**After every patch** — when Claude commits in a Firefox repo, a hook fires and extracts knowledge from the changes, storing it in the wiki for future sessions.

**After every wiki write** — a hook runs a lightweight lint pass to catch broken links and stale references.

You can also add knowledge manually at any time — spec URLs, bug learnings, or free-form facts — using `/firefox-wiki:add`. See [Commands](#commands) for details.

## Install

**1. Add the plugin:**
```shell
/plugin marketplace add firefox-wiki@firefox-wiki-local
/plugin install firefox-wiki@firefox-wiki-local
```

**2. Clone the wiki content repo:**
```bash
git clone https://github.com/alastor0325/firefox-wiki ~/firefox-wiki
```

**3. Initialize:**
```shell
/firefox-wiki:init
```

This verifies dependencies and creates the wiki directory structure. Follow any prompts it shows.

**Requirements:** `jq` · `pandoc` · `bmo-to-md`
```bash
brew install jq pandoc && cargo install bmo-to-md
```

---

## Commands

| Command | Purpose |
|---|---|
| `/firefox-wiki:init` | One-time setup |
| `/firefox-wiki:add <input>` | Add a spec, bug, or fact to the wiki |
| `/firefox-wiki:stats` | View usage metrics and lookup hit rate |

### Adding knowledge

`/firefox-wiki:add` accepts several input types:

| Input | What happens |
|---|---|
| `https://...` | Fetches and distills into `specs/` |
| `/path/to/file.pdf` | Reads PDF and distills into `specs/` |
| `bug 2026875` | Extracts knowledge from the bug |
| Natural language | Writes to `components/`, `relations/`, or `patterns/` |

```
/firefox-wiki:add https://www.w3.org/TR/media-source/
/firefox-wiki:add bug 2026875
/firefox-wiki:add AudioSink runs on the MDSM task queue, not its own thread
```

---

## Wiki structure

```
~/firefox-wiki/
  components/          # One page per Firefox class or subsystem
  relations/           # Cross-component interaction protocols
  patterns/            # Reusable mechanisms (e.g. WaitForData protocol)
  bugs/                # Learning pages for resolved non-security bugs
  specs/               # Distilled spec references (topic_org_identifier naming)
    MSE_W3C/
    EME_W3C/
    HTMLMedia_WHATWG/
    AVC_ITU_H264/
    HEVC_ITU_H265/
    ISOBMFF_ISO_14496_12/
    CENC_ISO_23001_7/
    ...
  INDEX.md             # Master index — Claude reads this first every session
  log.md               # Human-readable change history
  usage-log.jsonl      # Machine-readable event log
  lint-log.json        # Per-page lint and verify timestamps
  verify-report.md     # Latest verification report
```

---

## Accuracy

Every fact in the wiki must cite a verifiable source — a Searchfox URL, spec section, or bug number. Facts from memory or inference are not permitted.

Accuracy is maintained through three layers:

| Layer | What it checks | When |
|---|---|---|
| Write-time | Source citation present and valid | Every write |
| Lint | Broken links, dead Searchfox URLs, spec changes. Per-page intervals: components 14d, specs 180d | After every write; full scan on schedule |
| Verify | Re-reads primary sources and flags stale or unverifiable facts | User-triggered; nudged by `ingest`/`add` when pages are overdue |

---

## Content policy

**Never write to the wiki:**
- PoC code, crash triggers, exploit chains, or attack vectors
- Crash addresses, allocation sizes, or memory offsets
- Bug numbers of security-restricted Bugzilla bugs
- Pre-fix conditions stated as current facts

**Security bugs:** extract only neutral structural facts (component role, threading, ownership). If none exist, write nothing.

**Specs:** always distill — never copy verbatim. Add the required notice at the top of each page for private/paid specs (ISO, IEC, ITU-T).

---

## Development

Changes to `skills/*/SKILL.md` or `hooks/hooks.json` take effect immediately — no reinstall needed.

```bash
claude plugin validate .               # validate plugin structure
claude -p '/firefox-wiki:lint --full'  # test a skill
```

Bump `version` in `.claude-plugin/plugin.json` before any commit that changes skills or hooks.
