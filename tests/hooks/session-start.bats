#!/usr/bin/env bats
#
# Tests for hooks/session-start.
#
# Note 1: hook reads PROJECT_ROOT from `$(pwd)`, NOT from $CLAUDE_PROJECT_DIR.
# We must `cd "$SANDBOX_DIR"` before invoking the hook.
#
# Note 2: hook files are committed with CRLF line endings (Windows-origin),
# so direct exec fails kernel shebang lookup on Linux/Git-Bash. We invoke
# via `bash <hook-path>` to bypass the shebang. Same path Claude Code uses
# under run-hook.cmd on Windows.

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'
load '../_helpers/claude_env'

setup() {
  sandbox::create
  fixtures::seed_all
  # Override HOME so debug log writes (if SCRIBE_DEBUG=1) and any future
  # ${HOME}-touching code never hits the developer's real ~/.claude.
  export HOME="$SANDBOX_DIR/home"
  mkdir -p "$HOME/.claude"
  claude_env::session_start "startup"
}

teardown() {
  sandbox::cleanup
  claude_env::clear
}

@test "session-start exits 0 on a well-formed scribe project" {
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success
}

@test "session-start emits the project-scribe reminder" {
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success
  # Hook emits a JSON envelope wrapping a <project-scribe> reminder that
  # tells Claude to invoke reconcile-project-state.
  assert_output --partial "project-scribe"
  assert_output --partial "reconcile-project-state"
}

@test "session-start handles missing STATE.md gracefully (silent exit 0)" {
  rm -f "$SANDBOX_DIR/docs/STATE.md"
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success
  # No STATE.md → hook should produce no JSON output (silent no-op).
  assert_output ""
}

@test "session-start with matcher=resume still exits 0" {
  # Hook does not branch on matcher (per source inspection v0.7.1).
  # Test locks in current behavior; if branching is added later, update here.
  claude_env::session_start "resume"
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success
}

@test "session-start with matcher=compact still exits 0" {
  claude_env::session_start "compact"
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success
}

@test "session-start consumes and deletes pre-compact snapshot" {
  # PreCompact contract: SessionStart consumes docs/.scribe-snapshot.md
  # one-shot, deletes it after read.
  printf 'snapshot body\n' > "$SANDBOX_DIR/docs/.scribe-snapshot.md"
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success
  assert_output --partial "snapshot body"
  assert [ ! -f "$SANDBOX_DIR/docs/.scribe-snapshot.md" ]
}
