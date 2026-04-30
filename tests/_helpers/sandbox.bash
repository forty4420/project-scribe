# Sandbox helpers — isolated tmp project dir for hook/skill testing.

sandbox::create() {
  if [ -n "${SANDBOX_DIR:-}" ] && [ -d "$SANDBOX_DIR" ]; then
    sandbox::cleanup
  fi
  SANDBOX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scribe-test-sandbox.XXXXXX")"
  mkdir -p "$SANDBOX_DIR/docs"
  export SANDBOX_DIR
  export CLAUDE_PROJECT_DIR="$SANDBOX_DIR"
  export CLAUDE_PLUGIN_ROOT="${BATS_TEST_DIRNAME}/.."
}

sandbox::cleanup() {
  if [ -n "${SANDBOX_DIR:-}" ] && [ -d "$SANDBOX_DIR" ]; then
    rm -rf "$SANDBOX_DIR"
  fi
  unset SANDBOX_DIR CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT
}
