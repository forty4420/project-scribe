---
name: unlock-base
description: Temporarily remove base-scope deny rules from project .claude/settings.json so Write/Edit to guarded directories (persona/, providers/, tools/) can proceed. Use when user says "unlock base", "/unlock-base", "let me edit this locked file", or hits a "Base file locked" block from the pretooluse guardrail hook. Writes a backup to .claude/settings.locked.json and offers to restart Claude Code so the settings change takes effect.
---

# unlock-base

Lift the base-scope deny rules so edits to guarded directories become possible. Intended as a rare escape hatch — the default state is LOCKED. Always offer to relock afterwards.

## When to invoke

- User explicitly asks: "unlock base", "/unlock-base", "I need to edit this locked file"
- User hits the pretooluse `🔒 Base file locked` block and chooses the escape hatch
- Do NOT auto-invoke. Locks exist to catch drift; bypass must be deliberate.

## Preflight

1. Verify `pwd` contains a `.claude/settings.json` with a `permissions.deny` block. If not present, report: "No base-scope deny rules found in this project's .claude/settings.json — nothing to unlock." and STOP.
2. Verify `.claude/settings.locked.json` does NOT already exist. If it does, report: "Already unlocked — a backup at .claude/settings.locked.json exists. Run /lock-base to restore the guard first." and STOP.
3. Ask the user to confirm before doing anything:
   > "Unlocking will remove the deny rules for these paths:
   >   - src-tauri/src/persona/**
   >   - src-tauri/src/providers/**
   >   - src-tauri/src/tools/**
   >
   > Claude Code will need a RESTART for the change to take effect. Then edits to those paths will succeed silently. Run /lock-base when you're done to re-engage the guard.
   >
   > Proceed? (y/N)"

   Abort on anything other than y/yes/go/confirm.

## Unlock procedure

1. Copy current `.claude/settings.json` to `.claude/settings.locked.json` — this is the backup.
2. Edit `.claude/settings.json` to remove the `permissions.deny` array (leave `defaultMode` and other keys intact).
3. Add `.claude/settings.locked.json` to `.gitignore` if not already present (check for literal line, add if missing).
4. Print confirmation:
   ```
   🔓 Base-scope guard DISABLED for this project.
   Backup saved to: .claude/settings.locked.json
   Deny rules removed: src-tauri/src/{persona,providers,tools}/**

   ⚠️  Edit what you need, then run /lock-base to restore the guard.
   ⚠️  Settings change requires a Claude Code restart to take effect.
   ```

## Offer restart

After unlocking, check whether the `restart-self` skill is available (from the `cc-restart` plugin).

- **If available:** ask:
  > "Restart Claude Code now to apply? (y/N)"
  If yes, invoke the `restart-self` skill via the Skill tool. It handles preflight + confirmation + restart.

- **If not available:** print manual instructions:
  > "Restart Claude Code manually for the change to take effect:
  >   - Desktop: close and reopen the app.
  >   - Terminal: exit this session (Ctrl+D or /exit) and launch `claude` again.
  > Recommended: install the `cc-restart` plugin for a one-command restart."

## Safety notes

- Do NOT attempt to edit the deny rules inline in memory to bypass the permission check. Settings are cached at session start; any in-session edit is advisory until restart.
- The backup file is the only path back to locked state via `/lock-base`. Never delete `.claude/settings.locked.json` except through `/lock-base`.
- If the user wants to unlock a SINGLE file rather than all three dirs, refuse: the permission-deny syntax is directory-level and the unlock/lock skills treat all three dirs as one unit. They can delete the relevant deny entries manually if they want finer granularity, but warn this breaks the lock/unlock contract.

## Done report

One-liner summary: `🔓 Unlocked. Backup at .claude/settings.locked.json. Restart [pending|done] to apply. Run /lock-base when finished.`
