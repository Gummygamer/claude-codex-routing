#!/usr/bin/env bash
# Apply this snapshot of the Claude routing config to ~/.claude on a machine.
#
# Usage:
#   ./install-to-machine.sh           # dry run: show every change, write nothing
#   ./install-to-machine.sh --apply   # perform the install
#
# Existing files that would be replaced are copied to
# ~/.claude/backups/routing-<stamp>/ before anything is overwritten.
#
# settings.json is MERGED, not overwritten: only the `hooks` object from
# settings.hooks.json is applied. Machine-local preferences in
# settings.reference.json are left for you to apply by hand.

set -uo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
src="$repo/claude"
live="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

apply=0
[[ "${1:-}" == "--apply" ]] && apply=1
if [[ -n "${1:-}" && "${1:-}" != "--apply" ]]; then
  echo "install: unknown argument '$1' (expected --apply or nothing)" >&2
  exit 2
fi
((apply)) || echo "DRY RUN — nothing will be written. Re-run with --apply to install."
echo

[[ -d "$src" ]] || { echo "install: no snapshot at $src; run ./sync-from-live.sh first" >&2; exit 1; }

# Prerequisites. Missing ones are warnings: the config still installs, but the
# setup won't work until they're resolved.
warn=()
command -v jq    >/dev/null 2>&1 || warn+=("jq not on PATH — the sudo-guard hook and settings merge need it")
command -v codex >/dev/null 2>&1 || warn+=("codex CLI not on PATH — codex-handoff.sh will exit 127")
command -v claude >/dev/null 2>&1 || warn+=("claude not on PATH — cannot verify the agent loads")

stamp="$(date +%Y%m%d-%H%M%S)"
backup="$live/backups/routing-$stamp"
backed_up=0

save() {  # save <relative-path> — preserve the current live copy before we clobber it
  local rel="$1" cur="$live/$1"
  [[ -e "$cur" ]] || return 0
  if ((apply)); then
    mkdir -p -- "$backup/$(dirname -- "$rel")"
    cp -p -- "$cur" "$backup/$rel"
  fi
  echo "  backup  $rel"
  ((backed_up++))
}

installed=0
while IFS= read -r -d '' f; do
  rel="${f#"$src"/}"
  case "$rel" in settings.hooks.json|settings.reference.json) continue ;; esac

  save "$rel"
  if ((apply)); then
    mkdir -p -- "$live/$(dirname -- "$rel")"
    cp -- "$f" "$live/$rel"
    [[ "$rel" == bin/*.sh ]] && chmod +x -- "$live/$rel"
  fi
  echo "  install $rel"
  ((installed++))
done < <(find "$src" -type f -print0)

# Merge the hooks object into settings.json rather than replacing the file.
hooks="$src/settings.hooks.json"
if [[ -r "$hooks" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP    settings.json merge — jq unavailable" >&2
    warn+=("hooks were NOT merged into settings.json; do it by hand from settings.hooks.json")
  else
    save "settings.json"
    if ((apply)); then
      tmp="$(mktemp)"
      if [[ -r "$live/settings.json" ]] && jq -e . "$live/settings.json" >/dev/null 2>&1; then
        # Existing settings win on every key except hooks, which we take from the snapshot.
        jq -s '.[0] * {hooks: (.[1].hooks // {})}' "$live/settings.json" "$hooks" >"$tmp"
      else
        jq '.' "$hooks" >"$tmp"
      fi
      if jq -e . "$tmp" >/dev/null 2>&1; then
        mkdir -p -- "$live"
        mv -- "$tmp" "$live/settings.json"
      else
        rm -f -- "$tmp"
        echo "install: refusing to write invalid settings.json" >&2
        exit 1
      fi
    fi
    echo "  merge   settings.json (hooks only)"
  fi
fi

echo
if ((apply)); then
  echo "Installed $installed file(s) into $live"
  ((backed_up)) && echo "Replaced $backed_up existing file(s); originals in $backup"
  echo
  echo "Verify the agent frontmatter parses:"
  echo "  claude --debug agents 2>&1 | grep -i longtask-worker"
else
  echo "Would install $installed file(s) into $live (and back up $backed_up)."
fi

if ((${#warn[@]})); then
  printf '\nWarnings:\n' >&2
  printf '  - %s\n' "${warn[@]}" >&2
fi

echo
echo "Not applied automatically (per-machine decisions — see settings.reference.json):"
echo "  - permissions.defaultMode  (e.g. bypassPermissions)"
echo "  - model, effortLevel, theme, enabledPlugins"
