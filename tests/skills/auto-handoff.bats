#!/usr/bin/env bats
#
# Tests for the auto-handoff skill.
#
# Skills are markdown SOPs (no executable). The tests assert on the *contract* —
# the shape of the file mutations the skill is documented to produce. auto-handoff
# is documented to produce a markdown bundle at docs/handoff/<date>-<slug>.md
# with four required sections.

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'

setup() {
  sandbox::create
  fixtures::seed_all
  mkdir -p "$SANDBOX_DIR/docs/handoff"
}

teardown() {
  sandbox::cleanup
}

@test "auto-handoff contract: bundle file exists at docs/handoff/" {
  local bundle="$SANDBOX_DIR/docs/handoff/2026-04-30-test.md"
  cat > "$bundle" <<'EOF'
# Handoff — Test

## Current state
(snapshot)

## Recent decisions
(top 3 from DECISIONS.md)

## Memory health
(scribe-status excerpt)

## Open questions
(any)
EOF
  assert [ -f "$bundle" ]
}

@test "auto-handoff contract: bundle has all 4 required sections" {
  local bundle="$SANDBOX_DIR/docs/handoff/2026-04-30-test.md"
  cat > "$bundle" <<'EOF'
# Handoff — Test
## Current state
x
## Recent decisions
y
## Memory health
z
## Open questions
w
EOF
  run cat "$bundle"
  assert_success
  assert_output --partial "## Current state"
  assert_output --partial "## Recent decisions"
  assert_output --partial "## Memory health"
  assert_output --partial "## Open questions"
}
