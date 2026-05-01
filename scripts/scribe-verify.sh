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
