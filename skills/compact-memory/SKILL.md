---
name: compact-memory
description: Consolidate the project memory folder so MEMORY.md stays under the 200-line truncation limit and stale entries don't crowd out useful ones. Runs on threshold or on explicit request. Triggers include "compact memory", "clean up memory", "memory review", "prune memory", "MEMORY.md is too long".
---

# Compact project memory

Keep `~/.claude/projects/<slug>/memory/MEMORY.md` lean. It's the only file auto-loaded into every conversation — once it exceeds ~200 lines, older entries get silently truncated. This skill consolidates before that happens.

## When to invoke

- Explicit request: "compact memory", "clean up memory", "prune memory", "memory review"
- At session start if `reconcile-project-state` detects MEMORY.md > 180 lines
- On month boundary (first session of a new month, if tracking that)
- User observes memory giving stale or conflicting recommendations

## Pre-flight

1. Find the memory directory. Default path template: `~/.claude/projects/<cwd-slug>/memory/`. Slug = cwd path with `/` replaced by `-` and prefixed with `C--` on Windows. If directory missing → report "no project memory at <expected path>" and STOP.
2. Read `MEMORY.md` (the index). Count lines. Record size.
3. Enumerate all `*.md` files in the directory (the actual memory files — each pointed to from MEMORY.md). Record their sizes + last-modified dates.

## Analysis passes

### Pass 1: Duplicate detection
Compare every pair of memory files. If two files share:
- Same topic (name similarity + description overlap)
- Same or conflicting content (one supersedes another)

→ candidate for merge.

### Pass 2: Staleness by reference
For each memory file, grep the project repo for references to its subject (file paths mentioned, commands quoted, etc.).
- 0 matches in last 90 days of git history AND file is > 60 days old → candidate for archive.

### Pass 3: Superseded by CLAUDE.md or DECISIONS.md
For each memory file, check whether its content is now mirrored in:
- Project `CLAUDE.md`
- `docs/DECISIONS.md`
- Global `~/.claude/CLAUDE.md` APPLIED LEARNING

→ candidate for deletion (single source of truth principle).

### Pass 4: Narrative vs rule
Re-read each feedback/project-type memory. If content is project-narrative ("We discovered that when X happened...") instead of generalizable rule ("When X, do Y"), rewrite into rule form.

## Proposal output

Present results as a single table. User approves, edits, or rejects PER ROW:

```
| Action  | File(s)                      | Reason                        | Preview                         |
|---------|------------------------------|-------------------------------|---------------------------------|
| MERGE   | feedback_a.md, feedback_b.md | Overlapping topic             | [merged text preview]           |
| ARCHIVE | project_old_spec.md          | No refs in 90d, pre-ships     | Move to memory/archive/         |
| DELETE  | feedback_superseded.md       | Now in DECISIONS.md entry #42 | -                               |
| REWRITE | project_narrative.md         | Narrative → rule form         | [rewritten text preview]        |
```

**Safety gates:**
- Never delete without archive copy (move to `memory/archive/<date>/` preserving filename)
- Never modify MEMORY.md index until all file-level changes confirmed
- Require explicit user approval — no silent consolidation

## Execution phase

After user approves the table:

1. For each MERGE: create new consolidated file, archive both originals, update MEMORY.md index.
2. For each ARCHIVE: move file to `memory/archive/<YYYY-MM>/`, remove from MEMORY.md index.
3. For each DELETE: archive first, then delete, remove from index.
4. For each REWRITE: in-place rewrite, no archive needed (diff visible in VCS if tracked).
5. Regenerate MEMORY.md index: one line per active memory file, sorted by type (user → feedback → project → reference), entries under 150 chars.
6. Verify MEMORY.md now < 180 lines. If still over → suggest next round.

## Output summary

```
Compacted memory:
- Started: N files, MEMORY.md at L1 lines
- Merged: N pairs → N files
- Archived: N files
- Deleted: N files (all archived)
- Rewritten: N files
- Ended: N files, MEMORY.md at L2 lines

Archive: ~/.claude/projects/<slug>/memory/archive/<YYYY-MM>/
```

## Don't

- Do not delete without archiving. Archive is cheap; regret is expensive.
- Do not touch memory files for other projects.
- Do not consolidate across types (user / feedback / project / reference). Each type has distinct semantics.
- Do not treat MEMORY.md as content. It's an index. Content lives in per-topic `.md` files.
- Do not run on every session. Intended use: monthly or on threshold.

## Interaction with `/session-end` and `/compound`

This skill is a cleanup pass. It does NOT replace `/session-end` (runs memory codification from the current session) or `/compound` (routes new learnings to correct bucket). Those add; this one consolidates.
