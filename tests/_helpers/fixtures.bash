# Known-good fixture content for STATE.md / DECISIONS.md / MEMORY.md.
# Tests can call fixtures::seed to drop them into the sandbox.

fixtures::seed_state() {
  cat > "$SANDBOX_DIR/docs/STATE.md" <<'EOF'
# Project State — scribe-test-sandbox

## Current focus
Test scenario.

## Last shipped
- v0.0.1 — initial fixture — abc1234

## Next up
- Run more tests

## Deferred
(none)

## Specs
(none active)

## Plans
(none)
EOF
}

fixtures::seed_decisions() {
  cat > "$SANDBOX_DIR/docs/DECISIONS.md" <<'EOF'
# Decisions

## 2026-04-30 — Test fixture decision
**Context:** Testing.
**Decision:** Use fixtures.
**Alternatives considered:** Hardcode in tests.
**Revisit when:** Never.
EOF
}

fixtures::seed_memory_index() {
  cat > "$SANDBOX_DIR/MEMORY.md" <<'EOF'
- [Test rule](rule_test.md) — Sample memory entry for fixture
EOF
  cat > "$SANDBOX_DIR/rule_test.md" <<'EOF'
---
name: test rule
description: Sample memory entry
type: feedback
last_used: 2026-04-30
hits: 1
---

Test memory body.
EOF
}

fixtures::seed_all() {
  fixtures::seed_state
  fixtures::seed_decisions
  fixtures::seed_memory_index
}
