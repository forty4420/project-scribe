# project-scribe — DECISIONS

Append-only log. Newest at top. Format: 4 fields per entry.

---

## 2026-04-30 — Adopt bats-core for scribe tests

**Context:** Reviewer-3 flagged absence of test harness in the v0.6.0 smoke test. Refactors of hooks (`session-start`, `userprompt-context-warn`, `pre-compact`, `stop-mark-memory`) and the highest-leverage skills (`auto-handoff`, `log-decision`, `reconcile-project-state`) risk silent regressions. Pre-r/ClaudeAI launch credibility — hostile commenters will scan for "0 tests" as an attack surface.

**Decision:** Vendor bats-core + bats-support + bats-assert as git submodules under `tests/_libs/`. Cover all 4 hooks + the 3 high-leverage skills initially. CI runs on Ubuntu only — Windows users use Git Bash/WSL. Tests assert on the *contract* (file shape and content patterns), not on Claude AI behavior.

**Alternatives considered:** shellcheck-only (lint not test, doesn't catch behavioral regressions). Python pytest with subprocess wrappers (extra runtime dep, awkward for bash hooks). No tests at all (incurred debt, blocks the next 14 backlog items that all touch hook + skill internals).

**Revisit when:** Test runtime exceeds 30s (currently ~3s), OR Windows users hit fork-specific bugs not caught by Linux CI, OR coverage measurement (kcov) becomes load-bearing for a future contributor PR review.

**Superseded by:** —
**Valid until:** test runtime / platform / coverage triggers above.

---

## 2026-04-26 — Scope expanded to include context-awareness; name "project-scribe" kept

**Decision:** Scribe now also handles real-time context-usage monitoring
and unified session shutdown (the `/handoff` skill that bundles
log-decision + compact-decisions + update-project-state + compact-memory
+ handoff doc generation). The plugin name "project-scribe" is kept
despite this scope expansion.

**Why:** A scribe historically records, preserves, indexes, and
transfers knowledge — including watching the room and flagging when
the stack gets too tall. Memory + context-awareness sit inside that
same job description, not outside it. Renaming now would break the
public GitHub repo URL, plugin cache paths, and existing user
muscle memory for zero functional gain.

**How to apply:** When introducing scribe to new users, lead with the
record-keeper framing, not the project-management framing. If scope
expands further (e.g. multi-agent orchestration, code-search) and the
name becomes actively misleading, revisit. Current trigger to rename:
publishing broadly + new-user confusion.

**Superseded by:** —
**Valid until:** revisited if scribe ships features outside the
record-keep / preserve / transfer sphere.

---

## 2026-04-26 — Unified `/handoff` replaces `/shutdown-bundle`; standalone auto-handoff trigger merged in

**Decision:** Removed the separate `/shutdown-bundle` slash command.
Folded all bundle steps (log-decision → compact-decisions →
update-project-state → compact-memory → handoff doc) into the
`auto-handoff` skill, invoked via `/handoff`. Added smart auto-skip
for steps with nothing to do. Added `--quick` flag for doc-only mode.

**Why:** Two near-identical commands created cognitive overhead. The
distinction (handoff = doc only, bundle = doc + state ops) was
archaeological — built at different times, not by design. For 95% of
session-end work, users want everything saved. Edge cases (mid-task
panic save, experimental sessions) are handled by `--quick`.

**How to apply:** Always direct users to `/handoff`. The
context-warning hook surfaces this command at 30%+ context. The
old `commands/shutdown-bundle.md` file has been deleted; `/handoff`
is the only entry point.

**Superseded by:** —
**Valid until:** new evidence that smart-skip + `--quick` aren't
enough to cover the use cases the old separation served.

---

## 2026-04-26 — Statusline written in Python, not jq; lives in plugin

**Decision:** Scribe ships its own statusline at
`hooks/statusline.py`, written in Python 3 with no external
dependencies. A launcher at `~/.claude/scripts/scribe-statusline-launcher`
finds the latest installed plugin version and invokes it. The
launcher path is hardcoded in `~/.claude/settings.json` because
Claude Code's statusLine config does not support
`${CLAUDE_PLUGIN_ROOT}` substitution.

**Why:** The original statusline used `jq`, which is not installed by
default on Windows and most user systems. A jq install would require
per-OS instructions (winget / brew / apt) and PATH-refresh handling.
Python 3 is already required by Claude Code itself, so no new
dependency is added. The launcher abstracts the version-pinned cache
path so plugin upgrades don't break the statusline.

**How to apply:** When publishing scribe, document that users must
add the launcher path to their global `~/.claude/settings.json`
statusLine config. Provide a one-line install command in README.

**Superseded by:** —
**Valid until:** Claude Code adds `${CLAUDE_PLUGIN_ROOT}` support to
statusLine, at which point the launcher can be removed and the
statusline pointed directly at the plugin path.

---
