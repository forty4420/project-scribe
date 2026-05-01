# /scribe-verify — Design Spec

> **Source:** Backlog item #2 from `docs/research/2026-04-29-youtube-mining/synthesized-recommendations.md` §6 — Boris/Anthropic signal 9/10 ("verification-led development, structured CLAUDE.md files"). Brainstormed 2026-04-30.

## Problem

Scribe trusts what STATE.md says shipped. STATE drift, lying-by-omission ("forgot tests fail"), or stale "Last shipped" SHAs go undetected until the next reconcile or smoke test catches them. No automated way to ask "is the most recent ship-claim actually true?"

## Goal

Add `/project-scribe:scribe-verify` — a read-only diagnostic that reads STATE.md "Last shipped" claim, runs the project's verify command, checks git drift since the claimed SHA, and reports findings + suggested fixes. Catches drift before user notices.

## Non-goals

- **Not** a CI-status checker. GitLab/Bitbucket users excluded by GitHub coupling. Defer to a separate command if demand surfaces.
- **Not** a fixer. Read-only — surfaces drift, suggests fixes, but never edits STATE.md or commits.
- **Not** a test runner replacement. Wraps the project's verify command; doesn't define one.
- **Not** worktree-aware. Per the 2026-04-30 skip decision, defer worktree-specific behavior.

---

## Architecture

**Approach: Skill + helper bash script (Approach B from brainstorm).**

Heavy logic in bash for speed, determinism, testability. Skill stays thin (instructs Claude to invoke script and surface output). Sets precedent for `scripts/` dir for future cmds (#3 Context Audit, #4 token-budget tab likely candidates).

### File layout

```
scripts/
└── scribe-verify.sh                # heavy lifting

skills/scribe-verify/
└── SKILL.md                        # thin wrapper

commands/
└── scribe-verify.md                # /project-scribe:scribe-verify slash command (.md per scribe convention)

tests/
├── scripts/
│   └── scribe-verify.bats          # bash logic — sandbox + fixtures (~16 cases)
└── skills/
    └── scribe-verify.bats          # skill contract (~3 cases)
```

### Data flow

```
User → /project-scribe:scribe-verify
  ↓
slash command (.md) → loads skill
  ↓
SKILL.md → Claude invokes `bash $CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh`
  ↓
script:
  1. Resolve verify cmd (4-step hybrid)
  2. Parse STATE.md Last shipped SHA (with fuzzy fallback)
  3. Run verify cmd, 5min timeout (env override)
  4. Git diff claimed SHA..HEAD + working-tree status
  5. Emit markdown report w/ suggested fixes to stdout
  ↓
Claude surfaces markdown verbatim — no editorializing
```

**Read-only.** No file mutations. Matches `scribe-status` + `xref-lint` precedent.

---

## Verify command resolution (hybrid 4-step)

Resolution order — first match wins:

1. **`docs/.scribe-verify.sh`** if exists + executable → run it. User-explicit, highest precedence. Single bash file, exit code = pass/fail.
2. **`CLAUDE.md` `## Verify` section** if present → parse first fenced code block. Pattern: `awk` extracts content between `^## Verify` (case-insensitive) and next `^## ` heading. First triple-backtick block content → temp file → exec.
3. **Auto-detect** from project files (first match wins):
   - `package.json` → `npm test`
   - `Cargo.toml` → `cargo test`
   - `pyproject.toml` → `pytest` (fall back `python -m pytest`)
   - `Makefile` with `^test:` target → `make test`
   - `go.mod` → `go test ./...`
   - `Gemfile` → `bundle exec rake test` (fall back `rake test`)
   - `composer.json` → `composer test`
   - `mix.exs` → `mix test`
   - `pubspec.yaml` → `flutter test` (fall back `dart test`)
4. **No match** → exit 2 with report listing what was tried + offering fix:
   ```
   ❌ No verify command found.

   Tried:
   - docs/.scribe-verify.sh (not present)
   - CLAUDE.md ## Verify section (not found)
   - Auto-detect: no recognized project file

   → Create docs/.scribe-verify.sh with your project's test/build command.
   → Or add a `## Verify` section to CLAUDE.md with a fenced code block.
   ```

Result emitted in report header:
```
Verify command: `npm test`
Source: auto-detected from package.json
```

---

## STATE.md SHA parsing

Same fuzzy heading match as `reconcile-project-state` skill — accept `## Last shipped`, `## Shipped`, `## Recently shipped`, `## Recent commits`. Take first 5 bullets.

For top bullet, attempt SHA extraction:

1. **Explicit short-SHA** — regex `\b[0-9a-f]{7,40}\b`. First match wins (handles backtick-wrapped too).
2. **Fuzzy version-label fallback** when no SHA found:
   - Extract version-like token: regex `v?\d+\.\d+\.\d+`.
   - `git log --all --oneline --grep="$version"` — count matches.
     - **0 matches** → mark "unmatched."
     - **1 match** → use, disclose `*Claimed SHA matched via fuzzy version-label search for "vX.Y.Z" — disclose for transparency.*` in report.
     - **2+ matches** → verdict = ⚠️ ambiguous, abort drift checks (sections 1-3), report Section 0 with candidate list, exit with code 1.

**Honesty contract:** No silent guessing on multi-match. User resolves STATE first, re-runs.

---

## Drift detection

Three checks against claimed SHA:

```bash
# Check 1: claimed SHA exists
git cat-file -e "$claimed_sha^{commit}" 2>/dev/null

# Check 2: count commits between claimed and HEAD
ahead=$(git rev-list --count "$claimed_sha..HEAD")

# Check 3: working-tree status
git status --porcelain   # empty = clean
```

### Verdict matrix

| Verify cmd | SHA found | Ahead | Tree   | Verdict |
|------------|-----------|-------|--------|---------|
| pass       | yes       | 0     | clean  | ✅ all green |
| pass       | yes       | 0     | dirty  | ⚠️ uncommitted changes (file list embedded) |
| pass       | yes       | >0    | *      | ⚠️ commits ahead of claim (commit list embedded) |
| pass       | no        | n/a   | *      | ⚠️ claimed SHA missing |
| fail       | *         | *     | *      | ❌ verify failed (last 30 lines stderr+stdout) |
| timeout    | *         | *     | *      | ❌ verify timed out |
| ambiguous fuzzy | n/a  | n/a   | n/a    | ⚠️ ambiguous SHA (Section 0 only, drift checks aborted) |

**Working-tree dirty handling:** include `git status --porcelain` file list verbatim in report. No auto-classify benign-vs-real — user judges from file list.

---

## Markdown report shape

Single doc, sections always present (skipped sections explicit):

```markdown
# /scribe-verify — <verdict-glyph> <one-line-summary>

**Verify command:** `<cmd>`
**Source:** <docs/.scribe-verify.sh | CLAUDE.md ## Verify | auto-detected from <file>>
**Claimed SHA:** `<sha>` (from STATE.md "Last shipped" top entry)
<sha-disclosure if fuzzy>

---

## 1. Verify command result
**Status:** <pass | fail | timeout>
**Exit code:** <N>
**Duration:** <Ns>
<if fail or timeout: last 30 lines>
<if pass: "Output suppressed (verify passed). Re-run command directly to inspect.">

---

## 2. Git drift since claimed SHA
**Claimed SHA found in repo:** <yes | no>
<if no: warning + reconcile suggestion>
<if yes:>
  **Commits ahead of claim:** <N>
  <if N>0: list of commits (oldest first)>

---

## 3. Working tree status
**Clean:** <yes | no>
<if no:>
  **Modified/untracked files:**
  <git status --porcelain output>

---

## Suggested fixes
<context-sensitive — only fixes that apply>
```

**Ambiguous-fuzzy variant** (replaces sections 1-3):

```markdown
# /scribe-verify — ⚠️ ambiguous SHA match

**Verify command:** <not run — SHA resolution incomplete>
**Source:** <not resolved>

## 0. Ambiguous SHA match

STATE.md "Last shipped" top entry references `vX.Y.Z` but `git log --grep` returned multiple candidates:

- `<sha1>` <subject1>
- `<sha2>` <subject2>
- ...

→ Resolve by editing STATE.md to include the explicit short-SHA, then re-run /scribe-verify.

## Suggested fixes

→ Edit STATE.md "Last shipped" top entry to include explicit short-SHA from the candidate list above.
→ Or run reconcile-project-state to refresh against current git log.
```

---

## Timeout

- **Default:** 5 minutes. Covers ~95% of solo-dev test suites.
- **Override:** env var `SCRIBE_VERIFY_TIMEOUT=600` (seconds).
- **Implementation:** `timeout "${SCRIBE_VERIFY_TIMEOUT:-300}" bash -c "$cmd"`.
- **Timeout exit code:** 124 from `timeout`. Distinguish from verify-fail in report.

---

## Testing

### `tests/scripts/scribe-verify.bats` — bash logic (~16 cases)

**Verify-cmd resolution (4):**
1. `docs/.scribe-verify.sh` exists + executable → script picks it
2. CLAUDE.md `## Verify` block exists → script extracts first code block
3. Auto-detect: only `package.json` present → cmd = `npm test`
4. Nothing matches → exit 2, report contains "No verify command found"

**SHA parsing (3):**
5. STATE bullet explicit short-SHA → claimed SHA correct
6. STATE bullet version label only, single git log match → fuzzy disclosure
7. STATE bullet version label, multiple matches → ⚠️ ambiguous, sections 1-3 aborted

**Drift detection (5):**
8. Verify pass + SHA = HEAD + clean → ✅ all green
9. Verify pass + 3 commits ahead → ⚠️ commits ahead, 3 entries listed
10. Verify pass + dirty tree → ⚠️ uncommitted, file list embedded
11. Verify fail (exit 1) → ❌ failed, last 30 lines captured
12. Verify timeout (forced via `timeout 1` test) → ❌ timed out

**Edge cases (4):**
13. Claimed SHA not in repo (synthetic) → ⚠️ missing, fix points at reconcile
14. STATE.md missing → exit 2, "not a scribe project"
15. STATE.md no Last shipped heading → exit 2, points at update-project-state
16. `SCRIBE_VERIFY_TIMEOUT=10` env override honored

### `tests/skills/scribe-verify.bats` — skill contract (~3 cases)

1. SKILL.md frontmatter has `name: scribe-verify` + description triggers on "scribe-verify" / "/scribe-verify" / "verify ship claim"
2. SKILL.md instructs Claude to invoke `bash $CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh` (literal-pattern grep)
3. Output contract — when sandbox seeded with all-green fixtures, simulated invocation produces markdown starting with `# /scribe-verify — ✅`

### Runner integration

`tests/run.sh` default args extended: `--recursive tests/hooks tests/skills tests/integration tests/scripts`.

### CI integration

`.github/workflows/test.yml` runs the same `bash tests/run.sh` default — auto-picks up `tests/scripts/`.

### Runtime budget

Tests use mocked verify scripts (`echo pass; exit 0` etc.) — sub-second. Real-timeout test bounded to ~10s. Total additional runtime: <5s.

---

## Trigger phrases (skill description)

- "scribe-verify"
- "/scribe-verify"
- "verify ship claim"
- "is STATE.md current"
- "did the last ship actually pass"
- "drift check"
- "/project-scribe:scribe-verify"

---

## Out of scope (file separately if needed)

- CI-status drift checking (GitHub-coupled, defer to demand)
- Auto-fix STATE.md (write-mode `--fix` flag — defer)
- Worktree-aware behavior (skipped per 2026-04-30 decision)
- Caching verify-cmd resolution across invocations
- Parallel verify across multiple test commands

---

## Acceptance criteria

- [ ] `bash scripts/scribe-verify.sh` exits 0 on all-green project
- [ ] All 16 bats cases in `tests/scripts/scribe-verify.bats` pass
- [ ] All 3 bats cases in `tests/skills/scribe-verify.bats` pass
- [ ] `/project-scribe:scribe-verify` slash command resolves and runs
- [ ] Markdown report rendered correctly when piped to terminal (no broken formatting)
- [ ] Multi-match fuzzy resolution does NOT silently pick — verdict ⚠️ ambiguous fires
- [ ] Working-tree dirty case includes verbatim `git status --porcelain` output
- [ ] DECISIONS.md has v0.7.4 entry locking down the design
- [ ] CHANGELOG v0.7.4 entry
- [ ] plugin.json bumped 0.7.3 → 0.7.4
- [ ] Tag v0.7.4 created locally + pushed after merge
- [ ] CI green on master post-merge
