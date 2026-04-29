# How project-scribe compares

Honest comparison against the most-cited Claude Code memory plugins as of April 2026. Verified directly from each project's README. Where Scribe loses, this doc says so.

## Quick read

**Scribe is the only Claude Code memory plugin that prevents context loss before it happens.** Every other tool recovers what was lost. Scribe warns you at 30% and 40% context, then auto-snapshots before compaction so nothing leaks across the session boundary.

If you need semantic recall across thousands of past sessions, Scribe is the wrong tool — use MemPalace or Mem0. If you want a memory plugin that gets out of your way, lives in your repo as plain markdown, and stops compact from wiping your work, this is the one.

---

## Feature table

| Feature | **project-scribe** | claude-mem | claude-mem-lite | MemPalace | Mem0 | ShieldCortex (Claude Cortex) |
|---|---|---|---|---|---|---|
| **Storage** | Plain markdown in your repo | Chroma vector DB + SQLite | SQLite (FTS5 + TF-IDF) | ChromaDB + SQLite | Cloud or self-host (Postgres + vector store) | SQLite + ONNX embeddings |
| **Setup** | `init project scribe` | `npx claude-mem install` | `/plugin install` or `npx` | `pip install mempalace` | `pip install mem0ai` + cloud signup or `docker compose` | `npm install -g shieldcortex` |
| **Cost** | Free | Free | Free | Free | Free tier + paid cloud | Free |
| **API key required** | No | No (uses Claude SDK) | Optional (ANTHROPIC_API_KEY for direct calls) | No | Yes for cloud, no for self-host | No |
| **Heavy deps** | None | Chroma + agent-sdk | None (3 npm packages) | ChromaDB + Python + ~300 MB embedding model | Postgres + vector store + spaCy | ONNX embedding worker |
| **Where memories live** | In your repo (`docs/STATE.md`, `DECISIONS.md`, etc.) | `~/.claude-mem/` | `~/.claude-mem-lite/` | `~/.mempalace/` | Their cloud or your DB | Local SQLite |
| **Live context-% warning (30/40%)** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Auto-snapshot before compact** | ✅ (PreCompact hook) | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Decay scoring (frontmatter `last_used` + `hits`)** | ✅ | ❌ | ❌ (has session compression instead) | ❌ | ❌ | ✅ (temporal decay) |
| **Search** | grep / regex on markdown | LLM-summarized observations + semantic search | FTS5 BM25 + TF-IDF cosine + RRF | Semantic vector + temporal proximity | Multi-signal (semantic + BM25 + entity) | Semantic (ONNX) + FTS5 fallback |
| **Recall benchmark (LongMemEval R@5)** | n/a — not a recall tool | n/a | n/a | **96.6%** (raw, no LLM) | 93.4% (April 2026 algo) | n/a |
| **Cross-platform AI clients (Cursor, Codex)** | ❌ Claude Code only | ✅ Gemini CLI + OpenCode + OpenClaw | ❌ Claude Code only | ✅ Claude Code, Gemini CLI, MCP-compatible | ✅ Many (SDK-based) | ✅ Claude Code, Cursor, VS Code, OpenClaw |
| **Windows support** | ✅ Tested on Win 11 | ✅ | ❌ Linux/macOS only | ✅ (Python) | ✅ | ✅ |
| **License** | MIT | AGPL-3.0 | (check repo) | MIT | Apache-2.0 | MIT |
| **Reads at session start** | Yes — auto via SessionStart hook | Yes — context injection | Yes — startup dashboard | On `wake-up` command | Via SDK calls in agent loop | Yes — auto-extraction hook |
| **Project-scoped or global** | Per-project (markdown in repo root) | Per-project (`~/.claude-mem/`) | Per-project | Per-project (wings/rooms) | User+session+agent scopes | Per-project |
| **GitHub stars (April 2026)** | very early | 69k | 38 | early | huge (PyPI 100k+ downloads/mo) | 61 |

### Honest weak spots per tool

| Tool | Where it loses |
|---|---|
| **project-scribe** | No semantic search. If you need to recall a conversation from 6 months ago by paraphrased question, use MemPalace. Claude Code only — doesn't follow you to Cursor/Codex. |
| **claude-mem** | LLM call on every tool use is expensive. No prevent-compact warning. Heavy install (Chroma vector DB). |
| **claude-mem-lite** | No prevent-compact warning. **No Windows support** (POSIX scripts only). |
| **MemPalace** | Doesn't prevent context loss — purely recovery via search. Heavy install (Python + ChromaDB + 300 MB ONNX model). Verbose output if you don't scope properly. |
| **Mem0** | Cloud lock-in for the SaaS path; self-host needs Docker + Postgres. Aimed at building agents, not maintaining Claude Code projects. |
| **ShieldCortex** | No prevent-compact warning. No live context-awareness. Rebranded mid-2026 (was Claude Cortex). |

---

## Where Scribe is the right tool

✅ You work on long-running projects in Claude Code (multi-day, multi-session)
✅ You want decisions and current focus tracked **in the repo** (git-trackable, human-readable)
✅ You want to know **before** context fills up, not after compact wipes your work
✅ You don't want a vector database, embedding model, cloud account, or API key in your stack
✅ You're solo or small team where the markdown audit trail = the source of truth

## Where Scribe is the WRONG tool

❌ You need semantic recall — "what did I decide six months ago about X?" — across thousands of past sessions. Use MemPalace (96.6% R@5) or Mem0 (93.4%).
❌ You jump between Claude Code, Cursor, and Codex daily — Scribe is Claude Code only. Use Mem0 or ShieldCortex.
❌ You want to build a custom agent with persistent memory — Scribe is for tracking project state, not building agent backbones. Use Mem0.
❌ You want one global memory across all projects — Scribe is per-project by design. Use claude-mem.

---

## The unique angle

The differentiator isn't "plain markdown." Lots of tools store markdown.

**The differentiator is prevention.** Every other plugin recovers from context loss. Scribe is the only one that:

1. Watches your context % live and warns at 30% / 40%
2. Auto-snapshots state before compact runs
3. Restores the snapshot on next session start

That single workflow — `30% warning → /handoff → next session resumes` — saves more work than perfect semantic recall ever could. Because by the time you need recall, the work is already lost.

---

## Sources

- claude-mem: https://github.com/thedotmack/claude-mem (verified April 28, 2026)
- claude-mem-lite: https://github.com/sdsrss/claude-mem-lite (verified April 28, 2026)
- MemPalace: https://github.com/MemPalace/mempalace (verified April 28, 2026)
- Mem0: https://github.com/mem0ai/mem0 (verified April 28, 2026)
- ShieldCortex: https://github.com/Drakon-Systems-Ltd/ShieldCortex (verified April 28, 2026 — was claude-cortex)

If anything in this comparison is wrong, file an issue at https://github.com/forty4420/project-scribe/issues — we'll fix it.
