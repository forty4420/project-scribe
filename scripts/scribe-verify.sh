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
