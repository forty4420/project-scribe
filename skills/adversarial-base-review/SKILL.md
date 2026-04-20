---
name: adversarial-base-review
description: Run a contrarian review on diffs that touch base-scope paths or locked-rule files. Challenges the change against VISION rules, BASE_ALLOWLIST, and locked rules. Use before committing diffs under src-tauri/src/, src/components/, docs/BASE_ALLOWLIST.md, docs/v3/VISION.md, CLAUDE.md Locked section. Triggers: "adversarial review", "challenge this change", "check against vision", "base audit".
---

# Adversarial base-scope review

Contrarian second opinion on changes that touch policy or base code. Opposite of a normal review — this one actively argues AGAINST the change and looks for VISION rule drift.

## When to invoke

- Before committing any diff touching:
  - `src-tauri/src/**` (ownterm base Rust)
  - `src/components/**` (ownterm base frontend)
  - `docs/BASE_ALLOWLIST.md`
  - `docs/v3/VISION.md` (or any file named `VISION.md`, `RULES.md`, `POLICY.md`)
  - `CLAUDE.md` Locked / "don't re-argue" sections
  - `DECISIONS.md` when adding entries that modify locked rules
- On user request: "adversarial review", "challenge this", "base audit", "check against vision"
- As optional `[HITL]` gate when `tag-plan-tasks` flags a task in one of the categories above

## Pre-flight

1. Ensure there's a diff to review. Run `git diff --stat` — if empty, ask user which commit/branch/PR to review. Accept `<sha>`, `<branch>`, `HEAD~N`, or `--cached`.
2. Ensure `docs/BASE_ALLOWLIST.md` exists (confirms this is an allowlist-governed project). If not → fallback to generic adversarial review, note the absence.
3. Find the VISION file: prefer `docs/v3/VISION.md`, fall back to any `VISION.md` at repo root. If none exists → skip VISION-specific checks, note the absence.

## Review passes

Run these in order. For each pass, produce `FINDING:` lines only when something is off — no "all good" fluff.

### Pass 1: Base-allowlist violation
- Parse BASE_ALLOWLIST.md for allowed/NOT-allowed path globs.
- Check every new file in diff against NOT-allowed list.
- FINDING if new file in NOT-allowed path without matching DECISIONS.md entry.
- FINDING if file moved OUT of allowlist (deleted from allowed path) without DECISIONS entry.

### Pass 2: Locked-rule conflict
- Read `CLAUDE.md` (project-level) Locked section fully.
- For each locked rule, ask: does this diff violate the rule directly OR weaken the intent?
- FINDING example: Locked rule "no cloud relay for remote access" — diff adds HTTP call to external service → violation (maybe for unrelated reason; flag anyway).
- FINDING if diff silently deletes a locked rule from CLAUDE.md.
- FINDING if diff's commit message argues against a locked rule without DECISIONS.md first.

### Pass 3: VISION drift
- Read VISION.md if present. Focus on any sections numbered as "rules" (e.g. §7).
- Check each rule against diff behavior.
- FINDING if diff appears to contradict a VISION rule.
- FINDING if diff adds functionality to base that VISION explicitly names as plugin territory.

### Pass 4: DECISIONS-log gap
- If diff makes a durable choice (new architectural pattern, new dependency, policy change, trade-off), check `docs/DECISIONS.md` last 20 entries for a matching log entry.
- FINDING if decision-shaped change lacks DECISIONS entry.

### Pass 5: Scope creep
- Measure diff fan-out: how many top-level directories touched?
- FINDING if diff description is "fix X" but touches > 5 unrelated modules.
- FINDING if diff mixes refactor + feature + bug fix (should be separate commits).

### Pass 6: Reversibility
- FINDING if diff deletes a spec/plan file from `docs/superpowers/` without moving it to `archive/` or noting in DECISIONS.
- FINDING if diff force-modifies git history (amend a published commit).
- FINDING if diff removes a `#[cfg(test)]` gate or test file without adding equivalent coverage.

## Output format

```
Adversarial base review — <branch> (diff: N files, M lines)

Passes run: allowlist, locked, vision, decisions, scope, reversibility

FINDINGS:

[CRITICAL] <rule/pass> — <one-line description>
  File: <path>:<line>
  Why this blocks: <one sentence>
  To proceed: <what user must do — DECISIONS entry, VISION update, rule removal, etc.>

[WARN] <rule/pass> — <one-line description>
  File: <path>
  Why: <one sentence>

[INFO] <note that may not block but worth seeing>
```

If no findings: output single line `No adversarial findings — diff aligns with base allowlist, locked rules, and VISION.`

## Severity

- **CRITICAL** = blocks commit. VISION rule violation, allowlist breach, locked-rule erasure.
- **WARN** = user should review but can override. Scope creep, missing DECISIONS entry.
- **INFO** = observation only.

## Integration with codex plugin (optional)

If the `codex` plugin is installed AND the user requests deeper review, delegate pass 2-3 to `/codex:adversarial-review` with focus text:

```
Focus: locked-rule drift, VISION §N violations, base-allowlist breach. Repo root: <cwd>. Diff: <git diff output>.
```

Merge codex findings into this skill's output under a `[CODEX]` prefix.

## Don't

- Do not auto-block commits. Output findings; user decides.
- Do not modify any files. Read-only skill.
- Do not rewrite history or propose `git reset`.
- Do not flag cosmetic issues (whitespace, formatting) — that's for other skills.
- Do not replicate full codex review. This skill's value is VISION/locked-rule awareness; codex handles code quality.
