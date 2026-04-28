---
name: scribe-status
description: Read-only diagnostic that reports decay-system + Stop-hook health for the current scribe-enabled project. Lists every memory file with its last_used / hits / decay score / status bucket, plus bump-log freshness and Stop-hook registration. Triggers include "scribe status", "/scribe-status", "memory health", "is scribe working", "decay status".
---

# Scribe status

Read-only diagnostic. Reports the health of the decay system + Stop hook for
the current project. Mirrors the scoring formula and bucket rules from
`compact-memory` so the numbers match what compaction will see.

## Hard rules — never violate

- **Read-only.** Never modify any memory file, never touch `.bump-log`, never
  edit `hooks/hooks.json`, never write into `~/.claude/projects/<slug>/`.
  This skill is purely observational.
- **No backfill.** If a memory file lacks frontmatter, report it as
  "no frontmatter" — do NOT inject one. That is `compact-memory`'s job.
- **Bail silent if `docs/STATE.md` missing.** Project is not scribe-enabled;
  exit with no output.

## When to invoke

- User says "scribe status", "/scribe-status", "is scribe working",
  "memory health", "decay status", "show me memory state"
- After a session where the user wants to verify the Stop hook fired
- Before running `compact-memory` so the user can preview which files
  would be flagged

## Pre-flight

1. Confirm `docs/STATE.md` exists in the current project root. If missing →
   silent no-op, no output.
2. Resolve memory dir slug. Slug rule (mirrors `hooks/stop-mark-memory` line 34
   `echo "$PROJECT_ROOT" | sed -E 's|^/([a-zA-Z])/|\U\1--|; s|/|-|g'`):
   - Take the project root path (cwd).
   - On Windows / Git-Bash, paths begin `/c/Users/...` — uppercase the drive
     letter and replace the leading `/c/` with `C--`.
   - Replace every remaining `/` with `-`.
   - Example: `/c/Users/forty/Downloads/project-scribe` →
     `C--Users-forty-Downloads-project-scribe`.
3. Compose memory dir path: `~/.claude/projects/<slug>/memory/`.
4. If memory dir missing → report exactly:
   ```
   ## Scribe Status

   Memory dir: ~/.claude/projects/<slug>/memory/ (does not exist)

   No scribe memory yet — the Stop hook hasn't fired or the project hasn't
   been active long enough to accumulate memory files.
   ```
   then STOP. Still emit Stop-hook registration check (see step "Stop-hook
   health" below) so the user knows whether the hook is wired even when no
   memory has been written yet.

## Decay scoring (mirror compact-memory Pass 0)

Use today = current date (ISO). For each memory file with frontmatter:

```
weeks_idle    = floor((today - last_used) / 7)         # in days, then /7
decayed_hits  = hits * (0.9 ^ weeks_idle)
score         = (decayed_hits + 1) / (weeks_idle + 1)
```

Round `score` to 2 decimal places for display. Round `decayed_hits` to 2
decimals only if you choose to surface it (optional — primary table column
is `score`).

## Status bucket rules (mirror compact-memory)

Apply rules in this exact order — first match wins:

1. `score < 0.10` AND `weeks_idle > 16` → `DECAY-DELETE` candidate
2. `score < 0.25` AND `weeks_idle > 8`  → `DECAY-ARCHIVE` candidate
3. `hits >= 10`                          → `load-bearing` (protected)
4. `weeks_idle > 4`                      → `idle`
5. else                                  → `active`

For files with no frontmatter, status = `no-frontmatter` and score columns =
`-` (cannot compute without `last_used`/`hits`).

## Inventory pass

For each `*.md` file in `<MEM_DIR>` AND in `<MEM_DIR>/daily/` (skip `MEMORY.md`
— it's the index, not a memory entry; daily-note files at `daily/YYYY-MM-DD.md`
participate in decay scoring like any other memory file):

1. Read first 10 lines. Detect frontmatter via line 1 = `---`.
2. If frontmatter present, parse:
   - `last_used:` → ISO date (e.g. `2026-04-15`)
   - `hits:` → integer
3. Compute `weeks_idle`, `decayed_hits`, `score`, `status` per formulas above.
4. If frontmatter missing → record `no-frontmatter` row.

## Bump-log pass

Look for `<MEM_DIR>/.bump-log`:

- If absent → "no bump-log file"
- If present:
  - Count lines (each line = one bump record)
  - Get mtime of file → most recent activity
  - Compute hours since mtime
  - Tag "firing within 24h" if hours < 24, else "stale (last fired Nh / Nd ago)"

## Stop-hook health

1. Read `hooks/hooks.json` from project root (the plugin's own hook config).
   - If file missing → "Stop hook config missing — plugin not installed
     correctly?"
   - If present, look for a `Stop` entry under `hooks` whose command
     references `stop-mark-memory`. Confirm presence + whether `async: true`.
2. Cross-check with bump-log activity:
   - Hook registered + bump-log fresh (<24h) → "wired and firing"
   - Hook registered + bump-log stale or missing + memory files exist →
     "wired but not firing — check hook errors"
   - Hook registered + no memory files → "wired, no activity yet"
   - Hook NOT registered → "Stop hook missing from hooks.json — register
     it or run init-project-scribe again"

## Output format

Single markdown block. Plain text. No JSON. Shape:

```
## Scribe Status

Memory dir: ~/.claude/projects/<slug>/memory/
Total files: N (M with frontmatter, K without)

| File | last_used | hits | weeks_idle | score | status |
|------|-----------|------|------------|-------|--------|
| feedback_a.md | 2026-04-20 | 7 | 1 | 4.00 | active |
| user_role.md  | 2026-01-15 | 12 | 14 | 1.10 | load-bearing |
| feedback_old.md | 2025-09-01 | 2 | 34 | 0.07 | DECAY-DELETE |
| stale_memo.md | - | - | - | - | no-frontmatter |

Bump-log:
- N entries, last mtime YYYY-MM-DD HH:MM UTC
- Hook firing within 24h: yes / no (last fired Xh ago)

Stop hook: <status string>
  - hooks.json entry: present (async: true) / missing
  - last bump activity: Xh ago / never
  - diagnosis: <wired and firing | wired but not firing | wired, no activity yet | hook missing>
```

If memory dir missing, emit only:

```
## Scribe Status

Memory dir: ~/.claude/projects/<slug>/memory/ (does not exist)

No scribe memory yet — the Stop hook hasn't fired or the project hasn't
been active long enough to accumulate memory files.

Stop hook: <status string from hooks.json check>
```

## Sort order

Sort the file table by `status` priority then by `score` ascending so the
files most in need of attention surface first:

1. `DECAY-DELETE` rows
2. `DECAY-ARCHIVE` rows
3. `no-frontmatter` rows (backfill candidates)
4. `idle` rows
5. `load-bearing` rows
6. `active` rows

Within each bucket, sort by `score` ascending (lowest first) for decay
buckets, by `last_used` descending (most recent first) for active /
load-bearing.

## Don't

- Don't propose actions. This skill reports state — `compact-memory` is the
  one that proposes archive/delete/merge.
- Don't write anywhere. No new files, no edits, no `.bump-log` mutation.
- Don't crash on parse failures — if a file has malformed frontmatter,
  emit it as `no-frontmatter` and continue.
- Don't include `MEMORY.md` in the per-file table. It's the index file,
  not a memory entry.
- Don't include `.bump-log` in the per-file table. It's hook state.
- Don't recompute slug from `$HOME` or anything other than the project root
  (cwd). Slug is a function of the project path, not the user.
