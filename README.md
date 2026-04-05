# firefox-wiki-plugin

A Claude Code plugin that provides persistent knowledge management for Firefox engineers. Automatically ingests investigation findings into a structured wiki, looks up prior knowledge before investigations, and monitors usage to evaluate effectiveness.

## User Commands

These are the only commands you need to use directly:

| Command | Purpose |
|---|---|
| `/firefox-wiki:init` | Set up wiki directory structure (run once after cloning) |
| `/firefox-wiki:add <input>` | Add knowledge to the wiki — accepts natural language, a spec URL, or `bug <id>` |
| `/firefox-wiki:lint` | Check wiki integrity (`--lightweight` or `--full`) |
| `/firefox-wiki:stats` | View usage metrics and hit rate (run monthly) |

### `/firefox-wiki:add` examples

```
/firefox-wiki:add AudioSink consumes decoded frames on a dedicated thread, not the MDSM thread
/firefox-wiki:add https://html.spec.whatwg.org/multipage/media.html
/firefox-wiki:add bug 2026875
```

## Agent-Invoked Skills

These run automatically — you do not invoke them directly:

| Skill | Triggered by |
|---|---|
| `wiki-lookup` | Automatically before any bug investigation or triage session |
| `wiki-ingest` | Invoked by `wiki-add bug <id>` to extract and store investigation knowledge |

## Install

```shell
/plugin marketplace add alastor0325/firefox-wiki-plugin
/plugin install firefox-wiki@firefox-wiki-plugin
```

Then clone the wiki content repo and initialize:

```bash
git clone https://github.com/alastor0325/firefox-wiki ~/firefox-wiki
```

```shell
/firefox-wiki:init
```

## Requirements

- `jq` must be installed (`brew install jq` on macOS)
- Wiki content repo cloned to `~/firefox-wiki/` (or set `$WIKI_PATH`)

## Dev

```bash
claude --plugin-dir . -p '/firefox-wiki:init'
claude plugin validate .
```

Bump `version` in `.claude-plugin/plugin.json` before every commit that changes skills, hooks, or scripts.
