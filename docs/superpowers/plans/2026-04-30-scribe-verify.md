# /scribe-verify Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/superpowers/specs/2026-04-30-scribe-verify-design.md` (committed at SHA `d8a26a2`).

**Goal:** Add `/project-scribe:scribe-verify` — a read-only diagnostic that runs the project's verify command, parses STATE.md "Last shipped" claim, checks git drift, and reports findings + suggested fixes.

**Architecture:** Skill + helper bash script (Approach B). Heavy logic in `scripts/scribe-verify.sh` for speed/determinism/testability. Skill at `skills/scribe-verify/SKILL.md` is a thin wrapper that instructs Claude to invoke the script and surface its markdown output verbatim. Slash command at `commands/scribe-verify.md` matches the existing scribe `.md` convention.

**Tech Stack:** bash 5+, awk/sed/grep (no jq for STATE.md parsing — all markdown), `git`, `timeout` GNU coreutils, bats-core 1.13 (already vendored).

---

## Why this is #2

- Backlog item #1 (worktree-aware state) skipped 2026-04-30 (no active pain). Item #2 = highest-signal remaining (Boris/Anthropic 9/10 per research synthesis §6).
- Locks in scribe trustworthiness — closes "lying-by-omission" gap where STATE claims a ship that broke tests or never landed.
- Scaffolds the `scripts/` dir precedent that #3 (Context Audit) and #4 (token-budget tab) will reuse.
- Read-only diagnostic — low blast radius, easy to revert if mistaken.

## Scope (in)

- New script `scripts/scribe-verify.sh` with hybrid 4-step verify-cmd resolution, fuzzy STATE SHA parsing, drift detection, markdown report.
- New skill `skills/scribe-verify/SKILL.md` (thin SOP wrapper).
- New slash command `commands/scribe-verify.md`.
- 16 bats cases under `tests/scripts/scribe-verify.bats`, 3 under `tests/skills/scribe-verify.bats`.
- Update `tests/run.sh` default args to include `tests/scripts`.
- DECISIONS entry locking design + CHANGELOG v0.7.4 + plugin.json bump + tag.

## Scope (out, deferred)

- CI-status drift checking (GitHub-coupled, defer to demand).
- Auto-fix `--fix` flag — read-only stays.
- Worktree-aware behavior (skipped per 2026-04-30 decision).
- Caching verify-cmd resolution.
- Parallel verify across multiple test commands.

## File Structure

```
scripts/                                    # NEW directory (precedent for #3, #4)
└── scribe-verify.sh                        # Heavy lifting: resolve cmd, run, parse, report

skills/scribe-verify/                       # NEW skill dir
└── SKILL.md                                # Thin wrapper invokes script

commands/
└── scribe-verify.md                        # NEW — /project-scribe:scribe-verify slash

tests/scripts/                              # NEW test dir
└── scribe-verify.bats                      # ~16 cases — bash logic coverage

tests/skills/
└── scribe-verify.bats                      # NEW — 3 cases — skill contract

tests/run.sh                                # MODIFY — add tests/scripts to default args

.claude-plugin/plugin.json                  # MODIFY — version 0.7.3 → 0.7.4
CHANGELOG.md                                # MODIFY — prepend v0.7.4 entry
docs/STATE.md                               # MODIFY — Current focus + Last shipped
docs/DECISIONS.md                           # MODIFY — prepend v0.7.4 decision entry
README.md                                   # MODIFY — version badge 0.7.3 → 0.7.4
```

---

## Chunk 1: Script skeleton + verify-cmd resolution

### Task 1.1: Create `scripts/` dir + script skeleton

**Files:**
- Create: `scripts/scribe-verify.sh`

- [ ] **Step 1: Create scripts dir + skeleton script**

```bash
mkdir -p scripts
cat > scripts/scribe-verify.sh <<'SCRIPT'
#!/usr/bin/env bash
# /scribe-verify — read-only ship-claim verification
#
# Reads docs/STATE.md "Last shipped" top entry, runs the project's verify
# command, checks git drift since the claimed SHA, emits a markdown report.
#
# Exit codes:
#   0 = all green
#   1 = drift detected (warnings or verify fail)
#   2 = config missing (no STATE.md, no verify cmd, etc.)

set -uo pipefail

PROJECT_ROOT="$(pwd)"
STATE_FILE="${PROJECT_ROOT}/docs/STATE.md"

# Bail if not a scribe project.
if [ ! -f "$STATE_FILE" ]; then
    cat <<EOF
# /scribe-verify — ⚠️ not a scribe project

\`docs/STATE.md\` not found. This command requires a scribe-enabled project.

→ Run \`init project scribe\` to bootstrap.
EOF
    exit 2
fi

# Subsequent steps will fill in resolution + drift logic.
echo "skeleton — implement in subsequent tasks"
exit 2
SCRIPT
chmod +x scripts/scribe-verify.sh
```

- [ ] **Step 2: Verify skeleton runs**

Run: `bash scripts/scribe-verify.sh`
Expected (from a non-scribe dir): markdown error + exit 2.
Expected (from scribe-enabled cwd): "skeleton — implement..." + exit 2.

- [ ] **Step 3: Commit**

```bash
git add scripts/scribe-verify.sh
git commit -m "feat(scribe-verify): script skeleton + scribe-project gate"
```

### Task 1.2: Verify-cmd resolution function (4-step hybrid)

**Files:**
- Modify: `scripts/scribe-verify.sh`

- [ ] **Step 1: Append resolve_verify_cmd function**

Add this function above the existing skeleton invocation. Replace the trailing `echo` + `exit 2` with the resolver call.

```bash
# Resolves verify command via 4-step hybrid.
# Sets globals: VERIFY_CMD, VERIFY_SOURCE.
# Returns 2 if no command resolvable.
resolve_verify_cmd() {
    # Step 1: docs/.scribe-verify.sh
    local explicit="${PROJECT_ROOT}/docs/.scribe-verify.sh"
    if [ -x "$explicit" ]; then
        VERIFY_CMD="$explicit"
        VERIFY_SOURCE="docs/.scribe-verify.sh"
        return 0
    fi

    # Step 2: CLAUDE.md ## Verify section, first fenced code block
    local claudemd="${PROJECT_ROOT}/CLAUDE.md"
    if [ -f "$claudemd" ]; then
        # Awk: between ^## Verify (case-insensitive) and next ^## heading,
        # extract first fenced code block content.
        local block
        block=$(awk '
            BEGIN { in_section=0; in_block=0 }
            tolower($0) ~ /^## verify[[:space:]]*$/ { in_section=1; next }
            in_section && /^## / { exit }
            in_section && /^```/ { in_block=!in_block; next }
            in_section && in_block { print }
        ' "$claudemd")
        if [ -n "$block" ]; then
            local tmp
            tmp=$(mktemp "${TMPDIR:-/tmp}/scribe-verify-claudemd.XXXXXX")
            printf '%s\n' "$block" > "$tmp"
            chmod +x "$tmp"
            VERIFY_CMD="$tmp"
            VERIFY_SOURCE="CLAUDE.md ## Verify"
            return 0
        fi
    fi

    # Step 3: Auto-detect by project file
    if [ -f "${PROJECT_ROOT}/package.json" ];   then VERIFY_CMD="npm test";                           VERIFY_SOURCE="auto-detected from package.json";  return 0; fi
    if [ -f "${PROJECT_ROOT}/Cargo.toml" ];     then VERIFY_CMD="cargo test";                         VERIFY_SOURCE="auto-detected from Cargo.toml";    return 0; fi
    if [ -f "${PROJECT_ROOT}/pyproject.toml" ]; then VERIFY_CMD="pytest";                             VERIFY_SOURCE="auto-detected from pyproject.toml"; return 0; fi
    if [ -f "${PROJECT_ROOT}/Makefile" ] && grep -qE '^test:' "${PROJECT_ROOT}/Makefile"; then
        VERIFY_CMD="make test"; VERIFY_SOURCE="auto-detected from Makefile"; return 0
    fi
    if [ -f "${PROJECT_ROOT}/go.mod" ];         then VERIFY_CMD="go test ./...";                      VERIFY_SOURCE="auto-detected from go.mod";        return 0; fi
    if [ -f "${PROJECT_ROOT}/Gemfile" ];        then VERIFY_CMD="bundle exec rake test";              VERIFY_SOURCE="auto-detected from Gemfile";       return 0; fi
    if [ -f "${PROJECT_ROOT}/composer.json" ];  then VERIFY_CMD="composer test";                      VERIFY_SOURCE="auto-detected from composer.json"; return 0; fi
    if [ -f "${PROJECT_ROOT}/mix.exs" ];        then VERIFY_CMD="mix test";                           VERIFY_SOURCE="auto-detected from mix.exs";       return 0; fi
    if [ -f "${PROJECT_ROOT}/pubspec.yaml" ];   then VERIFY_CMD="flutter test";                       VERIFY_SOURCE="auto-detected from pubspec.yaml";  return 0; fi

    # Step 4: nothing matched
    return 2
}

# Replace skeleton placeholder with real resolver:
if ! resolve_verify_cmd; then
    cat <<EOF
# /scribe-verify — ❌ no verify command found

Tried:
- docs/.scribe-verify.sh (not present)
- CLAUDE.md ## Verify section (not found)
- Auto-detect: no recognized project file

→ Create docs/.scribe-verify.sh with your project's test/build command. Example:

    #!/usr/bin/env bash
    set -euo pipefail
    npm test && npm run build

→ Or add a \`## Verify\` section to CLAUDE.md with a fenced code block.
EOF
    exit 2
fi

echo "resolved: $VERIFY_CMD (source: $VERIFY_SOURCE)"
exit 0
```

- [ ] **Step 2: Smoke test against this scribe repo**

Run: `bash scripts/scribe-verify.sh`
Expected: `resolved: <some command> (source: <some source>)` + exit 0.

If the scribe repo has neither package.json nor Cargo.toml etc., expect the no-match error. (Scribe repo has none of these, so this should fail with the no-match path — that's correct, scaffolds the test fixture story.)

- [ ] **Step 3: Smoke test against a scratch dir with package.json**

```bash
tmp=$(mktemp -d)
cd "$tmp"
mkdir -p docs && touch docs/STATE.md && echo '{}' > package.json
bash "$OLDPWD/scripts/scribe-verify.sh"
cd "$OLDPWD"
rm -rf "$tmp"
```

Expected: `resolved: npm test (source: auto-detected from package.json)` + exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/scribe-verify.sh
git commit -m "feat(scribe-verify): hybrid 4-step verify-cmd resolution"
```

---

## Chunk 2: STATE.md SHA parsing + drift detection

### Task 2.1: SHA parsing function

**Files:**
- Modify: `scripts/scribe-verify.sh`

- [ ] **Step 1: Add parse_claimed_sha function**

Append above the resolver call:

```bash
# Parses claimed SHA from STATE.md "Last shipped" top bullet.
# Sets globals: CLAIMED_SHA, SHA_DISCLOSURE (text snippet, may be empty),
#               AMBIGUOUS_CANDIDATES (newline-separated, empty if not ambiguous).
# Returns:
#   0 = single SHA resolved (explicit or fuzzy-1-match)
#   1 = ambiguous fuzzy match (multiple candidates)
#   2 = no Last shipped block found
parse_claimed_sha() {
    CLAIMED_SHA=""
    SHA_DISCLOSURE=""
    AMBIGUOUS_CANDIDATES=""

    # Locate first bullet under fuzzy-matched shipped heading.
    local top_bullet
    top_bullet=$(awk '
        BEGIN { in_block=0 }
        tolower($0) ~ /^## (last shipped|shipped|recently shipped|recent commits)[[:space:]]*$/ { in_block=1; next }
        in_block && /^## / { exit }
        in_block && /^- / { print; exit }
    ' "$STATE_FILE")

    if [ -z "$top_bullet" ]; then
        return 2
    fi

    # Step 1: explicit short-SHA in bullet (handles backtick-wrapped too).
    local sha
    sha=$(printf '%s' "$top_bullet" | grep -oE '\b[0-9a-f]{7,40}\b' | head -n 1)
    if [ -n "$sha" ]; then
        CLAIMED_SHA="$sha"
        return 0
    fi

    # Step 2: fuzzy version-label fallback.
    local version
    version=$(printf '%s' "$top_bullet" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [ -z "$version" ]; then
        return 2
    fi

    local matches
    matches=$(git -C "$PROJECT_ROOT" log --all --oneline --grep="$version" 2>/dev/null || true)
    local count
    count=$(printf '%s' "$matches" | grep -c .)

    if [ "$count" = "0" ]; then
        return 2
    elif [ "$count" = "1" ]; then
        CLAIMED_SHA=$(printf '%s' "$matches" | awk '{ print $1 }')
        SHA_DISCLOSURE="*Claimed SHA matched via fuzzy version-label search for \"$version\" — disclose for transparency.*"
        return 0
    else
        AMBIGUOUS_CANDIDATES="$matches"
        return 1
    fi
}
```

- [ ] **Step 2: Adjust main flow to call parser after resolve**

Replace the trailing `echo "resolved: ..." + exit 0` block with:

```bash
parse_claimed_sha
parse_status=$?

case $parse_status in
    0) echo "claimed: $CLAIMED_SHA${SHA_DISCLOSURE:+ (fuzzy)}" ;;
    1) echo "ambiguous: $AMBIGUOUS_CANDIDATES" ;;
    2) echo "no Last shipped block parseable"; exit 2 ;;
esac

echo "resolved: $VERIFY_CMD ($VERIFY_SOURCE)"
exit 0
```

(This is debug scaffolding — replaced by real report logic in Chunk 3.)

- [ ] **Step 3: Smoke test against scribe repo**

Run: `bash scripts/scribe-verify.sh`
Expected output includes `claimed: 513856c...` (top SHA per current STATE.md) — exact SHA depends on current STATE state.

- [ ] **Step 4: Commit**

```bash
git add scripts/scribe-verify.sh
git commit -m "feat(scribe-verify): STATE.md SHA parsing with fuzzy version-label fallback"
```

### Task 2.2: Drift detection function

**Files:**
- Modify: `scripts/scribe-verify.sh`

- [ ] **Step 1: Add check_drift function**

Append above the main-flow block:

```bash
# Checks git drift against CLAIMED_SHA.
# Sets globals: SHA_FOUND (yes|no), AHEAD_COUNT, AHEAD_LIST, TREE_CLEAN (yes|no), TREE_FILES.
check_drift() {
    SHA_FOUND="no"; AHEAD_COUNT=0; AHEAD_LIST=""; TREE_CLEAN="yes"; TREE_FILES=""

    if git -C "$PROJECT_ROOT" cat-file -e "${CLAIMED_SHA}^{commit}" 2>/dev/null; then
        SHA_FOUND="yes"
        AHEAD_COUNT=$(git -C "$PROJECT_ROOT" rev-list --count "${CLAIMED_SHA}..HEAD" 2>/dev/null || echo 0)
        if [ "$AHEAD_COUNT" -gt 0 ]; then
            AHEAD_LIST=$(git -C "$PROJECT_ROOT" log --reverse --oneline "${CLAIMED_SHA}..HEAD" 2>/dev/null || true)
        fi
    fi

    TREE_FILES=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null || true)
    if [ -n "$TREE_FILES" ]; then
        TREE_CLEAN="no"
    fi
}
```

- [ ] **Step 2: Smoke test inline**

Replace main-flow debug block with:

```bash
parse_claimed_sha
parse_status=$?

if [ "$parse_status" = "1" ]; then
    echo "ambiguous"; printf '%s\n' "$AMBIGUOUS_CANDIDATES"
    exit 1
fi

if [ "$parse_status" = "2" ]; then
    echo "no parseable claim"; exit 2
fi

check_drift
echo "sha_found=$SHA_FOUND ahead=$AHEAD_COUNT tree_clean=$TREE_CLEAN"
echo "verify cmd: $VERIFY_CMD"
exit 0
```

- [ ] **Step 3: Run + verify outputs match repo state**

Run: `bash scripts/scribe-verify.sh` from inside scribe repo on master (clean tree).
Expected: `sha_found=yes ahead=0 tree_clean=yes`.

- [ ] **Step 4: Commit**

```bash
git add scripts/scribe-verify.sh
git commit -m "feat(scribe-verify): git drift detection (sha-found, ahead, tree-clean)"
```

---

## Chunk 3: Verify execution + markdown report

### Task 3.1: Run verify command with timeout

**Files:**
- Modify: `scripts/scribe-verify.sh`

- [ ] **Step 1: Add run_verify function**

Append above main-flow:

```bash
# Runs VERIFY_CMD with timeout. Sets globals:
# VERIFY_STATUS (pass|fail|timeout), VERIFY_EXIT, VERIFY_DURATION, VERIFY_OUTPUT (last 30 lines if not pass).
run_verify() {
    local timeout_sec="${SCRIBE_VERIFY_TIMEOUT:-300}"
    local out
    out=$(mktemp "${TMPDIR:-/tmp}/scribe-verify-out.XXXXXX")
    local start end

    start=$(date +%s)
    # Use bash -c for command-string compatibility with auto-detected cmds (npm test, etc.)
    # Explicit script paths still work because the path is its own command.
    if timeout "$timeout_sec" bash -c "cd \"$PROJECT_ROOT\" && $VERIFY_CMD" >"$out" 2>&1; then
        VERIFY_STATUS="pass"
        VERIFY_EXIT=0
    else
        VERIFY_EXIT=$?
        if [ "$VERIFY_EXIT" = "124" ]; then
            VERIFY_STATUS="timeout"
        else
            VERIFY_STATUS="fail"
        fi
    fi
    end=$(date +%s)
    VERIFY_DURATION=$((end - start))

    if [ "$VERIFY_STATUS" != "pass" ]; then
        VERIFY_OUTPUT=$(tail -n 30 "$out")
    else
        VERIFY_OUTPUT=""
    fi
    rm -f "$out"
}
```

- [ ] **Step 2: Wire run_verify into main flow**

Replace the smoke-test block with:

```bash
parse_claimed_sha
parse_status=$?

if [ "$parse_status" = "1" ]; then
    # Ambiguous — abort drift checks. Report Section 0 only.
    emit_ambiguous_report   # filled in next task
    exit 1
fi

if [ "$parse_status" = "2" ]; then
    cat <<EOF
# /scribe-verify — ⚠️ STATE.md "Last shipped" not parseable

Top bullet under \`## Last shipped\` did not yield an explicit SHA, and no version-label fuzzy match was found.

→ Run reconcile-project-state or update-project-state to refresh STATE.md.
EOF
    exit 2
fi

check_drift
run_verify
emit_report   # filled in next task
exit_code=$?
exit "$exit_code"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/scribe-verify.sh
git commit -m "feat(scribe-verify): run verify command with SCRIBE_VERIFY_TIMEOUT default 300s"
```

### Task 3.2: Markdown report emitters

**Files:**
- Modify: `scripts/scribe-verify.sh`

- [ ] **Step 1: Add emit_report + emit_ambiguous_report functions**

```bash
# Emit Section 0 only — used when fuzzy match returned multiple candidates.
emit_ambiguous_report() {
    cat <<EOF
# /scribe-verify — ⚠️ ambiguous SHA match

**Verify command:** <not run — SHA resolution incomplete>
**Source:** <not resolved>

## 0. Ambiguous SHA match

STATE.md "Last shipped" top entry references a version label, but \`git log --grep\` returned multiple candidate commits:

EOF
    printf '%s\n' "$AMBIGUOUS_CANDIDATES" | while IFS= read -r line; do
        echo "- \`$(echo "$line" | awk '{print $1}')\` $(echo "$line" | cut -d' ' -f2-)"
    done
    cat <<EOF

→ Resolve by editing STATE.md to include the explicit short-SHA, then re-run \`/project-scribe:scribe-verify\`.

## Suggested fixes

- → Edit STATE.md "Last shipped" top entry to include explicit short-SHA from the candidate list above.
- → Or run \`reconcile-project-state\` to refresh against current git log.
EOF
}

# Emit full report covering sections 1, 2, 3, and Suggested fixes.
# Returns the exit code the caller should propagate (0 / 1).
emit_report() {
    local glyph summary fixes
    fixes=""

    # Determine glyph + one-line summary from verdict matrix.
    if [ "$VERIFY_STATUS" = "fail" ]; then
        glyph="❌"; summary="verify command failed (exit $VERIFY_EXIT)"
    elif [ "$VERIFY_STATUS" = "timeout" ]; then
        glyph="❌"; summary="verify command timed out at ${SCRIBE_VERIFY_TIMEOUT:-300}s"
    elif [ "$SHA_FOUND" = "no" ]; then
        glyph="⚠️"; summary="claimed SHA not present in repo"
    elif [ "$AHEAD_COUNT" -gt 0 ]; then
        glyph="⚠️"; summary="$AHEAD_COUNT commit(s) ahead of claim"
    elif [ "$TREE_CLEAN" = "no" ]; then
        glyph="⚠️"; summary="working tree dirty"
    else
        glyph="✅"; summary="all green"
    fi

    cat <<EOF
# /scribe-verify — $glyph $summary

**Verify command:** \`$VERIFY_CMD\`
**Source:** $VERIFY_SOURCE
**Claimed SHA:** \`$CLAIMED_SHA\` (from STATE.md "Last shipped" top entry)
EOF
    [ -n "$SHA_DISCLOSURE" ] && printf '\n%s\n' "$SHA_DISCLOSURE"

    cat <<EOF

---

## 1. Verify command result

**Status:** $VERIFY_STATUS
**Exit code:** $VERIFY_EXIT
**Duration:** ${VERIFY_DURATION}s

EOF
    if [ "$VERIFY_STATUS" = "pass" ]; then
        echo "Output suppressed (verify passed). Re-run command directly to inspect."
    else
        echo '```'
        printf '%s\n' "$VERIFY_OUTPUT"
        echo '```'
        fixes="$fixes
- → Verify command failed — investigate test output above before claiming current ship."
    fi

    cat <<EOF

---

## 2. Git drift since claimed SHA

**Claimed SHA found in repo:** $SHA_FOUND
EOF

    if [ "$SHA_FOUND" = "no" ]; then
        cat <<EOF

⚠️ Claimed SHA \`$CLAIMED_SHA\` is not present in this repo. Possible causes: force-push, history rewrite, branch deleted.

EOF
        fixes="$fixes
- → Claimed SHA missing — run \`reconcile-project-state\` to refresh STATE.md against current git log."
    else
        echo "**Commits ahead of claim:** $AHEAD_COUNT"
        if [ "$AHEAD_COUNT" -gt 0 ]; then
            echo
            printf '%s\n' "$AHEAD_LIST" | while IFS= read -r line; do
                sha=$(echo "$line" | awk '{print $1}')
                subj=$(echo "$line" | cut -d' ' -f2-)
                echo "- \`$sha\` $subj"
            done
            fixes="$fixes
- → $AHEAD_COUNT commit(s) ahead of claim — either roll STATE.md forward (run reconcile) or claim what's actually shipped."
        fi
    fi

    cat <<EOF

---

## 3. Working tree status

**Clean:** $TREE_CLEAN
EOF
    if [ "$TREE_CLEAN" = "no" ]; then
        cat <<EOF

**Modified/untracked files:**

\`\`\`
$TREE_FILES
\`\`\`
EOF
        fixes="$fixes
- → Working tree dirty — review file list; commit, stash, or discard before re-running verify."
    fi

    if [ -n "$fixes" ]; then
        cat <<EOF

---

## Suggested fixes
$fixes
EOF
    fi

    # Exit code derivation.
    if [ "$glyph" = "✅" ]; then
        return 0
    else
        return 1
    fi
}
```

- [ ] **Step 2: Smoke test full pipeline against scribe repo**

Run: `bash scripts/scribe-verify.sh`

Expected on clean master with no verify cmd: exit 2 (no verify found) — scribe repo has no `package.json` etc. Add `docs/.scribe-verify.sh` temporarily:

```bash
cat > docs/.scribe-verify.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
bash tests/run.sh
EOF
chmod +x docs/.scribe-verify.sh
bash scripts/scribe-verify.sh
rm docs/.scribe-verify.sh
```

Expected: `# /scribe-verify — ✅ all green` heading + sections 1, 2, 3 all clean. Exit 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/scribe-verify.sh
git commit -m "feat(scribe-verify): markdown report emitters (full + ambiguous variants)"
```

---

## Chunk 4: Skill + slash command

### Task 4.1: Create skill SOP

**Files:**
- Create: `skills/scribe-verify/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: scribe-verify
description: Read-only verification gate. Runs the project's verify command, parses STATE.md "Last shipped" top entry, checks git drift since the claimed SHA, and emits a markdown report with suggested fixes. Triggers include "scribe-verify", "/scribe-verify", "verify ship claim", "is STATE.md current", "drift check", "did the last ship actually pass".
---

# Scribe verify

Read-only diagnostic. Catches "lying-by-omission" — STATE.md claims a ship
that broke tests, has commits since the claimed SHA, or references a SHA
that no longer exists.

## Hard rules — never violate

- **Read-only.** Never edit STATE.md, never commit, never modify any
  scribe state. The script writes nothing back to the repo.
- **No silent guessing on ambiguous fuzzy SHA match.** If multiple
  candidates resolve from a version label, abort drift checks and report
  the candidate list — let the user resolve.
- **Bail with a report (not silently) if STATE.md missing, no verify
  command resolvable, or no parseable Last shipped block.** Exit 2 with
  a markdown error pointing at the fix.

## When to invoke

- User says "scribe-verify", "/scribe-verify", "verify ship claim",
  "is STATE.md current", "did the last ship actually pass", "drift check"
- Before claiming a release in conversation ("just shipped v0.7.4" → run
  this first to confirm).
- After the auto-handoff skill writes a session bundle (verifies the
  shipped claim before the user closes the session).

## Pre-flight

The helper script handles all gates. Just invoke it and surface the
output verbatim.

## Execution

Invoke:

\`\`\`bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh"
\`\`\`

Exit codes:

- **0** — all green (verify passed, claimed SHA = HEAD, tree clean)
- **1** — drift detected (verify failed, commits ahead of claim,
  uncommitted changes, claimed SHA missing, or ambiguous fuzzy match)
- **2** — config missing (no STATE.md, no verify command resolvable, no
  parseable Last shipped block)

## Surface output

Print the script's stdout verbatim to the user. Do not editorialize, do
not summarize, do not add commentary. The report is the deliverable.

If exit code is non-zero, the report itself explains what went wrong and
what to fix — that is the contract. Trust the report.

## Configuration

Set \`SCRIBE_VERIFY_TIMEOUT\` (seconds) in the environment to override the
default 300s timeout for slow test suites. Example:

\`\`\`bash
SCRIBE_VERIFY_TIMEOUT=900 /project-scribe:scribe-verify
\`\`\`
```

- [ ] **Step 2: Validate frontmatter parses + skill is discoverable**

Run from scribe repo root:

```bash
grep -E "^(name|description):" skills/scribe-verify/SKILL.md
```

Expected: 2 lines. `name: scribe-verify` and `description: ...`.

- [ ] **Step 3: Commit**

```bash
git add skills/scribe-verify/SKILL.md
git commit -m "feat(skills): add scribe-verify skill SOP"
```

### Task 4.2: Create slash command

**Files:**
- Create: `commands/scribe-verify.md`

- [ ] **Step 1: Write commands/scribe-verify.md**

```markdown
---
description: Read-only verification gate. Runs the project's verify command, parses STATE.md "Last shipped" top entry, checks git drift since the claimed SHA, and emits a markdown report with suggested fixes.
---

Invoke the `scribe-verify` skill.

The skill will:
1. Resolve the verify command for this project via the 4-step hybrid (`docs/.scribe-verify.sh` → `CLAUDE.md` `## Verify` → auto-detect → error).
2. Parse STATE.md "Last shipped" top entry for an explicit short-SHA. Fall back to fuzzy version-label search if absent. Abort with ambiguity report if multiple candidates match.
3. Run the verify command with a 300s default timeout (`SCRIBE_VERIFY_TIMEOUT` env var to override).
4. Check git drift: claimed SHA exists in repo, commits between claim and HEAD, working-tree status.
5. Emit a markdown report with verdict glyph (✅ / ⚠️ / ❌), section-per-check, and context-sensitive suggested fixes.

Read-only. No writes anywhere — no STATE.md edits, no git mutation, no scribe state changes.
```

- [ ] **Step 2: Cross-check against existing slash conventions**

Run:

```bash
head -3 commands/scribe-status.md commands/xref-lint.md commands/scribe-verify.md
```

All three should start with `---` frontmatter, have a single `description:` field, and proceed with body text. Format consistency.

- [ ] **Step 3: Commit**

```bash
git add commands/scribe-verify.md
git commit -m "feat(commands): add /project-scribe:scribe-verify slash"
```

---

## Chunk 5: Tests

### Task 5.1: Bats infra — extend runner for tests/scripts

**Files:**
- Modify: `tests/run.sh`

- [ ] **Step 1: Add tests/scripts to default runner args**

Edit `tests/run.sh` — find the line:

```bash
exec "$BATS" --recursive tests/hooks tests/skills tests/integration
```

Replace with:

```bash
exec "$BATS" --recursive tests/hooks tests/skills tests/integration tests/scripts
```

- [ ] **Step 2: Verify runner still works**

```bash
mkdir -p tests/scripts   # no .bats files yet — runner handles empty dir
bash tests/run.sh 2>&1 | tail -3
```

Expected: existing 31 tests still run, no error about missing tests/scripts dir.

- [ ] **Step 3: Commit**

```bash
git add tests/run.sh
git commit -m "test(runner): include tests/scripts in default args"
```

### Task 5.2: tests/scripts/scribe-verify.bats — verify-cmd resolution (Tasks 1.x coverage)

**Files:**
- Create: `tests/scripts/scribe-verify.bats`

- [ ] **Step 1: Write 4 verify-cmd resolution tests**

```bash
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'

setup() {
  sandbox::create
  fixtures::seed_state
  export HOME="$SANDBOX_DIR/home"
  mkdir -p "$HOME/.claude"
}
teardown() { sandbox::cleanup; }

@test "resolve: docs/.scribe-verify.sh wins over auto-detect" {
  echo '{"name":"x"}' > "$SANDBOX_DIR/package.json"
  cat > "$SANDBOX_DIR/docs/.scribe-verify.sh" <<'EOF'
#!/usr/bin/env bash
echo explicit
EOF
  chmod +x "$SANDBOX_DIR/docs/.scribe-verify.sh"

  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_output --partial "docs/.scribe-verify.sh"
}

@test "resolve: CLAUDE.md ## Verify section beats auto-detect" {
  echo '{"name":"x"}' > "$SANDBOX_DIR/package.json"
  cat > "$SANDBOX_DIR/CLAUDE.md" <<'EOF'
# Project

## Verify

```bash
echo from-claude-md
```

## Other
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_output --partial "CLAUDE.md ## Verify"
}

@test "resolve: auto-detect package.json → npm test" {
  echo '{"name":"x"}' > "$SANDBOX_DIR/package.json"
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_output --partial "npm test"
  assert_output --partial "auto-detected from package.json"
}

@test "resolve: nothing matches → exit 2 + error report" {
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_failure 2
  assert_output --partial "No verify command found"
}
```

- [ ] **Step 2: Run + commit**

```bash
bash tests/run.sh tests/scripts/scribe-verify.bats
git add tests/scripts/scribe-verify.bats
git commit -m "test(scripts): cover scribe-verify resolve_verify_cmd 4-step hybrid"
```

If any test fails: investigate the helper script, NOT the test, unless the test reveals a wrong assertion. Per chunk-2 hook test pattern, prefer fixing the script over loosening tests.

### Task 5.3: tests/scripts/scribe-verify.bats — SHA parsing + drift (Tasks 2.x coverage)

**Files:**
- Modify: `tests/scripts/scribe-verify.bats`

- [ ] **Step 1: Append 8 cases (SHA + drift + edge)**

```bash
# Helper: init git in sandbox, plant a verify cmd, return committed SHA via stdout.
sandbox_init_git_with_verify() {
  cat > "$SANDBOX_DIR/docs/.scribe-verify.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$SANDBOX_DIR/docs/.scribe-verify.sh"
  ( cd "$SANDBOX_DIR" \
    && git init -q \
    && git config user.email t@t \
    && git config user.name t \
    && git add -A \
    && git commit -q -m "v0.0.1 — initial fixture" )
}

@test "sha-parse: explicit short-SHA in top bullet wins" {
  sandbox_init_git_with_verify
  local sha; sha=$(cd "$SANDBOX_DIR" && git rev-parse --short HEAD)
  cat > "$SANDBOX_DIR/docs/STATE.md" <<EOF
# Project State
## Current focus
x
## Last shipped
- v0.0.1 — fixture — \`$sha\`
## Next up
y
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_success
  assert_output --partial "✅ all green"
}

@test "sha-parse: fuzzy single-match emits disclosure" {
  sandbox_init_git_with_verify
  cat > "$SANDBOX_DIR/docs/STATE.md" <<'EOF'
# Project State
## Current focus
x
## Last shipped
- v0.0.1 — fixture (no SHA on this line)
## Next up
y
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_output --partial "fuzzy version-label search"
}

@test "sha-parse: ambiguous fuzzy match aborts sections 1-3" {
  sandbox_init_git_with_verify
  ( cd "$SANDBOX_DIR" && git commit --allow-empty -q -m "another v0.0.1 mention" )
  cat > "$SANDBOX_DIR/docs/STATE.md" <<'EOF'
# Project State
## Current focus
x
## Last shipped
- v0.0.1 — ambiguous label
## Next up
y
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_failure 1
  assert_output --partial "ambiguous SHA match"
  refute_output --partial "## 1. Verify command result"
}

@test "drift: verify pass + claimed = HEAD + clean = ✅" {
  sandbox_init_git_with_verify
  local sha; sha=$(cd "$SANDBOX_DIR" && git rev-parse --short HEAD)
  cat > "$SANDBOX_DIR/docs/STATE.md" <<EOF
# Project State
## Current focus
x
## Last shipped
- v0.0.1 — fixture — \`$sha\`
## Next up
y
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_success
  assert_output --partial "✅ all green"
}

@test "drift: 3 commits ahead emits ⚠️ + commit list" {
  sandbox_init_git_with_verify
  local sha; sha=$(cd "$SANDBOX_DIR" && git rev-parse --short HEAD)
  ( cd "$SANDBOX_DIR" \
    && git commit --allow-empty -q -m "second" \
    && git commit --allow-empty -q -m "third" \
    && git commit --allow-empty -q -m "fourth" )
  cat > "$SANDBOX_DIR/docs/STATE.md" <<EOF
# Project State
## Current focus
x
## Last shipped
- v0.0.1 — fixture — \`$sha\`
## Next up
y
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_failure 1
  assert_output --partial "3 commit"
  assert_output --partial "⚠️"
}

@test "drift: dirty tree emits ⚠️ + file list" {
  sandbox_init_git_with_verify
  local sha; sha=$(cd "$SANDBOX_DIR" && git rev-parse --short HEAD)
  echo "uncommitted" > "$SANDBOX_DIR/extra.txt"
  cat > "$SANDBOX_DIR/docs/STATE.md" <<EOF
# Project State
## Current focus
x
## Last shipped
- v0.0.1 — fixture — \`$sha\`
## Next up
y
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_failure 1
  assert_output --partial "extra.txt"
}

@test "drift: verify fail emits ❌ + last 30 lines" {
  ( cd "$SANDBOX_DIR" \
    && git init -q \
    && git config user.email t@t \
    && git config user.name t )
  cat > "$SANDBOX_DIR/docs/.scribe-verify.sh" <<'EOF'
#!/usr/bin/env bash
echo "FAIL_LINE_1"
echo "FAIL_LINE_2"
exit 1
EOF
  chmod +x "$SANDBOX_DIR/docs/.scribe-verify.sh"
  ( cd "$SANDBOX_DIR" && git add -A && git commit -q -m "v0.0.1 — fixture" )
  local sha; sha=$(cd "$SANDBOX_DIR" && git rev-parse --short HEAD)
  cat > "$SANDBOX_DIR/docs/STATE.md" <<EOF
# Project State
## Current focus
x
## Last shipped
- v0.0.1 — fixture — \`$sha\`
## Next up
y
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_failure 1
  assert_output --partial "❌ verify command failed"
  assert_output --partial "FAIL_LINE_2"
}

@test "drift: claimed SHA missing emits ⚠️ + reconcile suggestion" {
  sandbox_init_git_with_verify
  cat > "$SANDBOX_DIR/docs/STATE.md" <<'EOF'
# Project State
## Current focus
x
## Last shipped
- v0.0.0 — fixture — `0000000`
## Next up
y
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_failure 1
  assert_output --partial "claimed SHA not present in repo"
  assert_output --partial "reconcile-project-state"
}
```

- [ ] **Step 2: Run + commit**

```bash
bash tests/run.sh tests/scripts/scribe-verify.bats
git add tests/scripts/scribe-verify.bats
git commit -m "test(scripts): cover SHA parsing + drift detection (8 cases)"
```

### Task 5.4: tests/scripts/scribe-verify.bats — edge cases + timeout

**Files:**
- Modify: `tests/scripts/scribe-verify.bats`

- [ ] **Step 1: Append 4 edge-case tests**

```bash
@test "edge: STATE.md missing → exit 2 + not-a-scribe-project report" {
  rm -f "$SANDBOX_DIR/docs/STATE.md"
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_failure 2
  assert_output --partial "not a scribe project"
}

@test "edge: STATE.md without Last shipped block → exit 2" {
  sandbox_init_git_with_verify
  cat > "$SANDBOX_DIR/docs/STATE.md" <<'EOF'
# Project State
## Current focus
x
## Next up
y
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_failure 2
  assert_output --partial "Last shipped"
}

@test "edge: SCRIBE_VERIFY_TIMEOUT honored on slow verify" {
  ( cd "$SANDBOX_DIR" \
    && git init -q \
    && git config user.email t@t \
    && git config user.name t )
  cat > "$SANDBOX_DIR/docs/.scribe-verify.sh" <<'EOF'
#!/usr/bin/env bash
sleep 5
EOF
  chmod +x "$SANDBOX_DIR/docs/.scribe-verify.sh"
  ( cd "$SANDBOX_DIR" && git add -A && git commit -q -m "v0.0.1 — fixture" )
  local sha; sha=$(cd "$SANDBOX_DIR" && git rev-parse --short HEAD)
  cat > "$SANDBOX_DIR/docs/STATE.md" <<EOF
# Project State
## Current focus
x
## Last shipped
- v0.0.1 — fixture — \`$sha\`
## Next up
y
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" SCRIBE_VERIFY_TIMEOUT=1 \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_failure 1
  assert_output --partial "timed out"
}

@test "edge: working-tree dirty file list verbatim (no auto-classify)" {
  sandbox_init_git_with_verify
  local sha; sha=$(cd "$SANDBOX_DIR" && git rev-parse --short HEAD)
  echo "modify" >> "$SANDBOX_DIR/docs/.scribe-verify.sh"
  echo "untracked" > "$SANDBOX_DIR/.untracked"
  cat > "$SANDBOX_DIR/docs/STATE.md" <<EOF
# Project State
## Current focus
x
## Last shipped
- v0.0.1 — fixture — \`$sha\`
## Next up
y
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_failure 1
  assert_output --partial ".untracked"
  assert_output --partial "docs/.scribe-verify.sh"
}
```

- [ ] **Step 2: Run + commit**

```bash
bash tests/run.sh tests/scripts/scribe-verify.bats
git add tests/scripts/scribe-verify.bats
git commit -m "test(scripts): cover edge cases (missing files, timeout, dirty tree verbatim)"
```

### Task 5.5: tests/skills/scribe-verify.bats — skill contract

**Files:**
- Create: `tests/skills/scribe-verify.bats`

- [ ] **Step 1: Write 3 contract tests**

```bash
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'

setup() { sandbox::create; }
teardown() { sandbox::cleanup; }

@test "skill: SKILL.md frontmatter has correct name + trigger phrases" {
  run grep -E "^(name|description):" "$CLAUDE_PLUGIN_ROOT/skills/scribe-verify/SKILL.md"
  assert_success
  assert_output --partial "name: scribe-verify"
  assert_output --partial "scribe-verify"
  assert_output --partial "drift check"
}

@test "skill: SKILL.md instructs invoking the helper script" {
  run grep -E 'bash.*scribe-verify\.sh' "$CLAUDE_PLUGIN_ROOT/skills/scribe-verify/SKILL.md"
  assert_success
  assert_output --partial 'scripts/scribe-verify.sh'
}

@test "skill: command frontmatter present + matches conventions" {
  run head -3 "$CLAUDE_PLUGIN_ROOT/commands/scribe-verify.md"
  assert_success
  assert_line --index 0 "---"
  assert_output --partial "description:"
}
```

- [ ] **Step 2: Run + commit**

```bash
bash tests/run.sh tests/skills/scribe-verify.bats
git add tests/skills/scribe-verify.bats
git commit -m "test(skills): cover scribe-verify SKILL.md + commands/scribe-verify.md contract"
```

---

## Chunk 6: Wrap-up

### Task 6.1: Update STATE.md + DECISIONS.md

**Files:**
- Modify: `docs/STATE.md`
- Modify: `docs/DECISIONS.md`

- [ ] **Step 1: STATE.md current focus + last shipped**

In `docs/STATE.md`, update Current focus:

```markdown
v0.7.4 ships /project-scribe:scribe-verify — read-only verification gate that runs the project's verify command, parses STATE.md "Last shipped" claim, and reports git drift. Closes the "lying-by-omission" gap. Sets scripts/ dir precedent for upcoming Context Audit + token-budget tab features.
```

Update Last shipped — top entry (will be filled with merge SHA after PR lands; for now use placeholder):

```markdown
- v0.7.4 — `/project-scribe:scribe-verify` verification gate
- (existing v0.7.3 entry)
- (rest as-is)
```

- [ ] **Step 2: DECISIONS.md — log v0.7.4 entry**

Prepend to `docs/DECISIONS.md` above the most-recent entry:

```markdown
## 2026-04-30 — Scribe-verify: skill + helper script (Approach B), no CI/SHA-subject coupling

**Context:** Backlog item #2 from YouTube-mining synthesis (Boris/Anthropic 9/10 — verification-led development). Scribe trusts STATE.md "Last shipped" without verification, allowing lying-by-omission ("forgot tests fail"). Need an automated drift check.

**Decision:** Build `/project-scribe:scribe-verify` as a thin skill SOP wrapping a heavier `scripts/scribe-verify.sh` (Approach B). Hybrid 4-step verify-cmd resolution (`docs/.scribe-verify.sh` → `CLAUDE.md ## Verify` → auto-detect → error). Drift detection = exit code + git diff vs claimed SHA + working-tree status (Option B from brainstorm). Multi-match fuzzy SHA = ⚠️ ambiguous abort, never silent guess. Read-only — no STATE edits, no auto-fix. Sets `scripts/` dir precedent.

**Alternatives considered:** (a) Pure-skill no-helper (Approach C) — slow, expensive, weak test contract. (b) Full coverage drift = exit + diff + commit-subject match + GitHub CI status (Option D from brainstorm) — over-engineered, GitHub-coupled, alienates GitLab/Bitbucket. (c) Auto-fix `--fix` flag — blurs read-only diagnostic line.

**Revisit when:** GitLab/Bitbucket users request CI-status drift checking, OR a `--fix` write-mode is requested by ≥3 users, OR auto-detect false-positive rate exceeds 1-in-10 invocations (e.g. detects npm test in a project where `npm test` doesn't actually verify anything).

**Superseded by:** —
**Valid until:** triggers above.
```

- [ ] **Step 3: Commit**

```bash
git add docs/STATE.md docs/DECISIONS.md
git commit -m "chore: log v0.7.4 scribe-verify decision + state update"
```

### Task 6.2: Version bump + CHANGELOG + tag

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: Bump plugin.json**

In `.claude-plugin/plugin.json`, change `"version": "0.7.3"` → `"version": "0.7.4"`.

- [ ] **Step 2: Bump README badge**

In `README.md`, change `version-0.7.3-blue` → `version-0.7.4-blue`.

- [ ] **Step 3: Prepend CHANGELOG v0.7.4 entry**

Above the v0.7.3 entry in `CHANGELOG.md`:

```markdown
## v0.7.4 — `/project-scribe:scribe-verify` verification gate

### Added

- New `/project-scribe:scribe-verify` slash command + `scribe-verify` skill. Read-only diagnostic that runs the project's verify command, parses STATE.md "Last shipped" top entry, and reports git drift since the claimed SHA. Catches "lying-by-omission" (claimed ship that broke tests, commits since the claim, missing/dirty SHA).
- Hybrid 4-step verify-cmd resolution: `docs/.scribe-verify.sh` → `CLAUDE.md ## Verify` section → auto-detect by project file (npm/cargo/pytest/make/go/bundle/composer/mix/flutter) → markdown error pointing at fix.
- Multi-match fuzzy SHA = ⚠️ ambiguous abort with candidate list. No silent guessing.
- Markdown report with verdict glyph (✅ / ⚠️ / ❌), section-per-check, context-sensitive suggested fixes.
- 19 bats cases (16 script logic + 3 skill contract).
- Sets `scripts/` dir precedent for upcoming Context Audit + token-budget tab features.

### Notes

- Configuration: `SCRIBE_VERIFY_TIMEOUT=N` env var overrides default 300s timeout for slow test suites.
- Read-only. No STATE.md edits, no git mutation. User reads + acts.
- Plan: `docs/superpowers/plans/2026-04-30-scribe-verify.md`. Spec: `docs/superpowers/specs/2026-04-30-scribe-verify-design.md`.
```

- [ ] **Step 4: Commit + tag**

```bash
git add .claude-plugin/plugin.json README.md CHANGELOG.md
git commit -m "chore: bump v0.7.4 — scribe-verify"
git tag -a v0.7.4 -m "v0.7.4 — /project-scribe:scribe-verify verification gate"
```

(Do not push tag from controller — controller handles after PR merges to master, mirroring v0.7.3 process.)

---

## Acceptance criteria

- [ ] `bash tests/run.sh` exits 0; total cases = previous (31) + 19 new = ~50 (1 documented skip from v0.7.3 still present)
- [ ] `bash scripts/scribe-verify.sh` from inside scribe repo (with temp `docs/.scribe-verify.sh` planted) emits ✅ all green report on clean master
- [ ] `bash scripts/scribe-verify.sh` exit codes: 0 / 1 / 2 per matrix in spec
- [ ] All 16 cases in `tests/scripts/scribe-verify.bats` pass
- [ ] All 3 cases in `tests/skills/scribe-verify.bats` pass
- [ ] `commands/scribe-verify.md` follows the same frontmatter shape as `commands/scribe-status.md`, `commands/xref-lint.md`
- [ ] `skills/scribe-verify/SKILL.md` discoverable via `name:` field
- [ ] DECISIONS.md has v0.7.4 entry
- [ ] CHANGELOG.md has v0.7.4 entry as top section
- [ ] plugin.json shows `"version": "0.7.4"`
- [ ] README badge shows v0.7.4
- [ ] Tag `v0.7.4` exists locally (push deferred to controller)

## Out-of-scope follow-ups (file separately)

- CI-status drift checking (GitHub coupling)
- `--fix` write-mode for automatic STATE.md updates
- Caching verify-cmd resolution across invocations
- Parallel verify across multiple test commands
- Auto-detect for additional toolchains (Zig, Nim, Crystal, etc.)
- Worktree-aware verify (skipped per 2026-04-30 decision)
