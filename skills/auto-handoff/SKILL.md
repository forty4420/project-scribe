---
name: auto-handoff
description: Unified session shutdown — captures pending decisions, refreshes STATE.md, prunes MEMORY.md if needed, and writes a handoff document for the next session. Use when user says "handoff", "/handoff", "write a handoff", "save session", "shutdown", "wrap up", or when the scribe context-warning hook surfaces a /handoff suggestion. Smart-skips steps that have nothing to do. Pass --quick to write only the handoff doc and skip the bundle steps.
---

# auto-handoff — unified session shutdown + state transfer

Purpose: prevent context loss when switching sessions AND make sure
durable state (decisions, STATE.md, MEMORY.md) is current before
the transfer. Compaction throws away conversation detail; this skill
preserves what matters.

This skill replaces the old standalone handoff + the deprecated
`/shutdown-bundle` command. One command. Does the right thing.

## Trigger modes

1. **User request:** "/handoff", "write a handoff", "shutdown", "save session"
2. **Context warning:** the userprompt-context-warn hook surfaces a
   `<scribe-context-warning>` reminder at 30%+ usage. User runs handoff
   in response.
3. **Session-end:** before running `/compact`, offer handoff as a safer
   alternative.

## Modes

- **Default (full):** runs the bundle (decisions → state → memory → handoff doc).
- **`--quick`:** writes the handoff doc ONLY. Skips bundle steps. Use
  for mid-task panic saves or experimental sessions where you don't
  want to pollute durable state.

Detect mode from the user's prompt: presence of `--quick`, "quick handoff",
"just a handoff", "skip the bundle" → quick mode. Otherwise full.

## Procedure (full mode)

### Step 0 — Single confirmation

Announce the plan once, ask once:

> "Running full handoff. Will: (1) log pending decisions, (2) compact
> DECISIONS.md, (3) update STATE.md, (4) prune MEMORY.md if needed,
> (5) write handoff doc. Proceed? [y/n/quick]"

- `y` → run full bundle
- `quick` → switch to --quick mode (skip steps 1-4)
- `n` → abort, report nothing done

After this single confirmation, run all steps WITHOUT re-prompting.
Skipped steps print a one-line note. Failures print + halt.

### Step 1 — Base-scope drift pre-flight (if applicable)

If the project has `docs/BASE_ALLOWLIST.md`, run the pre-commit hook
read-only against the working tree before writing anything. This catches
drift sitting uncommitted.

```bash
# Read-only scan: list new/modified files under guarded directories,
# check against allowlist + known-good top-levels. Do NOT auto-stage.
bash .claude/hooks/precommit_base_guard.sh 2>&1 | head -50
```

If drift detected → flag in handoff doc under "⚠ Uncommitted base-scope
drift" but DO NOT abort. Drift may be intentional.

If no allowlist → skip silently.

### Step 2 — log-decision (auto-skip eligible)

Scan the session for DURABLE rule-shaped statements not yet in
DECISIONS.md. Indicators: "always do X", "never Y", "from now on",
"the rule is", "we decided".

- If none found → print `→ log-decision: no pending decisions, skipped.` Continue.
- If found → invoke the `log-decision` skill for each, batched.

### Step 3 — compact-decisions (auto-skip eligible)

If DECISIONS.md was not modified this session → print
`→ compact-decisions: DECISIONS.md unchanged, skipped.` Continue.

Otherwise → invoke the `compact-decisions` skill.

### Step 4 — update-project-state (always run)

Always run. Even if STATE.md feels current, the skill is idempotent
and refreshes the "Last shipped" block from `git log`. Cheap.

Invoke the `update-project-state` skill.

### Step 5 — compact-memory (auto-skip eligible)

Read MEMORY.md line count. If under 200 lines →
`→ compact-memory: MEMORY.md only N lines, skipped.` Continue.

If 200+ → invoke the `compact-memory` skill.

### Step 6 — Write handoff doc

This is the only step that runs in `--quick` mode too.

#### Gather state

1. **Current branch + last 5 commits** — `git log --oneline -5` + `git branch --show-current`
2. **Uncommitted files** — `git status --short`
3. **Active todos** — current TodoWrite list (in-progress + pending)
4. **DECISIONS.md changes this session** — `git diff --name-only HEAD docs/DECISIONS.md`
5. **Files edited this session** — 5-10 most substantive edits from tool history
6. **Open questions** — pending AskUserQuestion prompts, unresolved forks

#### Classify session phase

One of: spec-writing | plan-writing | executing | reviewing-debugging | meta-infra

#### Write file

Path: `docs/status/handoff-YYYY-MM-DD-HHMMSS.md`

Never overwrite. If `docs/status/` missing → fall back to `.handoffs/`.

Template:

```markdown
# Session Handoff — YYYY-MM-DD HH:MM:SS

**Branch:** <branch-name>
**Phase:** <phase>
**Mode:** full | quick
**Previous session ended at:** <commit SHA | "uncommitted work present">

---

## One-paragraph summary

<2-4 sentences on what this session accomplished and what's immediately next>

---

## Bundle results (full mode only)

- log-decision: <done | skipped — reason>
- compact-decisions: <done | skipped — reason>
- update-project-state: <done | skipped — reason>
- compact-memory: <done | skipped — reason>

(Omit this section in --quick mode.)

---

## Just decided (this session)

<Bulleted list of new rules from this session — link to DECISIONS.md entry IDs if logged>

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

## ⚠ Uncommitted base-scope drift

(Only present if step 1 found drift. List violations, one per line.)

---

## Open questions

<Any AskUserQuestion prompts still pending or unresolved decisions>

---

## Paste-this prompt for the new session

\`\`\`
Resume the <project> session handed off at <timestamp>. Read the handoff
at docs/status/handoff-<timestamp>.md for context.

Current focus: <one-line>
Next step: <one-line>

Before starting:
1. Read docs/STATE.md (scribe auto-reconciles on startup)
2. Read the handoff file in full
3. Confirm with me you understand where we are before taking any action.
\`\`\`

---

## What NOT to lose

<3-5 nuances from the conversation that might die in compaction:
specific phrasing for a locked decision, subtle tradeoffs discussed
but not recorded, rejected approaches that shouldn't be re-proposed>
```

### Step 7 — Reset cooldown

Delete the warn-hook cooldown marker so the next session's warnings
start clean:

```bash
rm -f "${HOME}/.claude/.scribe-context-last-warn" 2>/dev/null
```

### Step 8 — Final report

Print to chat:

```
✅ Handoff complete.

File: docs/status/handoff-<timestamp>.md

Bundle results:
- log-decision: <status>
- compact-decisions: <status>
- update-project-state: <status>
- compact-memory: <status>

Next session: paste the "Paste-this prompt" section into a new Claude
Code session. Or run /restart if you have cc-restart installed.
```

In `--quick` mode, omit the bundle results block.

## Procedure (quick mode)

Skip steps 2-5. Run step 1 (drift check), step 6 (write doc), step 7
(reset cooldown), step 8 (report).

Single confirmation prompt becomes:

> "Running quick handoff (doc only, no bundle). Proceed? [y/n]"

## What this skill does NOT do

- Does not run `/compact`. It's the alternative.
- Does not commit anything. User commits when ready.
- Does not push to remote.
- Does not auto-restart. User runs `/restart` separately.

## Interaction with scribe

- Scribe's `update-project-state` IS step 4 of this skill — fully integrated.
- DECISIONS.md is owned jointly: log-decision writes, compact-decisions consolidates, this skill orchestrates.
- STATE.md is owned by scribe; this skill triggers refresh, doesn't write directly.
- Handoff docs go in `docs/status/` alongside scribe's status memos.

## Migration note

This skill replaces the old `/shutdown-bundle` slash command. The
command file has been removed. All shutdown functionality now lives
in this single skill, invoked via `/handoff` or natural language.
