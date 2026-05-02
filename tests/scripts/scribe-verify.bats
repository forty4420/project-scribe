#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'

setup() {
  sandbox::create
  fixtures::seed_state
  export HOME="$SANDBOX_DIR/home"
  mkdir -p "$HOME/.claude"
}
teardown() { sandbox::cleanup; }

@test "resolve: docs/.scribe-verify.sh wins over auto-detect" {
  echo '{"name":"x"}' > "$SANDBOX_DIR/package.json"
  cat > "$SANDBOX_DIR/docs/.scribe-verify.sh" <<'EOF'
#!/usr/bin/env bash
echo explicit
EOF
  chmod +x "$SANDBOX_DIR/docs/.scribe-verify.sh"

  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_output --partial "docs/.scribe-verify.sh"
}

@test "resolve: CLAUDE.md ## Verify section beats auto-detect" {
  echo '{"name":"x"}' > "$SANDBOX_DIR/package.json"
  cat > "$SANDBOX_DIR/CLAUDE.md" <<'EOF'
# Project

## Verify

```bash
echo from-claude-md
```

## Other
EOF
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_output --partial "CLAUDE.md ## Verify"
}

@test "resolve: auto-detect package.json → npm test" {
  echo '{"name":"x"}' > "$SANDBOX_DIR/package.json"
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_output --partial "npm test"
  assert_output --partial "auto-detected from package.json"
}

@test "resolve: nothing matches → exit 2 + error report" {
  run env HOOK="$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh" \
      bash -c 'cd "$1" && bash "$HOOK"' _ "$SANDBOX_DIR"
  assert_failure 2
  assert_output --partial "no verify command found"
}
