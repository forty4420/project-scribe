# Sandbox helpers — isolated tmp project dir for hook/skill testing.

sandbox::create() {
  if [ -n "${SANDBOX_DIR:-}" ] && [ -d "$SANDBOX_DIR" ]; then
    sandbox::cleanup
  fi
  SANDBOX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scribe-test-sandbox.XXXXXX")"
  mkdir -p "$SANDBOX_DIR/docs"
  export SANDBOX_DIR
  export CLAUDE_PROJECT_DIR="$SANDBOX_DIR"
  # Resolve plugin root: walk up from test file dir until we find a hooks/
  # sibling. Tests live at tests/hooks/*.bats, tests/skills/*.bats,
  # tests/integration/*.bats — all 2 levels deep from project root.
  CLAUDE_PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export CLAUDE_PLUGIN_ROOT
}

sandbox::cleanup() {
  if [ -n "${SANDBOX_DIR:-}" ] && [ -d "$SANDBOX_DIR" ]; then
    rm -rf "$SANDBOX_DIR"
  fi
  unset SANDBOX_DIR CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT
}
