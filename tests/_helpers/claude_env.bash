# Mock the Claude Code env vars hooks expect.
# Real values come from Claude Code at runtime; tests inject sane defaults.

claude_env::default() {
  export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SANDBOX_DIR}"
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${BATS_TEST_DIRNAME}/..}"
  export CLAUDE_HOOK_EVENT="${CLAUDE_HOOK_EVENT:-SessionStart}"
  export CLAUDE_TRANSCRIPT_PATH=""
  export CLAUDE_SESSION_ID="test-session-$$"
}

claude_env::session_start() {
  claude_env::default
  export CLAUDE_HOOK_EVENT="SessionStart"
  export CLAUDE_HOOK_MATCHER="${1:-startup}"  # startup|resume|clear|compact
}

claude_env::user_prompt() {
  claude_env::default
  export CLAUDE_HOOK_EVENT="UserPromptSubmit"
  export CLAUDE_USER_PROMPT="${1:-test prompt}"
}

claude_env::pre_compact() {
  claude_env::default
  export CLAUDE_HOOK_EVENT="PreCompact"
  export CLAUDE_HOOK_MATCHER="${1:-manual}"
}

claude_env::stop() {
  claude_env::default
  export CLAUDE_HOOK_EVENT="Stop"
}

claude_env::clear() {
  unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_HOOK_EVENT \
        CLAUDE_HOOK_MATCHER CLAUDE_TRANSCRIPT_PATH CLAUDE_SESSION_ID \
        CLAUDE_USER_PROMPT
}
