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

Two modes:

**Batch mode** — if the user says "same", "no changes", "skip all", "keep all", or provides a single block with all three sections pre-filled, accept it in one turn and move straight to index rebuild. Skip the per-section prompting.

**Interactive mode (default)** — for each section, show current content and ask "update?":

1. **Current focus** (1 line) — "Current focus is: `<current>`. Keep, or update?"
2. **Next up** (3 bullets) — show existing list, ask for updated list. User can say "same" or provide new bullets.
3. **Blocked / deferred** — show existing, ask for adds/removes.

Never force-overwrite. If the user says "skip" on a specific section, keep the existing section and move on. A single "skip all" exits prompting entirely.

## Rebuild index tables

1. **Read config.** Parse the `<!-- scribe:config -->` HTML comment block at the top of STATE.md. Extract `specs_dir`, `plans_dir`, `status_dir`, and `legacy_status_dirs` (comma-separated, may be `none`).
   - If the config block is missing → fall back to defaults: check `docs/specs/` + `docs/superpowers/specs/`, prefer the one that exists. Same for plans. Warn the user: `STATE.md is missing the scribe:config block — add it manually or re-init. Using defaults for this run.`
2. Scan the resolved specs directory. For each spec file:
   - Read the first two lines for a title.
   - Check whether a matching status memo exists in `status_dir` or any path in `legacy_status_dirs`.
   - Status column: `shipped` if memo exists, `active` if a plan references this spec, `draft` otherwise.
3. Same for the plans directory — each plan lists its linked spec if one is referenced in its preamble.
4. Replace the `## Specs index` and `## Plans index` tables in STATE.md. Leave the `<!-- scribe:config -->` block untouched.

## Check for missing status memos

If any spec has status `shipped` (has a merge commit that references it) but no status memo file — warn:

```
Shipped specs without status memos:
- <spec-filename>

Create a status memo from docs/status/TEMPLATE.md? (yes/skip)
```

If user says yes, copy the template, fill the header fields, open the file in the user's editor (or print the path for them).

## Commit offer

Before offering, run `git status --porcelain` to check for unrelated modifications.

Files this skill may touch: `docs/STATE.md` and (optionally) new files in `docs/status/` created from the template.

**Clean tree (only scribe-owned files modified)** → offer:

```
docs(scribe): update state after <what-shipped>
```

Where `<what-shipped>` is derived from the commits added since the last STATE.md update. If nothing shipped, use "update state".

Stage only the scribe-owned paths explicitly (`git add docs/STATE.md docs/status/<new-memo>.md` — never `git add .` / `git add -A`).

**Dirty tree (other files modified or staged)** → warn first:

```
⚠️ Other changes present: <list of unrelated paths>.
Scribe will commit ONLY: docs/STATE.md[, docs/status/<memo>.md].
Unrelated changes stay in your working tree.
Proceed? (yes/skip)
```

If user says yes, stage scribe paths by name + commit. Leave every other file untouched.

## Don't touch

- DECISIONS.md — not rewritten by this skill.
- CLAUDE.md — only updated manually by the user or by init.
- `docs/status/*.md` (beyond offering to create missing ones) — those are edited as part of the spec's own workflow.
