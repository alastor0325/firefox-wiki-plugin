---
description: Initialize the Firefox Knowledge Wiki directory structure. Run once after cloning the wiki content repo.
---

## Steps

### 1. Determine WIKI_PATH

Use the `$WIKI_PATH` environment variable if set; otherwise default to `~/firefox-wiki/`.

### 2. Check prerequisites

Run `which jq`. If jq is not found, print this error and stop:

```
jq is required. Install with: brew install jq (macOS) or apt install jq (Linux)
```

Check whether `${CLAUDE_PLUGIN_ROOT}/scripts/log-wiki-read.sh` exists. If not found, warn the user but continue.

### 3. Create directory structure

Run `mkdir -p` for each of the following (it is safe to run even if they already exist):

- `$WIKI_PATH/specs/`
- `$WIKI_PATH/platform/`
- `$WIKI_PATH/components/`
- `$WIKI_PATH/relations/`
- `$WIKI_PATH/patterns/`
- `$WIKI_PATH/bugs/`

### 4. Create files if they do not already exist

Never overwrite a file that is already present. Check for existence before writing each one.

**`$WIKI_PATH/usage-log.jsonl`** — create as an empty file.

**`$WIKI_PATH/log.md`** — create with this content:

```markdown
# Wiki Change Log
Append-only. One entry per ingest or significant update.
```

**`$WIKI_PATH/glossary.md`** — create with this content:

```markdown
# Glossary

## Abbreviations
- **MFR**: MediaFormatReader
- **MDSM**: MediaDecoderStateMachine (also MDSM)
- **TBM**: TrackBuffersManager
- **MSE**: Media Source Extensions
- **EME**: Encrypted Media Extensions
- **CDM**: Content Decryption Module
- **WMF**: Windows Media Foundation
- **MFCDM**: Media Foundation CDM (Firefox's WMF CDM integration)
- **GMP**: Gecko Media Plugin
- **MSG**: MediaStreamGraph

## Common HRESULT Codes
| Code | Name | Meaning |
|---|---|---|
| 0xC00D7176 | MF_E_INCOMPATIBLE_SAMPLE_PROTECTION | HDCP output protection not established |
| 0x8004CD12 | DRM_E_TEE_INVALID_HWDRM_STATE | PlayReady TEE context invalidated (sleep/resume) |
| 0xC00D36B4 | MF_E_INVALIDMEDIATYPE | Media type rejected by MFT |
| 0xC00D3704 | MF_E_UNSUPPORTED_FORMAT | Format not supported by MFT |

## nsresult Codes (media-specific)
| Code | Meaning |
|---|---|
| NS_ERROR_DOM_MEDIA_FATAL_ERR | Unrecoverable media error |
| NS_ERROR_DOM_MEDIA_NOT_SUPPORTED_ERR | Format/codec not supported |
| NS_ERROR_DOM_MEDIA_WAITING_FOR_DATA | Demuxer has no data at requested time |
| NS_ERROR_DOM_MEDIA_CANCELED | Operation canceled (decoder shutdown) |
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

### 5. Print a status report

After completing all steps, print the following status report (filling in detected state for hooks and jq):

```
Firefox Knowledge Wiki initialized at: ~/firefox-wiki/

Directories: ✓ specs/ ✓ platform/ ✓ components/ ✓ relations/ ✓ patterns/ ✓ bugs/
Files:       ✓ INDEX.md  ✓ log.md  ✓ glossary.md  ✓ usage-log.jsonl

Hooks: [active / NOT FOUND — re-install plugin]
jq: [found / NOT FOUND — install with brew install jq]

Next steps:
- Clone or create wiki content: git clone ... ~/firefox-wiki
- Add knowledge: /firefox-wiki:add <statement>
- Before investigating a bug: wiki lookup runs automatically
```

Replace the bracketed placeholders with the actual detected state:
- `Hooks`: `active` if `log-wiki-read.sh` was found, otherwise `NOT FOUND — re-install plugin`
- `jq`: `found` if jq was found, otherwise `NOT FOUND — install with brew install jq`
