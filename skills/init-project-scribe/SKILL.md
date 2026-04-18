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
