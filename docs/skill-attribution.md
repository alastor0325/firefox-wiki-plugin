# Skill attribution for wiki usage events

## Why this exists

The wiki usage log (`usage-log.jsonl`) records `pre_lookup` and
`wiki_read` events whenever Claude consults the wiki. On their own these
events answer "how often did a consultation succeed?" (hit rate) but not
"which kind of work was consulting the wiki?" — and they cannot tell us
when a code-touching task ran *without* consulting the wiki at all.

To answer the second question we bracket every code-touching skill
invocation with a `session_start` / `session_end` pair and tag the wiki
events fired in between with the owning skill's `instance_id` + `skill`.

## Mechanism

```
PreToolUse(Skill)  → skill-start.sh  → push {instance_id, skill, args} to
                                        ~/.claude/state/skill-stack-<sid>.json
                                      → write session_start event

(during the skill) → wiki-pre-lookup.sh / log-wiki-read.sh
                                      → read stack top via _active-skill.sh
                                      → tag event with instance_id + skill
                                        + attribution_confidence

PostToolUse(Skill) → skill-end.sh    → pop the matching entry
                                      → write session_end event
```

The stack file is keyed by the Claude **session id**, taken from the
hook stdin's `.session_id` field (authoritative; the env var
`CLAUDE_CODE_SESSION_ID` is a fallback).

Only skills listed in `scripts/wiki-relevant-skills.txt` are tracked;
all other Skill invocations no-op.

## The parallel-attribution finding (2026-05-31)

A natural assumption was that background sub-agents (spawned via the
Agent tool with `run_in_background`) would each carry a distinct
session id or transcript path, letting each have its own stack file.

A direct probe disproved this. Two parallel sub-agents, each invoking a
Skill, both reported in their hook stdin:

- the **same** `session_id` as the parent
- the **same** `transcript_path` as the parent (the root conversation's
  transcript)
- a unique `tool_use_id` — but that is per-tool-call, so a later
  `wiki_read` (a different tool call) cannot be linked back to the Skill
  call that triggered it.

Conclusion: **there is no per-agent identifier available to the hooks.**
Truly-parallel skill instances share one stack file.

## How we stay honest: attribution_confidence

Rather than pretend, `_active-skill.sh` reports a confidence token with
every lookup, derived from the live stack:

| Confidence | Stack state | Meaning |
|---|---|---|
| `certain` | exactly one instance | skill + instance_id both reliable |
| `skill-certain` | >1 instance, all the same skill | skill reliable, instance_id best-effort |
| `ambiguous` | >1 instance, mixed skills | neither reliable |

The dominant parallel case — `/triage` fanning out N parallel
`/bug-start` sub-agents — is `skill-certain`: we cannot say *which*
bug-start instance read a page, but we can say it was bug-start. That is
exactly what per-skill Coverage and Hit Rate need, so those metrics stay
valid under fan-out. Only genuinely mixed-skill concurrency degrades to
`ambiguous`, and `/firefox-wiki:stats` excludes those events.

## Concurrency safety

Because parallel sub-agents write the same stack file, every
read-modify-write is wrapped in a coarse `mkdir`-based lock
(`stack_lock` / `stack_unlock` in `_stack-lib.sh`). A 10-way concurrent
push test preserves all 10 entries with no corruption. If the JSON is
ever found corrupt (interrupted write), `skill-start.sh` resets the
stack to just the current entry rather than dropping the hook.

## State location

Stack files live in `~/.claude/state/` and are **per-machine,
ephemeral** — a session id from one machine is meaningless on another,
and stacks are torn down as skills end. They are not synced. Everything
that must sync (scripts, allowlist, hook registration) ships in this
plugin repo.
