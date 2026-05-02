---
description: Read-only verification gate. Runs the project's verify command, parses STATE.md "Last shipped" top entry, checks git drift since the claimed SHA, and emits a markdown report with suggested fixes.
---

Invoke the `scribe-verify` skill.

The skill will:
1. Resolve the verify command for this project via the 4-step hybrid (`docs/.scribe-verify.sh` → `CLAUDE.md` `## Verify` → auto-detect → error).
2. Parse STATE.md "Last shipped" top entry for an explicit short-SHA. Fall back to fuzzy version-label search if absent. Abort with ambiguity report if multiple candidates match.
3. Run the verify command with a 300s default timeout (`SCRIBE_VERIFY_TIMEOUT` env var to override).
4. Check git drift: claimed SHA exists in repo, commits between claim and HEAD, working-tree status.
5. Emit a markdown report with verdict glyph (✅ / ⚠️ / ❌), section-per-check, and context-sensitive suggested fixes.

Read-only. No writes anywhere — no STATE.md edits, no git mutation, no scribe state changes.
