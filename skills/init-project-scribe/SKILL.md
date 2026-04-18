---
name: init-project-scribe
description: Use when the user asks to set up, initialize, bootstrap, or add project-scribe tracking to the current project. Triggers include "init project scribe", "initialize project scribe", "set up project scribe", "add project tracking", "enable scribe for this repo". One-shot operation — creates CLAUDE.md, docs/STATE.md, docs/DECISIONS.md, docs/README.md, docs/status/README.md, docs/status/TEMPLATE.md. Asks whether to also enable optional base-scope guardrails (for modular/plugin projects).
---

# Initialize project-scribe for this project

One-shot bootstrap. Two modes:

- **Indexing mode** (always installed) — creates the six files this plugin needs to track project context: `CLAUDE.md`, `docs/STATE.md`, `docs/DECISIONS.md`, `docs/README.md`, `docs/status/README.md`, `docs/status/TEMPLATE.md`.
- **Guardrails mode** (opt-in) — adds `docs/BASE_ALLOWLIST.md`, three hook scripts, permission-deny rules, and a git pre-commit hook. Only for projects with formal "base vs plugin" architectural rules. See `docs/guardrails.md` in the scribe repo for details.

Default is indexing-only. Ask the user before installing guardrails.

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
   - `{{specs_dir}}` — the specs directory the user picked (e.g. `docs/specs` or `docs/superpowers/specs`)
   - `{{plans_dir}}` — the plans directory the user picked
   - `{{legacy_status_dirs}}` — comma-separated list of any legacy status memo paths discovered (e.g. `docs/superpowers/plans/.notes`), or `none`
   - `{{last_shipped_block}}` — the git log output, formatted as markdown bullets
   - `{{specs_table}}` — rows for each spec found, status column = `draft` if no matching status memo exists, `shipped` if one does
   - `{{plans_table}}` — rows for each plan found

   The template includes a `<!-- scribe:config -->` HTML comment block at the top. Downstream skills (reconcile, update-project-state, deferred-rollup) parse this block to know where specs/plans/status memos live. Do NOT omit it.

3. **`docs/DECISIONS.md`** — write from `templates/DECISIONS.md.tmpl` with the project name filled. No entries yet; the template shows the shape.

4. **`docs/README.md`** — write from `templates/docs-README.md.tmpl`. Include a one-line blurb for every file currently in `docs/` and `docs/status/`.

5. **`docs/status/README.md`** — write from `templates/status-README.md.tmpl`. If any existing status memos were found (including legacy locations like `docs/superpowers/plans/.notes/`), link to them in a "Current status memos" section.

6. **`docs/status/TEMPLATE.md`** — write from `templates/spec-status.md.tmpl` verbatim.

## Optional — base-scope guardrails

After writing the six core files, ask the user **one more question**. Frame it as a decision, not a yes/no:

> "Does this project have a formal rule about what belongs in 'base' vs 'plugins' / 'extensions' / 'core vs app'? For example:
>
> - Plugin systems where core code must stay lean and features ship as plugins
> - Frameworks where library code is separate from application code
> - Any project with a 'don't put X in folder Y' rule that matters
>
> If YES, I can install base-scope guardrails: permission-layer deny rules, PreToolUse + pre-commit hooks, and a session-start health check. This catches both human and AI drift past architectural boundaries.
>
> If NO (or unsure), skip this. You can add guardrails later by creating `docs/BASE_ALLOWLIST.md` and re-running init.
>
> Install guardrails? [y/N, default N]"

If user says **no** or leaves blank: skip. Report normally. Indexing mode is complete.

If user says **yes**:

1. Create `docs/BASE_ALLOWLIST.md` from `templates/base-scope-guard/BASE_ALLOWLIST.md.template`. Replace `{PROJECT_NAME}` with the project name. Warn the user: "The template has placeholder entries. Edit docs/BASE_ALLOWLIST.md to list your project's actual base paths before committing."
2. Create `.claude/hooks/` directory.
3. Copy three hook scripts into `.claude/hooks/`:
   - `pretooluse_base_guard.sh` (from `templates/base-scope-guard/`)
   - `sessionstart_inject_rules.sh` (from `templates/base-scope-guard/`)
   - `precommit_base_guard.sh` (from `templates/base-scope-guard/`)
4. `chmod +x` all three.
5. Create or merge `.claude/settings.json` to wire SessionStart + PreToolUse hooks AND permission-layer deny rules. If the file exists, merge the `hooks` key and `permissions` key; do not clobber other settings. Shape:
   ```json
   {
     "permissions": {
       "defaultMode": "acceptEdits",
       "deny": [
         "Write({GUARDED_DIR_1}/**)",
         "Edit({GUARDED_DIR_1}/**)",
         "NotebookEdit({GUARDED_DIR_1}/**)"
       ]
     },
     "hooks": {
       "SessionStart": [
         { "hooks": [{ "type": "command", "command": "bash .claude/hooks/sessionstart_inject_rules.sh" }] }
       ],
       "PreToolUse": [
         { "matcher": "Write|Edit|NotebookEdit", "hooks": [{ "type": "command", "command": "bash .claude/hooks/pretooluse_base_guard.sh" }] }
       ]
     }
   }
   ```

   **Why both layers:** the hook fires first and shows a custom block message pointing at `/unlock-base`. The permission-layer `deny` is a hard wall that cannot be bypassed by accidentally clicking "Allow always" on a permission prompt — because no prompt is ever offered; denies skip the prompt entirely.

   **Populating `deny`:** parse `docs/BASE_ALLOWLIST.md` for entries under a `## ... NOT allowed` header and emit a `Write(<path>/**)`, `Edit(<path>/**)`, `NotebookEdit(<path>/**)` triple for each. If the user hasn't filled in the allowlist yet, emit an empty deny array and note: "Edit docs/BASE_ALLOWLIST.md to list NOT-allowed paths, then re-run init or add deny entries manually." The hook still fires regardless and catches new paths via the allowlist check.

   **`defaultMode: acceptEdits`:** required for hooks to be authoritative. If the user's global settings default to `bypassPermissions`, that bypass is skipped inside this project — project settings override. Do not set `bypassPermissions` or `default` here; both defeat the guardrail.
6. Install the pre-commit hook: `cp .claude/hooks/precommit_base_guard.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`. On Windows this copies; on Linux/macOS a symlink is also fine.
7. Tell user:
   - Edit `docs/BASE_ALLOWLIST.md` to list actual base paths before the next commit.
   - Hooks and deny rules won't fire for the current session — restart Claude Code to pick up `.claude/settings.json` changes.
   - Complementary skills installed: `base-audit` (run `/audit` before commits), `auto-handoff` (write session handoffs at context breakpoints), `unlock-base` (temporarily lift deny rules — run `/unlock-base` when you legitimately need to edit a locked dir), `lock-base` (restore deny rules after an unlock session — run `/lock-base` when done).
   - **If the `cc-restart` plugin is installed, `/unlock-base` and `/lock-base` offer a one-command restart. Otherwise they print manual restart instructions.**
   - **User global settings warning:** if `~/.claude/settings.json` has `Write(*)`, `Edit(*)`, or `NotebookEdit(*)` in its `permissions.allow`, those pre-approve writes BEFORE hooks and denies are consulted. Recommend the user remove those three entries from the global allow list. `Bash(*)`, `Read(*)`, etc. can stay.

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
