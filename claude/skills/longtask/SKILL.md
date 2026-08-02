---
name: longtask
description: Run a long task, work where the user says "this will take a while" or "keep going until it's done", or a task that will not fit in one conversation.
---

# Long-task execution

## What it does

Run a long task as a series of segments. Each segment is a fresh worker subagent that
cold-starts from disk. `maxTurns` only stops one worker invocation; it does **not**
erase that worker's saved context. The `/clear` equivalent comes from retiring that
worker permanently and creating a new `Agent` instance for the next segment. Opus 5
plans normally; a failed implementation gets one tentative Fable 5 recovery segment.
Codex makes every source edit.

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

Before the call, hash `PROGRESS.md` for the stall guard. Read only the `ROUTING:` line
in its Status section (`normal` if absent for older state). Spawn `longtask-worker`
for `normal`, or `longtask-recovery-worker` for `tentative-recovery`, in the
background (`run_in_background: true`) with a minimal prompt: the state directory
path and segment number. Nothing else. Save the returned task ID and output-file path.
The task lives in `TASK.md`; restating it in the prompt would defeat the entire point.

Use `TaskOutput` with `block: true` and a bounded timeout (or bounded reads of the
returned output file on versions that no longer expose `TaskOutput`) to wait for the
result. Never make the foreground Agent call itself the wait: the orchestrator needs
control back so it can detect a worker that is alive but no longer progressing.

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

If a `longtask-recovery-worker` startup/result explicitly says Fable credits are
exhausted, a usage limit was reached, or Fable is unavailable, retire it and spawn a
fresh ordinary `longtask-worker` for the same segment. Its
`ROUTING: tentative-recovery` state keeps GPT-5.6-Sol as executor while Opus 5 remains
the planner. No other error qualifies for this fallback.

## Step 3 — detect a stale segment

The soft runtime limit is 20 minutes by default. Crossing it does **not** make a
segment stale; it asks the parent Claude Code session to judge whether the worker is
still progressing.

At the soft limit, and after every additional 10 minutes, inspect only:

- the background task status (running, completed, failed, or stopped)
- the current `PROGRESS.md` hash
- `HEARTBEAT` (`SEGMENT`, `STAGE`, `UPDATED_EPOCH`, `DETAIL`, and `ARTIFACT_DIR`)
- file size and modification-time metadata in `ARTIFACT_DIR`, if one is named
- whether a numeric PID in that directory still belongs to the exact recorded
  `codex-handoff.sh` invocation

Do not read the worker transcript, Codex log contents, source files, or plan files.
Take one evidence snapshot, wait five bounded minutes, then take a second snapshot.
Claude must classify the result as `ACTIVE` or `STALE`; elapsed time by itself is
never sufficient. A newer `UPDATED_EPOCH` with the same stage and detail proves only
that the heartbeat loop is alive; it is not by itself meaningful progress.

Classify `ACTIVE` if durable progress, the heartbeat stage/detail, or the recorded
handoff artifacts advanced. A legitimate bounded wait with fresh heartbeat evidence
is also active. If the evidence is ambiguous, classify it active and check again at
the next interval.

Classify `STALE` only when the two snapshots show no meaningful progress and the
current stage has no credible live work behind it. Before stopping anything, write
`<state-dir>/STALE.md` atomically (temporary file in the state directory followed by
`mv`) with exactly `SEGMENT`, `TASK_ID`, `MARKED_EPOCH`, `STAGE`, `ARTIFACT_DIR`, and
`REASON` lines. Then call `TaskStop` for that exact background task ID. Treat that
worker ID as permanently retired and immediately launch segment `<N+1>` as a fresh
Agent invocation. The new worker recovers from `PROGRESS.md`, `STALE.md`, and the
named artifact directory.

Never use `SendMessage` as a liveness probe. A message changes the worker's work and
resuming it would preserve the context this relay is designed to discard.

## Step 4 — classify the return, then relay

A valid report begins with exactly one of `CONTINUE:`, `DONE:`, or `BLOCKED:` and is
at most three lines. Pass a valid report to the user as-is.

Reaching `maxTurns` may return partial prose or a nominally "completed" Agent result
instead of an explicit cap error. If the return is missing or malformed, do not ask
that worker for a corrected report and do not inspect its transcript. Treat it as a
capped segment, retire its ID, and say:

`CONTINUE: segment <N> ended without a final checkpoint report | NEXT: fresh worker will recover from PROGRESS.md`

Hash `PROGRESS.md` again after every return. Then launch the next segment with a new
`Agent` invocation unless a stop condition applies.

## Step 5 — stop conditions

Stop on `DONE`; on `BLOCKED` (surface the question and halt — do not guess on the
user's behalf); after two consecutive segments that leave `PROGRESS.md` byte-identical
(stall guard — compare a hash before and after, report the stall rather than burning
segments); or at the segment ceiling. The default ceiling is 20 and each invocation
may override it.

Hitting a worker's `maxTurns` is not a stop condition. It is the signal to retire that
worker and cold-start the next segment from disk.

## The rule that makes this work

The orchestrator never reads source files, plan files, Codex logs, worker transcripts,
or background-agent output beyond the worker's final three-line report. It reads only
`TASK.md` while initializing the task, the small state and file metadata allowed by
the stale guard, and the worker's final report. It never resumes a worker. These two
disciplines keep the parent context small and make every segment after the first a
real cold start.

## Resuming an interrupted long task

`/longtask resume <slug>` skips step 1 and loops against existing state. A run
interrupted at any point resumes from `PROGRESS.md`. An `IN FLIGHT` line that is not
`none` means the previous segment died mid-handoff — the next worker should check
whether those edits landed before redoing them.

This resumes the task from disk by spawning a new worker. It never resumes a previous
subagent transcript.

## Overrides

Turn cap per segment: edit `maxTurns` in `~/.claude/agents/longtask-worker.md`
(default 40). Stale-review soft limit: 20 minutes; follow-up interval: 10 minutes.
Segment ceiling: per invocation. `CODEX_HANDOFF_MODEL` /
`CODEX_HANDOFF_EFFORT` still apply to the Codex side.

Normal segments use GPT-5.6-Terra. A `tentative-recovery` segment uses GPT-5.6-Sol
at high reasoning effort and resets to normal after green verification.
