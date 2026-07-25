#!/usr/bin/env bash
# PostToolUse hook on ExitPlanMode: once a plan is approved, route execution to
# Codex (GPT-5.6-Terra) instead of having Claude implement it directly.
#
# Set CLAUDE_CODEX_ROUTING=off to disable.

set -uo pipefail

cat >/dev/null   # drain hook stdin; the plan lives in a file, not the payload

if [[ "${CLAUDE_CODEX_ROUTING:-on}" == "off" ]]; then
  exit 0
fi

read -r -d '' ctx <<'EOF'
EXECUTION ROUTING: this plan is approved, but you are the planning model only.
Do NOT implement it yourself — hand it to Codex via the `codex-exec` skill.

Invoke the `codex-exec` skill now and follow it: write the self-contained plan to
a file, then run `~/.claude/bin/codex-handoff.sh -f <plan-file> -C <project-dir>`
in the background (Codex runs GPT-5.6-Terra at high reasoning effort), and report
back what Codex actually changed.

The plan file must stand alone — Codex has none of this conversation's context.
EOF

jq -n --arg ctx "$ctx" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  },
  systemMessage: "Plan approved → routing execution to Codex (gpt-5.6-terra, high effort)"
}'
