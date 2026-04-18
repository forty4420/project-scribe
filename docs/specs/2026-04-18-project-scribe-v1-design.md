# project-scribe v1 Design

**Date:** 2026-04-18
**Scope:** A Claude Code plugin that maintains a per-project index, decisions log, and dashboard so Claude keeps context across sessions. Ships as an installable plugin with four skills, one slash command, and a session-start hook.
**Not in scope for v1:** Auto-publishing to GitHub, multi-project dashboard, session file per day, git hooks (pre-commit warnings), customizable file paths, markdown linter, rule-drift watch as a separate skill (folded into CLAUDE.md instruction instead).

---

## Why this plugin exists

Claude Code loses project context between sessions. Every new session on a long-running project requires re-grepping docs to reconstruct "what shipped, what's next, what did we decide." Decisions made in conversation die in transcripts. Locked architectural rules get re-litigated. Cross-cutting rules-of-engagement ("no users yet → break things freely", "Vitest deferred", "always use `max_completion_tokens` for GPT-5") aren't captured anywhere durable.

Research confirmed five adjacent tools exist (claude-mem, cc-sessions, developer-diary, adr-skills, cursor patterns). None match the shape we want: a curated STATE.md dashboard plus append-only DECISIONS.md plus session-start git-log reconcile plus log-decision trigger plus root CLAUDE.md pointer. Building it.

The metaphor is a book index. As the project grows, the index grows with it. Claude is the scribe — keeps the book's front-of-book index, decisions appendix, and chapter summaries current so every new reader (human or fresh Claude session) can map the territory in 5 minutes.

## Design principles

1. **Zero-cost when inactive.** Projects without `docs/STATE.md` pay nothing — the session-start hook no-ops silently.
2. **Auto-reconcile, not auto-write.** The reconcile skill only updates "Last shipped" from `git log`. Never touches "Current focus", "Next up", or "Deferred" — those stay user-curated.
3. **Append-only where possible.** DECISIONS.md never edits past entries. Reverses are new entries linking back.
4. **Anti-rot by structural trigger.** Files get updated at specific events (ship, decision, session-start), not on a "remember to update this" convention.
5. **Dogfood before publish.** v1 lives locally at `~/.claude/plugins/project-scribe/`. GitHub push comes after 2-3 sessions of real use.

## Architecture

Claude Code plugin with the conventional layout:

```
project-scribe/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── init-project-scribe/
│   │   ├── SKILL.md
│   │   └── templates/
│   │       ├── CLAUDE.md.tmpl
│   │       ├── STATE.md.tmpl
│   │       ├── DECISIONS.md.tmpl
│   │       ├── docs-README.md.tmpl
│   │       ├── status-README.md.tmpl
│   │       └── spec-status.md.tmpl
│   ├── reconcile-project-state/
│   │   └── SKILL.md
│   ├── log-decision/
│   │   └── SKILL.md
│   ├── update-project-state/
│   │   └── SKILL.md
│   └── deferred-rollup/
│       └── SKILL.md
├── commands/
│   └── scribe.md
├── hooks/
│   ├── hooks.json
│   ├── session-start
│   └── run-hook.cmd
├── docs/
│   ├── specs/
│   ├── plans/
│   └── ...(dogfooded scribe files for the plugin itself)
└── README.md
```

Plugin root becomes a git repo. Publishing to GitHub later = `git remote add origin` + push. No refactor.

## Files the plugin creates in a target project

All in the target project's tree. Init writes them once; subsequent skills read and append.

**`CLAUDE.md`** (target repo root)

Auto-loaded by Claude Code every session. ~60 lines max. Sections:

1. **Project name + one-line summary.** Filled during init.
2. **Read first.** Absolute paths to `docs/STATE.md`, `docs/DECISIONS.md`, plus whatever vision doc the project already has (VISION.md, CHARTER.md, README.md).
3. **Current focus.** One line. Updated by `update-project-state`.
4. **Locked — don't re-argue.** Bullet list seeded during init. User fills in. Examples from Own Term v3 would read:
   - All features beyond base are plugins (VISION §7 Rule 1)
   - No users yet — breaking changes OK, no migration paths
   - Vitest deferred — manual smoke only
5. **Rule-drift watch** (fixed paragraph in every CLAUDE.md):
   > If anything you or the user proposes contradicts the Locked list above, STOP and flag it before acting. Quote the specific rule. Ask whether to update the Locked list or back off the proposal. Never silently violate a locked rule.
6. **Where work lives.** Paths to specs, plans, status memos.

**`docs/STATE.md`** (dashboard)

One page. Sections:

- **Current focus** — 1 line
- **Last shipped** — 3-5 bullets, each `<SHA> — <commit message>`. Auto-reconciled by session-start hook.
- **Next up** — 3 bullets, user-curated
- **Blocked / deferred** — bullets, user-curated
- **Specs index** — markdown table: spec file | status (draft/active/shipped/deferred) | link to status memo
- **Plans index** — markdown table: plan file | linked spec | status

**`docs/DECISIONS.md`** (append-only log)

Newest on top. Each entry has exactly four fields:

```markdown
## 2026-04-18 — Break things freely until first external user

**Context:** Solo dev, pre-release, no installed base.

**Decision:** No migration paths, no deprecation cycles. Rename and delete freely.

**Revisit when:** First non-Michael user installs.
```

Title format: `## YYYY-MM-DD — <title>`. Date is the ID; no numbering. Reverses are new entries starting `## YYYY-MM-DD — Reverses YYYY-MM-DD: <title>` with a link back. Never edit past entries.

**`docs/README.md`** (~40 lines)

One-line blurb per file in `docs/` and `docs/status/`. The 5-minute map. Init generates from what exists; update-state appends when new files land.

**`docs/status/README.md`**

One paragraph explaining: every shipped spec gets a matching `<spec-slug>.md` memo here, following the shape below. Links to the existing status memos.

**`docs/status/TEMPLATE.md`**

Copy-paste starter for a new status memo. Shape proven on Own Term v3's plugin-foundation-status and providers-tab-status:

```markdown
# <Spec Name> — Implementation Status

**Spec:** docs/specs/YYYY-MM-DD-<slug>-design.md
**Plan:** docs/plans/YYYY-MM-DD-<slug>.md
**Shipped:** <date> on branch `<name>`
**Commits:** <count>

## Shipped
- <feature bullet>
- <feature bullet>

## Tests
- Unit: <count> passing
- Integration: <count> passing
- Manual smoke: <verified | pending>

## Deferred (resolved items use ~~strikethrough~~ with date + replacement spec link)
- <item> — <reason deferred>
- ~~<item>~~ ✅ Shipped <date> via <link>

## Known issues discovered
- <discovery>
```

## Skills

### `init-project-scribe`

Manual trigger. Run once per project when starting or retrofitting.

**Trigger words:** "set up project scribe", "initialize project scribe", "init project scribe", "add project tracking to this repo".

**Flow:**
1. Check for existing `docs/STATE.md`. If present, abort with "already initialized — use update-project-state to refresh".
2. Ask 3 questions:
   - Project name (1 line)
   - Current focus (1 sentence)
   - Specs directory path (default `docs/specs/`)
   - Plans directory path (default `docs/plans/`)
3. Scan spec and plan dirs if they exist.
4. Run `git log --oneline -5` for "Last shipped" seed.
5. Write all six template files with substitutions.
6. Commit: `chore(scribe): initialize project-scribe`

**Edge cases:**
- If `CLAUDE.md` already exists at root → append a "## Project-scribe additions" section rather than overwrite.
- If `docs/` doesn't exist → create it.
- If git repo not initialized → warn and skip git-log seed.

### `reconcile-project-state`

Session-start auto-trigger via hook. Can also be invoked manually.

**Trigger words:** "reconcile project state", "check project state", "refresh state".

**Flow:**
1. Look for `docs/STATE.md` in cwd. If missing → silent no-op (project isn't scribe-enabled).
2. Parse the "Last shipped" block. Extract SHAs.
3. Run `git log --oneline -10` in project root.
4. If the top SHA in git matches the top "Last shipped" entry → silent no-op.
5. If mismatch → rewrite the "Last shipped" block with the latest 3-5 commits, keep the rest of STATE.md untouched, announce inline: `Reconciled STATE.md — added N commits since last update.`
6. Do NOT commit the reconciliation automatically. User can choose to commit as part of their session-end.

**Never touches:** Current focus, Next up, Deferred, Specs index, Plans index. Those are user-curated.

### `log-decision`

Mid-session. Triggered by user statement or explicit call. Also auto-proposed when Claude detects a rule-shaped statement.

**Trigger words:** "log this decision", "record this rule", "save that as a decision", "log it".

**Auto-propose triggers:** When the user or Claude makes a statement that sounds like a durable rule (e.g., "no users yet so migrations don't matter", "always use X for Y", "defer Z until W"), Claude proposes: "that sounds like a durable decision — log it?"

**Flow:**
1. Prompt for 4 fields:
   - Title (1 line)
   - Context (2-4 sentences — why the decision was needed)
   - Decision (2-4 sentences — what was decided)
   - Revisit when (1 sentence — what condition would make this stale)
2. Prepend to `docs/DECISIONS.md` (newest on top).
3. Offer to commit: `docs(scribe): log decision — <title>`

**Never:** Edit past entries. Reverses are new entries.

### `update-project-state`

End-of-ship trigger. Runs after a spec ships or at session end.

**Trigger words:** "update project state", "refresh scribe", "session end" (when scribe active).

**Flow:**
1. Re-run the git-log reconciliation (same as reconcile skill).
2. Prompt for updated "Current focus" (default: keep existing).
3. Prompt for updated "Next up" bullets.
4. Prompt for any deferred items to add.
5. Scan `docs/specs/` and `docs/plans/` directories, rebuild the index tables by reading each file's top-matter (if present) or falling back to filename + first paragraph.
6. If any shipped spec is missing a status memo in `docs/status/`, warn and offer to create it from `docs/status/TEMPLATE.md`.
7. Offer to commit: `docs(scribe): update state after <what-shipped>`

### `deferred-rollup`

Read-only query skill.

**Trigger words:** "what's deferred", "show deferred items", "rollup deferred", "what's on the backlog".

**Flow:**
1. Read all `docs/status/*.md` files (skip README and TEMPLATE).
2. Extract the "Deferred" section from each.
3. Present a unified view grouped by source spec, with strikethrough items (resolved) in a separate "Recently resolved" section.
4. No file writes. No commits.

## Slash command — `/scribe`

Single-command readout for mid-session orientation.

**Behavior:**
- Reads `docs/STATE.md`
- Returns just the Current focus + Last shipped + Next up blocks
- No prose commentary from Claude
- If STATE.md doesn't exist, returns: `Project-scribe not initialized. Run init-project-scribe first.`

Lives in `commands/scribe.md` — Claude Code auto-registers files in that dir as slash commands.

## Hook

`SessionStart` hook, matcher `startup|resume|clear|compact`. Calls a shell script that invokes `reconcile-project-state`.

**`hooks/hooks.json`:**
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

**`hooks/session-start`** (bash): check for `docs/STATE.md` in cwd; if present, inject a system-reminder instructing Claude to run reconcile-project-state before first response. If absent, exit silently.

**`hooks/run-hook.cmd`** (Windows wrapper, mirrors superpowers' pattern): invokes the bash script via Git Bash so hooks work cross-platform.

## Rule-drift watch (not a skill — baked into CLAUDE.md)

Every project's `CLAUDE.md` template includes the fixed paragraph:

> ## Rule-drift watch
> If anything you or the user proposes contradicts the Locked list above, STOP and flag it before acting. Quote the specific rule. Ask whether to update the Locked list or back off the proposal. Never silently violate a locked rule.

This is enforcement via prompt, not code. CLAUDE.md auto-loads every session, Claude self-polices. If the Locked list grows, Claude keeps noticing. Zero extra infrastructure.

A future v2 could add a separate `watch-rule-drift` skill that inspects each exchange — but that's overkill for v1 and may hit the "skills fire on description match, not continuous monitoring" limitation anyway.

## Data flow

### New project session start

```
Session opens → SessionStart hook fires
  ↓
hook checks for docs/STATE.md
  ↓
present → invoke reconcile-project-state
  ↓
reconcile parses STATE.md "Last shipped"
  ↓
compares to git log --oneline -10
  ↓
match → silent no-op, Claude continues
mismatch → rewrite "Last shipped", announce inline
```

### User states a rule

```
User: "no users yet, breaking changes OK"
  ↓
Claude recognizes rule-shape statement
  ↓
Claude proposes: "log that as a decision?"
  ↓
User: yes
  ↓
log-decision skill runs → 4-field prompt
  ↓
append to DECISIONS.md top
  ↓
offer commit
```

### Spec ships

```
User: "session end" or "update project state"
  ↓
update-project-state skill runs
  ↓
git log reconcile → STATE.md "Last shipped" refreshed
  ↓
prompt: "Current focus unchanged? Next up?"
  ↓
scan specs/ + plans/ → rebuild index tables
  ↓
check docs/status/ for missing memos → warn
  ↓
offer commit
```

## Error handling

| Case | Behavior |
|---|---|
| Project has no `docs/STATE.md` | All skills except init either no-op or produce clear "not initialized" message. Session-start hook exits silent. |
| `docs/STATE.md` malformed (can't parse "Last shipped" block) | Reconcile reports: "STATE.md structure not recognized — run update-project-state to rebuild" and skips reconciliation. |
| Git repo not initialized | Reconcile skill skips git-log check with a one-line warning. Other skills work normally. |
| DECISIONS.md locked or read-only | log-decision reports error, offers to output the entry for manual paste. |
| User declines to commit | All skills leave files modified locally. User can commit later or discard. |
| Two reconcile attempts in the same session | Second one runs normally (idempotent). |
| Hook fires in a dir that's not a project | Silent no-op (no STATE.md = exit). |

## Testing

No automated tests for v1. Skills are prompts, not code. Validation = dogfooding on Own Term v3 for 2-3 sessions. Success criteria:

1. `init-project-scribe` creates all 6 files cleanly on Own Term v3. No breaking existing docs.
2. Session-start reconcile catches the drift between STATE.md and actual git log after Roles tab ships.
3. `log-decision` fires organically at least once during a work session and captures a real rule.
4. `update-project-state` produces a clean state refresh after Roles tab ships, including status memo warning.
5. `/scribe` slash command responds correctly.
6. `deferred-rollup` aggregates deferred items from Own Term's existing status memos.

If all six work on Own Term v3, ship to GitHub as v1.0.0 at `github.com/<user>/project-scribe`.

## Risk

Low.
- **No user-data migrations.** Plugin writes fresh files; only appends to DECISIONS.md.
- **Idempotent init.** Aborts cleanly if STATE.md already exists.
- **Zero-cost when disabled.** Hook no-ops on projects without STATE.md.
- **Skills are prompts.** If something breaks, it's a text edit, not a runtime bug.
- **Worst case:** plugin written but doesn't work well → delete the plugin dir, no project damage.

## Deferrals

- **Auto-publishing to GitHub.** v1 lives at `~/.claude/plugins/project-scribe/` as a local git repo. Push to GitHub after 2-3 sessions of dogfooding.
- **Multi-project dashboard.** "List all scribe-enabled projects" is a nice-to-have once there are 3+ projects using this.
- **Rule-drift watch as its own skill.** CLAUDE.md instruction covers the need. Revisit if the paragraph-level enforcement proves insufficient.
- **Session file per day.** DECISIONS + STATE cover the important stuff. Session narratives can go to DEVLOG.md equivalents if projects want them.
- **Git hooks (pre-commit warnings).** Commits that ship a spec without updating STATE would trigger a warning. Deferred as feature creep.
- **Customizable file paths.** `docs/` is hardcoded in v1. Projects that need a different layout can symlink or fork.
- **Markdown linter for status memos.** Rely on TEMPLATE.md to enforce shape by example.
- **Non-Claude-Code compatibility.** v1 targets Claude Code only. Cursor/Aider/Continue compatibility = v2 concern.

## Files touched (this plugin's own repo)

**New:**
- `project-scribe/.claude-plugin/plugin.json`
- `project-scribe/skills/init-project-scribe/SKILL.md`
- `project-scribe/skills/init-project-scribe/templates/*.tmpl` (6 templates)
- `project-scribe/skills/reconcile-project-state/SKILL.md`
- `project-scribe/skills/log-decision/SKILL.md`
- `project-scribe/skills/update-project-state/SKILL.md`
- `project-scribe/skills/deferred-rollup/SKILL.md`
- `project-scribe/commands/scribe.md`
- `project-scribe/hooks/hooks.json`
- `project-scribe/hooks/session-start`
- `project-scribe/hooks/run-hook.cmd`
- `project-scribe/README.md`

**New (plugin's own project-scribe files, dogfooded):**
- `project-scribe/CLAUDE.md`
- `project-scribe/docs/STATE.md`
- `project-scribe/docs/DECISIONS.md`
- `project-scribe/docs/README.md`
- `project-scribe/docs/status/README.md`
- `project-scribe/docs/status/TEMPLATE.md`
- `project-scribe/docs/specs/2026-04-18-project-scribe-v1-design.md` (this file)
- `project-scribe/docs/plans/2026-04-18-project-scribe-v1.md` (next step)

## Installation (v1, local)

```bash
# Plugin lives at /c/Users/forty/project-scribe
# Symlink into Claude Code plugins dir:
ln -s /c/Users/forty/project-scribe ~/.claude/plugins/project-scribe
# Restart Claude Code session → plugin loaded
# Per-project opt-in: cd to project, ask Claude "init project scribe"
```

Post-dogfood, publish to GitHub, add to `~/.claude/settings.json` plugin marketplace config for proper install.
