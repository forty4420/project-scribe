#!/usr/bin/env bats
#
# Tests for hooks/userprompt-context-warn.
#
# Hook gates:
#   1. cwd contains docs/STATE.md (scribe-enabled project)
#   2. ${HOME}/.claude/.scribe-context exists
#   3. context pct is integer 0-100
#   4. data is fresh (mtime within 1 hour)
#   5. pct >= 30
#   6. bucket (pct/5*5) > last_bucket recorded in .scribe-context-last-warn
#
# The hook ignores prompt content entirely. It reads no env vars from
# Claude Code's CLAUDE_USER_PROMPT — only the on-disk context-pct file.

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'
load '../_helpers/claude_env'

setup() {
  sandbox::create
  fixtures::seed_all
  # MANDATORY: override HOME so hook doesn't read/write the developer's
  # real ~/.claude/.scribe-context file. Without this, tests can pollute
  # real cooldown state and read state from the running session.
  export HOME="$SANDBOX_DIR/home"
  mkdir -p "$HOME/.claude"
}

teardown() {
  sandbox::cleanup
  claude_env::clear
}

@test "userprompt-context-warn exits 0 with no context file (silent gate)" {
  # Gate 2 fails — no $HOME/.claude/.scribe-context. Hook exits 0 silently.
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/userprompt-context-warn"
  assert_success
  assert_output ""
}

@test "userprompt-context-warn exits 0 silently when pct below threshold" {
  # Hook ignores prompt content. Stub context file with low pct.
  printf '5\n%s\n' "$(date +%s)" > "$HOME/.claude/.scribe-context"
  claude_env::user_prompt "any prompt"
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/userprompt-context-warn"
  assert_success
  # Below 30% threshold — no warning emitted.
  assert_output ""
}

@test "userprompt-context-warn emits warning at 40%+ (call-to-action)" {
  printf '45\n%s\n' "$(date +%s)" > "$HOME/.claude/.scribe-context"
  claude_env::user_prompt "any prompt"
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/userprompt-context-warn"
  assert_success
  assert_output --partial "Context at 45%"
  assert_output --partial "/handoff"
}

@test "userprompt-context-warn ignores prompt content (long/empty same as normal)" {
  # Hook reads no env vars from Claude Code's user prompt — only the
  # on-disk context file. This test locks that contract in: the same
  # context file produces the same hook output regardless of prompt size.
  printf '35\n%s\n' "$(date +%s)" > "$HOME/.claude/.scribe-context"
  cd "$SANDBOX_DIR"

  claude_env::user_prompt ""
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/userprompt-context-warn"
  assert_success
  local empty_output="$output"

  # Reset cooldown so second run doesn't get gated by bucket dedupe.
  rm -f "$HOME/.claude/.scribe-context-last-warn"

  claude_env::user_prompt "$(printf 'x%.0s' {1..5000})"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/userprompt-context-warn"
  assert_success
  assert_equal "$output" "$empty_output"
}

@test "userprompt-context-warn exits 0 silently when pct file is stale" {
  # Mtime gate: data older than 1 hour is treated as a previous session.
  # 7200s ago = 2 hours ago, well past the 3600s freshness window.
  local stale_ts=$(($(date +%s) - 7200))
  printf '50\n%s\n' "$stale_ts" > "$HOME/.claude/.scribe-context"
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/userprompt-context-warn"
  assert_success
  assert_output ""
}
