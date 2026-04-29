# Changelog

All notable changes to project-scribe. Newest first.

## v0.6.2 — README marketing-split: indexing core leads, guardrails opt-in

### Changed

- README rewritten to lead with the universal value (indexing, context-awareness, decay-tracked memory, bulletproof handoff) and demote guardrails to a single opt-in section pointing at `docs/guardrails.md`. Audience for guardrails is ~5% of users (modular framework / plugin maintainers); previous README spent ~40% of real estate on it. Now ~10%.
- New v0.5.0+ features (decay scoring, `/project-scribe:scribe-status`, `/project-scribe:xref-lint`, PreCompact snapshot hook) promoted to the top of the value-prop list — they were buried under guardrails docs.
- "Three modes" framing dropped; replaced with "what it does" bullet list. Mode framing required readers to figure out which mode applied to them before continuing — extra cognitive load for the 95% who only need indexing + context-awareness.
- Single "Guardrails mode (advanced, opt-in)" section near the end with a one-paragraph pitch + link to `docs/guardrails.md`. Full design + threat model unchanged in that doc.

### Notes

- No code changes. Documentation reorganization only.
- Guardrails functionality unchanged — same skills, hooks, commands, allowlist semantics. Just less prominent in the README.

## v0.6.1 — README namespace-prefix clarification

### Changed

- README documents the `/project-scribe:<command>` namespace-prefix invocation pattern. Bare slash invocations (`/scribe-status`, `/xref-lint`) return "Unknown command" — Anthropic's plugin slash commands require the namespace prefix. Discovered during v0.6.0 Phase 10 smoke test.
- New `## Invoking skills and slash commands` section near the top of the README with the full slash list and a note about natural-language invocation.
- Skills + commands tables updated to show namespace-prefixed slashes (`/project-scribe:scribe`, `/project-scribe:handoff`, `/project-scribe:audit`, etc.).

### Notes

- No code changes. Documentation patch only.

## v0.6.0 — Feature stack

### Added

- `/scribe-status` read-only diagnostic skill — reports decay-system + Stop-hook health without modifying anything. Mirrors compact-memory's Pass 0 scoring so numbers match what compaction will see.
- `xref-lint` skill — orphan plans, stale memo links, missing status memos, and (low-confidence) decision contradictions. Read-only; user decides on each finding. Confidence-tagged outputs.
- PreCompact snapshot hook (`hooks/pre-compact`) — auto-handoff safety net. Writes `docs/.scribe-snapshot.md` (gitignored) before compaction with last user prompt + current focus + last 3 decisions + last shipped + next up. SessionStart consumes and deletes (one-shot). Stale snapshots (>7 days) still inject but flag stale.
- Daily-note layer skeleton — `memory/daily/YYYY-MM-DD.md` convention. Created on init. Files participate in decay scoring + frontmatter bumps like any other memory file. Auto-capture (LLM-summarized turn → daily file) deferred to v0.7.0.
- "Alternatives considered" field in DECISIONS template — extends the entry shape from 4 fields to 5. Captures rejected options with reasons. Backwards compatible: old 4-field entries remain valid.
- README badges (Claude Code, version, license, CI) + post-install star/feedback CTA in init-project-scribe.
- Optional `SCRIBE_DEBUG=1` env var — when set, all four hooks (`pre-compact`, `session-start`, `stop-mark-memory`, `userprompt-context-warn`) log diagnostics to `~/.scribe-debug.log`. Default off; silent no-op behavior preserved.
- GitHub Actions CI: shellcheck on hooks, jq lint on hooks.json + plugin.json, frontmatter check on every SKILL.md. All jobs `continue-on-error` until v0.7.0 to avoid first-run noise blocking merges.

### Changed

- README first paragraph rewritten for search keyword density: leads with "Claude Code plugin," "persistent memory," "context handoff," "decisions log," "session continuity."
- `stop-mark-memory` glob now walks both top-level memory dir AND `memory/daily/` so daily-note files get frontmatter bumps. Plan said "no change needed — verify"; verification revealed the non-recursive glob was the bug.
- `compact-memory` and `scribe-status` enumeration now includes `memory/daily/` files.
- `auto-handoff` skill documents the safety-net relationship — PreCompact is the auto-handoff fallback, explicit `/handoff` remains canonical.

### Notes

- Decay system from v0.5.0 still in soak — verify via `/scribe-status` before relying on archive output.
- Plugin compatibility field (`requires`) deferred — pending verification of Anthropic plugin schema. Will land in v0.6.1 once exact key shape confirmed.

## v0.5.0 — Memory decay scoring + idempotent stop hook

See git log: `b5bd58e feat: memory decay scoring + idempotent stop hook (v0.5.0)`.

## v0.4.1 — Clipboard auto-copy + freshness gate fix

See git log: `b70e8ed feat: clipboard auto-copy + freshness gate fix (v0.4.1)`.

## v0.4.0 — Context-awareness mode + unified /handoff

See git log: `71ac0ef feat: context-awareness mode + unified /handoff (v0.4.0)`.

## v0.3.0 and earlier

See git log for full history.
