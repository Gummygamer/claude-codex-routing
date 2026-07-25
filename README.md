# Claude/Codex Routing

Portable backup of the two-model Claude Code setup on this machine:
**Claude Opus 5 plans, Codex (gpt-5.6-terra, high reasoning effort) executes** —
plus the turn-capped long-task relay that lets a long task survive a context reset.

Everything here is a snapshot of `~/.claude`. Nothing in this folder is live; the
live config is what's under `$HOME/.claude`.

## What's in the snapshot

| Path | Role |
|---|---|
| `claude/bin/codex-handoff.sh` | Hands an approved plan to Codex. Pins `gpt-5.6-terra` + `model_reasoning_effort=high`, logs to `~/.claude/codex-handoff/<stamp>.{log,summary.md}` |
| `claude/bin/codex-route-hook.sh` | `PostToolUse: ExitPlanMode` hook — on plan approval, routes execution to Codex instead of letting Claude implement |
| `claude/bin/longtask-init.sh` | Scaffolds `.longtask/<slug>/` state with a schema a cold worker can parse |
| `claude/agents/longtask-worker.md` | One long-task segment. `maxTurns: 40`, `model: opus`, `effort: high` |
| `claude/skills/codex-exec/SKILL.md` | The handoff skill Claude follows after plan approval |
| `claude/skills/longtask/SKILL.md` | `/longtask` orchestrator loop |
| `claude/settings.hooks.json` | Just the `hooks` object — merged into a new machine's settings |
| `claude/settings.reference.json` | Full `settings.json` for eyeballing. **Not** applied automatically |

## How the long-task relay works

Claude Code (v2.1.220) has no turn-based auto-clear: `autoCompactEnabled` /
`autoCompactThreshold` do context-size-triggered *compaction* (which keeps a lossy
summary), and no hook output field can reset context. But agent frontmatter supports
`maxTurns`.

So the reset is built from that. Each segment is a fresh `longtask-worker` subagent —
a cold start with zero conversation *is* the `/clear`. It reads state from
`.longtask/<slug>/PROGRESS.md`, plans one chunk as Opus 5, hands every source edit to
Codex, verifies, checkpoints back to disk, and dies at the cap. The orchestrator
spawns the next one and keeps only a ≤3-line report, so main-session context grows by
a few hundred tokens per segment rather than tens of thousands.

`PROGRESS.md` is the memory that survives each reset. Its `Landmines` section is the
part that actually saves time — it stops each cold worker re-learning what the last
one already paid for.

## Prerequisites on a new machine

- Claude Code — the `maxTurns` agent-frontmatter field is required. Verified present
  in v2.1.220.
- `codex` CLI on `PATH` with access to `gpt-5.6-terra` (built against codex-cli
  0.144.0).
- `jq` — used by the sudo-guard hook and by `install-to-machine.sh`.

## Restore onto a new machine

```sh
./install-to-machine.sh            # preview: shows every change, writes nothing
./install-to-machine.sh --apply    # actually install
```

It copies the assets into `~/.claude`, `chmod +x`es the scripts, and **merges**
`settings.hooks.json` into any existing `~/.claude/settings.json` rather than
overwriting it. Anything it would replace is backed up to
`~/.claude/backups/routing-<stamp>/` first.

Then confirm the agent frontmatter parses. `claude --debug agents` needs a prompt and
prints nothing useful on its own, so ask a throwaway session to enumerate its agents:

```sh
claude -p "List every subagent_type value you can pass to the Agent tool, one per line, nothing else."
```

`longtask-worker` should appear. A bad frontmatter value surfaces as
`has invalid maxTurns '...'. Must be a positive integer.`

An already-open session picks up newly written agents and skills without a restart —
observed directly during the build. No need to restart Claude Code after installing.

## Refresh this snapshot from the live config

```sh
./sync-from-live.sh
```

Copies `~/.claude` → this folder and warns about anything missing. Run it after
changing the live setup, then commit.

## Deliberately not included

- `settings.local.json` — per-machine permission allowlists, not portable.
- `.credentials.json`, `history.jsonl`, `sessions/`, `projects/`, `file-history/` —
  secrets and local session state.
- `enabledPlugins`, `theme` and other machine-local preferences: they're visible in
  `settings.reference.json` but the installer won't apply them.
- `permissions.defaultMode: bypassPermissions` is in the reference file but is **not**
  merged. It's a deliberate per-machine trust decision — set it yourself if you want
  it.
