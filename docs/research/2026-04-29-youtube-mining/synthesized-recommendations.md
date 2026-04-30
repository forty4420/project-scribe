# Scribe Plugin Upgrade Recommendations

Source: 25 YouTube videos analyzed across two topics.
- `claude code plugin best practices` — 13 videos, signal 7-9/10
- `claude code handoff session` — 12 videos, signal 8-9/10

Date: 2026-04-29 · Groq tokens: 138k (free tier)

---

## What scribe already does well

- Decision logging (`/log-decision`)
- State reconciliation against git log (`reconcile-project-state`)
- Handoff bundling (`auto-handoff`, `session-card`)
- Memory health + decay (`scribe-status`, `compact-memory`, `mark-memory-used`)
- Cross-reference linting (`xref-lint`)
- Base-scope guardrails (`lock-base`, `unlock-base`, `base-audit`)

---

## High-value upgrades worth building

### 1. Context Audit skill — directly competes with paid one mentioned in videos
**Source:** Brad (signal 8/10) — "free Context Audit skill identifies context bloat and gives recommendations"

**What:** Skill that scans current project's CLAUDE.md, MCP servers loaded, settings.json hooks, and active skills — reports token bloat sources with fix suggestions.

**Why it matters:** Most viewers cited "hitting Max plan usage limits" as #1 pain. Scribe already maintains CLAUDE.md — extending to audit it is natural fit.

**Effort:** Medium. New skill + analysis script. Reuses scribe's existing memory file scanning.

---

### 2. Plan-as-GitHub-issue persistence
**Source:** Matt Pocock (signal 7/10) — "store plans as GitHub issues for persistence across sessions"

**What:** Extension to `auto-handoff` — optionally push handoff doc to a GitHub issue. Issue becomes the durable artifact instead of local-only `.md`.

**Why it matters:** Handoff docs currently live in repo. GH issues survive repo wipes, are searchable, support comments, and integrate with PR workflow.

**Effort:** Low. `gh issue create` call + frontmatter flag in scribe's session bundle.

---

### 3. Pre-tool-use enforcement hook — DECISIONS.md gate
**Source:** Matt Pocock (signal 8/10) — "Convert CLAUDE.md instructions into deterministic hooks. Pre-tool use hooks block or redirect commands."

**What:** Pre-Bash/Edit hook that detects rule-shaped statements being violated (e.g. user said "no users yet, skip auth migrations" but Claude is editing auth files). Blocks with prompt to log decision or override.

**Why it matters:** Scribe's `decision-prompt` skill is reactive — surfaces decisions after the fact. Hook would enforce at write time. Natural marriage of scribe's decision-log + Pocock's hook pattern.

**Effort:** Medium. Existing `decision-prompt` logic + new `pre_tool_use` hook script.

---

### 4. Sub-agent chapter tracking
**Source:** Boris/Anthropic (signal 9/10) + Cole Medin (signal 9/10) — "agent teams collaborate in real-time, parallel sessions"

**What:** Scribe extension that opens a new "chapter" in STATE.md when Task tool spawns subagents, closes chapter when subagent completes. Records what each subagent did vs what main thread did.

**Why it matters:** With Opus 4.7's reduced default subagent use, when subagents DO fire, attribution matters. Currently invisible in scribe's state.

**Effort:** Medium. Stop hook on Task tool + parser.

---

### 5. Worktree-aware state files
**Source:** Developers Digest (signal 8/10) — "Git worktrees enable parallel branch editing via isolated CLI sessions"

**What:** Scribe detects when running in a worktree (vs main checkout) and uses worktree-specific STATE.md / DECISIONS.md path. Avoids cross-contamination of state between parallel feature branches.

**Why it matters:** Multiple Claude sessions across worktrees currently fight over the same scribe files. Pattern is increasingly common (Superpowers plugin uses worktrees in its workflow).

**Effort:** Low. Add `.git/worktrees/<name>/scribe/` lookup before falling back to repo root.

---

### 6. Verification-gate slash command
**Source:** Boris/Anthropic (signal 9/10) — "verification-led development, structured claude.md files"

**What:** New `/scribe-verify` command that reads STATE.md "Last shipped" claim, runs the project's verification command (npm test, cargo check, etc. — discovered from CLAUDE.md), reports drift.

**Why it matters:** Scribe currently trusts what user says shipped. Verification gate catches lying-by-omission ("forgot tests fail").

**Effort:** Low. Reuses `reconcile-project-state` scaffolding.

---

### 7. Token-budget tab in session-card
**Source:** Brad (signal 8/10) — "/context, /stats, token usage management"

**What:** `session-card` already summarizes project state. Add token-budget panel: 5-hour window remaining estimate, weekly cap projection, top context consumers.

**Why it matters:** Users hitting Max plan limits is universal pain point. Scribe's session-card is the natural surface to show "you're at 60% of weekly cap" alongside project status.

**Effort:** Medium. Need `claude usage` API or parse session logs. Worth scoping a brief proof-of-concept first.

---

### 8. Mobile/web continuation flag
**Source:** NetworkChuck + Chong-U (signal 8/10) — "Claude Code Remote Control, iOS, web — start anywhere, continue anywhere"

**What:** Scribe handoff already serializes state. Add explicit "continue-elsewhere" mode that produces a portable bundle (gist URL or pastebin) optimized for paste-into-mobile.

**Why it matters:** With official Claude Code mobile/web shipping, users will increasingly switch surfaces mid-task. Scribe handoff format is currently desktop-Claude-Code optimized.

**Effort:** Low. Existing handoff doc + size compression + auto-gist.

---

## Patterns to NOT adopt (anti-recommendations)

- **Ralph Wiggum auto-loop pattern** (`obra/superpowers`'s ralph-loop) — multiple videos warn against unsupervised auto-loops. Scribe should stay observation-only, not action-driving.
- **Context7 MCP server documentation lookup** — useful tool but not scribe's domain. Don't duplicate.
- **Beads workflow framework** (`steveyegge/beads`) — heavyweight task graph system. Scribe's deferred-rollup covers 80% of use case.
- **CLAUDE.md auto-generation** — `/init` already does this in core Claude Code. Don't reimplement.

---

## Source repositories worth installing/studying

| Repo | Stars/Signal | Why |
|------|--------------|-----|
| [obra/superpowers](https://github.com/obra/superpowers) | 3 mentions, 8-9/10 | Patterns for structured workflow plugins. Closest peer to scribe in terms of "Claude Code workflow shaper". |
| [coleam00/context-engineering-intro](https://github.com/coleam00/context-engineering-intro) | 9/10 | Context engineering primer — directly relevant to upgrade #1. |
| [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) | 9/10 | Engineering workflow plugin — study for plugin packaging conventions. |
| [anthropics/claude-quickstarts](https://github.com/anthropics/claude-quickstarts) | 8/10 | Anthropic's official long-running agent harness — reference impl for handoff state shape. |

---

## Recommended order of work

1. **Worktree-aware state files** (low effort, high frequency value) — start here.
2. **Plan-as-GitHub-issue persistence** (low effort, durable wins).
3. **Pre-tool-use DECISIONS.md gate** (medium effort, biggest behavioral upgrade).
4. **Context Audit skill** (medium effort, addresses universal pain).
5. **Verification-gate slash command** (low effort, locks in scribe trustworthiness).

Items 6-8 (chapter tracking, token budget tab, mobile continuation) — defer until 1-5 land.

---

## Token cost summary

- Stage 1 yt-dlp: $0
- Stage 2 Groq qwen3-32b: 138k tokens of 450k daily cap (30% used, free tier)
- Stage 3 local rank: $0
- Stage 4 this synthesis: ~6k Claude tokens (Max plan, negligible)

Total Max plan impact: pennies. Repeat next week with different topic phrasings to refresh signal.
