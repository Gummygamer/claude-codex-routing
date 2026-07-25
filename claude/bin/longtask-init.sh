#!/usr/bin/env bash
# Scaffold durable state for a turn-capped long task.
#
# The stable TASK.md and PROGRESS.md schema lets each cold-started worker resume
# from disk without spending turns recreating boilerplate.
#
# Usage:
#   longtask-init.sh <slug> [-C WORKDIR]

set -uo pipefail

usage() { sed -n '2,9p' "$0"; }

slug=""
workdir="$PWD"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -C|--cd)
      workdir="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "longtask-init: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$slug" ]]; then
        echo "longtask-init: expected one slug" >&2
        usage >&2
        exit 2
      fi
      slug="$1"
      shift
      ;;
  esac
done

if [[ -z "$slug" ]]; then
  echo "longtask-init: a slug is required" >&2
  usage >&2
  exit 2
fi

if [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "longtask-init: invalid slug '$slug'; use lowercase letters, digits, and hyphens" >&2
  exit 2
fi

if [[ ! -d "$workdir" ]]; then
  echo "longtask-init: workdir is not a directory: $workdir" >&2
  exit 2
fi

state_dir="$workdir/.longtask/$slug"
task_file="$state_dir/TASK.md"
progress_file="$state_dir/PROGRESS.md"
heartbeat_file="$state_dir/HEARTBEAT"

if [[ -e "$task_file" ]]; then
  echo "longtask-init: task already exists: $task_file; resume it instead" >&2
  exit 1
fi

mkdir -p "$state_dir/plans" "$state_dir/stale"

cat >"$task_file" <<EOF
# Task: $slug

## Goal
<the user's ask, verbatim>

## In scope

## Not in scope

## Decisions and constraints
<what the user chose, and anything they ruled out>

## Project facts
- Build:
- Test:
- Lint:
- Key paths:

## Definition of done
- [ ]
EOF

cat >"$progress_file" <<EOF
# Progress: $slug

## Status
NEXT: <the single next chunk, one line>
SEGMENTS: 0
IN FLIGHT: none

## Done

## Segment log

## Open questions / blockers

## Landmines
<!-- Things a cold worker would otherwise rediscover the hard way. -->
EOF

cat >"$heartbeat_file" <<EOF
SEGMENT: none
STAGE: initialized
UPDATED_EPOCH: $(date +%s)
DETAIL: awaiting first segment
ARTIFACT_DIR: none
EOF

if git -C "$workdir" rev-parse --git-dir >/dev/null 2>&1; then
  gitignore="$workdir/.gitignore"
  if [[ ! -f "$gitignore" ]] || ! grep -Fqx '.longtask/' "$gitignore"; then
    printf '.longtask/\n' >>"$gitignore"
  fi
fi

printf '%s\n' "$state_dir" "$task_file" "$progress_file" "$heartbeat_file"
