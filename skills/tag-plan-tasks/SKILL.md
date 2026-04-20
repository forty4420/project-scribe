---
name: tag-plan-tasks
description: Tag tasks in an implementation plan as AFK (AI-executable without supervision) or HITL (human-in-the-loop required). Use after writing-plans or brainstorming produces a multi-step plan, before execution begins. Triggers include "tag these tasks", "mark AFK/HITL", "classify this plan", "which steps need me".
---

# Tag plan tasks: AFK vs HITL

Every task in a plan is one of two shapes:

- **AFK** (Away From Keyboard) — safe for AI to execute autonomously. Reversible via `git revert`. Scoped to one module. No external side effects.
- **HITL** (Human-In-The-Loop) — requires human checkpoint before or during execution. Either irreversible, cross-cutting, or touches policy.

Tagging forces explicit pause points. Without it, AI barrels through policy edits the same way it fixes typos.

## When to invoke

- After `superpowers:writing-plans` produces a plan file
- After `superpowers:brainstorming` produces a step list
- When the user asks "tag these", "mark AFK/HITL", "which steps need me", "classify this plan"
- Before invoking `superpowers:executing-plans` on a multi-step plan

## Automatic HITL triggers

Any task matching any of these = HITL, no exceptions:

1. **Policy edits** — changes to `CLAUDE.md`, `AGENTS.md`, `docs/DECISIONS.md`, or any file named `VISION.md`, `RULES.md`, `POLICY.md`
2. **Allowlist / guardrail changes** — edits to `docs/BASE_ALLOWLIST.md`, `.claude/settings.json` deny/allow blocks, `.claude/settings.locked.json`, `.claude/hooks/`
3. **Locked-rule proposals** — any task that proposes adding/removing/modifying an item in a project's "Locked" or "don't re-argue" list
4. **Credentials / secrets** — rotation, new env vars, auth config, token storage
5. **Schema changes with data** — DB migrations that run against populated tables, destructive `ALTER TABLE`
6. **Force push / rebase on shared branches** — anything destructive to shared git history
7. **Release / publish** — `npm publish`, `gh release create`, `git tag -s`, plugin marketplace updates
8. **External service changes** — modifying production infra, DNS, cron jobs affecting other users
9. **Spec deletion / renaming** — any move that breaks existing `docs/superpowers/{specs,plans}` references
10. **Cross-cutting refactors** — changes touching 20+ files or multiple top-level modules

## AFK-default triggers

Any of these = AFK unless a HITL trigger also applies:

- Bug fix scoped to one function / module
- Test additions (unit or integration)
- Code formatting / lint auto-fixes
- Documentation updates to README or per-module docs (NOT policy docs above)
- Adding new files inside existing module boundaries
- Refactors scoped to one file
- Dependency updates from lockfile (already pinned ranges)
- TypeScript / lint error resolution

## Pipeline

1. Read the plan file (markdown with numbered or bulleted tasks).
2. For each task, evaluate against the trigger lists above.
3. Output the plan with a tag prefix on each task:
   - `[AFK]` — AI can run autonomously
   - `[HITL: <reason>]` — human checkpoint; reason names the trigger (e.g. `HITL: policy edit`, `HITL: allowlist change`)
4. Also produce a summary count at top:
   ```
   Plan summary: 12 tasks — 9 AFK, 3 HITL
   HITL gates: task 4 (policy edit), task 7 (allowlist change), task 11 (force push)
   ```
5. If a task is genuinely ambiguous (could go either way), tag as `[HITL: ambiguous — confirm scope]` and surface for user decision.
6. Do NOT modify the plan file in place — output the tagged version inline for review OR write to a sibling file `<plan>.tagged.md` if requested.

## Interaction with executing-plans

When `superpowers:executing-plans` runs a tagged plan:

- For each `[AFK]` task: execute without checkpoint
- For each `[HITL: ...]` task: STOP, summarize the task + reason, wait for explicit user "proceed" or "skip" before touching any tool
- If user overrides HITL repeatedly for same trigger type → flag it in `/session-end` memory candidates: "trigger <X> consistently overridden — reclassify as AFK?"

## Don't

- Do not tag tasks the user hasn't asked for tagging on. This skill runs on plans, not arbitrary to-do lists.
- Do not auto-downgrade HITL triggers even if the user overrode one last time. Each instance is independent.
- Do not modify the plan file silently. Always show tagged output first.
- Do not block on `[AFK]` tasks for non-HITL reasons (lint errors, etc.) — other skills handle those.
