---
name: lock-base
description: Restore base-scope deny rules from .claude/settings.locked.json backup, re-engaging the PreToolUse guardrail on src-tauri/src/persona/, providers/, and tools/. Use when user says "lock base", "/lock-base", "re-engage guardrails", or after finishing edits under an /unlock-base session. Deletes the backup and offers to restart Claude Code so the settings change takes effect.
---

# lock-base

Re-engage the base-scope guardrail after an `/unlock-base` session. Restores the deny rules from backup and deletes the backup file.

## When to invoke

- User explicitly asks: "lock base", "/lock-base", "re-engage guardrails", "relock"
- Automatically at the end of an edit session when `/unlock-base` was run earlier (ask first)
- Do NOT auto-invoke mid-session — wait for explicit cue.

## Preflight

1. Verify `pwd` contains `.claude/settings.locked.json`. If not present, report: "No backup found — /lock-base has nothing to restore. Either the project was never unlocked via /unlock-base, or the backup was deleted manually. To re-engage the guard, manually add the `permissions.deny` block back to .claude/settings.json and restart." and STOP.
2. Verify current `.claude/settings.json` exists. If missing, report the anomaly and STOP — manual intervention needed.
3. Ask the user to confirm:
   > "Restoring the base-scope deny rules from .claude/settings.locked.json.
   > Deny will reapply to:
   >   - src-tauri/src/persona/**
   >   - src-tauri/src/providers/**
   >   - src-tauri/src/tools/**
   >
   > Claude Code will need a RESTART for the change to take effect.
   >
   > Proceed? (y/N)"

   Abort on anything other than y/yes/go/confirm.

## Lock procedure

1. Copy `.claude/settings.locked.json` over `.claude/settings.json`.
2. Delete `.claude/settings.locked.json`.
3. Verify the restored `.claude/settings.json` contains the expected deny block. If deny is missing, warn loudly and refuse to delete the backup — something is off and manual inspection is needed.
4. Print confirmation:
   ```
   🔒 Base-scope guard RE-ENGAGED.
   Restored from: .claude/settings.locked.json (now deleted)
   Deny rules active: src-tauri/src/{persona,providers,tools}/**

   Settings change requires a Claude Code restart to take effect.
   ```

## Offer restart

After locking, check whether the `restart-self` skill is available (from the `cc-restart` plugin).

- **If available:** ask:
  > "Restart Claude Code now to apply? (y/N)"
  If yes, invoke the `restart-self` skill via the Skill tool.

- **If not available:** print manual instructions:
  > "Restart Claude Code manually for the change to take effect:
  >   - Desktop: close and reopen the app.
  >   - Terminal: exit this session (Ctrl+D or /exit) and launch `claude` again.
  > Recommended: install the `cc-restart` plugin for a one-command restart."

## Safety notes

- Never merge the backup into the current settings — the backup is authoritative for the deny block. Overwrite, don't merge. Other edits made to `.claude/settings.json` during the unlock window will be LOST. Warn the user in the confirmation prompt if the current settings.json differs from the backup in any field other than deny-related keys.
- If the user manually edited the deny block during unlock (e.g. added a new guarded directory), the backup is now stale. Detect by diffing current vs backup BEFORE overwriting. If they differ outside deny-related keys, ask: "Your current settings.json differs from the backup in [list fields]. Overwriting will lose those changes. Proceed anyway? (y/N)".

## Done report

One-liner summary: `🔒 Locked. Deny rules restored. Restart [pending|done] to apply. Guard is now active for src-tauri/src/{persona,providers,tools}/**.`
