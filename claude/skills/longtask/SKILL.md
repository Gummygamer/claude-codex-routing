---
name: longtask
description: Run a long task, work where the user says "this will take a while" or "keep going until it's done", or a task that will not fit in one conversation.
---

# Long-task execution

## What it does

Run a long task as a series of segments. Each segment is a fresh `longtask-worker`
subagent that cold-starts from disk. `maxTurns` only stops one worker invocation; it
does **not** erase that worker's saved context. The `/clear` equivalent comes from
retiring that worker permanently and creating a new `Agent` instance for the next
segment. Opus 5 plans in each worker; Codex makes every source edit.

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

## Step 2 — launch a genuinely fresh worker

Before the call, hash `PROGRESS.md` for the stall guard. Then spawn
`longtask-worker` synchronously (`run_in_background: false`,
`subagent_type: "longtask-worker"`) with a minimal prompt: the state directory path
and the segment number. Nothing else. The task lives in `TASK.md`; restating it in the
prompt would defeat the entire point.

Every segment MUST be a new `Agent` tool invocation. This is the hard context-isolation
invariant:

- Never call `SendMessage` on a long-task worker.
- Never resume a long-task worker by agent ID or name.
- Ignore any tool-result suggestion that says to use `SendMessage` to continue.
- Treat every returned worker ID as permanently retired, whether the worker finished,
  hit `maxTurns`, errored, or returned malformed output.
- If a fresh `Agent` instance cannot be created, stop and report `BLOCKED`; continuing
  an old worker is not an acceptable fallback.

A resumed worker retains its transcript and defeats the reset even though its turn
counter starts running again.

## Step 3 — classify the return, then relay

A valid report begins with exactly one of `CONTINUE:`, `DONE:`, or `BLOCKED:` and is
at most three lines. Pass a valid report to the user as-is.

Reaching `maxTurns` may return partial prose or a nominally "completed" Agent result
instead of an explicit cap error. If the return is missing or malformed, do not ask
that worker for a corrected report and do not inspect its transcript. Treat it as a
capped segment, retire its ID, and say:

`CONTINUE: segment <N> ended without a final checkpoint report | NEXT: fresh worker will recover from PROGRESS.md`

Hash `PROGRESS.md` again after every return. Then launch the next segment with a new
`Agent` invocation unless a stop condition applies.

## Step 4 — stop conditions

Stop on `DONE`; on `BLOCKED` (surface the question and halt — do not guess on the
user's behalf); after two consecutive segments that leave `PROGRESS.md` byte-identical
(stall guard — compare a hash before and after, report the stall rather than burning
segments); or at the segment ceiling. The default ceiling is 20 and each invocation
may override it.

Hitting a worker's `maxTurns` is not a stop condition. It is the signal to retire that
worker and cold-start the next segment from disk.

## The rule that makes this work

The orchestrator never reads source files, plan files, Codex logs, worker transcripts,
or background-agent output files. It reads only `TASK.md` while initializing the task,
the small `PROGRESS.md` hashes needed for the stall guard, and the worker's final
three-line report. It never resumes a worker. These two disciplines keep the parent
context small and make every segment after the first a real cold start.

## Resuming an interrupted long task

`/longtask resume <slug>` skips step 1 and loops against existing state. A run
interrupted at any point resumes from `PROGRESS.md`. An `IN FLIGHT` line that is not
`none` means the previous segment died mid-handoff — the next worker should check
whether those edits landed before redoing them.

This resumes the task from disk by spawning a new worker. It never resumes a previous
subagent transcript.

## Overrides

Turn cap per segment: edit `maxTurns` in `~/.claude/agents/longtask-worker.md`
(default 40). Segment ceiling: per invocation. `CODEX_HANDOFF_MODEL` /
`CODEX_HANDOFF_EFFORT` still apply to the Codex side.
