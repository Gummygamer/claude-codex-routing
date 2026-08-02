---
name: routing-recovery
description: Tentatively recover a failing planned implementation by switching the planner to Fable 5 and executor to GPT-5.6-Sol high, with Opus 5 as the planner fallback when Fable has no credits.
---

# Tentative failure recovery

Use this only after concrete failure evidence: a non-zero executor exit, a summary
that admits required work was skipped, independent verification failing because the
implementation is wrong, or the same implementation blocker recurring. Expected red
tests from an intentionally incomplete multi-step task are not failure evidence.

1. Write a self-contained recovery brief containing the approved goal and scope,
   files already changed, the exact command/output that proved failure, and what done
   means. Do not discard successful landed work.
2. Start a fresh `routing-recovery-worker` Agent (Fable 5) with only the absolute
   brief path and project directory. It will plan the repair and hand it to
   GPT-5.6-Sol at high reasoning effort.
3. If and only if Agent startup/result explicitly says Fable credits are exhausted,
   the usage limit was reached, or Fable is unavailable, permanently retire that
   worker and start a fresh `routing-recovery-worker-opus` with the same two inputs.
   Do not interpret a bad plan, tool error, timeout, malformed report, or failed Sol
   execution as a credit error.
4. Report and verify the recovery result. This switch is one-shot: subsequent normal
   work returns to Opus 5 + GPT-5.6-Terra. Never recursively trigger this skill from
   a failed recovery; surface the remaining blocker instead.

Run recovery workers in the background when the client supports it. Never resume a
failed Fable worker for the Opus fallback; the fallback must have a fresh context.
