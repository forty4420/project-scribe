---
name: base-audit
description: Self-critic pass that checks the current branch's diff against docs/BASE_ALLOWLIST.md and VISION rule-violations before commit. Use when the user says "audit", "check for drift", "did I violate any rules", "/audit", or before any commit that touches src-tauri/src/ or src/components/. Invoke preemptively before claiming work is complete.
---

# /audit — VISION rule-drift self-critic

Purpose: catch rule-drift before commit. The audit reads `docs/BASE_ALLOWLIST.md` if present, inspects the current branch's changes, and flags any new files or directories that violate the project's locked rules.

This is a **critic pass**, not an authority. Output is a report — Michael decides what to fix.

## When to run

- **Before any commit** that touches `src-tauri/src/`, `src/components/`, or that adds new top-level directories.
- **On user request:** "/audit", "audit this branch", "check for rule drift", "did I just violate VISION".
- **After implementing a plan** — preemptive, before reporting "done."

Skip if:
- The project has no `docs/BASE_ALLOWLIST.md` (not a scribe-enabled project with base-scope enforcement).
- The diff touches only docs, tests, configs, or plugin directories.

## Procedure

### Step 1 — Confirm this project uses base-scope enforcement

```bash
test -f docs/BASE_ALLOWLIST.md || { echo "No BASE_ALLOWLIST.md — audit skill not applicable to this project."; exit 0; }
```

### Step 2 — Gather the diff

```bash
# Get files added/modified relative to main branch (or current branch base)
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
git diff --name-status "$BASE_BRANCH"...HEAD
git diff --name-status --cached  # Also include staged-but-not-committed
git diff --name-status           # Also include unstaged-but-present
```

### Step 3 — For each new file under a guarded path, classify

Guarded path prefixes (read from BASE_ALLOWLIST.md if you want to be robust, or use these defaults):

- `src-tauri/src/`
- `src/components/`

For each newly-added or modified file under those prefixes:

1. Extract the path.
2. Look up BASE_ALLOWLIST.md. Is the path (or its parent directory) explicitly listed in an "allowed" section?
3. If yes → pass.
4. If no → check the "NOT allowed" section. If listed there, emit a **HIGH** violation. Else emit a **NEEDS-REVIEW** note (new path not yet classified).

### Step 4 — Check for locked-rule keyword hits in the diff

Quick grep pass for patterns that often indicate rule violations:

```bash
# New Provider-shaped files outside ~/.ownterm/
git diff "$BASE_BRANCH"...HEAD -- src-tauri/src/providers/ | grep -E "^\+" | head -5
# New Tool files
git diff "$BASE_BRANCH"...HEAD -- src-tauri/src/tools/    | grep -E "^\+" | head -5
# New persona fields
git diff "$BASE_BRANCH"...HEAD -- src-tauri/src/persona/  | grep -E "^\+" | head -5
```

Emit **NOTE** if any of these have non-trivial changes.

### Step 5 — Check spec discipline

For every modified spec file under `docs/superpowers/specs/`:

- Does the spec contain `## Origin` section?
- Does the spec contain `## Constitution check` section?
- If either missing → **MED** violation.

### Step 6 — Report

Output a single markdown block:

```markdown
## Audit Report

**Branch:** <current branch>
**Base:** <base branch>
**Files analyzed:** <count>

### Violations

- [HIGH/MED/NEEDS-REVIEW] <path> — <reason> — <suggestion>
- ...

### Clean

- <count> files checked, no issues

### Recommendations

- <one-liner actions Michael should take>
```

If no violations: short one-liner "Audit clean." No ceremony.

## What this skill does NOT do

- Does not edit files. Read-only.
- Does not run tests or builds.
- Does not autofix anything.
- Does not speak to the PreToolUse hook — that's a separate enforcer. This skill complements it by catching things the hook can't see (staged commits, renamed files, semantic violations in content).

## Interaction with the PreToolUse hook

PreToolUse catches individual Write/Edit calls during a session. This skill catches violations that:
- Made it past the hook (e.g. the hook wasn't armed)
- Span multiple commits on a branch
- Are semantic (new persona field inside an allowed file)

Run this skill before a commit even if the hook has been running cleanly. Belt and suspenders.
