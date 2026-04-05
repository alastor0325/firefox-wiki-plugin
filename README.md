# firefox-wiki-plugin

A Claude Code plugin that provides persistent knowledge management for Firefox engineers. Automatically ingests investigation findings into a structured wiki, looks up prior knowledge before investigations, and monitors usage to evaluate effectiveness.

## Skills

| Skill | Invoked by | Purpose |
|---|---|---|
| `/firefox-wiki:init` | User (once) | Set up wiki directory structure |
| `/firefox-wiki:add <statement>` | User | Add a fact or explanation in natural language |
| `/firefox-wiki:lookup <query>` | Agent | Find relevant wiki content before investigating |
| `/firefox-wiki:ingest` | Agent (auto via hook) | Extract and store knowledge after a patch lands |
| `/firefox-wiki:lint` | Agent (auto via hook) | Check wiki integrity after writes |
| `/firefox-wiki:stats` | User (monthly) | View usage metrics and hit rate |

## Install

```shell
/plugin marketplace add alastor0325/firefox-wiki-plugin
/plugin install firefox-wiki@firefox-wiki-plugin
```

Then clone the wiki content repo and run init:

```bash
git clone https://github.com/alastor0325/firefox-wiki ~/firefox-wiki
```

```shell
/firefox-wiki:init
```

## Requirements

- `jq` must be installed (`brew install jq` on macOS)
- Wiki content repo cloned to `~/firefox-wiki/` (or set `WIKI_PATH` env var)

## Dev

```bash
claude --plugin-dir . -p '/firefox-wiki:init'
claude plugin validate .
```

Bump `version` in `.claude-plugin/plugin.json` before every commit that changes skills, hooks, or scripts.
