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

# === Canary: guardrail health check ===
# If critical guardrail files are missing or corrupted, shout. Silent failure
# is the worst mode.
CANARY_ISSUES=""
PRECOMMIT=".git/hooks/pre-commit"
PRETOOLUSE=".claude/hooks/pretooluse_base_guard.sh"
PROJECT_SETTINGS=".claude/settings.json"

if [[ ! -x "$PRECOMMIT" ]]; then
  CANARY_ISSUES+="  - .git/hooks/pre-commit missing or not executable"$'\n'
fi
if [[ ! -f "$PRETOOLUSE" ]]; then
  CANARY_ISSUES+="  - .claude/hooks/pretooluse_base_guard.sh missing"$'\n'
fi
if [[ ! -f "$PROJECT_SETTINGS" ]] || ! grep -q '"deny"' "$PROJECT_SETTINGS" 2>/dev/null; then
  CANARY_ISSUES+="  - .claude/settings.json missing or lacks permissions.deny block"$'\n'
fi

if [[ -n "$CANARY_ISSUES" ]]; then
  echo "⚠️  GUARDRAIL HEALTH WARNING ⚠️"
  echo "One or more guardrail files missing/corrupted:"
  echo ""
  printf '%s' "$CANARY_ISSUES"
  echo ""
  echo "Base-scope enforcement is DEGRADED. Restore before touching base code."
  echo ""
fi

# === Working-tree scan: drift sitting uncommitted from prior session ===
# Runs same allowlist logic as pre-commit against untracked + modified files.
# Flags new files under guarded prefixes that would fail pre-commit.
if command -v git >/dev/null 2>&1 && [[ -d .git ]]; then
  # Get untracked (??) + added-but-unstaged files under src-tauri/ or src/
  DRIFT=$(git status --porcelain 2>/dev/null | awk '
    /^\?\? src-tauri\//  { print $2 }
    /^\?\? src\//        { print $2 }
    /^A  src-tauri\//    { print $2 }
    /^A  src\//          { print $2 }
  ')

  if [[ -n "$DRIFT" ]]; then
    SRCTAURI_OK="src assets capabilities tests gen icons resources"
    SRC_OK="assets components hooks lib plugins providers remote roles"

    FLAGGED=""
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      case "$path" in
        src-tauri/*)
          sub="${path#src-tauri/}"
          top="${sub%%/*}"
          if [[ "$sub" != "$top" ]]; then
            known=0
            for ok in $SRCTAURI_OK; do [[ "$top" == "$ok" ]] && known=1; done
            [[ $known -eq 0 ]] && FLAGGED+="  - $path (new top-level dir)"$'\n'
          fi
          ;;
        src/*)
          sub="${path#src/}"
          top="${sub%%/*}"
          if [[ "$sub" != "$top" ]]; then
            known=0
            for ok in $SRC_OK; do [[ "$top" == "$ok" ]] && known=1; done
            [[ $known -eq 0 ]] && FLAGGED+="  - $path (new top-level dir)"$'\n'
          fi
          ;;
      esac
      # Also flag untracked under src-tauri/src/ or src/components/ —
      # pre-commit would reject these at commit time; surface now.
      case "$path" in
        src-tauri/src/persona/*|src-tauri/src/providers/*|src-tauri/src/tools/*|src/components/PersonaManager.tsx)
          FLAGGED+="  - $path (inside NOT-allowed dir)"$'\n'
          ;;
      esac
    done <<<"$DRIFT"

    if [[ -n "$FLAGGED" ]]; then
      echo "⚠️  UNCOMMITTED BASE-SCOPE DRIFT DETECTED ⚠️"
      echo "The following uncommitted files would fail pre-commit:"
      echo ""
      printf '%s' "$FLAGGED"
      echo ""
      echo "Resolve before committing: move to ~/.ownterm/<category>/<name>/"
      echo "or log a DECISIONS.md entry + add to BASE_ALLOWLIST."
      echo ""
    fi
  fi
fi

echo "=== End of session-start context ==="
