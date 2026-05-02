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
