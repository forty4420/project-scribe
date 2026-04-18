# project-scribe

A Claude Code plugin that keeps a per-project index so Claude doesn't lose context across sessions.

## What it does

- **`docs/STATE.md`** — one-page dashboard: current focus, last shipped (auto-reconciled against git log), next up, deferred.
- **`docs/DECISIONS.md`** — append-only log of architectural / scope / rules-of-engagement decisions made in conversation.
- **`CLAUDE.md`** — auto-loaded by Claude Code at session start; points at the map.
- **`docs/status/`** — per-spec implementation memos with a consistent shape.

## Install (local)

```bash
# From this plugin's repo:
ln -s "$(pwd)" ~/.claude/plugins/project-scribe
# Or on Windows:
# mklink /J "%USERPROFILE%\.claude\plugins\project-scribe" "C:\path\to\project-scribe"

# Restart Claude Code.
```

## Per-project setup

Inside any project:

```
> init project scribe
```

Claude runs the `init-project-scribe` skill. Fill in project name + current focus. Done.

## Skills

- `init-project-scribe` — one-shot bootstrap
- `reconcile-project-state` — auto-fires at session start; updates STATE.md "Last shipped" from `git log`
- `log-decision` — append a 4-field entry to DECISIONS.md
- `update-project-state` — end-of-ship refresh
- `deferred-rollup` — read-only query across all status memos

## Slash command

- `/scribe` — dashboard readout from STATE.md

## License

MIT
