# Skill attribution for wiki usage events

## Why this exists

The wiki usage log (`usage-log.jsonl`) records `pre_lookup` and
`wiki_read` events whenever Claude consults the wiki. On their own these
answer "how often did a consultation succeed?" (hit rate) but not "which
kind of work was consulting the wiki?" — and they cannot tell us when a
code-touching task ran *without* consulting the wiki at all.

To answer those, we tag each wiki event with the skill that was active
when it fired, and we emit one `session_start` event per tracked-skill
invocation (the denominator: how often each skill ran).

## The model: "current skill" slot

```
PreToolUse(Skill)  → skill-start.sh
                     → overwrite ~/.claude/state/current-skill-<sid>.json
                       = {instance_id, skill, args, started_at}
                     → append a session_start event to usage-log.jsonl

(later tool calls) → wiki-pre-lookup.sh / log-wiki-read.sh
                     → read the slot via _active-skill.sh
                     → tag the pre_lookup / wiki_read event with the
                       slot's instance_id + skill
```

The slot is keyed by the Claude **session id**, taken from the hook
stdin's `.session_id` field (env var `CLAUDE_CODE_SESSION_ID` is a
fallback). It persists across conversation turns and is overwritten by
the next skill-start. Only skills in `scripts/wiki-relevant-skills.txt`
are tracked; all other Skill invocations no-op.

## Why there is no end event (the key finding)

The natural design is a `session_start` / `session_end` bracket:
`PreToolUse(Skill)` opens it, `PostToolUse(Skill)` closes it, and wiki
events in between attribute to the skill.

A live test (2026-05-31) disproved the assumption that
`PostToolUse(Skill)` marks the end of the skill's *work*:

```
21:02:03.793  session_start  bug-start
21:02:06.944  session_end    bug-start    ← 3.15s later
```

`PostToolUse(Skill)` fires when the Skill tool returns its **instructions
text** — about 3 seconds after start — not when the skill's multi-turn
work finishes. A searchfox search run immediately afterward (which in a
real `/bug-start` run is core investigation work) was logged with
`skill: null`: the bracket had already closed.

So an end-event bracket captures a ~3-second empty window and attributes
essentially nothing. The current-skill slot, which persists until the
next skill-start, is live during the actual work — which is the whole
point.

## Known inaccuracies (documented, accepted)

1. **Tail over-attribution.** Wiki reads after a skill's work is done but
   before the next skill-start still carry the last skill's instance_id.
   No signal detects this, so per-skill Coverage is a modest
   over-estimate.

2. **Parallel same-session sub-agents.** Background sub-agents share the
   parent's session_id AND transcript_path (verified via a parallel
   hook-input probe — only `tool_use_id` is unique, and that's per
   tool-call so it can't link a later wiki_read back to the skill). They
   therefore share one slot, last-writer-wins. In the dominant fan-out
   case (`/triage` → N parallel `/bug-start`) the *skill* is the same for
   all of them, so per-skill metrics stay valid; only per-instance joins
   are unreliable and should fall back to args/bug_id matching.

These are deliberate trade-offs: the available hooks expose no per-agent
identifier and no "skill work finished" signal, so precise per-instance
attribution under parallelism is not achievable. Per-skill aggregates —
the thing the evaluation actually needs — survive both inaccuracies.

## State location

Slot files live in `~/.claude/state/` and are **per-machine, ephemeral**.
A session id from one machine is meaningless on another. They are not
synced; everything that must sync (scripts, allowlist, hook registration)
ships in this plugin repo.

## Tests

`tests/test-skill-attribution.sh` exercises the model end to end:
allowlist filtering, slot overwrite on sequential skills, wiki events
inheriting the current skill, `skill: null` before any skill / for
non-allowlisted skills, and session-id isolation. Run it directly:

```
bash tests/test-skill-attribution.sh
```
