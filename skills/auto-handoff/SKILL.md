---
name: auto-handoff
description: Generate a session handoff document to transfer state to a new Claude Code session. Use when user says "handoff", "/handoff", "write a handoff", "create handoff", "time to hand off", or when context usage crosses 50% (agent-initiated). Produces a timestamped markdown file with current focus, just-decided facts, active todos, files touched, and a paste-ready prompt for the new session. Prevents drift during session switches.
---

# auto-handoff — session state transfer

Purpose: prevent context loss when switching sessions. Compaction throws away conversation detail; handoff preserves it in a durable markdown file that the next session reads at startup.

Trigger modes:

1. **User request:** "/handoff", "write a handoff", "hand off to new session"
2. **Context threshold:** when context usage exceeds ~50%, volunteer a handoff to the user. Do NOT silently generate — ask first.
3. **Session-end / compact-warning:** before running /compact, offer a handoff as a safer alternative.

## Procedure

### Step 0 — Base-scope drift pre-flight (scribe-enabled projects only)

If the project has `docs/BASE_ALLOWLIST.md`, run the pre-commit hook against
the working tree (staged + unstaged + untracked combined) before writing the
handoff. This catches drift that's sitting uncommitted — a common failure mode
where a bad file survives session switches without review.

```bash
# Simulate what pre-commit would see by staging everything, running the
# hook read-only, then resetting the index.
# Read-only alternative: scan `git status --porcelain` for new files under
# src-tauri/ or src/ and check against the allowlist + known-good top-levels.
bash .claude/hooks/precommit_base_guard.sh  # or scan logic inline
```

If drift is detected:
- Add a section **"⚠️ Uncommitted base-scope drift"** to the top of the handoff
  document listing the violations.
- Surface it in the chat reply so the user sees it before ending session.
- Do NOT refuse to write the handoff — drift might be intentional
  (mid-migration). The handoff's job is to carry state forward; flagging is
  enough.

If no allowlist in project, skip this step silently.

### Step 1 — Gather state

Collect in this order:

1. **Current branch + last 5 commits** — `git log --oneline -5` + `git branch --show-current`
2. **Uncommitted files** — `git status --short`
3. **Active todos from this session** — from TodoWrite state (read the current list, highlight in-progress + pending)
4. **New DECISIONS.md entries from this session** — `git diff --name-only HEAD docs/DECISIONS.md` (only if touched)
5. **Files edited this session** — rough list from tool-use history; focus on the 5-10 most substantive edits
6. **Open questions** — any AskUserQuestion prompts still pending, unresolved forks, or flagged "revisit when" items

### Step 2 — Classify the session phase

One of:
- **Spec writing** — currently drafting a design doc
- **Plan writing** — currently drafting an implementation plan
- **Executing** — walking a plan's tasks, committing as we go
- **Reviewing / debugging** — reading code, finding issues, not yet fixing
- **Meta / infra** — building guardrails, refactoring process, not shipping user features

This phase classification goes into the handoff so new-session me knows what mode we're in.

### Step 3 — Write the handoff file

Write to `docs/status/handoff-YYYY-MM-DD-HHMMSS.md` in the project root.

Do NOT overwrite existing handoff files. Use timestamp to keep a chronological trail. If the `docs/status/` directory doesn't exist, fall back to `.handoffs/` at project root.

Template:

```markdown
# Session Handoff — YYYY-MM-DD HH:MM:SS

**Branch:** <branch-name>
**Phase:** <phase from step 2>
**Previous session ended at:** <commit SHA | "uncommitted work present">

---

## One-paragraph summary

<2-4 sentences on what this session accomplished and what's immediately next>

---

## Just decided (this session)

<Bulleted list of new rules, locked choices, or agreed approaches from this session that aren't yet in DECISIONS.md, OR link to the DECISIONS.md entry if written>

---

## Active work

**In progress:**
- <current in-progress todo(s), exact phrasing>

**Next concrete step:**
<One sentence. What a new session should do first.>

**Pending todos:**
- <list of pending todos in order>

---

## Files touched this session

| Path | Status | Why |
|---|---|---|
| path/to/file.ext | modified/new/deleted | one-line reason |

---

## Uncommitted changes

<Output of `git status --short`. If empty, say "clean tree.">

---

## Open questions for Michael

<Any AskUserQuestion prompts still pending or unresolved decisions>

---

## Paste-this prompt for the new session

```
Resume the ownterm-v3 session handed off at <timestamp>. Read the handoff at
docs/status/handoff-<timestamp>.md for context. Current focus: <one-line>.
Next step: <one-line>.

Before starting:
1. Read docs/STATE.md (scribe auto-reconciles on startup)
2. Read the handoff file in full
3. Confirm with me you understand where we are before taking any action.
```

---

## What NOT to lose

<List 3-5 nuances from the conversation that might otherwise die in compaction.
Examples: specific phrasing Michael used for a locked decision, a subtle
tradeoff discussed but not recorded, a rejected approach that shouldn't be
re-proposed>
```

### Step 4 — Display handoff in chat

After writing the file, echo:

```
✅ Handoff written: docs/status/handoff-<timestamp>.md

Next session: paste the prompt from the "Paste-this prompt" section at the top of your new Claude Code session.
```

### Step 5 — Optional memory sync

If the session produced durable learnings (new feedback patterns, project facts), also update `.claude/projects/<proj>/memory/MEMORY.md` via the memory system. But only for truly durable facts — not session-ephemeral state.

## What this skill does NOT do

- Does not run `/compact`. It's an alternative, not a prelude.
- Does not commit anything. Michael commits when ready.
- Does not push to remote or notify external systems.
- Does not modify STATE.md. That's scribe's job.

## Interaction with project-scribe

- Scribe owns STATE.md (durable project state).
- This skill owns handoff files (per-session transfer documents).
- If both scribe and handoff are active: handoff references STATE.md, doesn't duplicate it.
- Scribe's `update-project-state` skill may be called after handoff to refresh the dashboard, but handoff itself doesn't trigger it.

## Context-threshold volunteer trigger

When context usage crosses ~50%, agent should ONE TIME (not repeatedly) prompt the user:

> "Context is at ~50%. Want me to write a handoff before we hit compaction? (Alternative to /compact — preserves conversation detail)"

If user says no, drop it. Don't re-prompt at 60%, 70% etc.
