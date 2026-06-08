---
description: >
  Release a new firefox-wiki plugin version: bump .claude-plugin/plugin.json,
  commit, tag + push with `claude plugin tag --push`, THEN file an issue on the
  fx-bug-toolkit repo so the downstream consumer stays in sync. The fx-bug-toolkit
  issue step is MANDATORY — a bump is not done until that issue is filed.
  Triggers on: "bump version", "/bump-version", "release firefox-wiki",
  "cut a release", "new wiki version", "publish the wiki plugin".
allowed-tools: [Read, Edit, Bash, AskUserQuestion]
---

# firefox-wiki Version Bump

Bumping this plugin has a downstream obligation to the **fx-bug-toolkit**
consumer: its `/update` skill refreshes an installed firefox-wiki plugin, and its
"Accumulated knowledge database" tutorial chapter documents this plugin's public
commands. Every bump must be mirrored by an issue so fx-bug-toolkit can review
whether anything needs updating.

**MANDATORY: the bump is not complete until the fx-bug-toolkit issue is filed
(Step 5). Do not report done before then.**

Downstream repo: **`alastor0325/fx-bug-toolkit`**.

---

## Step 1 — Decide the new version

```bash
python3 -c "import json;print(json.load(open('.claude-plugin/plugin.json'))['version'])"
```

Use the caller's level (`patch`/`minor`/`major`) or explicit version; otherwise
`AskUserQuestion` (show what each resolves to). Set `OLD` and `NEW`.

## Step 2 — Bump plugin.json

Edit only the `version` field in `.claude-plugin/plugin.json`. (`claude plugin
tag` validates that it matches the marketplace entry, so don't touch anything
else.)

## Step 3 — Verify

The tree must be healthy before tagging. Run whatever checks the repo has (hooks,
lint, any test script). A failing check is a hard blocker.

## Step 4 — Commit, tag, push

```bash
git add -A
git commit -m "release: vNEW

<one-line summary of what this release contains>"
claude plugin tag --push -m "firefox-wiki %s"   # tags firefox-wiki--vNEW from this commit, pushes both
```

Tag **only** from a green commit on the default branch.

## Step 5 — File the fx-bug-toolkit issue (MANDATORY)

Collect what changed so the issue is actionable:

```bash
PREV=$(git tag --list 'firefox-wiki--v*' --sort=-v:refname | sed -n 2p)
[ -n "$PREV" ] && git log --oneline "$PREV"..HEAD || git log --oneline -10
```

Write the body to a temp file (avoids shell-quoting), then:

```bash
gh issue create -R alastor0325/fx-bug-toolkit \
  --title "firefox-wiki plugin bumped to vNEW — review /update + tutorial" \
  --label enhancement \
  --body-file /tmp/wiki-bump-issue.md && rm -f /tmp/wiki-bump-issue.md
```

The body must include:
- The new version **NEW** and previous **OLD**.
- A short changelog (the `git log` above) — what changed and why it matters.
- The concrete ask: fx-bug-toolkit's `/update` auto-refreshes an installed
  firefox-wiki plugin (there is **no version pin** to bump), but review whether
  its **tutorial** ("Accumulated knowledge database") or `/update` step needs
  changes — especially if the **public commands** (`init` / `add` / `stats`) or
  the install steps changed.
- The source: the commit hash and tag `firefox-wiki--vNEW`.

Report the created issue URL.

## Step 6 — Summary

Report: old → new version, the pushed tag, the changelog, and the fx-bug-toolkit
issue URL. If the issue was NOT filed for any reason, say so loudly — the release
is incomplete.
