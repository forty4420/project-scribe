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
- `base-audit` — self-critic pass; checks current diff against `docs/BASE_ALLOWLIST.md` before commit
- `auto-handoff` — write a session handoff memo at context breakpoints
- `unlock-base` — temporarily lift base-scope deny rules (escape hatch for editing locked dirs)
- `lock-base` — restore deny rules after unlock

## Slash commands

- `/scribe` — dashboard readout from STATE.md
- `/unlock-base` — lift base-scope guardrails (offers restart)
- `/lock-base` — restore base-scope guardrails (offers restart)

## Base-scope enforcement (optional)

When you run `init-project-scribe`, you'll be asked whether to enable base-scope enforcement. If yes, this adds:

1. **Permission-layer deny rules** in `.claude/settings.json` for directories you've listed as "NOT allowed" in `docs/BASE_ALLOWLIST.md`. These are a hard wall: no "Allow always" prompt is ever offered because the write is rejected before the prompt stage.
2. **PreToolUse hook** that fires first and shows a custom block message with a pointer to `/unlock-base` — belt + suspenders.
3. **Pre-commit hook** that catches violations at the git layer too.
4. **SessionStart hook** that re-injects the guarded-path rules into Claude's context at every session.

### Unlock / lock workflow

If you legitimately need to edit a locked directory (rare — usually migration is correct):

```
> /unlock-base
```

Claude backs up `.claude/settings.json` to `.claude/settings.locked.json`, removes the deny rules, and offers to restart Claude Code so the settings take effect. Edit what you need, then:

```
> /lock-base
```

Restores the deny rules from backup, deletes the backup, offers restart. You're locked again.

### Recommended companion: `cc-restart`

The `unlock-base` and `lock-base` skills both need a Claude Code restart for settings changes to take effect. If you have the [`cc-restart`](https://github.com/forty4420/cc-restart) plugin installed, they'll offer a one-command restart. Without it, they fall back to printing manual restart instructions. Not required, but makes the flow smoother.

### Watch-out for user-global `permissions.allow`

If your user-global `~/.claude/settings.json` has `Write(*)`, `Edit(*)`, or `NotebookEdit(*)` in `permissions.allow`, those pre-approve writes BEFORE hooks and deny rules are consulted — silently defeating the guardrail. Remove those three entries from user-global allow; keep `Bash(*)`, `Read(*)`, etc. as-is.

## License

MIT
