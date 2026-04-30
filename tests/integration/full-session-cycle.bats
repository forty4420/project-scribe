#!/usr/bin/env bats
#
# Integration test — exercise the full hook chain end-to-end against a
# seeded sandbox project.
#
# Notes (mirrored from chunk-2 hook tests):
#   - Hooks read PROJECT_ROOT from `$(pwd)`, not from $CLAUDE_PROJECT_DIR.
#     Each hook invocation must run with cwd = $SANDBOX_DIR.
#   - pre-compact and stop-mark-memory read transcript_path from stdin
#     JSON. Use the env-var indirection pattern: `env HOOK=... bash -c
#     'echo "{}" | bash "$HOOK"'`.
#   - Hook files were committed with CRLF line endings, so direct exec
#     fails kernel shebang lookup. Always invoke via `bash <hook-path>`.
#   - HOME must be redirected so hooks don't touch the developer's real
#     ~/.claude state.

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'
load '../_helpers/claude_env'

setup() {
  sandbox::create
  fixtures::seed_all
  export HOME="$SANDBOX_DIR/home"
  mkdir -p "$HOME/.claude"
  # Initialize git in the sandbox so hooks/skills that introspect git
  # history have something to read. Subshell keeps the cd local.
  (
    cd "$SANDBOX_DIR"
    git init -q
    git config user.email "test@test"
    git config user.name "test"
    git add -A
    git commit -q -m "v0.0.1 — initial fixture"
  )
}

teardown() {
  sandbox::cleanup
  claude_env::clear
}

@test "integration: SessionStart → user prompt → Stop — all hooks exit 0" {
  # 1. SessionStart (startup)
  claude_env::session_start "startup"
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success

  # 2. UserPromptSubmit — no .scribe-context file present, so the hook
  #    should silently exit 0 (gate 2 fails). That's the realistic
  #    quiescent state at session start.
  claude_env::user_prompt "test prompt"
  cd "$SANDBOX_DIR"
  run bash "$CLAUDE_PLUGIN_ROOT/hooks/userprompt-context-warn"
  assert_success

  # 3. Stop — empty stdin, hook is currently expected to exit 0 with a
  #    transcript file present. Without one, set -euo pipefail + grep
  #    can return 1 (see stop-mark-memory.bats note). Plant a minimal
  #    transcript that has no memory references → no-op exit 0.
  claude_env::stop
  local transcript="$SANDBOX_DIR/transcript.jsonl"
  printf '{"role":"user","content":"unrelated"}\n' > "$transcript"
  cd "$SANDBOX_DIR"
  run env HOOK="$CLAUDE_PLUGIN_ROOT/hooks/stop-mark-memory" TRANSCRIPT="$transcript" \
      bash -c 'printf "{\"transcript_path\":\"%s\"}" "$TRANSCRIPT" | bash "$HOOK"'
  assert_success
}

@test "integration: PreCompact does not corrupt seeded state" {
  # PreCompact contract: writes docs/.scribe-snapshot.md but leaves
  # STATE.md and DECISIONS.md byte-for-byte unchanged. Snapshot creation
  # is expected behavior, not corruption — we don't check that here.
  local state_before
  local decisions_before
  state_before=$(sha256sum "$SANDBOX_DIR/docs/STATE.md" | cut -d' ' -f1)
  decisions_before=$(sha256sum "$SANDBOX_DIR/docs/DECISIONS.md" | cut -d' ' -f1)

  claude_env::pre_compact "manual"
  cd "$SANDBOX_DIR"
  run env HOOK="$CLAUDE_PLUGIN_ROOT/hooks/pre-compact" \
      bash -c 'echo "{}" | bash "$HOOK"'
  assert_success

  local state_after
  local decisions_after
  state_after=$(sha256sum "$SANDBOX_DIR/docs/STATE.md" | cut -d' ' -f1)
  decisions_after=$(sha256sum "$SANDBOX_DIR/docs/DECISIONS.md" | cut -d' ' -f1)
  assert_equal "$state_before" "$state_after"
  assert_equal "$decisions_before" "$decisions_after"
}
