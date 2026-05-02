#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'

setup() { sandbox::create; }
teardown() { sandbox::cleanup; }

@test "skill: SKILL.md frontmatter has correct name + trigger phrases" {
  run grep -E "^(name|description):" "$CLAUDE_PLUGIN_ROOT/skills/scribe-verify/SKILL.md"
  assert_success
  assert_output --partial "name: scribe-verify"
  assert_output --partial "scribe-verify"
  assert_output --partial "drift check"
}

@test "skill: SKILL.md instructs invoking the helper script" {
  run grep -E 'bash.*scribe-verify\.sh' "$CLAUDE_PLUGIN_ROOT/skills/scribe-verify/SKILL.md"
  assert_success
  assert_output --partial 'scripts/scribe-verify.sh'
}

@test "skill: command frontmatter present + matches conventions" {
  run head -3 "$CLAUDE_PLUGIN_ROOT/commands/scribe-verify.md"
  assert_success
  assert_line --index 0 "---"
  assert_output --partial "description:"
}
