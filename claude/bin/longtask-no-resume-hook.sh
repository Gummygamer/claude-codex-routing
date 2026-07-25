#!/usr/bin/env bash
# Prevent a turn-capped long-task worker from being resumed with SendMessage.
# A new Agent invocation is what gives the next segment a fresh context.

set -uo pipefail

input="$(cat)"
target="$(jq -r '.tool_input.to // .tool_input.recipient // empty' <<<"$input" 2>/dev/null)"
transcript="$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)"

[[ -n "$target" && -n "$transcript" ]] || exit 0

agent_id="${target#agent-}"
session_dir="${transcript%.jsonl}"
meta="$session_dir/subagents/agent-$agent_id.meta.json"

[[ -r "$meta" ]] || exit 0
jq -e '.agentType == "longtask-worker"' "$meta" >/dev/null 2>&1 || exit 0

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "Long-task workers are single-use; resuming one preserves its context.",
    additionalContext: "Do not retry SendMessage. Permanently retire this worker ID and launch the next segment with a brand-new Agent invocation using subagent_type longtask-worker. Recover only from PROGRESS.md."
  }
}'
