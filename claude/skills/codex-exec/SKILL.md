---
name: codex-exec
description: Hand an approved implementation plan to Codex (GPT-5.6-Terra, high reasoning effort) to execute. Use after a plan has been approved via ExitPlanMode, or whenever the user asks to hand work off to Codex / "let Codex build it". Claude plans; Codex edits the code.
---

# Codex execution handoff

This project routes work across two models: **Claude Opus 5 plans, Codex
(GPT-5.6-Terra, high reasoning effort) executes.** You are the planning side.
Your job here is to transfer the approved plan cleanly and then report what
Codex did — not to implement the plan yourself.

## Steps

1. **Write the plan to a file.** If plan mode already produced a plan file, use
   it. Otherwise write the approved plan to the scratchpad as
   `codex-plan-<short-slug>.md`.

   The plan must stand on its own — Codex starts with zero conversation
   context. Include anything it needs that lives only in this conversation:
   - concrete file paths (absolute), not "the file we looked at"
   - decisions the user made, and constraints they set
   - how to build / test / lint this project, if you learned it
   - what "done" looks like

2. **Run the handoff in the background.** Codex runs for minutes, so use
   `run_in_background: true`:

   ```
   ~/.claude/bin/codex-handoff.sh -f <plan-file> -C <project-dir>
   ```

   The script pins `--model gpt-5.6-terra` and
   `model_reasoning_effort=high`; do not pass a different model unless the user
   asks for one. Tell the user it's running and that output streams to
   `~/.claude/codex-handoff/<timestamp>.log`.

3. **Report the result.** When it finishes, read the summary at
   `~/.claude/codex-handoff/<timestamp>.summary.md` (the script prints the path)
   and relay what actually changed. Check the work — a non-zero exit or a
   summary admitting skipped steps is something the user needs to hear plainly,
   not smoothed over.

   If that evidence shows the implementation is failing, invoke the
   `routing-recovery` skill for one tentative recovery cycle. Fable 5 replans and
   GPT-5.6-Sol executes at high effort. If Fable explicitly has no credits or is
   unavailable, use the skill's fresh Opus 5 fallback while keeping Sol as executor.
   Do not trigger recovery merely because a multi-step task is not finished yet.

4. **Handle follow-ups.** If the user wants changes to what Codex built, that is
   new planning work: plan the fix, then hand off again. Small corrections you
   can make directly are fine — don't round-trip a one-line typo fix.

## When not to use this

- Research, code reading, explanation, review — no handoff, answer directly.
- Trivial single-file edits the user asked for directly, with no plan involved.
- The user explicitly says to implement it yourself.
- Inside a `longtask` segment, the worker calls `codex-handoff.sh` directly and waits instead of using this skill's background-and-report flow.

## Overrides

- `CODEX_HANDOFF_MODEL` / `CODEX_HANDOFF_EFFORT` change model and effort for one run.
- `CLAUDE_CODEX_ROUTING=off` disables the automatic post-plan routing hook.
