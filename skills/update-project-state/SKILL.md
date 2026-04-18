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

1. Scan the specs directory (from the config the init skill wrote into STATE.md — look for the section that says which dir was used).
2. For each spec file:
   - Read the first two lines for a title.
   - Check whether a matching status memo exists in `docs/status/` or any legacy location referenced by `docs/status/README.md`.
   - Status column: `shipped` if memo exists, `active` if a plan references this spec, `draft` otherwise.
3. Same for the plans directory — each plan lists its linked spec if one is referenced in its preamble.
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
