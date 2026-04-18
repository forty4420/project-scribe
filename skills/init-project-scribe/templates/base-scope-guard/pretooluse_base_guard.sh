#!/usr/bin/env bash
# PreToolUse hook — blocks Write/Edit operations that would create files in
# base paths (src-tauri/src/ or src/components/) not on the BASE_ALLOWLIST.
#
# Protocol (per Claude Code hook docs):
#   - Input: JSON on stdin with { tool_name, tool_input }
#   - Allow: exit 0 (silent) or exit 0 with stdout message
#   - Block: exit 2 with message on stderr (presented to Claude)
#   - Other non-zero: shown to user as error but doesn't block
#
# Design: fail-open if allowlist is missing. Fail-closed only on clear violations.

set -euo pipefail

ALLOWLIST="docs/BASE_ALLOWLIST.md"

# Fail-open: if allowlist isn't in this project, skip the hook silently.
# This keeps the hook safe when cwd is a non-scribe-enabled project.
if [[ ! -f "$ALLOWLIST" ]]; then
  exit 0
fi

# Read JSON input. Use jq if available, else minimal grep fallback.
INPUT=$(cat)

get_field() {
  local field="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$INPUT" | jq -r ".$field // empty"
  else
    # Naive grep fallback — good enough for flat one-level fields
    echo "$INPUT" | grep -oE "\"$field\"\\s*:\\s*\"[^\"]*\"" | head -1 | sed -E "s/.*\":\\s*\"([^\"]*)\".*/\\1/"
  fi
}

# Escape a string for safe embedding in a JSON string literal.
json_escape() {
  # Order matters: backslash first, then quote, then control chars.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Emit a PreToolUse deny decision as JSON on stdout and exit 0.
# Per Claude Code hook spec (late 2025+): JSON stdout with
# hookSpecificOutput.permissionDecision="deny" is the canonical block signal,
# and unlike exit 2 it is respected under permission_mode="bypassPermissions".
emit_deny() {
  local reason
  reason="$(json_escape "$1")"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

TOOL_NAME=$(get_field "tool_name")

# Only gate Write and Edit. Read/Bash/etc pass through.
case "$TOOL_NAME" in
  Write|Edit|NotebookEdit) ;;
  *) exit 0 ;;
esac

# Extract target file path. Write uses `file_path`; Edit uses `file_path`.
if command -v jq >/dev/null 2>&1; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
else
  FILE_PATH=$(echo "$INPUT" | grep -oE "\"file_path\"\\s*:\\s*\"[^\"]*\"" | head -1 | sed -E 's/.*":\s*"([^"]*)".*/\1/')
fi

if [[ -z "$FILE_PATH" ]]; then
  # No path means nothing to gate. Allow.
  exit 0
fi

# Normalize: strip absolute-path prefix if it matches cwd.
CWD=$(pwd)
RELPATH="${FILE_PATH#"$CWD"/}"
# Normalize Windows drive-letter cases (C:\Users\... vs /c/Users/...)
RELPATH_ALT1="${FILE_PATH#//*/}"   # strip //c/...
# Normalize Windows path: C:\a\b -> a/b (drop drive + convert slashes)
RELPATH_ALT2="$(echo "$FILE_PATH" | sed -E 's|^[A-Za-z]:[/\\]||; s|\\|/|g')"
# Strip CWD-without-drive prefix from ALT2 (handles C:\cwd\sub\file.rs case)
CWD_NODRIVE="$(echo "$CWD" | sed -E 's|^/[A-Za-z]/||; s|^[A-Za-z]:[/\\]||; s|\\|/|g')"
RELPATH_ALT3="${RELPATH_ALT2#"$CWD_NODRIVE"/}"

# Pick whichever starts with a broad guarded prefix (src-tauri/ or src/).
# Broadened 2026-04-18 to close Scenario C (outside-prefix drift).
for P in "$RELPATH" "$RELPATH_ALT1" "$RELPATH_ALT2" "$RELPATH_ALT3"; do
  case "$P" in
    src-tauri/*|src/*)
      RELPATH="$P"
      break
      ;;
  esac
done

# Only inspect files under broad guarded prefixes
case "$RELPATH" in
  src-tauri/*|src/*) ;;
  *) exit 0 ;;
esac

# Known-good top-level dirs (infrastructure) — these pass without allowlist check.
# New files in these dirs are normal development. Only invented top-levels
# (e.g. src-tauri/daemons/, src/services/) get caught.
SRCTAURI_OK="src assets capabilities tests gen icons resources"
SRC_OK="assets components hooks lib plugins providers remote roles"

is_known_toplevel() {
  local path="$1"
  case "$path" in
    src-tauri/*)
      local sub="${path#src-tauri/}"
      local top="${sub%%/*}"
      [[ "$sub" == "$top" ]] && return 0
      for ok in $SRCTAURI_OK; do
        [[ "$top" == "$ok" ]] && return 0
      done
      return 1
      ;;
    src/*)
      local sub="${path#src/}"
      local top="${sub%%/*}"
      [[ "$sub" == "$top" ]] && return 0
      for ok in $SRC_OK; do
        [[ "$top" == "$ok" ]] && return 0
      done
      return 1
      ;;
  esac
  return 0
}

# Catch NEW top-level dirs under src-tauri/ or src/ (Scenario C).
if ! is_known_toplevel "$RELPATH"; then
  TOP_MSG="🚫 New top-level dir under guarded prefix — write blocked.

Target: $RELPATH
Reason: Path creates a new top-level directory not in the known-good set.
Known-good under src-tauri/: $SRCTAURI_OK
Known-good under src/:        $SRC_OK

If this is legitimately base infrastructure:
  1. Log a DECISIONS.md entry justifying the new top-level dir.
  2. Add it to \$SRCTAURI_OK or \$SRC_OK in both:
     .claude/hooks/pretooluse_base_guard.sh
     .claude/hooks/precommit_base_guard.sh
  3. Re-try the write.

If this is plugin territory (VISION §7 Rule 1):
  Scaffold under ~/.ownterm/<category>/<name>/ instead.

See: CLAUDE.md \"Rule-drift watch\" + docs/audits/2026-04-18-base-scope-audit.md"
  echo "$TOP_MSG" >&2
  emit_deny "$TOP_MSG"
fi

# Files outside src-tauri/src/ and src/components/ but under a known-good
# top-level are infrastructure — pass without allowlist check.
case "$RELPATH" in
  src-tauri/src/*|src/components/*) ;;
  *) exit 0 ;;
esac

# Check if file already exists — if it does, we're modifying, not creating.
# Modifications are allowed; only NEW base files need allowlist vetting.
if [[ -f "$FILE_PATH" ]] || [[ -f "$RELPATH" ]]; then
  exit 0
fi

# File does not exist yet. This is a NEW file under a guarded prefix.
# Check allowlist. A path is allowed if its directory or the file itself
# is listed in an "allowed" section and NOT in a "NOT allowed" section.

# Check for "NOT allowed" first — explicit violations.
# We look for paths like `persona/`, `providers/`, `tools/`, `PersonaManager.tsx`
# inside blocks marked "NOT allowed".
BLOCKED_PATTERNS=$(awk '
  # Level 2 headers reset state based on their text
  /^## / {
    if ($0 ~ /NOT allowed/) { in_block = 1 }
    else if ($0 ~ /allowed/) { in_block = 0 }
    else { in_block = 0 }
    next
  }
  # Level 3 headers that mention allowed/NOT allowed override; otherwise inherit
  /^### / {
    if ($0 ~ /NOT allowed/) { in_block = 1 }
    else if ($0 ~ /allowed/) { in_block = 0 }
    # else: inherit previous in_block
    next
  }
  in_block && /^- `[^`]+`/ {
    match($0, /`[^`]+`/)
    token = substr($0, RSTART + 1, RLENGTH - 2)
    # strip trailing slash for directories
    sub(/\/$/, "", token)
    print token
  }
' "$ALLOWLIST")

# Check if RELPATH matches any blocked pattern
BLOCKED_MATCH=""
while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue
  # Match as prefix (directory) or exact (file)
  case "$RELPATH" in
    src-tauri/src/"$pattern"/*|src-tauri/src/"$pattern"|src/components/"$pattern"/*|src/components/"$pattern")
      BLOCKED_MATCH="$pattern"
      break
      ;;
  esac
done <<<"$BLOCKED_PATTERNS"

if [[ -n "$BLOCKED_MATCH" ]]; then
  MSG="🔒 Base file locked — write blocked.

Target: $RELPATH
Reason: Path matches \"NOT allowed\" pattern \"$BLOCKED_MATCH\" in $ALLOWLIST.

This module violates VISION §7 Rule 1 (all features beyond base are plugins).
It must migrate out of base before new files are added to it.

────────────────────────────────────────────────
NORMAL PATH (migration): keep this file locked.
  1. Write a DECISIONS.md entry amending the classification.
  2. Move the path from \"NOT allowed\" to \"allowed\" in $ALLOWLIST.
  3. Re-try the write.

ESCAPE HATCH (edit anyway, rare): unlock temporarily.
  Run: /unlock-base
  Unlocks the 3 guarded dirs, offers to restart (settings need restart
  to take effect). Then edit. Then run: /lock-base  to re-engage the guard.
────────────────────────────────────────────────

See: docs/audits/2026-04-18-base-scope-audit.md for context."
  echo "$MSG" >&2
  emit_deny "$MSG"
fi

# Not explicitly blocked. Check if it's in an "allowed" section.
# Level 2 headers set the section context. Level 3 subheaders don't change
# unless they explicitly mention allowed/NOT allowed.
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
    # else: inherit
    next
  }
  in_block && /^- `[^`]+`/ {
    match($0, /`[^`]+`/)
    token = substr($0, RSTART + 1, RLENGTH - 2)
    sub(/\/$/, "", token)
    print token
  }
' "$ALLOWLIST")

ALLOWED_MATCH=""
while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue
  case "$RELPATH" in
    src-tauri/src/"$pattern"/*|src-tauri/src/"$pattern"|src/components/"$pattern"/*|src/components/"$pattern")
      ALLOWED_MATCH="$pattern"
      break
      ;;
  esac
done <<<"$ALLOWED_PATTERNS"

if [[ -n "$ALLOWED_MATCH" ]]; then
  # Explicitly allowed — pass
  exit 0
fi

# Not in allowlist, not in blocklist — this is a NEW path under a guarded prefix.
# Require explicit review.
MSG="⚠️  NEW base path requires allowlist entry — write blocked.

Target: $RELPATH
This path is under a guarded prefix (src-tauri/src/ or src/components/) but is
neither explicitly allowed nor explicitly blocked in $ALLOWLIST.

To proceed:
  1. Decide: is this base (VISION §5, §8 primitive) or a plugin?
  2. If base: add the path to $ALLOWLIST with a VISION citation, log a decision.
  3. If plugin: create it under ~/.ownterm/<category>/<name>/ instead.

This is a rule-drift guard. See CLAUDE.md \"Rule-drift watch\" section."
echo "$MSG" >&2
emit_deny "$MSG"
