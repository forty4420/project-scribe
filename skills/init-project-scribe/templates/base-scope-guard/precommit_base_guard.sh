#!/usr/bin/env bash
# Pre-commit hook — rejects staged changes that introduce new files under
# src-tauri/src/ or src/components/ that aren't on BASE_ALLOWLIST.md.
#
# Install with:
#   cp .claude/hooks/precommit_base_guard.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# Or symlink so updates to the script propagate:
#   ln -sf ../../.claude/hooks/precommit_base_guard.sh .git/hooks/pre-commit
#
# Exit 0 = allow commit. Exit non-zero = abort commit.

set -euo pipefail

ALLOWLIST="docs/BASE_ALLOWLIST.md"

# Fail-open if allowlist missing.
[[ -f "$ALLOWLIST" ]] || exit 0

# Files added (A) or renamed-destination (R... with new name) in this commit,
# under guarded prefixes.
STAGED=$(git diff --cached --name-only --diff-filter=A -- \
  "src-tauri/src/" "src/components/" 2>/dev/null || true)

[[ -z "$STAGED" ]] && exit 0

# Parse allowed + blocked patterns from allowlist
ALLOWED_PATTERNS=$(awk '
  /^## / {
    if ($0 ~ /NOT allowed/) { in_block = 0 }
    else if ($0 ~ /allowed/) { in_block = 1 }
    else { in_block = 0 }
    next
  }
  /^### / {
    if ($0 ~ /NOT allowed/) { in_block = 0 }
    else if ($0 ~ /allowed/) { in_block = 1 }
    next
  }
  in_block && /^- `[^`]+`/ {
    match($0, /`[^`]+`/)
    token = substr($0, RSTART + 1, RLENGTH - 2)
    sub(/\/$/, "", token)
    print token
  }
' "$ALLOWLIST")

BLOCKED_PATTERNS=$(awk '
  /^## / {
    if ($0 ~ /NOT allowed/) { in_block = 1 }
    else if ($0 ~ /allowed/) { in_block = 0 }
    else { in_block = 0 }
    next
  }
  /^### / {
    if ($0 ~ /NOT allowed/) { in_block = 1 }
    else if ($0 ~ /allowed/) { in_block = 0 }
    next
  }
  in_block && /^- `[^`]+`/ {
    match($0, /`[^`]+`/)
    token = substr($0, RSTART + 1, RLENGTH - 2)
    sub(/\/$/, "", token)
    print token
  }
' "$ALLOWLIST")

VIOLATIONS=()
REVIEWS=()

while IFS= read -r path; do
  [[ -z "$path" ]] && continue

  # Check blocked first
  HIT_BLOCKED=""
  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    case "$path" in
      src-tauri/src/"$pattern"/*|src-tauri/src/"$pattern"|src/components/"$pattern"/*|src/components/"$pattern")
        HIT_BLOCKED="$pattern"
        break
        ;;
    esac
  done <<<"$BLOCKED_PATTERNS"

  if [[ -n "$HIT_BLOCKED" ]]; then
    VIOLATIONS+=("$path (violates \"$HIT_BLOCKED\" in NOT allowed)")
    continue
  fi

  # Check allowed
  HIT_ALLOWED=""
  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    case "$path" in
      src-tauri/src/"$pattern"/*|src-tauri/src/"$pattern"|src/components/"$pattern"/*|src/components/"$pattern")
        HIT_ALLOWED="$pattern"
        break
        ;;
    esac
  done <<<"$ALLOWED_PATTERNS"

  if [[ -z "$HIT_ALLOWED" ]]; then
    REVIEWS+=("$path")
  fi
done <<<"$STAGED"

if [[ ${#VIOLATIONS[@]} -eq 0 ]] && [[ ${#REVIEWS[@]} -eq 0 ]]; then
  exit 0
fi

echo "🚫 pre-commit: BASE_ALLOWLIST violations found" >&2
echo "" >&2

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  echo "HARD VIOLATIONS (explicitly NOT allowed):" >&2
  for v in "${VIOLATIONS[@]}"; do
    echo "  - $v" >&2
  done
  echo "" >&2
fi

if [[ ${#REVIEWS[@]} -gt 0 ]]; then
  echo "NEEDS REVIEW (new base paths not on allowlist):" >&2
  for r in "${REVIEWS[@]}"; do
    echo "  - $r" >&2
  done
  echo "" >&2
fi

cat >&2 <<EOF
To proceed:
  - If these are legitimately base: log a DECISIONS.md entry, add paths to
    docs/BASE_ALLOWLIST.md, re-stage, re-commit.
  - If these should be plugins: move to ~/.ownterm/<category>/<name>/ and remove
    from src-tauri/src/ or src/components/.
  - Bypass (not recommended): git commit --no-verify

See: docs/audits/2026-04-18-base-scope-audit.md
EOF

exit 1
