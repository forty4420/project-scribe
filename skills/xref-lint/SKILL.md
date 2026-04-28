---
name: xref-lint
description: Read-only lint for project artifact cross-references. Scans docs/plans, docs/specs, docs/status, DECISIONS.md, and STATE.md for orphan plans, stale memo links, missing status memos, and (low-confidence) decision contradictions. Reports findings as a markdown table — never auto-fixes. Triggers include "lint xref", "xref lint", "/xref-lint", "check cross-references", "audit project artifacts".
---

# xref-lint — cross-reference linter for scribe-tracked projects

Read-only audit. Walks the project's tracking artifacts and surfaces inconsistencies. The user decides what to do with each finding — this skill never edits anything.

## Hard rules — never violate

- **Read-only.** No edits, no auto-fix, no "while we're here" cleanup. Every finding is advisory.
- **Skip the entire skill if `docs/STATE.md` is missing.** Project is not scribe-enabled — emit one line and stop:
  ```
  xref-lint: docs/STATE.md not found — project is not scribe-enabled. Skipped.
  ```
- **Skip individual checks gracefully** when the input directory or file they need is missing. Report the skip in the table (severity `info`, location = the missing path) rather than crashing or omitting the row silently. Example: no `docs/specs/` dir → orphan-plans check emits one row with action "specs dir not found, skipped".
- **Confidence-tag every finding.** Every row in the output table carries a confidence column (`high` / `medium` / `low`). The contradiction probe is **always `low`** — false positives expected, never auto-resolve.
- **No new files.** Output is one markdown block to the chat. Don't write a report file. Don't touch `docs/` artifacts.

## When to invoke

- User says: "lint xref", "xref lint", "/xref-lint", "check cross-references", "audit project artifacts", "are the docs consistent"
- (Deferred — not wired in this phase.) `auto-handoff` may invoke this as a quality gate before writing the handoff doc. Document this here so a future session knows the contract: when `auto-handoff` calls `xref-lint`, treat any `error`-severity finding as a soft block (surface to user, ask whether to proceed). For now this skill stands alone.

## Pre-flight

1. Confirm `docs/STATE.md` exists in cwd. If missing → emit the skip line above and STOP.
2. Note which of the four input sources are present. This drives the per-check skip decisions.
   - `docs/plans/` — needed for orphan-plans check
   - `docs/specs/` — needed for orphan-plans check
   - `docs/status/` — needed for stale-memo-links check and missing-status-memo check
   - `docs/DECISIONS.md` — needed for contradiction probe
   - `docs/STATE.md` Specs index block — needed for missing-status-memo check
3. Today's date = current ISO date. (Used only if you want to flag stale snapshots — not required for these four checks.)

## Check 1 — Orphan plans (severity: warn, confidence: high)

**Definition:** A file in `docs/plans/` whose top of file does not reference an existing spec under `docs/specs/`.

**Skip conditions:** `docs/plans/` missing, OR `docs/specs/` missing. Emit one info row and move on.

**Detection:**

1. List every `*.md` file in `docs/plans/` (non-recursive).
2. For each plan file, read the first 10 lines.
3. Look for a spec reference. Accepted shapes:
   - `**Spec:**` followed on the same line by a path (e.g. `**Spec:** \`docs/specs/2026-04-18-project-scribe-v1-design.md\``)
   - A bare path like `docs/specs/<filename>.md` appearing in those first 10 lines
4. Resolve the referenced path:
   - If no reference at all → orphan, action "no Spec ref found in first 10 lines — link a spec or note it's spec-less in the plan body"
   - If reference present but file does not exist on disk → orphan, action "Spec ref points to missing file `<path>` — fix the path or restore the spec"
   - If reference present and file exists → not orphan, no row.

**Confidence:** `high` for both orphan shapes. The detection is deterministic: either the path string is present and resolves, or it isn't.

**Severity:** `warn`. Orphan plans aren't broken — they're just untracked. User can either add the spec link or accept the plan as standalone.

## Check 2 — Stale memo links (severity: error, confidence: high)

**Definition:** A status memo in `docs/status/` references a file path that does not exist on disk.

**Skip conditions:** `docs/status/` missing. Emit one info row and move on.

**Detection:**

1. List every `*.md` file in `docs/status/` (non-recursive). Skip `README.md` and `TEMPLATE.md` if present (those are scaffolding, not memos).
2. For each memo, scan the full file body for path-like tokens matching this regex (case-sensitive):
   ```
   \b[\w./-]+\.(md|rs|ts|tsx|toml|json)\b
   ```
   This catches paths like `docs/specs/foo.md`, `src/lib.rs`, `Cargo.toml`, `package.json`.
3. For each matched token:
   - Skip if it looks like a URL fragment (preceded by `://` or starts with `http`).
   - Skip if it's a code-fence example (inside a fenced ``` block) — best-effort detection by tracking fence state while scanning.
   - Skip if it's a glob (contains `*` or `?`).
   - Otherwise, resolve relative to the project root and check existence.
4. If the path does not exist → one row per stale link.

**Confidence:** `high`. File-existence is binary.

**Severity:** `error`. Stale links inside a status memo mean the audit trail is broken — high signal.

**Cap:** if more than 20 stale links across all memos, group them: emit one row per memo summarizing "<N> stale links" with location = memo filename, and let the user open the file to see the list. Avoid table flood.

## Check 3 — Missing status memo (severity: warn, confidence: medium)

**Definition:** A spec marked shipped in STATE.md's Specs index has no corresponding status memo at `docs/status/<spec-slug>.md`.

**Skip conditions:** STATE.md has no Specs index block (fuzzy heading match: `Specs`, `Specs index`, `Spec status`). Emit one info row.

**Detection:**

1. Locate the Specs block in STATE.md. Parse rows. Each row is expected to look like a markdown table or bullet entry mentioning a spec filename and a status keyword.
2. For each entry where the status reads `shipped` (case-insensitive) — accept variants `Shipped`, `SHIPPED`, `shipped ✅`:
   - Derive the spec slug. The slug is the spec's filename minus the `.md` extension and minus any leading date prefix.
     - Example: `2026-04-18-project-scribe-v1-design.md` → slug `project-scribe-v1-design` (strip the `YYYY-MM-DD-` prefix).
     - If no date prefix present, use the full basename minus `.md`.
   - Look for `docs/status/<slug>.md`. Accept exact match OR a memo whose filename starts with the slug (e.g. `docs/status/project-scribe-v1-design-postmortem.md`).
3. If no matching memo → one row per shipped-but-undocumented spec.

**Confidence:** `medium`. Slug derivation is a heuristic — false positives possible if the user named their memo differently. Suggest as candidate, not as definite finding.

**Severity:** `warn`. Missing memo isn't broken state, it's an audit-trail gap.

## Check 4 — Contradiction probe (severity: info, confidence: low)

**Definition:** Two DECISIONS.md entries that look like they assert opposing rules for the same subject.

**Why low-confidence:** Natural language similarity is fuzzy. Two entries can use the same words about different topics (e.g. "always run tests in CI" vs "never run tests on Windows in CI" are not contradictions — they cover different scopes). This check produces *candidates* for the user to eyeball. Never claim a contradiction exists; claim a *possible* contradiction.

**Skip conditions:** `docs/DECISIONS.md` missing.

**Detection (intentionally narrow to keep false positives low):**

1. Parse DECISIONS.md into entries. Entry boundary: `## YYYY-MM-DD — <title>`.
2. For each entry, extract the **Decision:** field body (the prose under the `**Decision:**` marker, up to the next blank line followed by `**`).
3. Within each Decision body, look for **rule-shaped statements** matching one of these patterns (case-insensitive):
   - `\b(always|must|require[ds]?|need[s]? to)\s+(\w+(?:\s+\w+){0,5})`
   - `\b(never|do not|don't|must not|cannot|can't)\s+(\w+(?:\s+\w+){0,5})`
4. Normalize the captured object phrase (the 1-6 words after the verb): lowercase, strip punctuation, drop stopwords (`the`, `a`, `an`, `to`, `of`, `for`).
5. Build two indices:
   - `positive[phrase] = list of (entry_title, snippet)` for `always/must/require` matches
   - `negative[phrase] = list of (entry_title, snippet)` for `never/don't/must not` matches
6. Compute the intersection of phrase keys between `positive` and `negative`. For each shared phrase, that's a candidate contradiction.

**Output one row per candidate**, location format = `<title-A> vs <title-B>`, action = "review both entries — confirm whether they cover the same subject; if yes, write a superseding decision, if no, ignore this finding".

**Hard caps to avoid noise:**
- Cap at 5 candidate rows. If more than 5, emit one summary row "5+ candidate contradictions in DECISIONS.md — re-run after manually reviewing the first batch".
- If the same phrase appears in both positive and negative lists from the **same entry**, skip it. That entry is internally explaining a rule plus its exception, not contradicting itself.
- Skip phrases shorter than 2 words after stopword removal — too generic.

**Confidence:** Always `low`. Always.

**Severity:** `info`. Never warn or error. The user must read both entries.

## Output format

One markdown block. Lead with a one-line summary. Then the table. Columns in this exact order:

```
## xref-lint findings

<N total: X errors, Y warns, Z infos>

| Check | Severity | Confidence | Location | Suggested action |
|-------|----------|------------|----------|------------------|
| orphan-plan       | warn  | high   | docs/plans/foo.md                          | No Spec ref found in first 10 lines — link a spec or note it's spec-less |
| orphan-plan       | warn  | high   | docs/plans/bar.md                          | Spec ref points to missing file docs/specs/dead.md — fix path or restore |
| stale-memo-link   | error | high   | docs/status/feat-x.md → src/old.rs         | File no longer exists — update memo or remove the reference |
| missing-status-memo | warn | medium | spec: 2026-04-18-thing.md (shipped)        | No memo at docs/status/thing.md — write one or rename memo to match slug |
| contradiction     | info  | low    | "Always use jq" vs "Never use jq on Win"   | Review both entries — confirm same subject before treating as contradiction |
| (skip)            | info  | high   | docs/specs/                                | specs dir not found, orphan-plans check skipped |
```

If zero findings: emit `## xref-lint findings\n\nAll cross-references look consistent. No action needed.`

## Sort order

Within the table, sort by severity descending (`error` first, then `warn`, then `info`). Within each severity tier, sort by check name alphabetically, then by location. This puts the most actionable items at the top.

## Don't

- Don't propose fixes the user didn't ask for. The "Suggested action" column is one short sentence — never a multi-step plan.
- Don't auto-resolve any finding, especially contradictions. The whole point is the user decides.
- Don't flag the same finding twice (e.g. one row per occurrence of the same stale link in the same memo — collapse into one row).
- Don't crash on malformed input. A status memo with binary garbage in it: emit one row "could not parse <file>" with severity info, continue.
- Don't run any of these checks if STATE.md is missing. The pre-flight check is absolute.
- Don't include code-fenced examples (inside ``` blocks) when scanning for stale-memo-links. They're documentation, not live references.
- Don't claim contradictions are real. The output text for contradiction rows must say "candidate" or "possible," never "found a contradiction."

## Future expansion (not in this phase)

- DECISIONS.md entries marked `**Superseded by:**` should resolve — the linked entry must exist. Flag as `error` if not. (Defer: needs robust supersede-link parsing.)
- Plans whose top-of-file lists `Status: shipped` but DECISIONS.md has no closing entry. (Defer: needs reliable status-line parsing.)
- Specs with no plan referencing them (reverse orphan check). (Defer: low signal — many specs intentionally have no implementation plan yet.)
