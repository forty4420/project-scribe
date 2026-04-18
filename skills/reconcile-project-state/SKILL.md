---
name: reconcile-project-state
description: Use at the start of any session in a scribe-enabled project, and whenever the user asks to "reconcile", "check state", or "refresh state". Compares docs/STATE.md "Last shipped" block against `git log --oneline -10`. Auto-updates the block when they drift. Never touches Current focus, Next up, or Deferred.
---

# Reconcile project state against git

Keep `docs/STATE.md` accurate without blocking the user.

## When to invoke

- Automatically at session start (triggered via the plugin's SessionStart hook when `docs/STATE.md` exists in cwd).
- When the user asks: "reconcile", "check project state", "refresh state", "is STATE.md current".

## Pre-flight

1. Check for `docs/STATE.md`. If missing → report "project-scribe is not initialized in this project. Run init-project-scribe first." and STOP.
2. Check for a git repo. If not a git repo → silent no-op with a one-line note: "Not a git repo — skipped git reconcile."

## Read the current "Last shipped" block

Parse `docs/STATE.md`. Find the `## Last shipped` heading (exact match, case-sensitive). Extract the 3-5 bullet lines under it. Each bullet should look like `- <7-char-SHA> — <message>`. Keep the list.

If the heading can't be found → report: "STATE.md structure not recognized — run update-project-state to rebuild." STOP.

## Compare to git log

Run `git log --oneline -10` in the project root. Compare the top SHA in git to the top SHA in the STATE.md "Last shipped" block.

**Match** (top SHAs equal) → silent no-op. Do not modify STATE.md. Do not emit any user-facing message.

**Mismatch** → rewrite the block.

## Rewrite behavior (mismatch case)

1. Take the latest 3-5 commits from `git log --oneline -10`.
2. Format each as `- <short-SHA> — <commit-message>`.
3. Replace the content under `## Last shipped` with the new bullets.
4. Do NOT touch any other section of STATE.md. Current focus, Next up, Deferred, Specs index, Plans index all stay as the user curated them.
5. Save STATE.md.
6. Announce inline to the user:

```
Reconciled STATE.md — added N commits since last scribe update.
```

Where N is the count of new SHAs.

## Never do

- Do not commit the reconciliation. The user decides when to commit.
- Do not modify any STATE.md section other than "Last shipped."
- Do not modify DECISIONS.md, CLAUDE.md, or anything in `docs/status/`.
- Do not prompt the user for input. This is a silent-when-aligned, auto-patching skill.
