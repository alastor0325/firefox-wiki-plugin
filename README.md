# firefox-wiki-plugin

A Claude Code plugin that maintains a persistent Firefox knowledge wiki. It automatically ingests learnings after each bug fix, looks up prior knowledge before investigations, keeps spec references current, and enforces a content policy that prevents sensitive security information from leaking.

## How it works

```
You land a patch  →  PostToolUse hook fires  →  /firefox-wiki:ingest extracts knowledge
                                                  and writes to components/ relations/ bugs/

You start an investigation  →  /firefox-wiki:lookup searches the wiki
                                and surfaces relevant components, patterns, and prior bugs

You add a spec URL  →  /firefox-wiki:add fetches, distills, and stores it in specs/<group>/
```

The wiki lives in a separate git repo (`~/firefox-wiki/` by default, or `$WIKI_PATH`).

---

## User commands

| Command | Purpose |
|---|---|
| `/firefox-wiki:init` | One-time setup: create wiki directory structure, verify dependencies |
| `/firefox-wiki:add <input>` | Add knowledge — accepts a spec URL, `bug <id>`, or natural language fact |
| `/firefox-wiki:lint` | Check wiki integrity. Use `--full` for interval-based accuracy checks |
| `/firefox-wiki:verify` | Quarterly correctness check — re-reads cited sources to confirm facts are still true |
| `/firefox-wiki:stats` | View usage metrics and lookup hit rate |

### `/firefox-wiki:add` input types

| Input | What happens |
|---|---|
| `https://...` | Fetches the URL, distills it into one or more spec pages under `specs/` |
| Local `/path/to/file.pdf` | Reads the PDF and distills it into spec pages |
| `bug 2026875` | Delegates to the `ingest` skill to extract knowledge from the bug |
| Natural language | Classifies and writes to the appropriate `components/`, `relations/`, or `patterns/` page |

**Examples:**
```
/firefox-wiki:add https://www.w3.org/TR/media-source/
/firefox-wiki:add https://www.rfc-editor.org/rfc/rfc6716
/firefox-wiki:add bug 2026875
/firefox-wiki:add AudioSink runs on the MDSM task queue, not its own thread
```

---

## Agent-invoked skills (hidden from users)

These run automatically via hooks and are not intended to be called directly.

| Skill | When it runs |
|---|---|
| `ingest` | After every `git commit` in a Firefox repo — extracts knowledge from the landed patch |
| `lookup` | Before any bug investigation or triage session — surfaces relevant prior knowledge |
| `verify` | Quarterly — re-reads cited sources via gecko-navigator to confirm facts are still correct. Forbidden from reading the wiki itself to avoid circular verification. |

---

## Hooks

Three `PostToolUse` hooks run silently in the background:

| Hook | Trigger | Action |
|---|---|---|
| Auto-ingest | `Bash` tool runs `git commit` in a Firefox repo | Calls `/firefox-wiki:ingest --auto` |
| Read logging | `Read` tool reads a file under `firefox-wiki/` | Appends a `wiki_read` event to `usage-log.jsonl` |
| Lint | `Write` or `Edit` tool modifies a file under `firefox-wiki/` | Runs `/firefox-wiki:lint --lightweight` |

---

## Wiki structure

```
~/firefox-wiki/
  components/          # One page per Firefox class or subsystem
  relations/           # Cross-component interaction protocols
  patterns/            # Reusable mechanisms (e.g. WaitForData protocol)
  bugs/                # Learning pages for non-security resolved bugs
  specs/
    HTMLMedia_WHATWG/  # WHATWG HTML §4.8 media elements
    MSE_W3C/           # W3C MSE
    EME_W3C/           # W3C EME
    WebCodecs_W3C/     # W3C WebCodecs
    WebAudio_W3C/      # W3C Web Audio API
    WebRTC_W3C/        # W3C WebRTC
    AVC_ITU_H264/      # ITU-T H.264
    HEVC_ITU_H265/     # ITU-T H.265
    ISOBMFF_ISO_14496_12/  # ISO/IEC 14496-12
    CENC_ISO_23001_7/  # ISO/IEC 23001-7 (Common Encryption)
    ...                # (topic_org_identifier naming convention)
  INDEX.md             # Master index — read first in every session
  log.md               # Human-readable change history
  usage-log.jsonl      # Machine-readable event log
  lint-log.json        # Per-page lint and verify timestamps (lint-last, verify-last, lint-source-rev)
  verify-report.md     # Latest correctness verification report
```

---

## Accuracy model

Wiki accuracy is maintained through three layers:

| Layer | Mechanism | Frequency |
|---|---|---|
| **Write-time** | All facts must cite a verifiable source (Searchfox URL, spec §section, bug number, or official vendor doc). Enforced via `~/.claude/CLAUDE.md` and agent instructions. | Every write |
| **Lint** | Checks structure, broken links, dead Searchfox URLs, missing class definitions, spec ETag changes. Per-page intervals: components 14 days, specs 180 days. State tracked in `lint-log.json`. | Automatic after writes; `--full` on schedule |
| **Verify** | Re-reads cited sources from primary sources only (Firefox source code, spec URLs, vendor docs). Forbidden from reading the wiki itself to avoid circular verification. Flags stale or unverifiable facts for correction. | Quarterly |

---

## Content policy

**Never write to the wiki:**
- PoC or testcase code that triggers a crash
- Attack vectors, exploit chains, or race timing sequences
- Crash addresses, allocation sizes, or memory offsets
- Bug numbers of security bugs that are still restricted on Bugzilla
- Pre-fix conditions stated as current facts ("must do X to avoid Y")

**For security bugs:** extract only neutral, always-true structural facts (component role, ownership model, threading). If no such facts exist, write nothing.

**For specs:** always distill — never copy verbatim. For private/paid specs (ISO, IEC, ITU-T), add the required notice at the top of each page.

---

## Install

```shell
/plugin marketplace add firefox-wiki@firefox-wiki-local
/plugin install firefox-wiki@firefox-wiki-local
```

Clone the wiki content repo and initialize:

```bash
git clone https://github.com/alastor0325/firefox-wiki ~/firefox-wiki
```

```shell
/firefox-wiki:init
```

### Requirements

- `pandoc` — for URL/HTML spec ingestion (`brew install pandoc`)
- `jq` — for hook scripts (`brew install jq`)
- `bmo-to-md` — for bug ingestion (`cargo install bmo-to-md`)

---

## Local development

The plugin is loaded via a local marketplace. Changes to `skills/*/SKILL.md` or `hooks/hooks.json` take effect immediately — no reinstall needed (the cache is a symlink to this repo).

```bash
# Validate plugin structure
claude plugin validate .

# Test a skill directly
claude -p '/firefox-wiki:lint --full'
```

Bump `version` in `.claude-plugin/plugin.json` before any commit that changes skills or hooks.
