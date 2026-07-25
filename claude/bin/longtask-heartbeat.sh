#!/usr/bin/env bash
# Atomically publish a long-task worker's current stage for the stale-worker guard.
#
# Usage:
#   longtask-heartbeat.sh STATE_DIR SEGMENT STAGE [DETAIL] [ARTIFACT_DIR]

set -uo pipefail

usage() { sed -n '2,6p' "$0"; }

state_dir="${1:-}"
segment="${2:-}"
stage="${3:-}"
detail="${4:-}"
artifact_dir="${5:-none}"

if [[ -z "$state_dir" || -z "$segment" || -z "$stage" || $# -gt 5 ]]; then
  usage >&2
  exit 2
fi

if [[ ! -d "$state_dir" || ! -f "$state_dir/TASK.md" || ! -f "$state_dir/PROGRESS.md" ]]; then
  echo "longtask-heartbeat: not a long-task state directory: $state_dir" >&2
  exit 2
fi

if [[ ! "$segment" =~ ^(none|[0-9]+)$ ]]; then
  echo "longtask-heartbeat: invalid segment: $segment" >&2
  exit 2
fi

if [[ ! "$stage" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "longtask-heartbeat: invalid stage: $stage" >&2
  exit 2
fi

# Keep the file line-oriented so the orchestrator can inspect it without pulling
# worker output or logs into its context.
detail="${detail//$'\n'/ }"
detail="${detail//$'\r'/ }"
artifact_dir="${artifact_dir//$'\n'/ }"
artifact_dir="${artifact_dir//$'\r'/ }"

tmp="$(mktemp "$state_dir/.HEARTBEAT.tmp.XXXXXX")" || exit 1
trap 'rm -f -- "$tmp"' EXIT

{
  printf 'SEGMENT: %s\n' "$segment"
  printf 'STAGE: %s\n' "$stage"
  printf 'UPDATED_EPOCH: %s\n' "$(date +%s)"
  printf 'DETAIL: %s\n' "${detail:-none}"
  printf 'ARTIFACT_DIR: %s\n' "$artifact_dir"
} >"$tmp"

mv -f -- "$tmp" "$state_dir/HEARTBEAT"
trap - EXIT
