# Project State — project-scribe

## Current focus

v0.6.0 smoke test (Phase 10). Verifying scribe-status, xref-lint, pre-compact hook, decay hook bumps, snapshot restore.

## Last shipped

- v0.6.0 — feature stack (scribe-status, xref-lint, pre-compact, daily-note skeleton, alternatives field, README badges, SCRIBE_DEBUG, CI workflow) — `2a67347`
- v0.5.0 — memory decay scoring + idempotent stop hook — `b5bd58e`
- v0.4.1 — clipboard auto-copy + freshness gate fix — `b70e8ed`
- v0.4.0 — context-awareness mode + unified /handoff — `71ac0ef`

## Next up

- Phase 10 HITL smoke test results → `docs/status/v0.6.0-smoke-test.md`
- v0.6.1 if smoke test surfaces bugs
- v0.7.0 candidates: bash test harness, LLM-summarized turn capture into daily notes

## Deferred

- Plugin "requires" compatibility field (Anthropic schema unverified)
- Schema-aware routing
- Daily-note auto-capture (skeleton only in v0.6.0)
- Promotion path / dreaming-lite
- Plugin rename for search disambiguation
- Desktop tray app for context warnings
- Marketing posts (r/ClaudeAI, X, HN)

## Specs

(none active — feature work tracked via plans + commits)

## Plans

| Plan | Status |
|------|--------|
| `docs/plans/v0.6.0-autonomous-rollout.md` | Phases 0-9 complete, Phase 10 HITL in progress |
| `docs/plans/v0.6.0-phase9-instructions.md` | Done |
| `docs/plans/repo-mining-ideas.md` | Reference (mining notes) |
