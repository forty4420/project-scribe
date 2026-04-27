# Repo mining — ideas for Scribe

Running list. Each entry: source repo, idea, fit score, effort, notes.

Discuss + prune at end of mining session.

---

## From zilliztech/claude-context

| Idea | Fit | Effort | Notes |
|------|-----|--------|-------|
| Merkle-tree incremental reindex for archived decisions | Low | Medium | Overkill for ~20K-token DECISIONS.md. Skip unless file grows 10x. |

## From kitfunso/hippo-memory

| Idea | Fit | Effort | Notes |
|------|-----|--------|-------|
| Memory decay (last_used + hits frontmatter, score formula) | High | Done | Shipped this session — `compact-memory` Pass 0, `stop-mark-memory` hook, `mark-memory-used` skill. |
| Auto-consolidation HITL queue | Low | Medium | Premature — MEMORY.md not big enough yet. Revisit at >500 lines. |
| Retrieval-strengthening | High | Done | Folded into decay (hits bump on reference). |

## From mohi-devhub/antivibe

| Idea | Fit | Effort | Notes |
|------|-----|--------|-------|
| Add "alternatives considered" field to DECISIONS template | Medium | Small | Kills repeat debates. Cost = each entry slightly longer. |
| Phase-grouping output | None | — | Already in scribe status memos. |

## From mksglu/context-mode

| Idea | Fit | Effort | Notes |
|------|-----|--------|-------|
| PreCompact hook → write snapshot file (last prompt, focus, in-flight files, last 3 decisions) | High | Medium | Auto-handoff on compact, no user action. Pair with SessionStart restore. |
| Priority-tiered budget for MEMORY.md (P1/P2/P3, drop low first) | Medium | Small | Replaces dumb 200-line truncation with smart drop. |
| "Last user prompt" preservation in snapshot | High | Small | Freshest signal vs stale "Current focus". |
| Sandboxed tool exec (ctx_execute) | None | — | Different problem domain. Skip. |
| FTS5 knowledge base | None | — | DECISIONS.md too small to need BM25. Skip. |
| Auto-capture every tool event | None | — | Conflicts with scribe's "explicit log" philosophy. Skip. |

---

## From NateBJones-Projects/OB1 (Open Brain)

Repo = full agentic OS — Postgres + pgvector + Supabase + MCP gateway + Slack/Discord capture + dashboards. Wrong scale for Scribe (per-project plugin, no DB). Skip whole-system adoption. Mine sub-recipes only.

| Idea | Fit | Effort | Notes |
|------|-----|--------|-------|
| Open Brain core (Postgres+pgvector cross-tool brain) | None | — | Out-of-scope. Scribe lives in repo, not external DB. |
| Auto-Capture skill (jaredirish) — capture "ACT NOW" items + session summary at session end | High | Small | Same family as `auto-handoff`. Worth reading their prompt structure for ideas — esp. ACT NOW vs context separation. |
| Aiception/Claudeception (jaredirish) — extract reusable lessons from work session → new skill | Medium | Medium | Pairs with your existing `/learn` + `/compound`. Self-improving skill creation. Could borrow "extract pattern → propose new skill" workflow. |
| Panning for Gold (jaredirish) — mine brain dumps/transcripts for actionable ideas | Low | — | Closer to inbox triage. Tangential. |
| Content Fingerprint Dedup (alanshurafa) — SHA-256 dedup on thought ingestion | Medium | Small | Apply to MEMORY.md entries before insert. Cheap dup-prevention without HITL queue. |
| Schema-Aware Routing — LLM routes unstructured text across multiple tables | Medium | Medium | Scribe has multiple sinks (MEMORY.md, DECISIONS.md, status memos, plans). Could borrow pattern: classify input → route to right file. Better than current "user picks." |
| Daily Digest recipe — automated daily summary | Low | — | Already covered by status memos. |
| World Model Diagnostic / Work Operating Model skills | None | — | Different domain (operator/investor workflows). |

**Worth pulling from OB1:**
1. **Fingerprint dedup** — drop-in safety before any memory write. Prevents same lesson-learned getting written 3x.
2. **Schema-aware routing concept** — when user logs random thought, classify: belongs in DECISIONS? MEMORY? STATE next-up? Plan deferred? Currently scribe makes user choose. Could auto-suggest.
3. **Aiception pattern** — read workflow for "lesson → new skill" automation. Pairs with your existing self-improving-agent skill.

---

## From zilliztech/memsearch

Cross-platform semantic memory plugin (Claude Code / OpenClaw / OpenCode / Codex). Markdown source of truth, Milvus = "shadow index" (rebuildable cache). 3-layer recall: search → expand → transcript. Hybrid: BM25 + dense + RRF. SHA-256 chunk hashing skips unchanged content. ONNX bge-m3 default = 558MB local model. Heavy install — Python 3.10+, ChromaDB/Milvus, embedding model. Whole stack = wrong scale for Scribe. But architecture choices contain real lessons.

| Idea | Fit | Effort | Notes |
|------|-----|--------|-------|
| Whole-system adoption (Milvus + bge-m3 embeddings + Stop hook) | None | — | Heavy. Scribe stays markdown-only. |
| Markdown = source of truth, vector DB = shadow rebuildable index | Pattern | — | Architecture lesson. Confirms Scribe shouldn't bind logic to a DB. Already correct. |
| Daily-note files `memory/YYYY-MM-DD.md` with `<!-- session:UUID -->` anchors | High | Small | Daily-note layer already on list (from 6-Levels video). Anchor pattern = idea: machine-parseable session boundary in markdown. Cheap. Lets `auto-handoff` find "what happened this session." |
| SHA-256 content hashing on chunks — skip unchanged on re-index | High | Small | Same as OB1 fingerprint dedup but applied per-chunk not per-entry. For Scribe: hash each MEMORY entry; on re-write, skip identical. Prevents duplicate frontmatter bumps. |
| 3-layer progressive recall: search → expand chunk → full transcript | Medium | Medium | Pattern: don't load full thing, surface snippet, drill down on demand. Scribe could mirror: STATE.md summary → spec status memo → full plan/decisions. "Drill-down" is mostly there manually. Could formalize. |
| File watcher auto-indexes on .md change | Low | — | Requires daemon. Scribe = on-demand model. Skip. |
| Pluggable embedding providers (ONNX / OpenAI / Ollama / Voyage / Jina / Mistral / local) | None | — | No embeddings in Scribe. Skip. |
| LLM-summarized last-turn append to daily file | High | Medium | At Stop, summarize turn → 2-3 bullets → append `memory/YYYY-MM-DD.md`. Decay-friendly. Pairs with daily-notes layer. Cost = small Haiku call per Stop. Trade: tokens for memory quality. |
| Stop-hook driven capture (not user-action) | Done | — | Already shipped via stop-mark-memory. |
| Auto-recall on natural-language trigger ("we discussed X before, what was…") | Medium | Medium | Skill that detects retrospective phrasing → grep daily-notes + return matches. Lighter than vector search for small corpus. |
| `/memory-recall <query>` slash command | Medium | Small | Simple grep over daily notes + memory dir. Surface matches inline. Cheap to add. |

**Worth pulling:**

1. **Daily-note files with session anchor comment** — `memory/YYYY-MM-DD.md` with `<!-- session:UUID -->` markers. Anchor lets parsers find session boundaries. Pairs with daily-notes layer already on list.
2. **SHA-256 content hash on memory entries** — before write, hash; if hash unchanged, skip. Prevents redundant frontmatter mutation. Small primitive, big stability win.
3. **LLM-summarized turn → daily-note append on Stop** — bigger lift. Scribe doesn't currently capture session content, only state. This adds true session log without manual handoff. Cost: per-Stop Haiku call. Optional, gated by config.
4. **`/memory-recall` slash command** — grep daily-notes + memory dir for keyword matches. No vectors. Simple, useful.

Skip: Milvus/ChromaDB, embedding models, vector search infra, file-watcher daemon, multi-platform plugin matrix.

---

## From MemPalace/mempalace

Verbatim conversation recall via ChromaDB + SQLite knowledge graph. Wing/room/drawer scoping. 96.6% R@5 raw on LongMemEval. Heavy install (Python 3.9+, ~300MB embedding model, ChromaDB). 29 MCP tools. Wrong scale + wrong problem for Scribe — but few sub-patterns interesting.

| Idea | Fit | Effort | Notes |
|------|-----|--------|-------|
| Whole-system adoption (verbatim conversation recall + vector backend) | None | — | Scribe ≠ conversation recall. Skip. |
| Wing/room/drawer scoping (people/projects → wings, topics → rooms, content → drawers) | Low | — | Three-level scope is just nested folders. Scribe already does specs/plans/status. |
| Pluggable backend interface (`backends/base.py`) — swap ChromaDB without touching rest | Pattern | — | Architecture lesson, not direct steal. If Scribe ever grows storage layer, decouple it. |
| Temporal entity-relationship graph with validity windows (add, query, invalidate, timeline) | Medium | Big | Interesting for DECISIONS — "decision X was valid 2026-01 to 2026-04, superseded by Y." Would need new schema. Maybe overkill. |
| Auto-save hooks: periodic + pre-compression | Done | — | Scribe shipped Stop hook this session. Same family. |
| `mempalace sweep <transcript-dir>` — idempotent, resume-safe, one drawer per message | Medium | Medium | Idempotency pattern useful for stop-mark-memory. Currently substring-match could double-bump if same session loops. Add per-session dedupe key. |
| Agent diaries — each specialist agent gets its own wing | Low | — | Scribe doesn't run multi-agent. Skip. |
| Benchmark-driven development (LongMemEval, LoCoMo, ConvoMem, MemBench reproducible scripts) | Pattern | — | Discipline note: if Scribe grows complex, write benchmark before claiming improvement. |

**Worth pulling:**

1. **Idempotent + resume-safe sweep pattern** — current `stop-mark-memory` hook substring-matches on transcript. If transcript path stays same across multiple Stop fires in one session, file gets bumped multiple times. Add session dedupe: track which (transcript_path, file) pairs already bumped today. Cheap fix.
2. **Temporal validity windows on DECISIONS** — `valid_from: 2026-01-15`, `superseded_by: <id>` fields. Lets you query "what was true on 2026-03-01" cleanly. Optional, only if Scribe grows audit-trail use cases.
3. **Pluggable-backend discipline** — pure architecture lesson. Don't refactor now. Note for later if storage layer expands.

Skip: vector search, ChromaDB, Python deps, MCP tool surface, knowledge graph in SQLite.

---

## From karpathy/llm-wiki gist

Pattern: persistent compounding knowledge artifact. Three layers — raw sources (immutable), wiki (LLM-owned markdown), schema config (CLAUDE.md/AGENTS.md). Ingest writes/updates 10-15 wiki pages + appends log entry. Query searches `index.md`, synthesizes with citations.

| Idea | Fit | Effort | Notes |
|------|-----|--------|-------|
| Three-layer split: raw / wiki / schema | Partial | — | Scribe already has equivalent: external sources / docs/STATE+DECISIONS / CLAUDE.md+rules. Confirms shape. |
| `index.md` content catalog with one-line summaries + metadata | High | Small | Scribe's STATE.md lacks per-file metadata. Could enrich with last-touched date, summary line. Already does specs/plans index tables. |
| `log.md` append-only chronological record, parseable format `## [DATE] operation \| title` | High | Small | Scribe DECISIONS.md is close but mixed-format. Status memos are date-keyed but per-spec, not project-wide. Single project-wide append-only log = useful new artifact. |
| Multi-page update on single ingest — cross-reference maintenance | Medium | Medium | When DECISIONS entry lands, scan plans/specs for affected files, prompt to update. Manual today. |
| Lint pass: contradictions, stale claims, orphan pages, missing cross-refs | High | Medium | Scribe has piecemeal lint (reconcile-project-state, base-audit) but no "find contradictions across DECISIONS" pass. Worth adding. |
| Hybrid indexing — text index now, vector at scale | None | — | Wrong scale for Scribe. Skip vector. |
| Wiki-pattern whole adoption (raw/ + wiki/ folders) | None | — | Scribe = operational memory, not research wiki. Skip. |

**Worth pulling:**

1. **Project-wide append-only `log.md`** — chronological event log, parseable. `## YYYY-MM-DD shipped | <spec-name>` / `## YYYY-MM-DD decided | <decision-title>` / `## YYYY-MM-DD deferred | <item>`. Replaces git-log-grep with intentional record. Pairs with `update-project-state` reconcile.
2. **Cross-reference lint** — single skill scans DECISIONS for contradictions ("decision A says X, decision B says not-X"), orphan plans (plan with no spec ref), stale memo links. Run on `auto-handoff`.
3. **Per-entry metadata in indexes** — STATE.md spec/plan tables already exist. Add `last_touched`, `status`, one-line summary. Tiny lift.

---

## From "skill chaining / context fork" video (transcript)

Topic: skill bloat at scale. Three-layer fix: (1) context fork in YAML frontmatter — skill runs in subagent fork, results don't bleed to main context, (2) file handoff between steps — temp dir, write minimal JSON per step, next step reads only what it needs, (3) bang commands `` `!cat file.json` `` — programmatic shell substitution at zero token cost, no Claude judgment burned. Demo: lead-research skill 51K tokens → 5-8K (85% reduction).

Not memory-system content. Skill-design discipline. Relevant for Scribe because Scribe IS skills.

| Idea | Fit | Effort | Notes |
|------|-----|--------|-------|
| Context fork in YAML frontmatter — skill runs in subagent, output filtered back | High | Small | Scribe skills run inline. Big ones (`compact-memory`, `auto-handoff`, `update-project-state`) bloat caller context with intermediate work. Fork = one-line YAML add. Audit which skills should fork. |
| File handoff between chained steps — temp dir, minimal JSON per step | Medium | Medium | Scribe skill chains light today. But `auto-handoff` already orchestrates multiple sub-skills (reconcile + compact + state-update + handoff-write). Could route intermediates through `.scribe/tmp/` instead of inline. |
| Bang commands — `` `!cat .scribe/state.json` `` substitutes file content at parse-time, zero tokens | High | Small | Big win for Scribe SessionStart. Currently bash hook builds reminder + escapes JSON manually. Bang-command substitution from skill body = cleaner. Also useful in `reconcile-project-state` to inject git-log without making Claude read it. |
| Sub-skills as composable atoms vs monolith skill | Medium | Medium | Matches deep-modules philosophy. Scribe's `auto-handoff` is monolith-ish. Could extract `capture-pending-decisions`, `prune-memory`, `write-handoff-doc` as fork-ables. |
| "Find as of today" / "in 2026" cadence-anchor when Claude makes architecture calls | Low | — | General prompt hygiene. Not Scribe-specific. |
| Temp-dir housekeeping (cron clear of `.scribe/tmp/`) | Medium | Small | If file-handoff adopted, need cleanup. Cheap. |
| Observability per-skill (token usage, run count) | Low | — | Out-of-scope for plugin. User-level concern. |

**Worth pulling:**

1. **Context fork audit** — review every Scribe skill, mark which should run as subagent fork. Heavy ones (`compact-memory`, `auto-handoff`, `consolidate-memory`) = good fork candidates. Light ones (`log-decision`, `mark-memory-used`) = stay inline. One-line YAML change per skill.
2. **Bang-command substitution in skills + hooks** — replace manual cat-and-escape patterns with `` `!cat path` `` substitution. Cleaner skill bodies, zero token cost on injection. Audit `reconcile-project-state`, `update-project-state`, `auto-handoff` for candidates.
3. **File-handoff convention for chained skills** — define `.scribe/tmp/` as workspace for skill chain intermediates. Document in init-project-scribe. Add `.gitignore` entry. Keeps multi-step skills from bloating context.
4. **Sub-skill extraction** — break monolith skills (esp. `auto-handoff`) into composable forked atoms.

Skip: lead-research-specific patterns, observability tooling, cron schedule.

---

## From "6 Levels of Claude Code Memory" video (transcript)

Surveys: Pavl Hurin pattern, John Connelly hook, openclaw, memsearch (Zilliz), Claude Mem, Me Palace, Carpathy LLM wiki, Recall, LightRAG, Open Brain (Nate Jones), Mem0.

| Idea | Fit | Effort | Notes |
|------|-----|--------|-------|
| `claude/memory/` index pattern: MEMORY.md as table-of-contents only, per-topic files loaded on demand | Partial-match | — | Scribe already does this. Confirms pattern. |
| Domain/tool subfolders: `domain/topic.md`, `tools/slack.md` — granular, one file per topic | Medium | Small | Could enrich scribe memory layout. Currently flat dir. |
| "Reorganize memory" command — read all memory, dedupe, merge, split, restore by date, update index | Done | — | Existing `consolidate-memory` + `compact-memory` skills cover this. |
| SessionStart hook auto-injects MEMORY.md index (not full content) | Done | — | Scribe SessionStart hook already injects state directive. |
| Anthropic's unreleased "Chyros" daemon — always-on, watches project, consolidates while idle | Watch | — | Future Anthropic feature. May obviate custom solutions. |
| openclaw's "dreaming" — background scoring promotes recurring daily-note patterns into MEMORY.md, prunes stale | High | Medium | Same family as decay we shipped. Promotion path missing — daily notes never get promoted to long-term. Could add. |
| Daily-notes layer — one file per date, running log of what shipped/decided/failed | High | Small | Scribe has status memos per-spec but not date-keyed daily log. Could pair with decay. |
| memsearch — semantic chunking + BM25/vector search via UserPromptSubmit hook, top-3 auto-inject | Low | Big | Heavy install. Scribe's memory dir small. Skip until pain real. |
| Me Palace — verbatim conversation recall via SQL+Chroma, wing/room/drawer index | None | — | Wrong problem. Scribe = decisions/state, not conversation transcript recall. |
| Carpathy LLM wiki — raw/wiki folder split, Claude writes wiki, never raw | None | — | Knowledge base ≠ operational memory. Skip. |
| Open Brain — Postgres on Supabase, cross-tool MCP layer | None | — | Cross-tool portability irrelevant to Scribe (per-project plugin). |
| Mem0 SaaS | None | — | Vendor lock + data on their servers. Skip. |

**Concrete additions worth considering:**

1. **Daily-notes layer** — `memory/daily/YYYY-MM-DD.md` running log. Decay scoring already there will prune stale dailies.
2. **Promotion path (dreaming-lite)** — pattern that appears in N daily notes gets promoted to a topical memory file. Manual trigger first, automate later.
3. **Domain/tool subfolder convention** — document in `init-project-scribe`. Don't enforce, just suggest.

---

---

## Discussion notes

- Decay shipped untested in prod. Verify on real session before bundling more changes.
- Plugin v0.4.1 → bump when next batch ships. Probably 0.5.0.
