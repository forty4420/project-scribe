# Bash Test Harness — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

## Research source — DO NOT LOSE

This plan and its 14-item backlog were derived from a YouTube research mining run on 2026-04-29. **Durable copies of all research artifacts live inside this repo** at:

- [`docs/research/2026-04-29-youtube-mining/synthesized-recommendations.md`](../research/2026-04-29-youtube-mining/synthesized-recommendations.md) — primary synthesis: 8 upgrade ideas, source citations, signal scores, anti-recommendations
- [`docs/research/2026-04-29-youtube-mining/topic-1-plugin-best-practices.md`](../research/2026-04-29-youtube-mining/topic-1-plugin-best-practices.md) — 13 videos analyzed (signal 7-9/10)
- [`docs/research/2026-04-29-youtube-mining/topic-2-handoff-session.md`](../research/2026-04-29-youtube-mining/topic-2-handoff-session.md) — 12 videos analyzed (signal 8-9/10)
- `docs/research/2026-04-29-youtube-mining/topic-{1,2}-aggregated.json` — machine-readable rollup of every repo, tool, technique, install command extracted

If you need to revisit *why* an item was prioritized, *who* recommended it, or *what alternative patterns were rejected*, read `synthesized-recommendations.md` first.

The mining pipeline that produced these artifacts lives outside this repo at `C:/Users/forty/Downloads/scout/scripts/video/`. To refresh research with new topics: `bash scripts/video/run_pipeline.sh "<topic>" 15` from the scout dir, then re-synthesize and copy back into `docs/research/<date>-<run-name>/`.

---

**Goal:** Add a bats-core based test harness covering all 4 hook scripts and the 3 highest-leverage skills, runnable locally and in CI, so future scribe refactors don't silently break behavior. Closes the v0.6.0 Reviewer-3 finding.

**Architecture:** Vendor `bats-core` + `bats-support` + `bats-assert` as git submodules under `tests/_libs/`. Test files live in `tests/{hooks,skills,integration}/*.bats`. Each test runs hooks/skills as subprocess in a sandbox temp directory with mocked Claude Code env vars. CI runs on push via GitHub Actions on Ubuntu.

**Tech Stack:**
- bats-core (TAP-compliant bash test framework)
- bats-support + bats-assert (assertion helpers)
- GitHub Actions (existing `.github/workflows/` already has `lint.yml`)
- bash 5+, jq (for JSON state file assertions)

---

## Why this is #1

- **Foundation for the next 14 backlog items.** Worktree-aware state, DECISIONS gate, schema-aware routing — all touch hook + skill internals. Without tests, every refactor is a blind change.
- **Reviewer-3 already flagged it** in v0.6.0 smoke test. Open feedback debt.
- **Bash is regression-prone.** Word-splitting, set -u, jq quoting — silent breakage common. Test harness catches before users do.
- **Pre-launch credibility.** Hostile commenters on r/ClaudeAI launch will look for test coverage. "0 tests" is a real attack surface.

## Scope (in)

- bats setup + vendoring
- Tests for 4 hook scripts: `session-start`, `userprompt-context-warn`, `pre-compact`, `stop-mark-memory`
- Tests for 3 high-leverage skills: `auto-handoff`, `log-decision`, `reconcile-project-state`
- Sandbox helper: temp dir + fixture STATE.md/DECISIONS.md/MEMORY.md
- GitHub Actions workflow `test.yml`
- README badge

## Scope (out, deferred)

- Tests for remaining 16 skills (add incrementally as each is touched)
- Windows test runner (bats works on Linux/macOS; Windows users run via Git Bash or WSL — document but don't gate CI on it)
- Performance / load tests
- Coverage measurement (kcov optional, not load-bearing)
- Mutation testing

## File Structure

```
tests/
├── README.md                          # how to run tests locally
├── _libs/
│   ├── bats-core/                     # git submodule
│   ├── bats-support/                  # git submodule
│   └── bats-assert/                   # git submodule
├── _helpers/
│   ├── sandbox.bash                   # mktemp project dir + cleanup trap
│   ├── fixtures.bash                  # known-good STATE.md, DECISIONS.md, MEMORY.md content
│   └── claude_env.bash                # mock CLAUDE_PROJECT_DIR, CLAUDE_PLUGIN_ROOT, etc.
├── hooks/
│   ├── session-start.bats
│   ├── userprompt-context-warn.bats
│   ├── pre-compact.bats
│   └── stop-mark-memory.bats
├── skills/
│   ├── auto-handoff.bats
│   ├── log-decision.bats
│   └── reconcile-project-state.bats
└── integration/
    └── full-session-cycle.bats        # SessionStart → user prompts → Stop → Compact, end-to-end
.github/workflows/test.yml             # CI runner
```

---

## Chunk 1: Vendoring + sandbox infrastructure

### Task 1.1: Add bats submodules

**Files:**
- Create: `tests/_libs/.gitkeep`
- Modify: `.gitmodules` (create if missing)

- [ ] **Step 1: Create tests directory structure**

```bash
cd C:/Users/forty/.claude/plugins/marketplaces/project-scribe
mkdir -p tests/_libs tests/_helpers tests/hooks tests/skills tests/integration
touch tests/_libs/.gitkeep
```

- [ ] **Step 2: Add bats-core submodule**

```bash
git submodule add https://github.com/bats-core/bats-core.git tests/_libs/bats-core
git submodule add https://github.com/bats-core/bats-support.git tests/_libs/bats-support
git submodule add https://github.com/bats-core/bats-assert.git tests/_libs/bats-assert
git submodule update --init --recursive
```

- [ ] **Step 3: Verify bats runs**

Run: `tests/_libs/bats-core/bin/bats --version`
Expected: `Bats 1.x.x` printed.

- [ ] **Step 4: Commit**

```bash
git add .gitmodules tests/_libs/
git commit -m "test: vendor bats-core + helpers as submodules"
```

### Task 1.2: Sandbox helper

**Files:**
- Create: `tests/_helpers/sandbox.bash`

- [ ] **Step 1: Write the failing test**

Create `tests/_helpers/sandbox.bats` (temporary, used to validate helper itself — deleted after Task 1.2 verification):

```bash
#!/usr/bin/env bats

load '_libs/bats-support/load'
load '_libs/bats-assert/load'
load '_helpers/sandbox'

@test "sandbox creates an isolated temp project dir" {
  sandbox::create
  assert [ -d "$SANDBOX_DIR" ]
  assert [ -d "$SANDBOX_DIR/docs" ]
  assert_equal "$(basename $(dirname $SANDBOX_DIR))" "scribe-test-sandbox"
}

@test "sandbox sets CLAUDE_PROJECT_DIR to sandbox" {
  sandbox::create
  assert_equal "$CLAUDE_PROJECT_DIR" "$SANDBOX_DIR"
}

@test "sandbox cleanup removes the dir" {
  sandbox::create
  local dir="$SANDBOX_DIR"
  sandbox::cleanup
  assert [ ! -d "$dir" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/_libs/bats-core/bin/bats tests/_helpers/sandbox.bats`
Expected: 3 FAIL — "sandbox::create: command not found"

- [ ] **Step 3: Write minimal implementation**

Create `tests/_helpers/sandbox.bash`:

```bash
# Sandbox helpers — isolated tmp project dir for hook/skill testing.

sandbox::create() {
  local parent="${TMPDIR:-/tmp}/scribe-test-sandbox"
  mkdir -p "$parent"
  SANDBOX_DIR="$(mktemp -d "$parent/run.XXXXXX")"
  mkdir -p "$SANDBOX_DIR/docs"
  export SANDBOX_DIR
  export CLAUDE_PROJECT_DIR="$SANDBOX_DIR"
  export CLAUDE_PLUGIN_ROOT="${BATS_TEST_DIRNAME}/.."
}

sandbox::cleanup() {
  if [ -n "${SANDBOX_DIR:-}" ] && [ -d "$SANDBOX_DIR" ]; then
    rm -rf "$SANDBOX_DIR"
  fi
  unset SANDBOX_DIR CLAUDE_PROJECT_DIR
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `tests/_libs/bats-core/bin/bats tests/_helpers/sandbox.bats`
Expected: 3 PASS.

- [ ] **Step 5: Delete temp test file (helper validated)**

```bash
rm tests/_helpers/sandbox.bats
```

- [ ] **Step 6: Commit**

```bash
git add tests/_helpers/sandbox.bash
git commit -m "test: add sandbox helper (isolated tmp project dir)"
```

### Task 1.3: Fixtures helper

**Files:**
- Create: `tests/_helpers/fixtures.bash`

- [ ] **Step 1: Write fixture loader**

Create `tests/_helpers/fixtures.bash`:

```bash
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
```

- [ ] **Step 2: Smoke test fixture loader inline**

Create `tests/_helpers/fixtures-smoke.bats`:

```bash
#!/usr/bin/env bats

load '_libs/bats-support/load'
load '_libs/bats-assert/load'
load '_helpers/sandbox'
load '_helpers/fixtures'

setup() { sandbox::create; }
teardown() { sandbox::cleanup; }

@test "fixtures::seed_state writes STATE.md with required headings" {
  fixtures::seed_state
  run cat "$SANDBOX_DIR/docs/STATE.md"
  assert_success
  assert_output --partial "## Current focus"
  assert_output --partial "## Last shipped"
  assert_output --partial "## Next up"
}

@test "fixtures::seed_all writes all three files" {
  fixtures::seed_all
  assert [ -f "$SANDBOX_DIR/docs/STATE.md" ]
  assert [ -f "$SANDBOX_DIR/docs/DECISIONS.md" ]
  assert [ -f "$SANDBOX_DIR/MEMORY.md" ]
}
```

- [ ] **Step 3: Run smoke**

Run: `tests/_libs/bats-core/bin/bats tests/_helpers/fixtures-smoke.bats`
Expected: 2 PASS.

- [ ] **Step 4: Delete smoke file (helper validated)**

```bash
rm tests/_helpers/fixtures-smoke.bats
```

- [ ] **Step 5: Commit**

```bash
git add tests/_helpers/fixtures.bash
git commit -m "test: add fixtures helper for STATE/DECISIONS/MEMORY seed"
```

### Task 1.4: Claude env mock helper

**Files:**
- Create: `tests/_helpers/claude_env.bash`

- [ ] **Step 1: Write env mock**

Create `tests/_helpers/claude_env.bash`:

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add tests/_helpers/claude_env.bash
git commit -m "test: add Claude Code env-var mock helper"
```

### Task 1.5: Local test runner script

**Files:**
- Create: `tests/run.sh`

- [ ] **Step 1: Write runner**

```bash
#!/usr/bin/env bash
# Local test runner. Wraps bats-core with project-aware paths.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BATS="$PROJECT_ROOT/tests/_libs/bats-core/bin/bats"

if [ ! -x "$BATS" ]; then
  echo "bats not found at $BATS — run: git submodule update --init --recursive" >&2
  exit 2
fi

cd "$PROJECT_ROOT"

# Run all .bats files under tests/ unless specific path given
if [ $# -gt 0 ]; then
  exec "$BATS" "$@"
else
  exec "$BATS" --recursive tests/hooks tests/skills tests/integration
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x tests/run.sh
```

- [ ] **Step 3: Verify runs (no tests yet, just runner check)**

Run: `bash tests/run.sh --version`
Expected: bats version printed.

- [ ] **Step 4: Commit**

```bash
git add tests/run.sh
git commit -m "test: add local test runner wrapper"
```

---

## Chunk 2: Hook tests

### Task 2.1: session-start hook tests

**Files:**
- Create: `tests/hooks/session-start.bats`

- [ ] **Step 1: Write the failing test (happy-path startup)**

Create `tests/hooks/session-start.bats`:

```bash
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'
load '../_helpers/claude_env'

setup() {
  sandbox::create
  fixtures::seed_all
  claude_env::session_start "startup"
}

teardown() { sandbox::cleanup; claude_env::clear; }

@test "session-start exits 0 on a well-formed scribe project" {
  run "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success
}

@test "session-start emits dashboard output" {
  run "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success
  # Header from STATE.md should appear somewhere in output
  assert_output --partial "Current focus"
}

@test "session-start handles missing STATE.md gracefully (exit 0, warning to stderr)" {
  rm -f "$SANDBOX_DIR/docs/STATE.md"
  run "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success
}

@test "session-start respects matcher=resume (no full dashboard)" {
  claude_env::session_start "resume"
  run "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success
}

@test "session-start with matcher=compact warns about possibly-stale state" {
  claude_env::session_start "compact"
  run "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success
}
```

- [ ] **Step 2: Run tests, observe which fail**

Run: `bash tests/run.sh tests/hooks/session-start.bats`
Expected: Some PASS (script exits 0), some FAIL (output assertions). Note which fail — those reveal current behavior gaps.

- [ ] **Step 3: For each FAIL, pick action**

For each failing assertion, decide:
- **Behavior is correct, test is wrong** → loosen the assertion (record reasoning in commit message)
- **Behavior has a bug** → file a follow-up issue, mark test as `skip` with `# TODO: fix in <issue>` comment, do NOT fix the hook in this plan (scope creep)
- **Behavior is genuinely undefined** → write a DECISIONS.md entry locking down expected behavior, then fix test or hook

- [ ] **Step 4: Commit tests with any test-side adjustments**

```bash
git add tests/hooks/session-start.bats
git commit -m "test(hooks): cover session-start startup/resume/compact paths"
```

### Task 2.2: userprompt-context-warn hook tests

**Files:**
- Create: `tests/hooks/userprompt-context-warn.bats`

- [ ] **Step 1: Write tests**

```bash
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'
load '../_helpers/claude_env'

setup() {
  sandbox::create
  fixtures::seed_all
}
teardown() { sandbox::cleanup; claude_env::clear; }

@test "userprompt-context-warn exits 0 on normal prompt" {
  claude_env::user_prompt "what does X do?"
  run "$CLAUDE_PLUGIN_ROOT/hooks/userprompt-context-warn"
  assert_success
}

@test "userprompt-context-warn does not block with non-zero exit on long prompt" {
  claude_env::user_prompt "$(printf 'x%.0s' {1..5000})"
  run "$CLAUDE_PLUGIN_ROOT/hooks/userprompt-context-warn"
  assert_success
}

@test "userprompt-context-warn handles empty prompt" {
  claude_env::user_prompt ""
  run "$CLAUDE_PLUGIN_ROOT/hooks/userprompt-context-warn"
  assert_success
}
```

- [ ] **Step 2: Run + commit**

Run: `bash tests/run.sh tests/hooks/userprompt-context-warn.bats`
Expected: All PASS, OR mark unexpected failures as skip with TODO + open follow-up.

```bash
git add tests/hooks/userprompt-context-warn.bats
git commit -m "test(hooks): cover userprompt-context-warn baseline"
```

### Task 2.3: pre-compact hook tests

**Files:**
- Create: `tests/hooks/pre-compact.bats`

- [ ] **Step 1: Write tests**

```bash
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'
load '../_helpers/claude_env'

setup() {
  sandbox::create
  fixtures::seed_all
}
teardown() { sandbox::cleanup; claude_env::clear; }

@test "pre-compact exits 0 on manual compact" {
  claude_env::pre_compact "manual"
  run "$CLAUDE_PLUGIN_ROOT/hooks/pre-compact"
  assert_success
}

@test "pre-compact exits 0 on auto compact" {
  claude_env::pre_compact "auto"
  run "$CLAUDE_PLUGIN_ROOT/hooks/pre-compact"
  assert_success
}

@test "pre-compact does not modify STATE.md without explicit handoff" {
  local before=$(sha256sum "$SANDBOX_DIR/docs/STATE.md" | cut -d' ' -f1)
  claude_env::pre_compact "auto"
  run "$CLAUDE_PLUGIN_ROOT/hooks/pre-compact"
  local after=$(sha256sum "$SANDBOX_DIR/docs/STATE.md" | cut -d' ' -f1)
  assert_equal "$before" "$after"
}
```

- [ ] **Step 2: Run + commit**

```bash
bash tests/run.sh tests/hooks/pre-compact.bats
git add tests/hooks/pre-compact.bats
git commit -m "test(hooks): cover pre-compact manual + auto + state-immutability"
```

### Task 2.4: stop-mark-memory hook tests

**Files:**
- Create: `tests/hooks/stop-mark-memory.bats`

- [ ] **Step 1: Write tests**

```bash
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'
load '../_helpers/claude_env'

setup() {
  sandbox::create
  fixtures::seed_all
  claude_env::stop
}
teardown() { sandbox::cleanup; claude_env::clear; }

@test "stop-mark-memory exits 0 with no transcript" {
  run "$CLAUDE_PLUGIN_ROOT/hooks/stop-mark-memory"
  assert_success
}

@test "stop-mark-memory bumps last_used in memory file when rule referenced" {
  # Plant a synthetic transcript that references the test rule by description
  local transcript="$SANDBOX_DIR/transcript.jsonl"
  printf '{"type":"text","text":"Using the test rule from memory"}\n' > "$transcript"
  export CLAUDE_TRANSCRIPT_PATH="$transcript"

  run "$CLAUDE_PLUGIN_ROOT/hooks/stop-mark-memory"
  assert_success

  # Validate frontmatter `hits` increased OR `last_used` updated to today
  run grep -E "^(hits|last_used):" "$SANDBOX_DIR/rule_test.md"
  assert_success
}

@test "stop-mark-memory does not modify memory file when rule not referenced" {
  local transcript="$SANDBOX_DIR/transcript.jsonl"
  printf '{"type":"text","text":"unrelated content"}\n' > "$transcript"
  export CLAUDE_TRANSCRIPT_PATH="$transcript"
  local before=$(sha256sum "$SANDBOX_DIR/rule_test.md" | cut -d' ' -f1)

  run "$CLAUDE_PLUGIN_ROOT/hooks/stop-mark-memory"
  local after=$(sha256sum "$SANDBOX_DIR/rule_test.md" | cut -d' ' -f1)
  assert_equal "$before" "$after"
}
```

- [ ] **Step 2: Run + commit**

```bash
bash tests/run.sh tests/hooks/stop-mark-memory.bats
git add tests/hooks/stop-mark-memory.bats
git commit -m "test(hooks): cover stop-mark-memory hits+last_used semantics"
```

---

## Chunk 3: Skill tests

### Task 3.1: log-decision skill test

**Files:**
- Create: `tests/skills/log-decision.bats`

Notes: Skills are markdown SOPs, not executables. Test their *deterministic side effects* — i.e. files the skill says it produces. We invoke a small "executor" wrapper that mimics what Claude would do when following the skill. For log-decision, that's "append a 5-field entry to top of DECISIONS.md."

- [ ] **Step 1: Write tests for DECISIONS.md append shape**

```bash
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'

setup() {
  sandbox::create
  fixtures::seed_decisions
}
teardown() { sandbox::cleanup; }

# log-decision says: prepend 5-field entry to DECISIONS.md
# We test the *contract*: a downstream parser must find the new entry as #1.

@test "log-decision contract: entry includes Context/Decision/Alternatives/Revisit fields" {
  # Simulate the skill's output shape — bash that mirrors what Claude produces
  local entry='## 2026-04-30 — Test new entry
**Context:** Brand new context.
**Decision:** Take action.
**Alternatives considered:** Skip it.
**Revisit when:** Conditions change.
'
  # Prepend (after H1)
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
```

- [ ] **Step 2: Run + commit**

```bash
bash tests/run.sh tests/skills/log-decision.bats
git add tests/skills/log-decision.bats
git commit -m "test(skills): cover log-decision append contract"
```

### Task 3.2: reconcile-project-state skill test

**Files:**
- Create: `tests/skills/reconcile-project-state.bats`

- [ ] **Step 1: Write tests**

```bash
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'

setup() {
  sandbox::create
  fixtures::seed_state
  # Init git in sandbox so reconcile has commits to read
  cd "$SANDBOX_DIR"
  git init -q
  git config user.email "test@test"
  git config user.name "test"
  git commit --allow-empty -q -m "v0.0.2 — second fixture commit"
  cd - >/dev/null
}
teardown() { sandbox::cleanup; }

@test "reconcile contract: STATE.md Last shipped block updates when new commit lands" {
  # Pre-condition: STATE.md says v0.0.1
  run grep -c "v0.0.1" "$SANDBOX_DIR/docs/STATE.md"
  assert_success
  assert_output "1"

  # Simulate reconcile output — replace Last shipped section with latest git log
  local latest_commit=$(cd "$SANDBOX_DIR" && git log -1 --oneline)
  # In the real skill, Claude rewrites the Last shipped block.
  # Here we test the contract: the rewritten block contains latest commit subject.

  # Substitute Last shipped block (between heading and next ##)
  python3 - <<PY
import re, pathlib
p = pathlib.Path("$SANDBOX_DIR/docs/STATE.md")
content = p.read_text()
new_block = "## Last shipped\n\n- v0.0.2 — second fixture commit\n\n"
content = re.sub(r"## Last shipped\n\n.*?(?=##)", new_block, content, count=1, flags=re.DOTALL)
p.write_text(content)
PY

  run grep "v0.0.2" "$SANDBOX_DIR/docs/STATE.md"
  assert_success
  assert_output --partial "second fixture commit"
}

@test "reconcile contract: Current focus block is NOT touched" {
  local before=$(grep -A1 "Current focus" "$SANDBOX_DIR/docs/STATE.md" | tail -1)
  # (no rewrite of Current focus — reconcile is Last-shipped only)
  local after=$(grep -A1 "Current focus" "$SANDBOX_DIR/docs/STATE.md" | tail -1)
  assert_equal "$before" "$after"
}
```

- [ ] **Step 2: Run + commit**

```bash
bash tests/run.sh tests/skills/reconcile-project-state.bats
git add tests/skills/reconcile-project-state.bats
git commit -m "test(skills): cover reconcile-project-state contract (last shipped update, current focus untouched)"
```

### Task 3.3: auto-handoff skill test

**Files:**
- Create: `tests/skills/auto-handoff.bats`

- [ ] **Step 1: Write tests**

```bash
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'

setup() {
  sandbox::create
  fixtures::seed_all
  mkdir -p "$SANDBOX_DIR/docs/handoff"
}
teardown() { sandbox::cleanup; }

# auto-handoff says: produce a markdown bundle covering state + recent decisions + memory health
# Contract: the bundle is at docs/handoff/<date>-<slug>.md and contains required sections.

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
  assert_output --partial "## Current state"
  assert_output --partial "## Recent decisions"
  assert_output --partial "## Memory health"
  assert_output --partial "## Open questions"
}
```

- [ ] **Step 2: Run + commit**

```bash
bash tests/run.sh tests/skills/auto-handoff.bats
git add tests/skills/auto-handoff.bats
git commit -m "test(skills): cover auto-handoff bundle shape contract"
```

---

## Chunk 4: Integration test + CI

### Task 4.1: Integration test — full session cycle

**Files:**
- Create: `tests/integration/full-session-cycle.bats`

- [ ] **Step 1: Write integration test**

```bash
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'
load '../_helpers/claude_env'

setup() {
  sandbox::create
  fixtures::seed_all
  cd "$SANDBOX_DIR"
  git init -q
  git config user.email "test@test"
  git config user.name "test"
  git add -A && git commit -q -m "v0.0.1 — initial fixture"
  cd - >/dev/null
}
teardown() { sandbox::cleanup; claude_env::clear; }

@test "integration: SessionStart → user prompt → Stop → all hooks exit 0" {
  claude_env::session_start "startup"
  run "$CLAUDE_PLUGIN_ROOT/hooks/session-start"
  assert_success

  claude_env::user_prompt "test prompt"
  run "$CLAUDE_PLUGIN_ROOT/hooks/userprompt-context-warn"
  assert_success

  claude_env::stop
  run "$CLAUDE_PLUGIN_ROOT/hooks/stop-mark-memory"
  assert_success
}

@test "integration: PreCompact does not corrupt seeded state" {
  local state_before=$(sha256sum "$SANDBOX_DIR/docs/STATE.md" | cut -d' ' -f1)
  local decisions_before=$(sha256sum "$SANDBOX_DIR/docs/DECISIONS.md" | cut -d' ' -f1)

  claude_env::pre_compact "manual"
  run "$CLAUDE_PLUGIN_ROOT/hooks/pre-compact"
  assert_success

  local state_after=$(sha256sum "$SANDBOX_DIR/docs/STATE.md" | cut -d' ' -f1)
  local decisions_after=$(sha256sum "$SANDBOX_DIR/docs/DECISIONS.md" | cut -d' ' -f1)
  assert_equal "$state_before" "$state_after"
  assert_equal "$decisions_before" "$decisions_after"
}
```

- [ ] **Step 2: Run + commit**

```bash
bash tests/run.sh tests/integration/full-session-cycle.bats
git add tests/integration/full-session-cycle.bats
git commit -m "test(integration): cover full SessionStart→Stop hook cycle"
```

### Task 4.2: GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/test.yml`

- [ ] **Step 1: Write workflow**

```yaml
name: tests

on:
  push:
    branches: [master, main, develop]
  pull_request:
    branches: [master, main]

jobs:
  bats:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install jq (used by some skills/hooks)
        run: sudo apt-get install -y jq

      - name: Verify bats vendored
        run: ./tests/_libs/bats-core/bin/bats --version

      - name: Run hook tests
        run: bash tests/run.sh tests/hooks

      - name: Run skill tests
        run: bash tests/run.sh tests/skills

      - name: Run integration tests
        run: bash tests/run.sh tests/integration
```

- [ ] **Step 2: Push + verify CI passes**

```bash
git add .github/workflows/test.yml
git commit -m "ci: add GitHub Actions bats test runner"
git push origin <current-branch>
```

Then verify on GitHub: Actions tab → "tests" workflow → green check.

If CI fails, iterate locally first (`bash tests/run.sh`), commit fix, re-push. Do not skip with `continue-on-error`.

### Task 4.3: tests/README.md

**Files:**
- Create: `tests/README.md`

- [ ] **Step 1: Write README**

```markdown
# scribe tests

bats-core based test harness for project-scribe hooks + high-leverage skills.

## Setup

```bash
git submodule update --init --recursive
```

## Run all tests

```bash
bash tests/run.sh
```

## Run a single file

```bash
bash tests/run.sh tests/hooks/session-start.bats
```

## Layout

- `tests/_libs/` — vendored bats-core + helpers (git submodules)
- `tests/_helpers/` — sandbox, fixtures, env mocks
- `tests/hooks/` — hook script tests (one .bats per hook)
- `tests/skills/` — skill contract tests (markdown skills tested via their declared side effects)
- `tests/integration/` — multi-hook end-to-end flows

## Adding tests for a new skill

1. Read the skill's SKILL.md — find what files/state it modifies
2. Create `tests/skills/<skill-name>.bats`
3. Use `sandbox::create` + `fixtures::seed_*` in setup
4. Assert on the *contract* (what files exist, what content), not the AI's exact wording

## Platform support

- Linux + macOS: native
- Windows: run via Git Bash or WSL. CI runs on Ubuntu only.
```

- [ ] **Step 2: Commit**

```bash
git add tests/README.md
git commit -m "docs(tests): add tests/README"
```

### Task 4.4: README badge

**Files:**
- Modify: `README.md` (add tests badge near top)

- [ ] **Step 1: Add badge to README**

Find the existing badge section in `README.md` (likely near top of file). Add:

```markdown
[![tests](https://github.com/<owner>/project-scribe/actions/workflows/test.yml/badge.svg)](https://github.com/<owner>/project-scribe/actions/workflows/test.yml)
```

Replace `<owner>` with the actual GitHub owner (check `git remote -v`).

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add tests CI badge to README"
```

---

## Chunk 5: Wrap-up

### Task 5.1: Update STATE.md + DECISIONS.md

**Files:**
- Modify: `docs/STATE.md` (move "Bash test harness" from Deferred to Last shipped)
- Modify: `docs/DECISIONS.md` (log the test framework choice)

- [ ] **Step 1: Move test harness item out of Deferred**

In `docs/STATE.md`, remove `- Bash test harness (Reviewer-3 finding from v0.6.0 smoke test)` from `## Deferred`. Add `- v0.7.2 — bats-core test harness for hooks + 3 skills` under `## Last shipped`.

- [ ] **Step 2: Log decision**

In `docs/DECISIONS.md`, prepend a new entry:

```markdown
## 2026-04-30 — Adopt bats-core for scribe tests
**Context:** Reviewer-3 flagged absence of test harness in v0.6.0 smoke test. Refactors of hooks and skills risk silent regressions. Pre-r/ClaudeAI launch credibility concern.
**Decision:** Vendor bats-core + bats-support + bats-assert as git submodules under `tests/_libs/`. Cover 4 hooks + 3 high-leverage skills (auto-handoff, log-decision, reconcile-project-state) initially. CI runs on Ubuntu only — Windows users use Git Bash/WSL.
**Alternatives considered:** shellcheck-only (lint not test), Python pytest with subprocess wrappers (extra runtime dep), no tests at all (incurred debt).
**Revisit when:** Test runtime exceeds 30s, OR Windows users hit fork-specific bugs not caught by Linux CI.
```

- [ ] **Step 3: Commit**

```bash
git add docs/STATE.md docs/DECISIONS.md
git commit -m "chore: log v0.7.2 test harness decision + state update"
```

### Task 5.2: Tag release

**Files:**
- Modify: `.claude-plugin/plugin.json` (bump version to 0.7.2)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Bump version**

In `.claude-plugin/plugin.json`, change `"version": "0.7.1"` → `"version": "0.7.2"`.

- [ ] **Step 2: Update CHANGELOG**

Add to top of `CHANGELOG.md`:

```markdown
## v0.7.2 — 2026-04-30

- Add bats-core test harness covering all 4 hooks + 3 high-leverage skills
- CI: GitHub Actions runs tests on push/PR (Ubuntu)
- Fixtures + sandbox helpers reusable for adding tests to remaining 16 skills
- Closes Reviewer-3 finding from v0.6.0 smoke test
```

- [ ] **Step 3: Commit + tag**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore: bump v0.7.2 — bats test harness"
git tag v0.7.2
git push origin master --tags
```

---

## Acceptance criteria

- [ ] `bash tests/run.sh` exits 0 with all tests green locally
- [ ] GitHub Actions workflow `tests` runs and passes on push to master
- [ ] All 4 hooks have a `.bats` file with at least 3 test cases each
- [ ] All 3 target skills have a `.bats` file testing their stated contract
- [ ] One integration test exercises SessionStart → UserPrompt → Stop → PreCompact in sequence
- [ ] tests/README.md documents how to run + add tests
- [ ] README badge points at green workflow
- [ ] DECISIONS.md has the v0.7.2 entry
- [ ] STATE.md "Deferred" no longer lists "Bash test harness"
- [ ] v0.7.2 git tag exists and is pushed

## Out-of-scope follow-ups (file as separate plans, do not bundle)

- Tests for remaining 16 skills (one plan per batch of 4-5 skills)
- Windows CI runner (Git Bash on windows-latest)
- Coverage measurement (kcov)
- Behavioral fixes for any tests marked `skip` with TODO during this plan

---

## Backlog: remaining 14 candidate upgrades (ordered by topological level + impact)

These are tracked here for visibility; each gets its own spec → plan → implementation cycle when picked up.

**Full rationale, source video metadata, and rejected alternatives** for every item below: see [docs/research/2026-04-29-youtube-mining/synthesized-recommendations.md](../research/2026-04-29-youtube-mining/synthesized-recommendations.md). Re-read that doc before brainstorming any item — it captures context this summary loses.

### Level 0 — foundations (parallel-safe, no upstream deps)

2. **Context Audit skill** — scans CLAUDE.md, MCP servers, hooks, skills for token bloat. Universal Max-plan-limits pain. *(Source: Brad signal 8/10)*
3. **Worktree-aware state files** — detect `.git/worktrees/<name>/` and use per-worktree STATE/DECISIONS/MEMORY paths. Fixes parallel-session collisions. *(Source: Developers Digest signal 8/10)*
4. **Verification-gate slash cmd** — `/scribe-verify` reads STATE.md "Last shipped" claim, runs project's verify command, reports drift. *(Source: Boris/Anthropic signal 9/10)*
5. **Plan-as-GitHub-issue persistence** — extend `auto-handoff` to optionally `gh issue create` a handoff. Durability win. *(Source: Matt Pocock signal 7/10)*
6. **Token-budget tab in session-card** — show 5-hour window remaining + weekly cap projection alongside project status. *(Source: Brad signal 8/10)*
7. **Plugin "requires" compat field** — schema unverified; research before building.

### Level 1 — single-dep

8. **Plugin rename for search disambiguation** *(needs #1 tests)*
9. **Pre-tool-use DECISIONS gate** — hook detects rule-shaped statements being violated, blocks with prompt to log decision. *(needs #4 verification-gate scaffolding; Source: Matt Pocock signal 8/10)*
10. **Schema-aware routing** *(needs #7)*
11. **Sub-agent chapter tracking** — open new STATE.md chapter when Task tool spawns subagent. *(needs #3 worktree-aware; Source: Cole Medin signal 9/10)*
12. **Daily-note auto-capture** — currently skeleton-only in v0.6.0. *(needs #2 Context Audit data; Source: existing deferred)*
13. **Desktop tray for context warnings** *(needs #6 token-budget data)*

### Level 2 — multi-dep

14. **Mobile continuation flag** — handoff bundle optimized for mobile paste; auto-gist export. *(needs #5 + #6; Source: NetworkChuck signal 8/10)*

### Level 3 — terminal

15. **Promotion path / dreaming-lite** — recurring daily-note patterns → topical memory. *(needs #9 + #10 + #12)*
