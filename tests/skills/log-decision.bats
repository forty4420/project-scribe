#!/usr/bin/env bats
#
# Tests for the log-decision skill.
#
# Skills are markdown SOPs (no executable). The tests assert on the *contract* —
# the shape of the file mutations the skill is documented to produce. The bash
# inside each test simulates what a Claude following the skill would do, then
# asserts the artifact has the expected shape.

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'

setup() {
  sandbox::create
  fixtures::seed_decisions
}

teardown() {
  sandbox::cleanup
}

# log-decision says: prepend a 5-field entry to DECISIONS.md (Context / Decision /
# Alternatives considered / Revisit when, plus a dated heading).
# Contract test: a downstream parser must find the new entry as the top-most one.

@test "log-decision contract: entry includes Context/Decision/Alternatives/Revisit fields" {
  local entry='## 2026-04-30 — Test new entry
**Context:** Brand new context.
**Decision:** Take action.
**Alternatives considered:** Skip it.
**Revisit when:** Conditions change.
'
  # Prepend after the H1
  awk -v entry="$entry" 'NR==1{print; print ""; print entry; next} 1' \
    "$SANDBOX_DIR/docs/DECISIONS.md" > "$SANDBOX_DIR/docs/DECISIONS.md.new"
  mv "$SANDBOX_DIR/docs/DECISIONS.md.new" "$SANDBOX_DIR/docs/DECISIONS.md"

  run head -20 "$SANDBOX_DIR/docs/DECISIONS.md"
  assert_success
  assert_output --partial "**Context:**"
  assert_output --partial "**Decision:**"
  assert_output --partial "**Alternatives considered:**"
  assert_output --partial "**Revisit when:**"
}

@test "log-decision contract: original entries preserved below new one" {
  local entry='## 2026-04-30 — Test new entry
**Context:** New.
**Decision:** Action.
**Alternatives considered:** None.
**Revisit when:** Later.
'
  awk -v entry="$entry" 'NR==1{print; print ""; print entry; next} 1' \
    "$SANDBOX_DIR/docs/DECISIONS.md" > "$SANDBOX_DIR/docs/DECISIONS.md.new"
  mv "$SANDBOX_DIR/docs/DECISIONS.md.new" "$SANDBOX_DIR/docs/DECISIONS.md"

  run grep -c "Test fixture decision" "$SANDBOX_DIR/docs/DECISIONS.md"
  assert_success
  assert_output "1"
}
