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
        # extract content of FIRST fenced code block only. Stops at the
        # closing fence so subsequent example/non-example blocks under the
        # same section don't merge into the resolved command.
        local block
        block=$(awk '
            BEGIN { in_section=0; in_block=0 }
            tolower($0) ~ /^## verify[[:space:]]*$/ { in_section=1; next }
            in_section && /^## / { exit }
            in_section && /^```/ {
                if (in_block) { exit }
                in_block=1; next
            }
            in_section && in_block { print }
        ' "$claudemd")
        if [ -n "$block" ]; then
            CLAUDEMD_TMP=$(mktemp "${TMPDIR:-/tmp}/scribe-verify-claudemd.XXXXXX")
            # Trap-based cleanup so the tmp file does not orphan in $TMPDIR
            # across many invocations. Global var so trap can resolve at
            # script EXIT (function-locals would be out of scope).
            trap 'rm -f "${CLAUDEMD_TMP:-}"' EXIT
            printf '%s\n' "$block" > "$CLAUDEMD_TMP"
            chmod +x "$CLAUDEMD_TMP"
            VERIFY_CMD="$CLAUDEMD_TMP"
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
    # `|| echo 0` guards against empty input — `grep -c .` on empty stream
    # exits 1 with count 0 inside command substitution, leaving $count empty.
    # Without the fallback, the "0" branch below mis-fires as "ambiguous."
    count=$(printf '%s' "$matches" | grep -c . || echo 0)

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

parse_claimed_sha
parse_status=$?

if [ "$parse_status" = "1" ]; then
    emit_ambiguous_report
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
emit_report
exit_code=$?
exit "$exit_code"
