---
name: compact-decisions
description: Archive oldest entries from docs/DECISIONS.md when file grows past a token threshold. Preserves audit trail via git + linked archive file. Triggers include "compact decisions", "archive old decisions", "DECISIONS.md is too long", or auto-offer at session start when file crosses ~20K tokens (~500 lines).
---

# Compact DECISIONS.md — archive oldest, keep live file lean

**Why this exists:** `docs/DECISIONS.md` is append-only and grows forever. Claude Code loads it in full every time it's referenced. Past ~20K tokens it starts crowding out useful context and slowing recall. Managed Agents Memory caps individual memory files at 100KB / ~25K tokens for the same reason — many small focused files beat one giant file.

**What this skill does NOT do:** rewrite, merge, or summarize entries. Every entry stays intact. Old entries move to an archive file. The live DECISIONS.md shrinks.

## When to invoke

- Explicit: "compact decisions", "archive old decisions", "DECISIONS.md is too long".
- Auto-offer: `reconcile-project-state` detects DECISIONS.md > 20000 tokens or > 500 lines. Offer once per session, non-blocking.
- Year boundary: first session of a new calendar year, if last archive file doesn't cover prior year.

Never run silently. Always propose + wait for approval.

## Pre-flight

1. Locate `docs/DECISIONS.md`. Missing → report "project-scribe not initialized" and STOP.
2. Count lines + estimate tokens (1 token ≈ 4 chars for rough cut).
3. Parse entries: every `## YYYY-MM-DD — <title>` heading is one entry boundary.
4. Sort by date descending (newest first is the file convention).
5. Report current stats: `DECISIONS.md: N entries, L lines, ~T tokens`.

## Propose archive split

Default strategy: **keep last 12 months live, archive everything older.**

1. Determine cutoff: today minus 12 months.
2. Entries newer than cutoff → stay in `DECISIONS.md`.
3. Entries older than cutoff → move to `docs/DECISIONS-archive-<YYYY>.md`, one file per calendar year.

Present plan as table:

```
| Action  | Entry                                  | Destination                      |
|---------|----------------------------------------|----------------------------------|
| KEEP    | 2026-04-22 — voice-setup service is base | docs/DECISIONS.md              |
| ARCHIVE | 2025-11-04 — old plugin shape rejected   | docs/DECISIONS-archive-2025.md |
| ARCHIVE | 2025-09-12 — rust+tauri locked           | docs/DECISIONS-archive-2025.md |
```

Ask user to approve, edit cutoff, or reject.

## Execution phase

After approval:

1. Create archive file(s) if missing. Preamble:

   ```markdown
   # Own Term — Decisions Archive <YEAR>

   Archived from `docs/DECISIONS.md` on <YYYY-MM-DD>. Append-only. No edits to past entries.

   Current decisions live at [docs/DECISIONS.md](DECISIONS.md). Full history lives in git.

   ---
   ```

2. Append each archived entry verbatim to the appropriate year file, newest on top (match live file convention).

3. Rewrite `docs/DECISIONS.md`:
   - Keep original preamble.
   - Add a `## Archive` section at the bottom (above the final `_No more decisions logged yet_ marker if present) listing every archive file by year:

     ```markdown
     ---

     ## Archive

     - [2025 decisions](DECISIONS-archive-2025.md)
     - [2024 decisions](DECISIONS-archive-2024.md)
     ```

   - Kept entries stay in place, untouched.

4. Verify:
   - Line count now under 500.
   - Every archived entry appears exactly once in an archive file.
   - No entry appears in both live and archive.

## Commit offer

Run `git status --porcelain` first. Commit only scribe-owned files:

```
docs(scribe): archive pre-<YEAR> decisions
```

Stage explicitly:
```
git add docs/DECISIONS.md docs/DECISIONS-archive-*.md
```

Never `git add .` / `git add -A`.

Dirty tree with unrelated changes → warn, list paths, confirm before staging.

## Safety gates

- Entry count before = entry count after (sum of live + archives). If mismatch → abort, report diff, do not save.
- Archive file write is all-or-nothing per year. If one entry fails to append, revert that year's archive file.
- Never rewrite archive files once created. Only append.
- If user cancels mid-flow, leave DECISIONS.md untouched on disk.

## Don't

- Do not merge or summarize entries. Audit trail requires verbatim preservation.
- Do not change entry format. Four-field shape stays.
- Do not archive entries newer than the cutoff, even if the user wants the live file smaller. Suggest tighter cutoff instead.
- Do not run on every session. Threshold-driven only.
- Do not delete archive files. They are permanent.

## Interaction with other skills

- `log-decision`: unaffected. New entries still write to the top of live `DECISIONS.md`.
- `reconcile-project-state`: may trigger this skill at session start via token check. No auto-run.
- `base-audit`: unaffected. Reads live DECISIONS.md for current rules; archived entries are historical record, not active rules.
