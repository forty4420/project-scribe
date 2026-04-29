# project-scribe

![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-c97539?logo=claude)
![Version](https://img.shields.io/badge/version-0.6.2-blue)
![License](https://img.shields.io/badge/license-MIT-green)
[![CI](https://github.com/forty4420/project-scribe/actions/workflows/lint.yml/badge.svg)](https://github.com/forty4420/project-scribe/actions/workflows/lint.yml)

A Claude Code plugin for persistent memory, context handoff, decisions log, and session continuity. Your project's record-keeper — tracks state, decisions, and live context so nothing gets lost between sessions.

**Powered-by-Scribe badge** for your own README:

```markdown
[![memory: scribe](https://img.shields.io/badge/memory-scribe-blue)](https://github.com/forty4420/project-scribe)
```

---

## What it does

- **Indexing** — tracks project state, decisions, specs, and plans in plain markdown files inside your repo.
- **Context-awareness** — watches Claude Code context usage in real time. Surfaces non-blocking warnings starting at 30%, escalates at 40%, offers a unified `/project-scribe:handoff` to save state before compaction.
- **Decay-tracked memory** — per-project memory files with `last_used` + `hits` frontmatter. Stop hook bumps on reference. `compact-memory` archives idle entries automatically. Load-bearing rules (`hits >= 10`) protected.
- **Bulletproof handoff** — PreCompact hook auto-writes a snapshot before compaction. SessionStart consumes + deletes it. Even if you never run `/handoff`, working state survives compact.

Indexing + context-awareness fit any project. No setup beyond `init project scribe`.

If you maintain a modular framework or plugin system that needs **architectural enforcement** ("core vs extension" rules), there's an opt-in **guardrails mode** documented separately: **[docs/guardrails.md](docs/guardrails.md)**.

---

## Install

```bash
# Linux / macOS
ln -s "$(pwd)" ~/.claude/plugins/project-scribe

# Windows
mklink /J "%USERPROFILE%\.claude\plugins\project-scribe" "C:\path\to\project-scribe"

# Restart Claude Code.
```

---

## Per-project setup

Inside any project:

```
> init project scribe
```

Claude runs the `init-project-scribe` skill. Asks 4 questions:
1. Project name + current focus
2. Where specs and plans live
3. Any locked architectural rules
4. Enable base-scope guardrails? (y/N) — say **N** unless you actively need architectural enforcement (most users say N)

Files created: `CLAUDE.md`, `docs/STATE.md`, `docs/DECISIONS.md`, status memo template. That's it.

---

## Invoking skills and slash commands

All scribe slash commands need the namespace prefix `/project-scribe:` — bare `/scribe-status` returns "Unknown command". This matches the Anthropic plugin convention.

```
/project-scribe:scribe          # dashboard readout from STATE.md
/project-scribe:scribe-status   # decay system + Stop hook health (read-only)
/project-scribe:xref-lint       # cross-reference lint (read-only)
/project-scribe:handoff         # unified session shutdown
/project-scribe:compact-decisions
/project-scribe:redact
```

For natural-language invocation, type the trigger phrase verbatim — e.g. "scribe status", "lint xref", "handoff", "compact memory". The agent invokes the matching skill automatically.

---

## What you get in your repo

- **`docs/STATE.md`** — one-page dashboard: current focus, last shipped (auto-reconciled against `git log`), next up, deferred, specs + plans index.
- **`docs/DECISIONS.md`** — append-only log of architectural / scope / rules-of-engagement decisions made in conversation.
- **`docs/status/`** — per-spec implementation memos with a consistent shape.
- **`CLAUDE.md`** — auto-loaded by Claude Code at session start; points at the map.

Plus a per-project memory dir at `~/.claude/projects/<slug>/memory/` (managed by the plugin, lives outside your repo so it doesn't pollute git).

---

## Skills

| Skill / Command | What it does |
|---|---|
| `init-project-scribe` | One-shot bootstrap |
| `reconcile-project-state` | Auto-fires at session start; updates STATE.md "Last shipped" from `git log` |
| `update-project-state` | End-of-ship refresh — prompts for new Current focus / Next up / Deferred, rebuilds indexes |
| `decision-prompt` | **Proactive** — agent watches for rule-shaped moments (never/always/defer/veto) and offers one-line "log this? y/n" prompt |
| `log-decision` | Append a 4-field entry to DECISIONS.md (called by decision-prompt or user explicitly) |
| `deferred-rollup` | Read-only query across all status memos |
| `auto-handoff` (`/project-scribe:handoff`) | Unified session shutdown — captures pending decisions, refreshes STATE.md, prunes MEMORY.md if needed, writes handoff doc. `--quick` flag = doc only. |
| `compact-memory` | Decay-aware memory pruning. Archives idle files, protects load-bearing ones. |
| `mark-memory-used` | Manual fallback when Stop hook misses or rule applied via paraphrase |
| `/project-scribe:scribe` | Dashboard readout from STATE.md |
| `/project-scribe:scribe-status` | Decay-system + Stop-hook diagnostic (read-only). v0.6.0+. |
| `/project-scribe:xref-lint` | Cross-reference lint — orphan plans, stale memo links, contradiction probes (read-only). v0.6.0+. |

---

## Context-awareness in detail

Reads Claude Code's statusline JSON via a small Python script and writes the current context percentage to `~/.claude/.scribe-context`. A `UserPromptSubmit` hook reads that file each turn and, if the project is scribe-enabled (`docs/STATE.md` exists), surfaces a warning when usage crosses thresholds:

| Range | Behavior |
|---|---|
| Below 30% | Silent |
| 30-39% | Soft heads-up. Suggests `/project-scribe:handoff` or `/project-scribe:handoff --quick` |
| 40%+ | Stronger nudge. Suggests `/project-scribe:handoff` to save before compaction |

Cooldown: only re-warns when usage jumps a 5% bucket (30 → 35 → 40 → ...) so the chat isn't spammed.

Statusline command points at `~/.claude/scripts/scribe-statusline-launcher` — a small wrapper that finds the latest installed scribe plugin version and runs its `hooks/statusline.py`. No `jq` dependency — uses Python 3 (already required by Claude Code itself).

### Desktop vs CLI

Auto-warnings depend on Claude Code's statusline running, which it currently does **only in CLI / terminal mode**. The desktop Electron app does not invoke statusline commands ([Anthropic Issue #41456](https://github.com/anthropics/claude-code/issues/41456) — pending).

**What this means in practice:**

- **CLI users:** auto-warnings fire as expected.
- **Desktop users:** desktop already shows context % in its own UI (bottom-right corner). Use that as the visual cue and run `/project-scribe:handoff` manually.

Scribe's other features work identically on both clients.

### `/project-scribe:handoff` clipboard auto-copy

When `/project-scribe:handoff` finishes, the "Paste-this prompt" block is automatically copied to your clipboard (uses `clip.exe` on Windows, `pbcopy` on macOS, `xclip`/`xsel`/`wl-copy` on Linux). The same prompt is also printed in chat as a fallback.

Workflow becomes: `/project-scribe:handoff` → wait for "✅ Handoff complete" → open new chat in sidebar → Ctrl+V (Cmd+V on Mac). Two clicks, no manual copy.

---

## Memory decay (v0.5.0+)

Memory files in `~/.claude/projects/<slug>/memory/` get YAML frontmatter:

```yaml
---
last_used: 2026-04-28
hits: 4
---
```

The Stop hook bumps these fields when a memory file is referenced in a session. `compact-memory` scores files by `(decayed_hits + 1) / (weeks_idle + 1)` and proposes archive candidates. Files with `hits >= 10` are load-bearing and never auto-archived.

Run `/project-scribe:scribe-status` any time to see decay scores + Stop-hook health without modifying anything.

---

## Troubleshooting

Set `SCRIBE_DEBUG=1` in your shell to enable diagnostic logging from scribe's hooks. When set, each fire of `pre-compact`, `session-start`, `stop-mark-memory`, and `userprompt-context-warn` appends a line to `~/.scribe-debug.log` with timestamp, hook name, action, and a short detail. Default off — silent no-op preserved unless explicitly enabled.

Tail the log to confirm hooks are firing if you suspect they're not.

---

## Guardrails mode (advanced, opt-in)

For projects with strict "core vs extension" architectural rules — plugin systems, frameworks, modular codebases. Adds five enforcement layers (permission deny, PreToolUse hook, pre-commit hook, SessionStart canary, base-audit skill) that catch architectural drift before commits.

If you don't have an explicit "this folder is off-limits for new features" rule, you don't need this. Skip it.

Full design + threat model: **[docs/guardrails.md](docs/guardrails.md)**.

---

## License

MIT
