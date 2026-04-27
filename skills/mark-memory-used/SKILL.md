---
name: mark-memory-used
description: Manually bump last_used + hits frontmatter on a memory file. Backup for the stop-mark-memory hook when it misses or for explicit "this rule was load-bearing this session" requests. Triggers include "mark memory used", "bump memory hit", "this memory was useful".
---

# Mark memory used

Updates decay-tracking frontmatter on a memory file so the next `compact-memory`
run keeps it instead of archiving as idle.

The `stop-mark-memory` hook does this automatically at session end by scanning
the transcript for memory-file basenames. This skill is the manual fallback for:

- Hook didn't fire (e.g. session crashed)
- Memory was applied but not quoted by basename (paraphrased rule)
- User wants to explicitly mark a memory as still relevant before compaction

## When to invoke

- User says "this memory helped" / "mark X as used" / "bump hits on Y"
- After compact-memory proposes archiving a file you know is still relevant
- After a long session where you applied memory rules without quoting filenames

NOT on:
- Loading MEMORY.md index at session start (read != use)
- Listing memory files for compaction
- Browse-only requests ("what's in memory")

## Operation

1. Resolve memory dir: `~/.claude/projects/<slug>/memory/` where slug =
   project root path with `/` → `-`, drive letter prefixed `C--` on Windows.
2. Identify target file. If user named it ambiguously, list candidates and ask.
3. Read first 10 lines. Detect frontmatter (opens with `---` on line 1).
4. If frontmatter present:
   - Set `last_used: <today ISO>`
   - Increment `hits` by 1 (default 0 if absent)
5. If frontmatter missing:
   - Prepend block:
     ```yaml
     ---
     last_used: <today ISO>
     hits: 1
     ---

     ```
6. Write back. Body content untouched.

## Don't

- Do not bump twice in same session for same file. Dedupe by path.
- Do not modify body content.
- Do not bump on passive reads — only when memory was actually applied.
- Do not touch MEMORY.md index. It's not a memory entry, it's the table of contents.

## Example

User: "the windows-npx-paths.md rule saved me, mark it used"

Skill:
1. Find `~/.claude/projects/<slug>/memory/windows-npx-paths.md`
2. Current frontmatter: `last_used: 2026-02-10`, `hits: 3`
3. Update to: `last_used: 2026-04-27`, `hits: 4`
4. Confirm: "Bumped windows-npx-paths.md → hits 4, last_used 2026-04-27"
