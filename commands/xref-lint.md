---
description: Read-only cross-reference lint — orphan plans, stale memo links, missing status memos, and (low-confidence) decision contradictions. Reports findings as one markdown table. Never auto-fixes.
---

Invoke the `xref-lint` skill.

The skill will:
1. Bail silent if `docs/STATE.md` is missing (project not scribe-enabled).
2. Run four checks against the project's tracking artifacts:
   - **orphan-plan** — plan in `docs/plans/` with no spec ref or a broken spec ref (severity warn, confidence high).
   - **stale-memo-link** — file path inside `docs/status/*.md` that no longer exists (severity error, confidence high).
   - **missing-status-memo** — spec marked shipped in STATE.md's Specs index but no `docs/status/<slug>.md` exists (severity warn, confidence medium).
   - **contradiction** — DECISIONS.md entries with rule-shaped statements that look like opposing rules for the same subject (severity info, confidence always low).
3. Skip individual checks gracefully when their input is missing (e.g., no `docs/specs/` dir → orphan-plans check reports "skipped" rather than crashing).
4. Emit one markdown table with columns: check, severity, confidence, location, suggested action. Sorted error → warn → info.

Read-only. No edits, no auto-fix. The user decides what to do with each finding.
