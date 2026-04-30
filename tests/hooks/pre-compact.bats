#!/usr/bin/env bats
#
# Tests for hooks/pre-compact.
#
# Hook reads stdin JSON for transcript_path. Writes a snapshot to
# docs/.scribe-snapshot.md. Never modifies STATE.md or DECISIONS.md.

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
}

teardown() {
  sandbox::cleanup
  claude_env::clear
}

@test "pre-compact exits 0 on manual compact (no transcript path)" {
  # Empty stdin — hook tolerates missing transcript_path and still writes
  # a snapshot with whatever it can extract from STATE.md.
  cd "$SANDBOX_DIR"
  run env HOOK="$CLAUDE_PLUGIN_ROOT/hooks/pre-compact" \
      bash -c 'echo "" | bash "$HOOK"'
  assert_success
}

@test "pre-compact writes snapshot when transcript provided (auto compact)" {
  # The snapshot file is the contract. Stronger assertion than exit 0.
  local transcript="$SANDBOX_DIR/transcript.jsonl"
  printf '{"role":"user","content":"hello world"}\n' > "$transcript"
  cd "$SANDBOX_DIR"
  run env HOOK="$CLAUDE_PLUGIN_ROOT/hooks/pre-compact" TRANSCRIPT="$transcript" \
      bash -c 'printf "{\"transcript_path\":\"%s\"}" "$TRANSCRIPT" | bash "$HOOK"'
  assert_success
  assert [ -f "$SANDBOX_DIR/docs/.scribe-snapshot.md" ]
  # Snapshot should embed extracted Current focus from seeded STATE.md.
  run cat "$SANDBOX_DIR/docs/.scribe-snapshot.md"
  assert_success
  assert_output --partial "Current focus"
  assert_output --partial "Test scenario"
}

@test "pre-compact extracts last user prompt from transcript" {
  local transcript="$SANDBOX_DIR/transcript.jsonl"
  cat > "$transcript" <<'EOF'
{"role":"user","content":"first prompt"}
{"role":"assistant","content":"reply"}
{"role":"user","content":"second prompt MARKER"}
EOF
  cd "$SANDBOX_DIR"
  run env HOOK="$CLAUDE_PLUGIN_ROOT/hooks/pre-compact" TRANSCRIPT="$transcript" \
      bash -c 'printf "{\"transcript_path\":\"%s\"}" "$TRANSCRIPT" | bash "$HOOK"'
  assert_success
  run cat "$SANDBOX_DIR/docs/.scribe-snapshot.md"
  assert_success
  assert_output --partial "MARKER"
}

@test "pre-compact does not modify STATE.md" {
  local before
  before=$(sha256sum "$SANDBOX_DIR/docs/STATE.md" | cut -d' ' -f1)
  cd "$SANDBOX_DIR"
  run env HOOK="$CLAUDE_PLUGIN_ROOT/hooks/pre-compact" \
      bash -c 'echo "" | bash "$HOOK"'
  assert_success
  local after
  after=$(sha256sum "$SANDBOX_DIR/docs/STATE.md" | cut -d' ' -f1)
  assert_equal "$before" "$after"
}

@test "pre-compact does not modify DECISIONS.md" {
  local before
  before=$(sha256sum "$SANDBOX_DIR/docs/DECISIONS.md" | cut -d' ' -f1)
  cd "$SANDBOX_DIR"
  run env HOOK="$CLAUDE_PLUGIN_ROOT/hooks/pre-compact" \
      bash -c 'echo "" | bash "$HOOK"'
  assert_success
  local after
  after=$(sha256sum "$SANDBOX_DIR/docs/DECISIONS.md" | cut -d' ' -f1)
  assert_equal "$before" "$after"
}

@test "pre-compact silent no-op without STATE.md (not scribe-enabled)" {
  rm -f "$SANDBOX_DIR/docs/STATE.md"
  cd "$SANDBOX_DIR"
  run env HOOK="$CLAUDE_PLUGIN_ROOT/hooks/pre-compact" \
      bash -c 'echo "" | bash "$HOOK"'
  assert_success
  # No snapshot should be created.
  assert [ ! -f "$SANDBOX_DIR/docs/.scribe-snapshot.md" ]
}
