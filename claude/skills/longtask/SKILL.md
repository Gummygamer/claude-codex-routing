---
name: longtask
description: Run a long task, work where the user says "this will take a while" or "keep going until it's done", or a task that will not fit in one conversation.
---

# Long-task execution

## What it does

Run a long task as a series of segments. Each segment is a fresh `longtask-worker`
subagent that cold-starts from disk, so the conversation never accumulates — the turn
cap plus the cold start together are the `/clear`. Opus 5 plans in each worker; Codex
makes every source edit.

## Step 1 — set up state

Derive a kebab-case slug. Run:

```
~/.claude/bin/longtask-init.sh <slug> -C <project-dir>
```

Then fill in `TASK.md` from the conversation: goal verbatim, scope and non-scope, the
user's decisions and constraints, build/test/lint commands, and a definition-of-done
checklist. Set the first `NEXT:` in `PROGRESS.md`.

Getting `TASK.md` right is the highest-leverage thing here — it is the only thing
every future segment sees, and no worker can recover a constraint that was mentioned
in conversation but never written down.

## Step 2 — loop

Spawn `longtask-worker` synchronously (`run_in_background: false`,
`subagent_type: "longtask-worker"`) with a minimal prompt: the state directory path
and the segment number. Nothing else. The task lives in `TASK.md`; restating it in the
prompt would defeat the entire point.

## Step 3 — relay

Pass the worker's ≤3-line report to the user as-is, then spawn the next segment.

## Step 4 — stop conditions

Stop on `DONE`; on `BLOCKED` (surface the question and halt — do not guess on the
user's behalf); after two consecutive segments that leave `PROGRESS.md` byte-identical
(stall guard — compare a hash before and after, report the stall rather than burning
segments); or at the segment ceiling. The default ceiling is 20 and each invocation
may override it.

## The rule that makes this work

The orchestrator never reads source files, plan files, or Codex logs. That discipline
is the only thing keeping its context small, and breaking it once undoes the benefit
for the whole run.

## Resuming

`/longtask resume <slug>` skips step 1 and loops against existing state. A run
interrupted at any point resumes from `PROGRESS.md`. An `IN FLIGHT` line that is not
`none` means the previous segment died mid-handoff — the next worker should check
whether those edits landed before redoing them.

## Overrides

Turn cap per segment: edit `maxTurns` in `~/.claude/agents/longtask-worker.md`
(default 40). Segment ceiling: per invocation. `CODEX_HANDOFF_MODEL` /
`CODEX_HANDOFF_EFFORT` still apply to the Codex side.
