---
description: Archive oldest entries from docs/DECISIONS.md to a per-year archive file when the live file grows past ~20K tokens. Entry-preserving — no rewrites, no merges.
---

Invoke the `compact-decisions` skill.

The skill will:
1. Count entries + tokens in `docs/DECISIONS.md`.
2. Propose a cutoff (default: last 12 months stay live, older moves to `docs/DECISIONS-archive-<YEAR>.md`).
3. Wait for approval of the table.
4. Move approved entries verbatim into archive file(s), update live file, add an Archive index section.
5. Offer a single scoped commit staging only scribe-owned files.

Never silent. Never merges or summarizes. Every entry preserved verbatim.
