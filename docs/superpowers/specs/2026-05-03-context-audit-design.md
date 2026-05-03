# /context-audit — Design Spec

> **Source:** Backlog item #3 from `docs/research/2026-04-29-youtube-mining/synthesized-recommendations.md` §1 — Brad signal 8/10 ("free Context Audit skill identifies context bloat and gives recommendations"). Brainstormed 2026-05-03.

## Problem

Most viewers of Brad's video cited "hitting Max plan usage limits" as their #1 pain. Scribe maintains CLAUDE.md and tracks state but has no diagnostic for context bloat — the real driver of token drain. Users don't know which files cost the most, which CLAUDE.md sections duplicate global rules, which date markers are years stale, or which MCP servers idle-cost 24k tokens just by being listed in `claude_desktop_config.json`.

Brad shipped a paid Context Audit skill. Scribe should ship a free one — and integrate it with scribe's existing memory + state machinery.

## Goal

Add `/project-scribe:context-audit` — a read-only diagnostic that scans the project's CLAUDE.md targets (project + global) and MCP server configs (project `.mcp.json` + OS-specific global `claude_desktop_config.json`), classifies findings by severity, and emits a markdown report with concrete suggested patches. Read-only: never mutates user config.

## Non-goals

- **Not** a hooks/skills auditor (yet). Brad's source mentioned hooks + active skills. Defer to v0.7.6 — start with CLAUDE.md + MCP, the two biggest token sinks.
- **Not** an auto-fixer. Surfaces findings + suggests patches; user applies manually. Matches scribe-verify honesty contract.
- **Not** runtime-aware. Static-file analysis only. No "MCP servers loaded but unused this session" detection (that's backlog item #4 — Token-budget tab).
- **Not** a tokenizer. Char/4 heuristic, ±15% accuracy footnoted. Same precedent set by `compact-decisions` size check.
- **Not** configurable thresholds via JSON file. Hardcoded `5000`/`15000` defaults in v0.7.5. Configurable file deferred to v0.7.6 if demand surfaces.

---

## Architecture

**Approach: Skill + helper bash script (matches v0.7.4 `scripts/` precedent).**

Single-shot bash script does target resolution, parsing, token counting, three detection passes (size / duplication / staleness), MCP enumeration, severity classification, and markdown report formatting. Skill stays thin — instructs Claude to invoke script, surface output, optionally save report to `docs/status/`.

Rejected alternative: multi-script split (`scripts/lib/audit-claude.sh` + `audit-mcp.sh` + `audit-format.sh`). Invents `scripts/lib/` convention speculatively before second feature needs it. Single file ~500 lines is well within readable bash range with disciplined function decomposition.

### File layout

```
scripts/
├── context-audit.sh                  # heavy lifting (~500 lines projected)
└── mcp-token-estimates.json          # curated MCP cost lookup table

skills/context-audit/
└── SKILL.md                          # thin wrapper (~50 lines)

commands/
└── context-audit.md                  # /project-scribe:context-audit slash command

tests/
├── scripts/
│   └── context-audit.bats            # bash logic — ~17 cases
└── skills/
    └── context-audit.bats            # skill contract — ~3 cases
```

### Data flow

```
User → /project-scribe:context-audit [flags]
         ↓
       commands/context-audit.md (shim invokes skill)
         ↓
       skills/context-audit/SKILL.md (Claude reads SOP)
         ↓
       scripts/context-audit.sh
         │
         ├─ Resolve CLAUDE.md targets (project + global)
         ├─ Resolve MCP configs (project .mcp.json + OS-specific global)
         ├─ For each CLAUDE.md target:
         │    ├─ Token count (char/4)
         │    ├─ Duplication scan (paragraph block hashing)
         │    └─ Staleness scan (date markers + dead refs)
         ├─ For each MCP server:
         │    ├─ Look up estimate from mcp-token-estimates.json
         │    └─ Honest fallback: [unknown — connect to measure]
         ├─ Classify severity (5k warn / 15k critical)
         └─ Emit markdown report → stdout
         ↓
       Claude saves to docs/status/context-audit-YYYY-MM-DD.md (unless --no-save)
         ↓
       User reads report, applies suggested patches manually
```

---

## CLI surface

### Slash command

```
/project-scribe:context-audit [--no-save] [--global-only|--project-only] [--no-mcp]
```

### Flags

| Flag | Meaning |
|---|---|
| `--no-save` | Stdout only. Skip `docs/status/` write. |
| `--global-only` | Audit only `~/.claude/CLAUDE.md` + `~/.claude/rules/**` + global MCP config. Skip project paths. |
| `--project-only` | Audit only `$PWD/CLAUDE.md` + `$PWD/CLAUDE.local.md` + project `.mcp.json`. Skip globals. |
| `--no-mcp` | Skip MCP audit entirely (text-file-only fast mode). |

`--global-only` and `--project-only` are mutually exclusive — script aborts with error if both passed.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Audit completed successfully. No critical findings. |
| `1` | Audit completed successfully. ≥1 critical finding present. (Lets user gate CI on this if they want.) |
| `2` | Audit failed (malformed config, missing $HOME, mutex flag conflict). |

---

## Target resolution

### CLAUDE.md targets (4 slots)

| Slot | Path | Required? |
|---|---|---|
| Project main | `$PWD/CLAUDE.md` | optional |
| Project local | `$PWD/CLAUDE.local.md` | optional |
| Global main | `$HOME/.claude/CLAUDE.md` | optional |
| Global rules | `$HOME/.claude/rules/**/*.md` | optional |

Missing slots silently skipped. If all four missing → report shows `(no CLAUDE.md files found)` in size section.

### MCP config targets (cross-OS)

OS detection via `$OSTYPE`:

| `$OSTYPE` prefix | Global config path |
|---|---|
| `msys`, `cygwin`, `win` | `$APPDATA\Claude\claude_desktop_config.json` |
| `darwin` | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| `linux-gnu` | `~/.config/Claude/claude_desktop_config.json` |

Project MCP config: `$PWD/.mcp.json` (same path all OSes).

**Honesty:** if expected global config path missing → MCP audit reports `[unknown — global config not found at expected path: <path>]` rather than silent skip. Matches scribe-verify ambiguous-abort contract.

**Malformed JSON** → exit code 2, error message naming the bad file. No partial-parse recovery.

---

## Detection logic

### Size

For each CLAUDE.md target + each MCP server:

1. Token estimate:
   - CLAUDE.md → `wc -c < file` divided by 4
   - MCP server → lookup in `mcp-token-estimates.json` by server name

2. Severity classification:
   - `< 5000` → ok, no row in report
   - `5000 ≤ x < 15000` → ⚠️ warn
   - `≥ 15000` → 🔴 critical

3. Suggested fixes per CLAUDE.md size finding:
   - Identify largest sections (split on `^## ` headings, count tokens per section)
   - Recommend top 3 sections to extract / compress / move to `~/.claude/context/` lazy-load files

### Duplication

Cross-file substring scan:

1. Read each CLAUDE.md target. Split into paragraph blocks (delimited by `\n\n+`).
2. For each block ≥ 200 chars: compute sha1, take first 16 hex chars.
3. Hashmap: `hash → list of (file, line_number)`.
4. Any hash with ≥ 2 entries → flag as duplicate.
5. Report: hash's source files, total tokens wasted = `block_tokens × (count - 1)`.

**Why ≥ 200 chars:** filters noise from short repeated tokens (`# Notes`, blank lines, common phrases).

### Staleness

**Date markers:**

1. `grep -nE '\b[0-9]{4}-[0-9]{2}-[0-9]{2}\b'` across CLAUDE.md targets.
2. Determine "today" — use `$SCRIBE_AUDIT_TODAY` env var if set (YYYY-MM-DD format), else `date +%Y-%m-%d`. Env override exists so bats fixtures with hardcoded dates don't rot over time. Same precedent as `SCRIBE_VERIFY_TIMEOUT` from v0.7.4.
3. For each match: parse YYYY-MM-DD, compare to today.
4. If > 6 months stale → flag with file:line + nearest `^#+ ` heading above.

**Dead references:**

1. Regex match markdown links to local file paths: `\]\(([^)]+\.(md|sh|json|toml|ts|tsx|js|py|rs))\)`.
2. Skip `http://` / `https://` / `mailto:` URLs.
3. For each path: resolve relative to source file's dir. Test with `[ -e "$path" ]`.
4. Missing → flag as dead reference.

**Edge-case catch:** broken http-mangled local refs like `[handoff.md](http://handoff.md)`. The http:// strip would skip these. Detection rule: if URL host contains a dot AND path ends in known local-file extension AND no host-like authority (just `http://filename.md`) → still treat as dead local ref. Implementation: regex `https?://[^/]*\.(md|sh|...)` (host part is just a filename) → flag.

---

## MCP token-cost estimation

### Lookup table: `scripts/mcp-token-estimates.json`

```json
{
  "version": 1,
  "updated": "2026-05-03",
  "estimates": {
    "stripe":     { "tokens": 12000, "notes": "Heavy when API key set" },
    "playwright": { "tokens": 24000, "notes": "Heaviest common server" },
    "github":     { "tokens":  5000, "notes": "Always-on for most users" },
    "memory":     { "tokens":  3000, "notes": "Always-on for most users" },
    "filesystem": { "tokens":  2000, "notes": "Lightweight" },
    "brave":      { "tokens":  2500, "notes": "Web search" },
    "slack":      { "tokens":  4000, "notes": "Channel/user listing scales" },
    "linear":     { "tokens":  6000, "notes": "Issue/team listing" },
    "sentry":     { "tokens":  3500, "notes": "Project listing" },
    "stripe-mcp": { "tokens": 12000, "alias_of": "stripe" }
  }
}
```

~30 entries total. Aliases supported (e.g. `stripe-mcp` → `stripe`). Schema version field lets future v2 add fields without breaking.

### Matching logic

1. Read `mcpServers` keys from each MCP config.
2. Lowercase + trim each server name.
3. Direct match → use estimate.
4. No match → emit `[unknown — connect to measure]` row.
5. PR invitation in report footer: "File a PR to add `<server>` to `scripts/mcp-token-estimates.json`."

---

## Report format

Markdown. Sections in fixed order. Empty sections rendered with `(none found)` so absence is unambiguous.

```markdown
# Context Audit — YYYY-MM-DD

**Scope:** project + global · **Targets scanned:** N · **Total estimated tokens:** X,XXX

---

## Summary

| Severity | Count |
|---|---|
| 🔴 Critical | C |
| ⚠️ Warning  | W |

Top consumers:
1. <path> — <tokens> <severity-icon>
2. ...

---

## Size findings

(per finding: file path, token count, threshold note, suggested-fix bullet list)

## Duplication findings

(per finding: hash short, files containing it, total wasted tokens, suggested-fix)

## Staleness findings

### Date markers > 6mo
(per finding: file:line, nearest heading, age in months)

### Dead references
(per finding: file:line, broken link target, suggested action — fix path or remove link)

## MCP audit

(table: server | source [project/global] | est. tokens | status)

(unknown servers list with PR invitation)

---

*Estimates ±15% (char/4 heuristic). Run `/project-scribe:context-audit --no-save` for stdout-only. File at `docs/status/context-audit-YYYY-MM-DD.md`.*
```

---

## Save behavior

Default: skill writes report to `docs/status/context-audit-YYYY-MM-DD.md`.

Collision: same-day re-runs append timestamp suffix → `context-audit-YYYY-MM-DD-HHMMSS.md`. No silent overwrite (matches scribe-verify caution about silent state mutations).

`--no-save` flag → stdout only, no file write. Useful for CI gates that just check exit code.

---

## Edge cases + honesty contract

| Scenario | Behavior |
|---|---|
| No CLAUDE.md anywhere | Report shows `(no CLAUDE.md files found)`, MCP audit still runs |
| Empty MCP configs (`{"mcpServers": {}}`) | MCP section: `(no MCP servers configured)` |
| Malformed `.mcp.json` JSON | Exit code 2, name the bad file in error message |
| `$HOME` unset | Try `getent passwd $USER` fallback. Still missing → exit code 2. |
| `$OSTYPE` unrecognized | Default to Linux path, warn in report header that OS detection fell back |
| Both `--global-only` and `--project-only` passed | Exit code 2, error |
| Date-marker regex matches today's date | Not flagged (0 months stale) |
| Date-marker matches future date | Flagged with note "future date — likely typo" |
| Duplicate block but only in single file (multi-occurrence within one file) | Not flagged — only cross-file dups count |

---

## Test plan

### `tests/scripts/context-audit.bats` (~18 active cases + 1 skip-with-TODO)

**Target resolution (3):**
1. Project CLAUDE.md present → counted in report
2. Project CLAUDE.md absent → globals-only audit, project section shows `(none)`
3. `--global-only` flag → project paths skipped entirely

**Token counting (2):**
4. Char/4 heuristic on known fixture (1000 chars → 250 tokens)
5. Empty file → 0 tokens, no warn row

**Size classification (3):**
6. File at ~4999 tokens (19996 chars) → ok, no row
7. File at ~6000 tokens → ⚠️ warn
8. File at ~16000 tokens → 🔴 critical

**Duplication (3):**
9. Same 250-char block in two files → flagged with both paths + waste calc
10. 100-char block (under threshold) → not flagged
11. Boundary cases: 199-char block (under) → not flagged; 201-char block (over) → flagged. Locks the threshold against silent drift on future refactors.

**Staleness — date markers (2):**
12. With `SCRIBE_AUDIT_TODAY=2026-05-03`, CLAUDE.md fixture containing `2024-01-15` → flagged with line + heading
13. With `SCRIBE_AUDIT_TODAY=2026-05-03`, CLAUDE.md fixture containing `2026-04-01` → not flagged

(Both cases pin `$SCRIBE_AUDIT_TODAY` so fixtures don't rot over real-time.)

**Staleness — dead refs (2):**
14. `[foo](./missing.md)` → flagged
15. `[bar](https://example.com)` → URL, not flagged

**MCP (2):**
16. Project `.mcp.json` with known server (e.g. stripe) → estimate from lookup table
17. `.mcp.json` with unknown server → `[unknown — connect to measure]` honest fallback

**OS path resolution (1):**
18. `$OSTYPE=darwin` mock → resolves macOS global config path; Linux/Windows mocks resolve theirs

**Skip-with-TODO commitments (locked, do not re-decide at plan time):**
- Malformed `.mcp.json` JSON → exit code 2 — **active test**
- `$HOME` unset → graceful abort — **skip-with-TODO** (bats helpers including `tests/_helpers/sandbox.bash` depend on $HOME). TODO message: `SKIP: $HOME-unset path requires bats helper rework — defer to v0.7.6`.

### `tests/skills/context-audit.bats` (~3 contract cases)

1. SKILL.md exists with valid frontmatter (name, description, type)
2. Slash command file exists at `commands/context-audit.md`
3. `scripts/context-audit.sh` is executable (`-x`)

### Test fixtures

Fresh fixtures under `tests/_fixtures/context-audit/`:
- `claude-md-tiny/` — 100-token file, baseline
- `claude-md-warn/` — ~6k tokens
- `claude-md-critical/` — ~16k tokens
- `claude-md-dup-a.md` + `claude-md-dup-b.md` — share a 250-char block
- `claude-md-stale-date.md` — contains `2024-01-15`
- `claude-md-fresh-date.md` — contains current-month date
- `claude-md-dead-ref.md` — `[x](./missing.md)`
- `mcp-config-known.json` — single stripe entry
- `mcp-config-unknown.json` — single `custom-tool` entry
- `mcp-config-empty.json` — `{"mcpServers": {}}`
- `mcp-config-malformed.json` — invalid JSON

Reuse `tests/_helpers/{sandbox,fixtures,claude_env}.bash` per v0.7.3 precedent.

### CI

`.github/workflows/test.yml` already runs `tests/scripts/` (added in v0.7.4). New file auto-discovered. **No workflow change needed** — gotcha #7 from handoff already mitigated.

---

## Open questions

- **MCP estimate source-of-truth maintenance:** lookup table will drift as MCP servers update. Initial v0.7.5 list is best-effort + PR invitation in report footer. Long-term: maybe scrape published MCP registries quarterly. Not blocking ship.
- **`docs/status/` collision policy:** chose timestamp suffix on same-day re-run. Alternative: prompt user. Decided no — read-only diagnostic shouldn't block on prompts.
- **Should report compute project-vs-global savings?** E.g. "moving X from project to global saves N tokens × M projects." Out of scope — single-project scan only. Scribe doesn't know about user's other projects.

---

## Definition of done

1. ✅ All ~18 script bats cases + ~3 skill contract cases (~21 total) passing locally + in CI
2. ✅ `/project-scribe:context-audit` invokes cleanly on the scribe repo itself (dogfood)
3. ✅ Report saved to `docs/status/` with correct format
4. ✅ All four flags work as documented
5. ✅ Three exit codes correctly emitted
6. ✅ Cross-OS path resolution verified via OSTYPE mocking in bats
7. ✅ DECISIONS.md entry logged (architecture decision)
8. ✅ CHANGELOG.md updated with v0.7.5 entry
9. ✅ `.claude-plugin/plugin.json` bumped 0.7.4 → 0.7.5
10. ✅ PR merged with CI green
