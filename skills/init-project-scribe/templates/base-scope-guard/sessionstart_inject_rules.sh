#!/usr/bin/env bash
# SessionStart hook — injects top-of-allowlist + Locked rules into the new
# session so Claude sees the rules without having to read CLAUDE.md first.
#
# Protocol: stdout is inserted into session context. No stderr, no nonzero
# exit (would abort session setup).

set -uo pipefail

ALLOWLIST="docs/BASE_ALLOWLIST.md"
CLAUDEMD="CLAUDE.md"

# Fail-silent if not a scribe-enabled project
if [[ ! -f "$ALLOWLIST" ]] && [[ ! -f "$CLAUDEMD" ]]; then
  exit 0
fi

cat <<EOF
=== Base-scope enforcement active ===

This project uses BASE_ALLOWLIST.md + PreToolUse hook to prevent rule-drift.
Writes to new paths under src-tauri/src/ or src/components/ are blocked
unless the path is listed in docs/BASE_ALLOWLIST.md.

Quick rules (full list in CLAUDE.md "Locked" + VISION §7):
  - All features beyond base are plugins. VISION §7 Rule 1.
  - NEVER add new persona/, providers/, or tools/ files to base. Migrate instead.
  - New base paths require a DECISIONS.md entry + allowlist edit BEFORE code.
  - Run /audit before committing changes under guarded paths.

EOF

if [[ -f "$ALLOWLIST" ]]; then
  echo "=== BASE_ALLOWLIST.md (NOT allowed sections) ==="
  echo ""
  awk '
    /^## / {
      if ($0 ~ /NOT allowed/) { in_block = 1; print; next }
      else { in_block = 0 }
    }
    in_block { print }
  ' "$ALLOWLIST"
  echo ""
fi

echo "=== End of session-start context ==="
