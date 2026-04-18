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
