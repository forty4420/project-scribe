#!/usr/bin/env bats
#
# Tests for the reconcile-project-state skill.
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
  fixtures::seed_state
  # Init git in sandbox so reconcile has commits to read.
  pushd "$SANDBOX_DIR" >/dev/null
  git init -q
  git config user.email "test@test"
  git config user.name "test"
  git commit --allow-empty -q -m "v0.0.2 — second fixture commit"
  popd >/dev/null
}

teardown() {
  sandbox::cleanup
}

# reconcile-project-state says: rewrite the "Last shipped" block in STATE.md
# from the latest git log entries. Current focus / Next up / Deferred are NOT
# touched.
#
# We use awk (not python) so this works on any Git Bash without a python dep.

@test "reconcile contract: STATE.md Last shipped block updates when new commit lands" {
  # Pre-condition: STATE.md says v0.0.1.
  run grep -c "v0.0.1" "$SANDBOX_DIR/docs/STATE.md"
  assert_success
  assert_output "1"

  # Simulate the reconcile rewrite: replace the "Last shipped" block contents
  # with the latest commit subject. awk reads up to the next "## " heading.
  awk '
    /^## Last shipped/ {
      print
      print ""
      print "- v0.0.2 — second fixture commit"
      print ""
      in_block = 1
      next
    }
    in_block && /^## / { in_block = 0 }
    !in_block { print }
  ' "$SANDBOX_DIR/docs/STATE.md" > "$SANDBOX_DIR/docs/STATE.md.new"
  mv "$SANDBOX_DIR/docs/STATE.md.new" "$SANDBOX_DIR/docs/STATE.md"

  run grep "v0.0.2" "$SANDBOX_DIR/docs/STATE.md"
  assert_success
  assert_output --partial "second fixture commit"
}

@test "reconcile contract: Current focus block is NOT touched" {
  local before
  before=$(grep -A1 "^## Current focus" "$SANDBOX_DIR/docs/STATE.md" | tail -1)

  # Simulate the reconcile rewrite (Last shipped only — Current focus untouched).
  awk '
    /^## Last shipped/ {
      print
      print ""
      print "- v0.0.2 — second fixture commit"
      print ""
      in_block = 1
      next
    }
    in_block && /^## / { in_block = 0 }
    !in_block { print }
  ' "$SANDBOX_DIR/docs/STATE.md" > "$SANDBOX_DIR/docs/STATE.md.new"
  mv "$SANDBOX_DIR/docs/STATE.md.new" "$SANDBOX_DIR/docs/STATE.md"

  local after
  after=$(grep -A1 "^## Current focus" "$SANDBOX_DIR/docs/STATE.md" | tail -1)
  assert_equal "$before" "$after"
}
