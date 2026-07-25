#!/usr/bin/env bash
# Snapshot the live Claude routing config from ~/.claude into this folder, so it
# can be applied to another machine later with ./install-to-machine.sh
#
# Usage: ./sync-from-live.sh
#
# Missing assets are reported as warnings, not failures — a partially built setup
# still snapshots what exists, and tells you what it couldn't find.

set -uo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
live="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
dest="$repo/claude"

# Assets carried to a new machine. Paths are relative to the config dir.
assets=(
  bin/codex-handoff.sh
  bin/codex-route-hook.sh
  bin/longtask-init.sh
  bin/longtask-no-resume-hook.sh
  agents/longtask-worker.md
  skills/codex-exec/SKILL.md
  skills/longtask/SKILL.md
)

[[ -d "$live" ]] || { echo "sync: no live config at $live" >&2; exit 1; }

copied=0
missing=()

for rel in "${assets[@]}"; do
  src="$live/$rel"
  if [[ -r "$src" ]]; then
    mkdir -p -- "$dest/$(dirname -- "$rel")"
    cp -p -- "$src" "$dest/$rel"
    echo "  ok      $rel"
    ((copied++))
  else
    echo "  MISSING $rel" >&2
    missing+=("$rel")
  fi
done

# settings.json: split into the portable part (hooks) and a reference copy.
# The reference copy is never auto-applied — it holds machine-local preferences
# and the bypassPermissions trust decision.
if [[ -r "$live/settings.json" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "sync: jq not found; cannot split settings.json" >&2
    missing+=("settings.hooks.json (jq unavailable)")
  elif ! jq -e . "$live/settings.json" >/dev/null 2>&1; then
    echo "sync: settings.json is not valid JSON; skipping" >&2
    missing+=("settings.hooks.json (invalid JSON)")
  else
    mkdir -p -- "$dest"
    jq '{hooks: (.hooks // {})}' "$live/settings.json" >"$dest/settings.hooks.json"
    cp -p -- "$live/settings.json" "$dest/settings.reference.json"
    echo "  ok      settings.hooks.json + settings.reference.json"
    ((copied += 2))
  fi
else
  echo "  MISSING settings.json" >&2
  missing+=("settings.json")
fi

echo
echo "Snapshotted $copied file(s) into $dest"

if ((${#missing[@]})); then
  printf '\nNot snapshotted (%d):\n' "${#missing[@]}" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo >&2
  echo "The snapshot is incomplete. Fix the live config, then re-run." >&2
  exit 2
fi

echo "Snapshot complete."
