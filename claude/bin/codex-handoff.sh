#!/usr/bin/env bash
# Hand an approved implementation plan to Codex for execution.
#
# Claude Code (Opus 5) plans; this script hands the plan to Codex running
# GPT-5.6-Terra at high reasoning effort, which does the actual editing.
#
# Usage:
#   codex-handoff.sh -f PLAN_FILE [-C WORKDIR] [-- extra codex args...]
#   echo "plan text" | codex-handoff.sh [-C WORKDIR]
#
# Env overrides: CODEX_HANDOFF_MODEL, CODEX_HANDOFF_EFFORT

set -uo pipefail

MODEL="${CODEX_HANDOFF_MODEL:-gpt-5.6-terra}"
EFFORT="${CODEX_HANDOFF_EFFORT:-high}"
LOG_DIR="${CODEX_HANDOFF_LOG_DIR:-$HOME/.claude/codex-handoff}"

plan_file=""
workdir="$PWD"

usage() { sed -n '2,12p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--plan-file) plan_file="${2:-}"; shift 2 ;;
    -C|--cd)        workdir="${2:-}";   shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    --)             shift; break ;;
    *)              break ;;
  esac
done

if ! command -v codex >/dev/null 2>&1; then
  echo "codex-handoff: 'codex' CLI not found on PATH" >&2
  exit 127
fi

if [[ -n "$plan_file" ]]; then
  [[ -r "$plan_file" ]] || { echo "codex-handoff: cannot read plan file: $plan_file" >&2; exit 1; }
  plan="$(cat -- "$plan_file")"
else
  plan="$(cat)"
fi

[[ -n "${plan//[[:space:]]/}" ]] || { echo "codex-handoff: empty plan" >&2; exit 1; }

mkdir -p "$LOG_DIR"
stamp="$(date +%Y%m%d-%H%M%S)"
log="$LOG_DIR/$stamp.log"
summary="$LOG_DIR/$stamp.summary.md"

prompt="You are the execution stage of a two-model workflow. Claude Opus 5 produced the
plan below and it has already been approved by the user. Your job is to implement it.

Rules:
- Implement the plan as written. Do not re-plan, re-scope, or ask for approval.
- If a step turns out to be wrong or impossible, implement everything else and
  state plainly at the end what you skipped and why.
- Verify your work (build/tests/lints) where the project provides a way to.
- Finish with a short report: what changed, which files, what you verified.

Working directory: $workdir

===== APPROVED PLAN =====
$plan
===== END PLAN ====="

echo "→ Codex handoff: model=$MODEL effort=$EFFORT cwd=$workdir" >&2
echo "→ Log: $log" >&2

printf '%s\n' "$prompt" | codex exec \
  --model "$MODEL" \
  -c "model_reasoning_effort=\"$EFFORT\"" \
  --cd "$workdir" \
  --skip-git-repo-check \
  --output-last-message "$summary" \
  --color never \
  "$@" - 2>&1 | tee "$log"

status="${PIPESTATUS[0]}"
echo "→ Codex exited with status $status; summary: $summary" >&2
exit "$status"
