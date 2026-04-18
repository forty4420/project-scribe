# project-scribe v1 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the project-scribe Claude Code plugin v1 as a local git repo at `C:/Users/forty/project-scribe/`, then install it via symlink and initialize it on Own Term v3 as the first dogfooded project.

**Architecture:** Prompt-based plugin — each skill is a SKILL.md file whose body is the instruction Claude follows when the skill is invoked. Templates are `.tmpl` files the init skill writes into target projects with simple `{{placeholder}}` substitution done by Claude during the init. One cross-platform shell hook (bash + cmd wrapper) fires on session-start and injects a reconcile reminder if `docs/STATE.md` is present in cwd.

**Tech Stack:** Markdown (SKILL.md, templates, commands), bash (hook script), batch (Windows wrapper), JSON (plugin manifest, hooks config). No runtime language beyond the session-start hook's shell script.

**Spec:** `docs/specs/2026-04-18-project-scribe-v1-design.md` — read end-to-end before starting.

**Context you need before starting:**
- Read the spec.
- Read `C:/Users/forty/.claude/plugins/cache/superpowers-git/superpowers/33e55e60b2ef/` to see a working plugin layout: `.claude-plugin/plugin.json`, `skills/<name>/SKILL.md`, `hooks/hooks.json` + `hooks/session-start` + `hooks/run-hook.cmd`. Mirror this structure.
- Read superpowers' `hooks/session-start` for the JSON-escape + `additionalContext` output pattern. Copy it — don't reinvent.
- Read superpowers' `hooks/run-hook.cmd` for the polyglot bash+cmd wrapper. Copy verbatim.
- **No users yet.** Plugin can be freely rewritten until v1 ships. Don't add defensive back-compat code.
- **Caveman mode active** for user chat. Code comments, commit messages, doc files stay in full sentences.
- **Working directory for plugin repo:** `C:/Users/forty/project-scribe/`. Git repo already initialized. Spec already committed at `654a327`.
- **Working directory for Own Term v3 init:** `C:/Users/forty/Downloads/ownterm-v3/`. That's where Task 16 runs.

---

## File structure

**Plugin repo — `C:/Users/forty/project-scribe/`:**

```
project-scribe/
├── .claude-plugin/
│   └── plugin.json                          NEW
├── .gitignore                                NEW
├── README.md                                 NEW
├── skills/
│   ├── init-project-scribe/
│   │   ├── SKILL.md                          NEW
│   │   └── templates/
│   │       ├── CLAUDE.md.tmpl                NEW
│   │       ├── STATE.md.tmpl                 NEW
│   │       ├── DECISIONS.md.tmpl             NEW
│   │       ├── docs-README.md.tmpl           NEW
│   │       ├── status-README.md.tmpl         NEW
│   │       └── spec-status.md.tmpl           NEW
│   ├── reconcile-project-state/
│   │   └── SKILL.md                          NEW
│   ├── log-decision/
│   │   └── SKILL.md                          NEW
│   ├── update-project-state/
│   │   └── SKILL.md                          NEW
│   └── deferred-rollup/
│       └── SKILL.md                          NEW
├── commands/
│   └── scribe.md                             NEW
├── hooks/
│   ├── hooks.json                            NEW
│   ├── session-start                         NEW
│   └── run-hook.cmd                          NEW
└── docs/
    ├── specs/
    │   └── 2026-04-18-project-scribe-v1-design.md   EXISTS (shipped)
    └── plans/
        └── 2026-04-18-project-scribe-v1.md   NEW (this file)
```

**Plugin's own dogfooded files (built by Task 15 after plugin is functional):**

```
project-scribe/
├── CLAUDE.md                                 NEW (via init on itself)
├── docs/
│   ├── STATE.md                              NEW (via init)
│   ├── DECISIONS.md                          NEW (via init)
│   ├── README.md                             NEW (via init)
│   └── status/
│       ├── README.md                         NEW (via init)
│       └── TEMPLATE.md                       NEW (via init)
```

**Own Term v3 files (built by Task 16):**

```
C:/Users/forty/Downloads/ownterm-v3/
├── CLAUDE.md                                 NEW (via init)
└── docs/
    ├── STATE.md                              NEW (via init)
    ├── DECISIONS.md                          NEW (via init)
    ├── README.md                             NEW (via init)
    └── status/
        ├── README.md                         NEW (via init)
        └── TEMPLATE.md                       NEW (via init)
```

Note: Own Term v3 already has `docs/superpowers/plans/.notes/*-status.md` memos. Task 16 preserves these — init skill detects existing status memos and links to them instead of overwriting.

---

## Chunk 1: Plugin scaffolding + manifest + hook

### Task 1: Plugin manifest and scaffolding

**Files:**
- Create: `C:/Users/forty/project-scribe/.claude-plugin/plugin.json`
- Create: `C:/Users/forty/project-scribe/.gitignore`
- Create: `C:/Users/forty/project-scribe/README.md`

- [ ] **Step 1: Write plugin.json**

```json
{
  "name": "project-scribe",
  "description": "Per-project index, decisions log, and dashboard that Claude maintains across sessions. Reconciles against git log at session start so context doesn't rot.",
  "version": "0.1.0",
  "author": {
    "name": "Michael Adams",
    "email": "forty4420@gmail.com"
  },
  "license": "MIT",
  "keywords": ["project-memory", "session-context", "index", "decisions", "state-tracking"]
}
```

- [ ] **Step 2: Write .gitignore**

```
.DS_Store
Thumbs.db
*.tmp
*.bak
node_modules/
```

- [ ] **Step 3: Write README.md with install + usage**

```markdown
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
```

- [ ] **Step 4: Commit**

```bash
cd "C:/Users/forty/project-scribe" && git add .claude-plugin/ .gitignore README.md && git commit -m "feat: plugin manifest + README + gitignore"
```

### Task 2: Session-start hook (cross-platform shell + cmd wrapper)

**Files:**
- Create: `C:/Users/forty/project-scribe/hooks/hooks.json`
- Create: `C:/Users/forty/project-scribe/hooks/session-start`
- Create: `C:/Users/forty/project-scribe/hooks/run-hook.cmd`

- [ ] **Step 1: Write hooks.json (matches superpowers pattern)**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "'${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd' session-start",
            "async": false
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Write hooks/session-start (bash)**

The hook reads `docs/STATE.md` from cwd (if present) and injects a system-reminder directing Claude to run `reconcile-project-state` on the first response. If STATE.md is absent, the hook exits silent — zero cost on non-scribe projects.

```bash
#!/usr/bin/env bash
# SessionStart hook for project-scribe plugin.
#
# Checks cwd for docs/STATE.md. If present, injects a reminder instructing
# Claude to run the reconcile-project-state skill before its first response.
# If absent, exits silently. Zero-cost for projects that haven't opted in.

set -euo pipefail

PROJECT_ROOT="$(pwd)"
STATE_FILE="${PROJECT_ROOT}/docs/STATE.md"

if [ ! -f "$STATE_FILE" ]; then
    # Not a scribe-enabled project. Silent no-op.
    exit 0
fi

# Build the reminder. Claude will see this as a system-reminder in the
# session context and act on it before responding to the user.
reminder=$'<project-scribe>\nThis project is project-scribe enabled. Before your first response:\n\n1. Invoke the `reconcile-project-state` skill to check `docs/STATE.md` against `git log`.\n2. If drift is detected, the skill will update STATE.md\'s "Last shipped" block and announce the reconcile inline.\n3. If no drift, the skill silently confirms and you proceed normally.\n\nThe rest of the session-context conventions (decision logging, locked rules, etc.) are in the project\'s `CLAUDE.md`.\n</project-scribe>'

# Escape for JSON embedding (same pattern superpowers uses).
escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

reminder_escaped=$(escape_for_json "$reminder")

# Emit JSON for both Claude Code and Cursor hook shapes.
cat <<EOF
{
  "additional_context": "${reminder_escaped}",
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${reminder_escaped}"
  }
}
EOF

exit 0
```

- [ ] **Step 3: Write hooks/run-hook.cmd (polyglot wrapper, copy from superpowers)**

```
: << 'CMDBLOCK'
@echo off
REM Cross-platform polyglot wrapper for hook scripts.
REM On Windows: cmd.exe runs the batch portion, which finds and calls bash.
REM On Unix: the shell interprets this as a script (: is a no-op in bash).
REM
REM Usage: run-hook.cmd <script-name> [args...]

if "%~1"=="" (
    echo run-hook.cmd: missing script name >&2
    exit /b 1
)

set "HOOK_DIR=%~dp0"

if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

where bash >nul 2>nul
if %ERRORLEVEL% equ 0 (
    bash "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

exit /b 0
CMDBLOCK

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
```

- [ ] **Step 4: Make hook executable on Unix**

```bash
chmod +x C:/Users/forty/project-scribe/hooks/session-start
```

(Windows git will track the file-mode bit; useful if plugin later ships cross-platform.)

- [ ] **Step 5: Test the hook in isolation**

```bash
cd /tmp && rm -rf scribe-hook-test && mkdir scribe-hook-test && cd scribe-hook-test
# Case A: no STATE.md → silent no-op (exit 0, no JSON)
bash "C:/Users/forty/project-scribe/hooks/session-start" && echo "OK"
# Expected: "OK" with no JSON emitted.

# Case B: STATE.md present → emits JSON with reminder
mkdir -p docs && echo "# STATE" > docs/STATE.md
bash "C:/Users/forty/project-scribe/hooks/session-start"
# Expected: valid JSON with "additional_context" containing "reconcile-project-state".
```

- [ ] **Step 6: Commit**

```bash
cd "C:/Users/forty/project-scribe" && git add hooks/ && git commit -m "feat(hooks): session-start reconcile trigger with cross-platform wrapper"
```

---

## Chunk 2: Skills (five SKILL.md files)

### Task 3: init-project-scribe skill

**Files:**
- Create: `C:/Users/forty/project-scribe/skills/init-project-scribe/SKILL.md`

- [ ] **Step 1: Write the skill**

```markdown
---
name: init-project-scribe
description: Use when the user asks to set up, initialize, bootstrap, or add project-scribe tracking to the current project. Triggers include "init project scribe", "initialize project scribe", "set up project scribe", "add project tracking", "enable scribe for this repo". One-shot operation — creates CLAUDE.md, docs/STATE.md, docs/DECISIONS.md, docs/README.md, docs/status/README.md, docs/status/TEMPLATE.md.
---

# Initialize project-scribe for this project

One-shot bootstrap. Create the six files this plugin needs to start tracking project context in the current working directory.

## When to invoke

- User explicitly asks: "init project scribe", "set up scribe", "enable project tracking", etc.
- Do NOT auto-invoke. Only when the user asks.

## Pre-flight

1. Confirm `pwd` is the target project root. If ambiguous, ask.
2. Check for existing `docs/STATE.md`. If present: STOP and report "project-scribe is already initialized here — use the update-project-state skill to refresh, or delete docs/STATE.md first if you want to re-init."
3. Check for existing `CLAUDE.md` at root. If present: plan to append a "## Project-scribe additions" section instead of overwriting.
4. If `docs/` doesn't exist, plan to create it.
5. Check whether `git` is available and the project is a git repo. If not, plan to skip the git-log seed with a warning in the output.

## Gather 3-4 inputs from the user

Ask one at a time, plain language:

1. **Project name** — short name for the project. Default to the directory's basename if the user says "whatever."
2. **Current focus** — one sentence describing what's being worked on right now.
3. **Specs directory** — where specs live. Default `docs/specs/` or `docs/superpowers/specs/`. Check both; prefer the one that exists.
4. **Plans directory** — where plans live. Default `docs/plans/` or `docs/superpowers/plans/`. Check both; prefer the one that exists.

If the user says "just use defaults", pick the existing directory or `docs/specs/` + `docs/plans/` if neither exists.

## Gather the "Locked" rules

Ask: "Any locked architectural rules for this project? Things that shouldn't be re-argued mid-session? One per line. Leave blank if none yet — you can add them later."

Examples to prompt with if the user is unsure:
- "All new features are plugins, not base modifications"
- "No users yet — breaking changes OK"
- "Cross-platform is non-negotiable"

Collect the list. May be empty.

## Seed "Last shipped" from git

Run `git log --oneline -5` in the project root. Keep the output verbatim for the STATE.md "Last shipped" section. If the command fails (not a git repo), use the placeholder text `_not a git repository — fill this in manually_`.

## Scan specs and plans directories

1. List files in the specs directory (if it exists). For each file, read the first two lines to extract a title.
2. List files in the plans directory (if it exists). For each file, look for a `**Spec:**` reference on the first 10 lines; record the linked spec.
3. Check for existing status memos at `docs/status/*.md` or `docs/superpowers/plans/.notes/*.md`. Note their paths — DO NOT move or delete them.

## Write the files

All paths are relative to project root.

1. **`CLAUDE.md`** — if doesn't exist, write from `templates/CLAUDE.md.tmpl` with placeholders filled. If exists, append a clearly-delimited "## Project-scribe additions" block with the same content minus the top headings.

2. **`docs/STATE.md`** — write from `templates/STATE.md.tmpl` with:
   - `{{project_name}}`
   - `{{current_focus}}`
   - `{{last_shipped_block}}` — the git log output, formatted as markdown bullets
   - `{{specs_table}}` — rows for each spec found, status column = `draft` if no matching status memo exists, `shipped` if one does
   - `{{plans_table}}` — rows for each plan found

3. **`docs/DECISIONS.md`** — write from `templates/DECISIONS.md.tmpl` with the project name filled. No entries yet; the template shows the shape.

4. **`docs/README.md`** — write from `templates/docs-README.md.tmpl`. Include a one-line blurb for every file currently in `docs/` and `docs/status/`.

5. **`docs/status/README.md`** — write from `templates/status-README.md.tmpl`. If any existing status memos were found (including legacy locations like `docs/superpowers/plans/.notes/`), link to them in a "Current status memos" section.

6. **`docs/status/TEMPLATE.md`** — write from `templates/spec-status.md.tmpl` verbatim.

## Commit

Offer the user a single commit:

```
chore(scribe): initialize project-scribe

Adds CLAUDE.md, docs/STATE.md, docs/DECISIONS.md, docs/README.md,
docs/status/README.md, docs/status/TEMPLATE.md.

Current focus: {{current_focus}}
```

If the user declines, leave files on disk uncommitted.

## Done report

Tell the user what was created. Flag any edge cases:
- CLAUDE.md was appended rather than created fresh
- Git wasn't available, so Last shipped is a placeholder
- Existing status memos were linked but not moved

Point them at the first thing to try: `/scribe` to see the dashboard, or "log a decision" to capture their first rule.
```

- [ ] **Step 2: Commit**

```bash
cd "C:/Users/forty/project-scribe" && git add skills/init-project-scribe/SKILL.md && git commit -m "feat(skills): init-project-scribe bootstrap skill"
```

### Task 4: reconcile-project-state skill

**Files:**
- Create: `C:/Users/forty/project-scribe/skills/reconcile-project-state/SKILL.md`

- [ ] **Step 1: Write the skill**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
cd "C:/Users/forty/project-scribe" && git add skills/reconcile-project-state/SKILL.md && git commit -m "feat(skills): reconcile-project-state auto-reconciler"
```

### Task 5: log-decision skill

**Files:**
- Create: `C:/Users/forty/project-scribe/skills/log-decision/SKILL.md`

- [ ] **Step 1: Write the skill**

```markdown
---
name: log-decision
description: Use when the user asks to log a decision, save a rule, record a trade-off, or when you recognize a rule-shaped statement in the conversation ("no users yet", "always do X for Y", "defer Z until W") and want to capture it. Appends a 4-field entry to the top of docs/DECISIONS.md.
---

# Log a project decision

Append-only decision log. Never edit past entries.

## When to invoke

- User explicit ask: "log this decision", "record that rule", "save as decision", "log it".
- Auto-propose (but don't write until user confirms): when the user makes a statement that sounds like a durable rule, ask: "that sounds like a durable decision — log it?"
  - Rule-shaped statements include: scope boundaries ("no X until Y"), technical constants ("always use A for B"), priorities ("Z is not shipping in v1"), trade-offs ("we accept <cost> because <reason>").

## Pre-flight

1. Check for `docs/DECISIONS.md`. If missing → suggest running init-project-scribe first.
2. Confirm the user wants to log this (if auto-proposed — do not write without confirmation).

## Gather the 4 fields

Plain-language prompt, one at a time or in one block depending on user preference:

1. **Title** — short, 3-8 words. Example: "Break things freely until first external user"
2. **Context** — why this decision was needed. 2-4 sentences. Example: "Solo dev, pre-release, no installed base. Every migration/deprecation cycle we add now is premature."
3. **Decision** — what was decided. 2-4 sentences. Example: "No migration paths, no deprecation cycles. Rename and delete freely. Config keys can change schema."
4. **Revisit when** — what condition would make this stale. 1 sentence. Example: "First non-Michael user installs."

If the user wants to skip Revisit-when, default to "Revisit when this decision feels wrong."

## Format the entry

```markdown
## YYYY-MM-DD — <Title>

**Context:** <context text>

**Decision:** <decision text>

**Revisit when:** <revisit text>
```

Date = today's date in ISO format.

## Insert into DECISIONS.md

1. Read `docs/DECISIONS.md`.
2. Find the first `## ` heading (the most recent decision) OR the end of the preamble (if no decisions yet).
3. Insert the new entry immediately above the first heading (so newest is on top).
4. Save.

## Commit offer

Offer:

```
docs(scribe): log decision — <title>
```

User can decline; file stays modified.

## Reversing a decision

If the user wants to reverse a past decision, do NOT edit the past entry. Create a new entry:

```markdown
## YYYY-MM-DD — Reverses YYYY-MM-DD: <original title>

**Context:** <what changed>

**Decision:** <new decision>

**Revisit when:** <condition>
```

And mention the original date in the title. The log tells the story chronologically.
```

- [ ] **Step 2: Commit**

```bash
cd "C:/Users/forty/project-scribe" && git add skills/log-decision/SKILL.md && git commit -m "feat(skills): log-decision append-only log skill"
```

### Task 6: update-project-state skill

**Files:**
- Create: `C:/Users/forty/project-scribe/skills/update-project-state/SKILL.md`

- [ ] **Step 1: Write the skill**

```markdown
---
name: update-project-state
description: Use at session end or after a spec ships. Runs git reconcile, prompts for updated Current focus / Next up / Deferred, rebuilds Specs and Plans index tables from disk, warns about missing status memos. Triggers include "update project state", "refresh scribe", "scribe update", and "session end" when scribe is active.
---

# Update project state

End-of-session or end-of-ship refresh for STATE.md.

## When to invoke

- User explicit: "update project state", "refresh scribe", "scribe update".
- Automatic consideration: when the user says "session end" or "/session-end" in a scribe-enabled project.

## Pre-flight

1. Check for `docs/STATE.md`. Missing → suggest init.
2. Run the reconcile-project-state skill first (or inline its logic). "Last shipped" must be current before the rest runs.

## Prompt for updates

For each section, show the current content and ask "update?":

1. **Current focus** (1 line) — "Current focus is: `<current>`. Keep, or update?"
2. **Next up** (3 bullets) — show existing list, ask for updated list. User can say "same" or provide new bullets.
3. **Blocked / deferred** — show existing, ask for adds/removes.

Never force-overwrite. If the user says "skip", keep the existing section and move on.

## Rebuild index tables

1. Scan `{{specs_dir}}` (from the config the init skill wrote into STATE.md — look for the section that says which dir was used).
2. For each spec file:
   - Read the first two lines for a title.
   - Check whether a matching status memo exists in `docs/status/` or any legacy location referenced by `docs/status/README.md`.
   - Status column: `shipped` if memo exists, `active` if a plan references this spec, `draft` otherwise.
3. Same for `{{plans_dir}}` — each plan lists its linked spec if one is referenced in its preamble.
4. Replace the `## Specs index` and `## Plans index` tables in STATE.md.

## Check for missing status memos

If any spec has status `shipped` (has a merge commit that references it) but no status memo file — warn:

```
Shipped specs without status memos:
- <spec-filename>

Create a status memo from docs/status/TEMPLATE.md? (yes/skip)
```

If user says yes, copy the template, fill the header fields, open the file in the user's editor (or print the path for them).

## Commit offer

```
docs(scribe): update state after <what-shipped>
```

Where `<what-shipped>` is derived from the commits added since the last STATE.md update. If nothing shipped, use "update state".

## Don't touch

- DECISIONS.md — not rewritten by this skill.
- CLAUDE.md — only updated manually by the user or by init.
- `docs/status/*.md` (beyond offering to create missing ones) — those are edited as part of the spec's own workflow.
```

- [ ] **Step 2: Commit**

```bash
cd "C:/Users/forty/project-scribe" && git add skills/update-project-state/SKILL.md && git commit -m "feat(skills): update-project-state end-of-ship refresh"
```

### Task 7: deferred-rollup skill

**Files:**
- Create: `C:/Users/forty/project-scribe/skills/deferred-rollup/SKILL.md`

- [ ] **Step 1: Write the skill**

```markdown
---
name: deferred-rollup
description: Use when the user asks "what's deferred", "show deferred items", "what's on the backlog", "rollup deferred". Read-only. Aggregates deferred sections from all status memos into one view.
---

# Deferred items roll-up

Read-only report. Don't modify any files.

## When to invoke

- User asks: "what's deferred", "show deferred items", "what's on the backlog", "rollup deferred across specs", "give me the deferred list".

## Pre-flight

1. Check for `docs/status/`. If missing → "project-scribe is not initialized here."
2. Also scan any legacy status paths referenced in `docs/status/README.md` (e.g., `docs/superpowers/plans/.notes/*.md` on projects that pre-date this plugin).

## Collect deferred items

1. Read every `*.md` file in `docs/status/` (skip `README.md` and `TEMPLATE.md`).
2. Also read legacy status paths if any.
3. For each file:
   - Extract the spec name from the first heading.
   - Find the section titled `## Deferred` or `## Deferrals` (case-insensitive).
   - Collect the bullet list under it.
   - Separately collect any bullets marked with `~~strikethrough~~` — those are the resolved ones.

## Present the rollup

Output in two sections:

```
## Still deferred

### From <spec-name>
- <bullet>
- <bullet>

### From <spec-name>
- <bullet>

## Recently resolved

### From <spec-name>
- ~~<bullet>~~ ✅ <shipped-note>
```

If no deferred items found, report: "No deferred items tracked. All shipped specs' status memos are fully resolved or don't track deferrals."

## Don't do

- Don't write to any file.
- Don't commit.
- Don't suggest moving things around. This is a read-only report.
```

- [ ] **Step 2: Commit**

```bash
cd "C:/Users/forty/project-scribe" && git add skills/deferred-rollup/SKILL.md && git commit -m "feat(skills): deferred-rollup read-only query"
```

---

## Chunk 3: Templates

### Task 8: Init templates — CLAUDE.md + STATE.md + DECISIONS.md

**Files:**
- Create: `C:/Users/forty/project-scribe/skills/init-project-scribe/templates/CLAUDE.md.tmpl`
- Create: `C:/Users/forty/project-scribe/skills/init-project-scribe/templates/STATE.md.tmpl`
- Create: `C:/Users/forty/project-scribe/skills/init-project-scribe/templates/DECISIONS.md.tmpl`

- [ ] **Step 1: Write CLAUDE.md.tmpl**

```markdown
# {{project_name}}

{{project_summary}}

## Read first (every new session)

1. `docs/STATE.md` — current focus, last shipped, next up, deferred, specs/plans index
2. `docs/DECISIONS.md` — top 5 entries, for recent rules of engagement
3. Any project vision / charter doc (e.g. `docs/v3/VISION.md` on Own Term)

## Current focus

{{current_focus}}

## Locked — don't re-argue

{{locked_rules}}

## Rule-drift watch

If anything you or the user proposes contradicts the Locked list above, STOP and flag it before acting. Quote the specific rule. Ask whether to update the Locked list or back off the proposal. Never silently violate a locked rule.

## Where work lives

- Specs: `{{specs_dir}}`
- Plans: `{{plans_dir}}`
- Implementation status memos: `docs/status/` (one per shipped spec)
- Decisions log: `docs/DECISIONS.md`
- Project-scribe state dashboard: `docs/STATE.md`

## How to update project state

- Auto: session-start hook runs `reconcile-project-state` to sync "Last shipped" with `git log`.
- After a spec ships: ask Claude to "update project state" — refreshes Next up, adds deferred items, rebuilds indexes.
- Mid-session: ask Claude to "log a decision" when a durable rule gets stated.
- Quick readout: `/scribe` — returns current focus + last shipped + next up.
```

- [ ] **Step 2: Write STATE.md.tmpl**

```markdown
# {{project_name}} — Project State

_Maintained by [project-scribe](https://github.com/<user>/project-scribe). Updated auto-ish at session start (Last shipped) and by the user on ship (Current focus / Next up / Deferred)._

## Current focus

{{current_focus}}

## Last shipped

{{last_shipped_block}}

## Next up

{{next_up_block}}

## Blocked / deferred

{{deferred_block}}

## Specs index

| Spec | Status | Status memo |
|---|---|---|
{{specs_table}}

## Plans index

| Plan | Linked spec | Status |
|---|---|---|
{{plans_table}}
```

- [ ] **Step 3: Write DECISIONS.md.tmpl**

```markdown
# {{project_name}} — Decisions

Append-only log of project-wide decisions. Newest on top. Four fields each. Never edit past entries — reverses are new entries linking back.

---

_No decisions logged yet. First decision will appear above this line._
```

- [ ] **Step 4: Commit**

```bash
cd "C:/Users/forty/project-scribe" && git add skills/init-project-scribe/templates/CLAUDE.md.tmpl skills/init-project-scribe/templates/STATE.md.tmpl skills/init-project-scribe/templates/DECISIONS.md.tmpl && git commit -m "feat(templates): CLAUDE.md + STATE.md + DECISIONS.md templates"
```

### Task 9: Init templates — docs-README + status-README + spec-status

**Files:**
- Create: `C:/Users/forty/project-scribe/skills/init-project-scribe/templates/docs-README.md.tmpl`
- Create: `C:/Users/forty/project-scribe/skills/init-project-scribe/templates/status-README.md.tmpl`
- Create: `C:/Users/forty/project-scribe/skills/init-project-scribe/templates/spec-status.md.tmpl`

- [ ] **Step 1: Write docs-README.md.tmpl**

```markdown
# {{project_name}} — docs map

Five-minute orientation for new readers (human or AI).

## Top of book

- **`STATE.md`** — the dashboard. Current focus, last shipped, what's next, deferred items.
- **`DECISIONS.md`** — append-only log of architectural and scope decisions.
- **`README.md`** — this file. Map of what's in docs/.

## Work artifacts

- **`{{specs_dir_rel}}`** — design specs, one file per spec.
- **`{{plans_dir_rel}}`** — implementation plans tied to specs.
- **`status/`** — implementation status memos, one per shipped spec. See `status/README.md`.

## Other

{{other_docs_bullets}}

## How this file stays current

Update this map when new top-level files or directories land in `docs/`. The `update-project-state` skill does not auto-update this file — it's manually curated because folder structure is a deliberate choice.
```

- [ ] **Step 2: Write status-README.md.tmpl**

```markdown
# Implementation status memos

Every shipped spec gets a matching `<spec-slug>.md` memo in this directory.

## Shape

Copy `TEMPLATE.md` when starting a new memo. Sections:

- **Shipped** — bullet list of what the spec delivered
- **Tests** — unit / integration / manual verification counts
- **Deferred** — bullet list of items punted to future work; mark resolved items with `~~strikethrough~~` plus a link to the spec that resolved them
- **Known issues discovered** — quirks / vendor bugs / gotchas surfaced during implementation

## Why this pattern

Running list of "what shipped, what's still open, what we learned." Prevents deferred items from getting lost across spec boundaries and gives future sessions a quick map of what's done.

The `deferred-rollup` skill reads every file here and aggregates the Deferred sections into one view.

## Current status memos

{{status_memos_list}}
```

- [ ] **Step 3: Write spec-status.md.tmpl**

```markdown
# {{spec_name}} — Implementation Status

**Spec:** {{specs_dir}}/YYYY-MM-DD-<slug>-design.md
**Plan:** {{plans_dir}}/YYYY-MM-DD-<slug>.md
**Shipped:** YYYY-MM-DD on branch `<name>`
**Commits:** <count>

## Shipped

- <feature bullet>
- <feature bullet>

## Tests

- Unit: <count> passing
- Integration: <count> passing
- Manual smoke: <verified | pending>

## Deferred

_Items the spec flagged as out-of-scope for this pass. Mark resolved ones with ~~strikethrough~~ and a date + replacement link when they eventually ship._

- <item> — <reason deferred>
- <item> — <reason deferred>

## Known issues discovered

_Quirks and gotchas that weren't in the spec but surfaced during implementation. Future sessions reading this save the rediscovery time._

- <discovery>

## Branch state

Current branch + merge status.
```

- [ ] **Step 4: Commit**

```bash
cd "C:/Users/forty/project-scribe" && git add skills/init-project-scribe/templates/ && git commit -m "feat(templates): docs-README + status-README + spec-status templates"
```

---

## Chunk 4: Slash command + install + dogfood

### Task 10: /scribe slash command

**Files:**
- Create: `C:/Users/forty/project-scribe/commands/scribe.md`

- [ ] **Step 1: Write the command**

```markdown
---
description: Dashboard readout from docs/STATE.md — current focus, last shipped, next up.
---

Read `docs/STATE.md` from the current project root.

Extract and display these three sections, verbatim, nothing else:

1. Current focus
2. Last shipped
3. Next up

Format as a compact block. No prose commentary. No suggestions. Just the data.

If `docs/STATE.md` doesn't exist, respond: `Project-scribe not initialized. Run init-project-scribe to enable.`

If the file exists but any of the three sections is missing, report: `STATE.md is incomplete — run update-project-state to rebuild.`
```

- [ ] **Step 2: Commit**

```bash
cd "C:/Users/forty/project-scribe" && git add commands/scribe.md && git commit -m "feat(commands): /scribe dashboard readout"
```

### Task 11: Install the plugin via symlink

**Files:** none modified (filesystem operation)

- [ ] **Step 1: Verify plugins dir exists**

```bash
ls -la "C:/Users/forty/.claude/plugins/" 2>&1 | head -5
```

Expected: dir exists with other plugins (superpowers, etc.) inside.

- [ ] **Step 2: Create symlink (Windows requires admin or Developer Mode — fall back to junction if needed)**

Try symlink first:

```bash
cd "C:/Users/forty/.claude/plugins" && ln -s "/c/Users/forty/project-scribe" project-scribe && ls -la project-scribe
```

Expected: symlink listed pointing at the plugin repo. If `ln -s` fails on Windows, use mklink:

```cmd
mklink /J "C:\Users\forty\.claude\plugins\project-scribe" "C:\Users\forty\project-scribe"
```

(`/J` = directory junction; works without admin.)

- [ ] **Step 3: Verify Claude Code picks it up**

Can't verify in-session (needs a new session to reload plugins). Confirm the symlink target readable:

```bash
ls "C:/Users/forty/.claude/plugins/project-scribe/.claude-plugin/plugin.json"
cat "C:/Users/forty/.claude/plugins/project-scribe/.claude-plugin/plugin.json"
```

Expected: file is readable through the symlink/junction, correct content.

- [ ] **Step 4: Note for next session**

Log a reminder: "Start a new Claude Code session to pick up the project-scribe plugin. Skills and the /scribe slash command will be available after reload."

No commit needed — filesystem change, not in the plugin repo.

### Task 12: Dogfood — initialize project-scribe on the plugin itself

**Files (in `C:/Users/forty/project-scribe/`):**
- Create: `CLAUDE.md`
- Create: `docs/STATE.md`
- Create: `docs/DECISIONS.md`
- Create: `docs/README.md`
- Create: `docs/status/README.md`
- Create: `docs/status/TEMPLATE.md`

- [ ] **Step 1: Walk through the init-project-scribe skill manually**

Plugin's session hasn't reloaded yet, so the init skill isn't invokable via Claude Code. Execute the skill's behavior by hand based on the SKILL.md written in Task 3. Inputs:

- Project name: `project-scribe`
- Current focus: `v1 implementation complete, dogfooding begins next session`
- Specs dir: `docs/specs`
- Plans dir: `docs/plans`
- Locked rules:
  - `Prompt-based — skills are markdown, not code. No compilation.`
  - `Hook must no-op when STATE.md absent. Zero cost on non-scribe projects.`
  - `DECISIONS.md is append-only. Never edit past entries.`

- [ ] **Step 2: Fill CLAUDE.md from template**

Substitute all `{{placeholders}}` with values from Step 1. Write to `C:/Users/forty/project-scribe/CLAUDE.md`.

- [ ] **Step 3: Fill STATE.md from template**

Run `git log --oneline -10` in the plugin repo. Use the top 3-5 commits for "Last shipped". Leave "Next up" as:

```
- Reload Claude Code session to activate the plugin.
- Verify /scribe command works against the plugin's own STATE.md.
- Initialize project-scribe on Own Term v3 (first external dogfood).
```

Leave "Deferred" empty. Build specs index with just the v1 design spec; plans index with this plan file.

- [ ] **Step 4: Fill DECISIONS.md from template**

Start with the 3 locked rules as 3 initial decisions (dated today). Example:

```markdown
## 2026-04-18 — Hook must no-op when STATE.md absent

**Context:** Plugin's SessionStart hook fires in every cwd. If it adds cost to every project — even those that haven't opted in — the plugin is a tax on the whole Claude Code install.

**Decision:** The hook checks for `docs/STATE.md` and exits silently when absent. No JSON output, no context injection. Projects that haven't run init-project-scribe pay zero cost.

**Revisit when:** Someone wants per-user opt-in at the Claude Code config level (then the cwd check becomes redundant).
```

- [ ] **Step 5: Fill docs/README.md from template**

List every file currently in `docs/`. Note the plugin is self-hosting — its own spec and plan documents live under `docs/specs/` and `docs/plans/`.

- [ ] **Step 6: Fill docs/status/README.md from template**

No status memos yet (v1 isn't shipped — it's in development). Leave the "Current status memos" section as "None yet."

- [ ] **Step 7: Copy TEMPLATE.md verbatim**

From `skills/init-project-scribe/templates/spec-status.md.tmpl` to `docs/status/TEMPLATE.md`, no substitutions.

- [ ] **Step 8: Commit**

```bash
cd "C:/Users/forty/project-scribe" && git add CLAUDE.md docs/STATE.md docs/DECISIONS.md docs/README.md docs/status/README.md docs/status/TEMPLATE.md && git commit -m "chore(scribe): initialize project-scribe on itself"
```

---

## Chunk 5: Apply to Own Term v3 + wrap

### Task 13: Audit Own Term v3's existing docs before init

**Files:** none modified (inspection only)

- [ ] **Step 1: Inventory existing docs**

```bash
cd "C:/Users/forty/Downloads/ownterm-v3" && ls -la docs/v3/ docs/superpowers/specs/ docs/superpowers/plans/ docs/superpowers/plans/.notes/ 2>&1 | head -40
```

Note: `docs/v3/` has VISION, HANDOFF, DEVLOG, RC1-FINISH-PLAN, NEXT-SESSION-PROMPT, PLUGIN-GUIDE. `docs/superpowers/specs/` has 8 spec files. `docs/superpowers/plans/` has ~18 plan files. `.notes/` has 3 status memos.

- [ ] **Step 2: Check for existing CLAUDE.md**

```bash
ls "C:/Users/forty/Downloads/ownterm-v3/CLAUDE.md" 2>&1
```

If present, init-project-scribe's append behavior kicks in. If absent, fresh write.

- [ ] **Step 3: Decide the docs layout**

Own Term v3 uses `docs/superpowers/specs/` and `docs/superpowers/plans/`. The plugin defaults to `docs/specs/` and `docs/plans/`. During init, use `docs/superpowers/specs/` and `docs/superpowers/plans/` as the `{{specs_dir}}` and `{{plans_dir}}` values. Legacy status memos at `docs/superpowers/plans/.notes/*-status.md` get linked in the new `docs/status/README.md`.

- [ ] **Step 4: Plan the Locked rules from VISION §4 + recent DECISIONS-style statements**

Pre-draft the Locked list for Own Term v3. Starter set:

- All features beyond base are plugins (VISION §7 Rule 1)
- No users yet — breaking changes OK, no migration paths
- Vitest deferred — manual smoke testing only for frontend
- Rust + Tauri + React stack is locked; do not propose alternatives
- Remote access must be user-owned (no cloud relay ever — Rule 12)
- KokoroClone is default TTS, Whisper is default STT
- "Unit" is the locked persona name (user-renameable in wizard)
- MIT license, cross-platform required (Windows/Mac/Linux)

No commit for this task — inspection only.

### Task 14: Initialize project-scribe on Own Term v3

**Files (in `C:/Users/forty/Downloads/ownterm-v3/`):**
- Create: `CLAUDE.md`
- Create: `docs/STATE.md`
- Create: `docs/DECISIONS.md`
- Create: `docs/README.md`
- Create: `docs/status/README.md`
- Create: `docs/status/TEMPLATE.md`

- [ ] **Step 1: Build CLAUDE.md**

Fill the template with:

- Project name: `Own Term v3`
- Project summary: `Cross-platform desktop terminal environment with an AI living inside it. Base = chat + multi-tab PTY terminals + TTS/STT + voice wake word + memory engine + plugin loader + remote access. Everything else is a plugin.`
- Current focus: `Roles tab + Role catalog spec executing (paused for project-scribe dogfood)`
- Locked rules: from Task 13 Step 4
- Specs dir: `docs/superpowers/specs/`
- Plans dir: `docs/superpowers/plans/`

Write to `C:/Users/forty/Downloads/ownterm-v3/CLAUDE.md`. If a file already exists there, append under a clearly-marked "## Project-scribe additions" heading instead.

- [ ] **Step 2: Build docs/STATE.md**

Last shipped = top 5 of `git log --oneline -5` in `C:/Users/forty/Downloads/ownterm-v3`. Should include today's commits: `a0cf5e8 docs: Roles tab + Role catalog design spec`, `9983d9f docs: Roles tab + Role catalog implementation plan`, `5518a72 fix(providers-ui): click-outside closes instance menu`, etc.

Current focus: `Roles tab spec executing (paused while project-scribe plugin is built)`.

Next up:
- Resume Roles tab plan execution (tasks 1-13)
- Ship Roles catalog + /advisor wiring
- Run manual smoke checklist

Deferred: pull from the existing providers-tab-status.md + plugin-foundation-status.md "Deferred" sections. Key items:
- Audio tab spec (TTS/STT multi-instance)
- SSRF check on live_update_endpoint
- Vitest / RTL frontend test harness
- Instance rename as atomic op
- Chat header composite id
- Base UI polish (chip spawned 2026-04-18)
- Modal click-outside on ProviderInstanceForm
- Form field styling

Specs index: scan `docs/superpowers/specs/` and tabulate. Status = `shipped` if matching status memo exists in `docs/superpowers/plans/.notes/`.

Plans index: scan `docs/superpowers/plans/`. Link to referenced spec. Status based on whether the plan is done (check DEVLOG.md + git log for evidence).

- [ ] **Step 3: Build docs/DECISIONS.md**

Seed with 5-6 durable decisions from today's sessions:

```markdown
## 2026-04-18 — Break things freely until first external user

**Context:** Solo dev, pre-release, zero installed base. Every migration path or deprecation cycle added now is premature.

**Decision:** No migration paths. No deprecation cycles. Config keys can change schema without backward-compat shims. Plugins can redefine their manifest fields. Renames are one-shot rewrites, not aliases.

**Revisit when:** First non-Michael user installs Own Term.

---

## 2026-04-18 — Craft Terminal is a pre-installed Skin, not base

**Context:** Rule 1 (VISION §7): all features beyond base are plugins. Visual theming is a feature. Base should ship with zero theme code.

**Decision:** Craft Terminal is a Skin plugin at `~/.ownterm/skins/craft-terminal/` that ships pre-installed. Base CSS is functional minimum (matches `.settings-*` palette today). Big visual polish lands via the skin system, not base.

**Revisit when:** A future Craft Terminal iteration exercises skin system gaps that base needs to fill.

---

## 2026-04-18 — Vitest deferred, manual smoke only for frontend

**Context:** Providers Tab spec §7b called for Vitest unit tests. Adding Vitest + jsdom + RTL + config is a 300-line dev-tooling PR that would triple the spec's scope.

**Decision:** Ship the frontend without Vitest. Rely on TypeScript types + Rust-side validation + manual smoke testing for correctness. Track "Vitest + RTL harness" as its own follow-on task.

**Revisit when:** (a) a frontend-only bug would have been caught by unit tests and lands in prod, or (b) a new contributor wants a frontend test harness before touching React.

---

## 2026-04-18 — /advisor is user-driven, not model-driven

**Context:** VISION §8 defines an `advisor` slot on Role. Two ways to invoke: (a) current model decides when to consult advisor, (b) user types /advisor explicitly. Option (a) requires the current model to know its own limits and route reliably — models are inconsistent at this.

**Decision:** /advisor is an explicit slash command. User types it when they want a second opinion. The advisor model answers that one message. Transcript labels the bubble `[advisor: <model>]`.

**Revisit when:** An auto-router model / heuristic exists that routes reliably. Or when the user wants the advisor to chime in without prompting.

---

## 2026-04-18 — Hard-cut migrations: wipe legacy keys, write new ones

**Context:** The Roles tab spec introduces `[roles] default_role` to replace `[roles] default_provider`. With users, migration would preserve legacy keys indefinitely. Without users, legacy keys are pure tech debt.

**Decision:** Startup migration runs once: converts legacy `default_provider` into a synthesized `migrated-default` role, writes new `default_role`, deletes the legacy key. Config doesn't carry old keys forward.

**Revisit when:** First external user is about to install — then add back-compat shims before v3.0.0 ships.

---

## 2026-04-18 — Project-scribe is the context system; it's a plugin, not a script

**Context:** Claude loses context across sessions on long projects. Michael wanted a system for tracking what shipped, what's next, what was decided. Research showed nothing in the Claude Code ecosystem does exactly this.

**Decision:** Build project-scribe as a Claude Code plugin. Five skills, one hook, one slash command. Dogfood on Own Term v3 before publishing. Adopt it as the first scribe-enabled project today.

**Revisit when:** Claude Code ships an official project-memory system (Anthropic issue #13853 is tracking this).
```

- [ ] **Step 4: Build docs/README.md**

One-line blurb per file in `docs/v3/` and `docs/superpowers/`:

```markdown
# Own Term v3 — docs map

## Top of book

- `STATE.md` — current focus, last shipped, next up, deferred
- `DECISIONS.md` — append-only rules-of-engagement log
- `README.md` — this map

## Product docs (docs/v3/)

- `VISION.md` — locked product spec (478 lines, 15 non-negotiable rules)
- `DEVLOG.md` — narrative history from v0 through current week
- `HANDOFF.md` — original session-resume doc (historical; STATE.md is the living dashboard now)
- `RC1-FINISH-PLAN.md` — pre-project-scribe gap analysis; reference only
- `NEXT-SESSION-PROMPT.md` — Milestone 1 kickoff prompt (historical)
- `PLUGIN-GUIDE.md` — how to write a plugin

## Work artifacts (docs/superpowers/)

- `specs/` — design specs (8 files, dated YYYY-MM-DD)
- `plans/` — implementation plans tied to specs (18 files)
- `plans/.notes/` — legacy location for status memos (kept for history; new memos go to docs/status/)

## Implementation status (docs/status/)

- `README.md` — convention explainer
- `TEMPLATE.md` — starter for new status memos
- See docs/status/README.md for current memos

## How this file stays current

Add a blurb when new top-level files or directories land in `docs/`. Not auto-updated — folder structure is a deliberate choice.
```

- [ ] **Step 5: Build docs/status/README.md**

```markdown
# Own Term v3 — Implementation status memos

Every shipped spec gets a matching memo here.

## Current status memos

New memos live in this directory going forward. Legacy memos from before project-scribe was installed live at `docs/superpowers/plans/.notes/`:

- [`docs/superpowers/plans/.notes/plugin-foundation-status.md`](../superpowers/plans/.notes/plugin-foundation-status.md) — Plugin Foundation v1 (shipped 2026-04-16)
- [`docs/superpowers/plans/.notes/providers-tab-status.md`](../superpowers/plans/.notes/providers-tab-status.md) — Providers Tab (shipped 2026-04-17)

## How to add a new memo

Copy `TEMPLATE.md` to `<spec-slug>.md` in this directory. Fill in the sections. The `deferred-rollup` skill reads both this directory and the legacy location above.

## Shape

- **Shipped** — what the spec delivered
- **Tests** — counts: unit / integration / manual
- **Deferred** — items punted to future specs (strikethrough resolved ones)
- **Known issues discovered** — quirks found during implementation
```

- [ ] **Step 6: Copy TEMPLATE.md**

Copy `skills/init-project-scribe/templates/spec-status.md.tmpl` verbatim (with no placeholder replacement, since it's the starter for future users) to `docs/status/TEMPLATE.md`.

- [ ] **Step 7: Commit in Own Term v3**

```bash
cd "C:/Users/forty/Downloads/ownterm-v3" && git add CLAUDE.md docs/STATE.md docs/DECISIONS.md docs/README.md docs/status/ && git commit -m "$(cat <<'EOF'
chore(scribe): initialize project-scribe

First scribe-enabled project. Dashboard at docs/STATE.md, decisions log
at docs/DECISIONS.md, auto-loaded CLAUDE.md at repo root. Existing
status memos at docs/superpowers/plans/.notes/ stay put and are linked
from the new docs/status/README.md.

Six decisions seeded from recent sessions:
- Break things freely until first external user
- Craft Terminal is a pre-installed Skin, not base
- Vitest deferred, manual smoke only for frontend
- /advisor is user-driven, not model-driven
- Hard-cut migrations: wipe legacy keys, write new ones
- Project-scribe is the context system; plugin not script

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 15: Final verification + session-end note

**Files:** none modified

- [ ] **Step 1: Verify plugin layout**

```bash
find "C:/Users/forty/project-scribe" -type f -not -path "*/.git/*" | sort
```

Expected list includes:
- `.claude-plugin/plugin.json`
- `.gitignore`
- `README.md`
- `CLAUDE.md`
- `hooks/hooks.json`
- `hooks/run-hook.cmd`
- `hooks/session-start`
- `commands/scribe.md`
- `skills/init-project-scribe/SKILL.md` + 6 templates
- `skills/reconcile-project-state/SKILL.md`
- `skills/log-decision/SKILL.md`
- `skills/update-project-state/SKILL.md`
- `skills/deferred-rollup/SKILL.md`
- `docs/STATE.md`
- `docs/DECISIONS.md`
- `docs/README.md`
- `docs/status/README.md`
- `docs/status/TEMPLATE.md`
- `docs/specs/2026-04-18-project-scribe-v1-design.md`
- `docs/plans/2026-04-18-project-scribe-v1.md`

- [ ] **Step 2: Verify symlink/junction into Claude plugins dir**

```bash
ls "C:/Users/forty/.claude/plugins/project-scribe/" | head -10
```

Expected: plugin files visible through the link.

- [ ] **Step 3: Verify Own Term v3 scribe files**

```bash
cd "C:/Users/forty/Downloads/ownterm-v3" && ls CLAUDE.md docs/STATE.md docs/DECISIONS.md docs/README.md docs/status/README.md docs/status/TEMPLATE.md
```

Expected: all 6 files present.

- [ ] **Step 4: Log follow-ups**

Write a short note for tomorrow's session. Goes in Own Term v3's STATE.md "Next up" — or as a new DECISIONS entry if the user wants:

> Tomorrow:
> 1. Open a fresh Claude Code session. Plugin should auto-load. First response should invoke reconcile-project-state automatically.
> 2. Test `/scribe` slash command against Own Term v3's STATE.md.
> 3. Ask Claude to "what's deferred" — verify deferred-rollup reads both `docs/status/` and legacy `docs/superpowers/plans/.notes/`.
> 4. If all three work, resume Roles tab plan execution from Task 1.
> 5. If any break, iterate on the plugin SKILL.md files and re-test. Plugin repo is at `C:/Users/forty/project-scribe/`.

No commit. This is session-end narrative.

- [ ] **Step 5: Done report**

Summarize to the user:
- Plugin repo at `C:/Users/forty/project-scribe/` (N commits)
- Installed via symlink/junction at `~/.claude/plugins/project-scribe`
- Own Term v3 initialized as first scribe-enabled project (6 files added, 1 commit)
- Roles tab tasks 1-13 still paused; resume in tomorrow's session after verifying the plugin works

---

## Notes for the implementing agent

- **User asked for autonomous execution** — no questions tomorrow, just build and report. Don't stop to ask for permission unless a genuine blocker arises (git repo borked, disk full, etc.).
- **Caveman mode active** — user chat stays terse. Code, commit messages, spec docs, SKILL.md files stay in full sentences.
- **Plugin lives at `C:/Users/forty/project-scribe/`** — absolute path. Don't confuse with Own Term v3.
- **Own Term v3 lives at `C:/Users/forty/Downloads/ownterm-v3/`** — Task 16 (renumbered to 14 in this version) runs there.
- **Don't touch `docs/superpowers/plans/.notes/`** in Own Term — those legacy memos stay put. Link to them from the new `docs/status/README.md`.
- **Skill bodies are prompts** — they're read by Claude and followed. Clarity matters more than brevity. Write them like instructions to a junior engineer who's never seen this plugin before.
- **No tests** — plugin is prompt-based. Validation is dogfooding in the next session.
- **Windows filesystem notes:** `mklink /J` for directory junctions, `ln -s` only works if Developer Mode is on. Junction is fine and more portable.
- **If the hook doesn't fire after symlinking:** re-check the `command` path in `hooks.json` — `${CLAUDE_PLUGIN_ROOT}` is expanded by Claude Code, should resolve to the symlink target's absolute path.
