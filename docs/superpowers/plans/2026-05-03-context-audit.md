# /context-audit Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/superpowers/specs/2026-05-03-context-audit-design.md` (committed at SHA `8396332`).

**Goal:** Add `/project-scribe:context-audit` — read-only diagnostic that scans CLAUDE.md (project + global) and MCP server configs (project `.mcp.json` + OS-specific global `claude_desktop_config.json`), classifies findings by size / duplication / staleness severity, and emits a markdown report with concrete suggested patches.

**Architecture:** Skill + helper bash script (matches v0.7.4 `scripts/` precedent). Single bash script does target resolution, parsing, char/4 token counting, three detection passes, MCP enumeration, severity classification, and markdown formatting. Skill stays thin — instructs Claude to invoke script and surface output. Slash command at `commands/context-audit.md` matches scribe `.md` convention.

**Tech Stack:** bash 5+, awk/sed/grep, `jq` for JSON parsing, `sha1sum` (or `shasum -a 1` on macOS), `date` (GNU coreutils on Linux/Win-msys, BSD on macOS — date arithmetic differs, abstracted via helper), bats-core 1.13 (vendored).

---

## Why this is #3

- v0.7.3 (test harness) and v0.7.4 (scribe-verify) shipped; this is the next backlog item per handoff `b3c50da`.
- Brad signal 8/10 — addresses universal pain ("hitting Max plan usage limits") cited across multiple research videos.
- Reuses every v0.7.4 precedent: `scripts/` dir, SKILL.md thin wrapper, bats parity, read-only honesty contract, ambiguous-abort discipline.
- Static-file analysis only — low blast radius, easy to revert if mistaken.

## Scope (in)

- New `scripts/context-audit.sh` — heavy lifter (~500 lines projected).
- New `scripts/mcp-token-estimates.json` — curated lookup table (~30 entries, schema versioned).
- New `skills/context-audit/SKILL.md` — thin SOP wrapper.
- New `commands/context-audit.md` — slash command shim.
- ~18 active bats cases under `tests/scripts/context-audit.bats` + 1 skip-with-TODO.
- ~3 contract cases under `tests/skills/context-audit.bats`.
- Test fixtures under `tests/_fixtures/context-audit/`.
- DECISIONS.md entry locking architecture choices.
- CHANGELOG.md v0.7.5 entry + plugin.json + README badge bumps.

## Scope (out, deferred)

- Hooks/skills audit (Brad mentioned both — defer to v0.7.6).
- Runtime-aware "MCP loaded but unused this session" detection (overlaps backlog #4 token-budget tab).
- Configurable thresholds via JSON (hardcoded `5000`/`15000` ship in v0.7.5).
- Auto-fix flag (read-only stays).
- `--mcp-only` flag (defer if demand).
- Quarterly MCP estimate registry scrape (manual PR updates for now).

## File Structure

```
scripts/
├── context-audit.sh                  # NEW — heavy lifting
└── mcp-token-estimates.json          # NEW — curated MCP cost table

skills/context-audit/
└── SKILL.md                          # NEW — thin wrapper

commands/
└── context-audit.md                  # NEW — /project-scribe:context-audit

tests/scripts/
└── context-audit.bats                # NEW — ~18 active + 1 skip-TODO

tests/skills/
└── context-audit.bats                # NEW — 3 contract cases

tests/_fixtures/context-audit/        # NEW dir
├── claude-md-tiny.md
├── claude-md-warn.md
├── claude-md-critical.md
├── claude-md-dup-a.md
├── claude-md-dup-b.md
├── claude-md-stale-date.md
├── claude-md-fresh-date.md
├── claude-md-dead-ref.md
├── claude-md-dup-boundary-a.md       # 199-char block
├── claude-md-dup-boundary-b.md       # 201-char block
├── mcp-config-known.json
├── mcp-config-unknown.json
├── mcp-config-empty.json
└── mcp-config-malformed.json

.claude-plugin/plugin.json            # MODIFY — 0.7.4 → 0.7.5
CHANGELOG.md                          # MODIFY — prepend v0.7.5
docs/STATE.md                         # MODIFY — Current focus + Last shipped
docs/DECISIONS.md                     # MODIFY — prepend architecture decision
README.md                             # MODIFY — version badge bump
```

---

## Chunk 1: Script skeleton + target resolution

### Task 1.1: Create scripts skeleton + flag parsing

**Files:**
- Create: `scripts/context-audit.sh`

- [ ] **Step 1: Create skeleton with flag parsing + exit codes**

```bash
mkdir -p scripts
cat > scripts/context-audit.sh <<'SCRIPT'
#!/usr/bin/env bash
# context-audit.sh — read-only diagnostic for CLAUDE.md + MCP token bloat.
# See docs/superpowers/specs/2026-05-03-context-audit-design.md for design.

set -uo pipefail

# --- Bash version preflight (mapfile/associative arrays need bash 4+) ---
if [[ ${BASH_VERSINFO[0]:-0} -lt 4 ]]; then
  echo "ERROR: context-audit requires bash 4+. Stock macOS bash is 3.2 — install via Homebrew." >&2
  exit 2
fi

# --- Flag parsing ---

NO_SAVE=0
GLOBAL_ONLY=0
PROJECT_ONLY=0
NO_MCP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-save)      NO_SAVE=1; shift ;;
    --global-only)  GLOBAL_ONLY=1; shift ;;
    --project-only) PROJECT_ONLY=1; shift ;;
    --no-mcp)       NO_MCP=1; shift ;;
    -h|--help)
      cat <<'HELP'
Usage: context-audit.sh [--no-save] [--global-only|--project-only] [--no-mcp]
Read-only audit of CLAUDE.md + MCP configs. Emits markdown report to stdout.
HELP
      exit 0
      ;;
    *) echo "ERROR: unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [[ $GLOBAL_ONLY -eq 1 && $PROJECT_ONLY -eq 1 ]]; then
  echo "ERROR: --global-only and --project-only are mutually exclusive" >&2
  exit 2
fi

# --- Today (env override for test stability) ---

TODAY="${SCRIBE_AUDIT_TODAY:-$(date +%Y-%m-%d)}"

# --- OS detection ---

detect_os() {
  case "${OSTYPE:-}" in
    msys*|cygwin*|win*)  echo "windows" ;;
    darwin*)             echo "macos" ;;
    linux-gnu*|linux*)   echo "linux" ;;
    *)                   echo "linux-fallback" ;;  # warned in report header
  esac
}

# --- Stub: main pipeline (filled in later tasks) ---

main() {
  echo "# Context Audit — $TODAY"
  echo ""
  echo "(implementation in progress)"
}

main "$@"
SCRIPT
chmod +x scripts/context-audit.sh
```

- [ ] **Step 2: Verify script runs + flag parsing works**

Run: `bash scripts/context-audit.sh --help`
Expected: prints usage, exits 0.

Run: `bash scripts/context-audit.sh --bogus`
Expected: prints `ERROR: unknown flag: --bogus`, exit 2.

Run: `bash scripts/context-audit.sh --global-only --project-only`
Expected: prints mutex error, exit 2.

- [ ] **Step 3: Commit**

```bash
git add scripts/context-audit.sh
git commit -m "feat(context-audit): script skeleton + flag parsing (v0.7.5 wip)"
```

---

### Task 1.2: Bats setup — first 3 target-resolution tests

**Files:**
- Create: `tests/scripts/context-audit.bats`
- Create: `tests/_fixtures/context-audit/claude-md-tiny.md`

- [ ] **Step 1: Write the failing tests**

```bash
mkdir -p tests/_fixtures/context-audit
cat > tests/_fixtures/context-audit/claude-md-tiny.md <<'EOF'
# Tiny CLAUDE.md fixture
A few lines. Under threshold.
EOF

cat > tests/scripts/context-audit.bats <<'BATS'
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'
load '../_helpers/sandbox'
load '../_helpers/fixtures'

setup() {
  sandbox::create
  export HOME="$SANDBOX_DIR/home"
  mkdir -p "$HOME/.claude"
  SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/context-audit.sh"
  export SCRIPT
  # Pin "today" so date-based fixtures never rot.
  export SCRIBE_AUDIT_TODAY="2026-05-03"
}
teardown() { sandbox::cleanup; }

@test "resolve: project CLAUDE.md present → counted with absolute path" {
  rm -f "$HOME/.claude/CLAUDE.md"  # defensive isolation
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-tiny.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  # Absolute path assertion — proves resolver actually found the file,
  # not just that the literal "CLAUDE.md" substring appears (which would
  # also match the "(no CLAUDE.md files found)" empty-state line).
  assert_output --partial "$SANDBOX_DIR/CLAUDE.md"
}

@test "resolve: project CLAUDE.md absent → globals-only audit, project (none)" {
  rm -f "$HOME/.claude/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  assert_output --partial "(no CLAUDE.md files found)"
  refute_output --partial "$SANDBOX_DIR/CLAUDE.md"
}

@test "resolve: --global-only flag → project paths skipped" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-tiny.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2" --global-only' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  refute_output --partial "$SANDBOX_DIR/CLAUDE.md"
}
BATS
```

- [ ] **Step 2: Run tests — expect all 3 to fail**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: 3 failures (skeleton emits placeholder text, doesn't yet enumerate files).

- [ ] **Step 3: Implement target resolution in `main()`**

Replace the stub `main()` in `scripts/context-audit.sh` with target-resolution logic:

```bash
# --- Target resolution ---

resolve_claude_md_targets() {
  local project_only=$1 global_only=$2
  local targets=()

  if [[ $global_only -eq 0 ]]; then
    [[ -f "$PWD/CLAUDE.md"        ]] && targets+=("$PWD/CLAUDE.md")
    [[ -f "$PWD/CLAUDE.local.md"  ]] && targets+=("$PWD/CLAUDE.local.md")
  fi

  if [[ $project_only -eq 0 ]]; then
    [[ -f "$HOME/.claude/CLAUDE.md" ]] && targets+=("$HOME/.claude/CLAUDE.md")
    if [[ -d "$HOME/.claude/rules" ]]; then
      while IFS= read -r -d '' f; do
        targets+=("$f")
      done < <(find "$HOME/.claude/rules" -type f -name '*.md' -print0 2>/dev/null)
    fi
  fi

  printf '%s\n' "${targets[@]}"
}

# Replace stub main() with:
main() {
  local os
  os="$(detect_os)"

  echo "# Context Audit — $TODAY"
  echo ""

  local targets
  mapfile -t targets < <(resolve_claude_md_targets "$PROJECT_ONLY" "$GLOBAL_ONLY")

  echo "## Size findings"
  echo ""

  if [[ ${#targets[@]} -eq 0 ]]; then
    echo "(no CLAUDE.md files found)"
  else
    for t in "${targets[@]}"; do
      echo "- $t"
    done
  fi
}
```

- [ ] **Step 4: Re-run tests — expect all 3 to pass**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/context-audit.sh tests/scripts/context-audit.bats tests/_fixtures/context-audit/
git commit -m "feat(context-audit): target resolution + first 3 bats cases"
```

---

### Task 1.3: MCP config target resolution + OSTYPE handling

**Files:**
- Modify: `scripts/context-audit.sh`
- Modify: `tests/scripts/context-audit.bats` (add OSTYPE test)

- [ ] **Step 1: Write failing OSTYPE test**

Append to `tests/scripts/context-audit.bats`:

```bash
@test "os: OSTYPE=darwin resolves macOS global config path" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-tiny.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  run env OSTYPE=darwin23 bash -c 'cd "$1" && bash "$2" --debug-paths' \
      _ "$SANDBOX_DIR" "$SCRIPT"
  assert_output --partial "Library/Application Support/Claude/claude_desktop_config.json"
}

@test "os: OSTYPE=linux-gnu resolves Linux global config path" {
  run env OSTYPE=linux-gnu bash -c 'cd "$1" && bash "$2" --debug-paths' \
      _ "$SANDBOX_DIR" "$SCRIPT"
  assert_output --partial ".config/Claude/claude_desktop_config.json"
}

@test "os: OSTYPE=msys resolves Windows global config path" {
  run env OSTYPE=msys APPDATA="$SANDBOX_DIR/Roaming" \
      bash -c 'cd "$1" && bash "$2" --debug-paths' \
      _ "$SANDBOX_DIR" "$SCRIPT"
  assert_output --partial "Claude/claude_desktop_config.json"
}

@test "os: OSTYPE=unknown-bsd → fallback to Linux + warn in header" {
  run env OSTYPE=unknown-bsd bash -c 'cd "$1" && bash "$2"' \
      _ "$SANDBOX_DIR" "$SCRIPT"
  assert_output --partial "OS detection fell back"
}
```

- [ ] **Step 2: Run test — expect fail**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: 1 failure on the OSTYPE test (no `--debug-paths` flag yet).

- [ ] **Step 3: Implement MCP target resolution + `--debug-paths`**

In `scripts/context-audit.sh`, add flag:

```bash
DEBUG_PATHS=0
# In flag-parse loop:
    --debug-paths)  DEBUG_PATHS=1; shift ;;
```

Add resolver:

```bash
resolve_mcp_global_config() {
  local os=$1
  case "$os" in
    windows)
      # APPDATA may be unset in bats env; fall back to a normalized path.
      local appdata="${APPDATA:-$HOME/AppData/Roaming}"
      echo "$appdata/Claude/claude_desktop_config.json"
      ;;
    macos)
      echo "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
      ;;
    linux|linux-fallback)
      echo "$HOME/.config/Claude/claude_desktop_config.json"
      ;;
  esac
}

resolve_mcp_project_config() {
  echo "$PWD/.mcp.json"
}
```

In `main()`, before emitting report:

```bash
  local mcp_global mcp_project
  mcp_global="$(resolve_mcp_global_config "$os")"
  mcp_project="$(resolve_mcp_project_config)"

  if [[ $DEBUG_PATHS -eq 1 ]]; then
    echo "MCP global config: $mcp_global"
    echo "MCP project config: $mcp_project"
    return 0
  fi

  # If detect_os fell back, surface that in the report header so the
  # OS-fallback test (and human readers) see why path resolution defaulted.
  if [[ "$os" = "linux-fallback" ]]; then
    echo "_Note: OS detection fell back to Linux paths (OSTYPE=$OSTYPE unrecognized)._"
    echo ""
  fi
```

- [ ] **Step 4: Re-run tests — expect all pass**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/context-audit.sh tests/scripts/context-audit.bats
git commit -m "feat(context-audit): MCP config resolution + OS-specific paths"
```

---

## Chunk 2: Token counting + size classification

### Task 2.1: Char/4 token counter + size fixtures

**Files:**
- Modify: `scripts/context-audit.sh`
- Create: `tests/_fixtures/context-audit/claude-md-warn.md` (~24,000 chars → ~6,000 tokens)
- Create: `tests/_fixtures/context-audit/claude-md-critical.md` (~64,000 chars → ~16,000 tokens)
- Modify: `tests/scripts/context-audit.bats`

- [ ] **Step 1: Generate size fixtures**

Math reference: token count = `chars / 4` (integer division). Warn band = 5000–14999 tokens (20000–59999 chars). Critical = ≥15000 tokens (≥60000 chars).

```bash
# warn fixture: target ~6000 tokens = ~24000 chars.
# "Word " × 5000 = 25000 chars + 16-char header = 25016 chars → 6254 tokens. Solid warn.
awk 'BEGIN{printf "# Warn fixture\n\n"; for(i=0;i<5000;i++) printf "Word "}' \
  > tests/_fixtures/context-audit/claude-md-warn.md

# critical fixture: target ~16000 tokens = ~64000 chars.
# "Word " × 13000 = 65000 chars + 20-char header = 65020 chars → 16255 tokens. Solid critical.
awk 'BEGIN{printf "# Critical fixture\n\n"; for(i=0;i<13000;i++) printf "Word "}' \
  > tests/_fixtures/context-audit/claude-md-critical.md

# Hard assert sizes — fail loudly if generation drifts on different awk impls.
WARN_BYTES=$(wc -c < tests/_fixtures/context-audit/claude-md-warn.md)
CRIT_BYTES=$(wc -c < tests/_fixtures/context-audit/claude-md-critical.md)
[ "$WARN_BYTES" -ge 20000 ] && [ "$WARN_BYTES" -lt 60000 ] || { echo "WARN fixture out of band: $WARN_BYTES"; exit 1; }
[ "$CRIT_BYTES" -ge 60000 ] || { echo "CRIT fixture undersized: $CRIT_BYTES"; exit 1; }
echo "warn=$WARN_BYTES bytes, crit=$CRIT_BYTES bytes — both in target band."
```

- [ ] **Step 2: Write failing token-counting tests**

Append to `tests/scripts/context-audit.bats`:

```bash
@test "tokens: empty file → 0 tokens, no warn row" {
  : > "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  refute_output --partial "⚠️"
  refute_output --partial "🔴"
}

@test "tokens: 1000-char fixture → ~250 tokens, no warn" {
  printf '%.0s.' {1..1000} > "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  refute_output --partial "⚠️"
  refute_output --partial "🔴"
}

@test "size: ~6k token file → ⚠️ warn" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-warn.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  assert_output --partial "⚠️"
}

@test "size: ~16k token file → 🔴 critical, exit 1" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-critical.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_failure 1
  assert_output --partial "🔴"
}

@test "size: just-under-warn (4999 tokens / 19996 chars) → ok, no row, exit 0" {
  printf '%.0s.' $(seq 1 19996) > "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  refute_output --partial "⚠️"
  refute_output --partial "🔴"
}

@test "size: at-warn-threshold (5000 tokens / 20000 chars) → ⚠️ warn, exit 0" {
  printf '%.0s.' $(seq 1 20000) > "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  assert_output --partial "⚠️"
  refute_output --partial "🔴"
}

@test "size: just-under-critical (14999 tokens / 59996 chars) → ⚠️ warn, exit 0" {
  printf '%.0s.' $(seq 1 59996) > "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  assert_output --partial "⚠️"
  refute_output --partial "🔴"
}

@test "size: at-critical-threshold (15000 tokens / 60000 chars) → 🔴 critical, exit 1" {
  printf '%.0s.' $(seq 1 60000) > "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_failure 1
  assert_output --partial "🔴"
}
```

- [ ] **Step 3: Run tests — expect 5 fails**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: 5 token/size tests fail (no classification yet).

- [ ] **Step 4: Implement token counting + size classification + DEFERRED exit-1**

Add to `scripts/context-audit.sh`:

```bash
# --- Token counting (char/4 heuristic) ---

count_tokens_file() {
  local f=$1
  local chars
  # wc -c may emit leading whitespace on some platforms; bash arithmetic
  # tolerates this in (( )) context.
  chars=$(wc -c < "$f" 2>/dev/null || echo 0)
  echo $(( chars / 4 ))
}

# Severity boundaries:
#   < 5000      → ok       (no row in report)
#   5000–14999  → warn     (⚠️ row, exit 0)
#   ≥ 15000     → critical (🔴 row, defer exit 1 to end of main)
classify_size() {
  local tokens=$1
  if   (( tokens >= 15000 )); then echo "critical"
  elif (( tokens >=  5000 )); then echo "warn"
  else                              echo "ok"
  fi
}

# Module-level flag — set by size loop, checked at end of main(). Deferring
# the exit means MCP, staleness, dups, footer all still render even when a
# CLAUDE.md target is critical. Exit-immediately would truncate the report.
HAS_CRITICAL=0
```

Replace the simple loop in `main()` (this is the COMPLETE main() body for this chunk — later chunks append more sections before the final exit check):

```bash
  local critical_count=0 warn_count=0
  local size_lines=()

  for t in "${targets[@]}"; do
    local tokens severity
    tokens=$(count_tokens_file "$t")
    severity=$(classify_size "$tokens")
    case "$severity" in
      critical) critical_count=$((critical_count+1))
                HAS_CRITICAL=1
                size_lines+=("- 🔴 $t — $tokens tokens (≥15000 critical)") ;;
      warn)     warn_count=$((warn_count+1))
                size_lines+=("- ⚠️ $t — $tokens tokens (5000–14999 warn)") ;;
      ok)       : ;;
    esac
  done

  echo "## Summary"
  echo ""
  echo "| Severity | Count |"
  echo "|---|---|"
  echo "| 🔴 Critical | $critical_count |"
  echo "| ⚠️ Warning  | $warn_count |"
  echo ""
  echo "## Size findings"
  echo ""
  if [[ ${#targets[@]} -eq 0 ]]; then
    echo "(no CLAUDE.md files found)"
  elif [[ ${#size_lines[@]} -eq 0 ]]; then
    echo "(no size issues found)"
  else
    printf '%s\n' "${size_lines[@]}"
  fi

  # NOTE: NO `exit 1` here. Later chunks append duplication, staleness, MCP,
  # and footer sections AFTER this. The exit check lives at the bottom of
  # main() (added in Chunk 5 Task 5.2 alongside the report-completion logic).
  # For Chunk 2 in isolation, append this at the very end of main():
  if (( HAS_CRITICAL > 0 )); then
    exit 1
  fi
```

- [ ] **Step 5: Re-run tests — expect all pass**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: all current tests (~9) pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/context-audit.sh tests/scripts/context-audit.bats tests/_fixtures/context-audit/claude-md-{warn,critical}.md
git commit -m "feat(context-audit): char/4 token count + size severity classification"
```

---

## Chunk 3: Duplication detection

### Task 3.1: Cross-file paragraph hashing + boundary tests

**Files:**
- Modify: `scripts/context-audit.sh`
- Create: `tests/_fixtures/context-audit/claude-md-dup-a.md`
- Create: `tests/_fixtures/context-audit/claude-md-dup-b.md`
- Create: `tests/_fixtures/context-audit/claude-md-dup-boundary-a.md`
- Create: `tests/_fixtures/context-audit/claude-md-dup-boundary-b.md`
- Modify: `tests/scripts/context-audit.bats`

- [ ] **Step 1: Generate dup fixtures (250-char shared block)**

```bash
SHARED_250=$(printf '%.0sx' {1..250})

cat > tests/_fixtures/context-audit/claude-md-dup-a.md <<EOF
# File A

$SHARED_250

Unique to A.
EOF

cat > tests/_fixtures/context-audit/claude-md-dup-b.md <<EOF
# File B

$SHARED_250

Unique to B.
EOF

# Boundary fixtures: 199 (under) and 201 (over)
SHORT_199=$(printf '%.0sy' {1..199})
LONG_201=$(printf '%.0sz' {1..201})

cat > tests/_fixtures/context-audit/claude-md-dup-boundary-a.md <<EOF
# Boundary A

$SHORT_199

$LONG_201
EOF

cat > tests/_fixtures/context-audit/claude-md-dup-boundary-b.md <<EOF
# Boundary B

$SHORT_199

$LONG_201
EOF
```

- [ ] **Step 2: Write failing duplication tests**

Append to `tests/scripts/context-audit.bats`:

```bash
@test "dup: same 250-char block in two files → flagged with both paths" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-dup-a.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-dup-b.md" \
     "$SANDBOX_DIR/CLAUDE.local.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  assert_output --partial "Duplication findings"
  assert_output --partial "CLAUDE.md"
  assert_output --partial "CLAUDE.local.md"
}

@test "dup: 100-char block (under 200 threshold) → not flagged" {
  cat > "$SANDBOX_DIR/CLAUDE.md" <<EOF
# A

$(printf '%.0sx' {1..100})

Unique A.
EOF
  cat > "$SANDBOX_DIR/CLAUDE.local.md" <<EOF
# B

$(printf '%.0sx' {1..100})

Unique B.
EOF
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  refute_output --partial "Duplication findings"
}

@test "dup: boundary cases — 199 not flagged, 201 flagged (exactly one finding)" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-dup-boundary-a.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-dup-boundary-b.md" \
     "$SANDBOX_DIR/CLAUDE.local.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  # Exactly one "duplicate block" finding (the 201-char z-block). The 199-char
  # y-block must NOT appear in any flagged finding line.
  local dup_count
  dup_count=$(echo "$output" | grep -c "duplicate block" || true)
  [ "$dup_count" = "1" ]
  # Direct content assertion: a 50-char fragment of the 199-char block must
  # not appear anywhere in the duplicate-findings section.
  refute_output --partial "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
}

@test "dup: same block twice in single file → NOT flagged (spec edge case)" {
  # Spec requires: only cross-file dups count. Within-file repetition is
  # silently ignored.
  local block
  block=$(printf '%.0sw' {1..250})
  cat > "$SANDBOX_DIR/CLAUDE.md" <<EOF
# Single file with two copies of the same 250-char block

$block

Some unique text in between.

$block

Trailing.
EOF
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  refute_output --partial "duplicate block"
}
```

- [ ] **Step 3: Run tests — expect 3 fails**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: 3 dup tests fail (no detection yet).

- [ ] **Step 4: Implement duplication scan (bash temp-file approach, no awk-internal hashing)**

Rationale: previous draft passed paragraph content through `awk` → `printf` → shell pipe. Backticks, `$()`, embedded quotes, and newlines in CLAUDE.md content broke that. Replaced with a pure-bash approach: bash splits each file into paragraph blocks via awk emitting NUL-separated records, then bash hashes each block via temp file + `sha1sum`/`shasum`. Eliminates the entire shell-quoting failure surface. Also tracks REAL line numbers (not paragraph index) and suppresses within-file-only duplicates per spec.

Add to `scripts/context-audit.sh`:

```bash
# --- Duplication detection ---

# Pick available sha1 binary. Linux has sha1sum; macOS has shasum -a 1.
sha1_for_file() {
  local f=$1
  if   command -v sha1sum >/dev/null 2>&1; then sha1sum "$f" | awk '{print $1}' | cut -c1-16
  elif command -v shasum  >/dev/null 2>&1; then shasum -a 1 "$f" | awk '{print $1}' | cut -c1-16
  else return 1
  fi
}

# Emit one record per >=200-char paragraph block:
#   <file>\t<start-line>\t<block-byte-length>\t<NUL-delimited-block-bytes>\n
# We use NUL between fields-with-content and \n as record terminator works
# only if blocks contain no NUL — CLAUDE.md content is text so this holds.
# Implementation: awk emits "file\tstart_line\tlength\tblock\0" and bash
# reads via `read -d ''` (NUL-delimited).
extract_blocks_to() {
  local out_file=$1
  shift
  for f in "$@"; do
    awk -v file="$f" '
      BEGIN { line = 1; in_block = 0; block = ""; block_start = 1; block_len = 0 }
      /^[[:space:]]*$/ {
        if (in_block && block_len >= 200) {
          printf "%s\t%d\t%d\t%s\0", file, block_start, block_len, block
        }
        in_block = 0; block = ""; block_len = 0
        line++
        next
      }
      {
        if (!in_block) { block_start = line; in_block = 1 }
        if (block_len > 0) { block = block "\n" $0; block_len += length($0) + 1 }
        else               { block = $0;             block_len  = length($0) }
        line++
      }
      END {
        if (in_block && block_len >= 200) {
          printf "%s\t%d\t%d\t%s\0", file, block_start, block_len, block
        }
      }
    ' "$f"
  done >> "$out_file"
}

scan_duplicates() {
  local -a files=("$@")
  if [[ ${#files[@]} -lt 2 ]]; then return 0; fi

  # Bail gracefully if no sha1 binary at all.
  if ! command -v sha1sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo "(skipped — no sha1 binary available)"
    return 0
  fi

  local raw hashes_dir
  raw=$(mktemp)
  hashes_dir=$(mktemp -d)
  trap 'rm -rf "$raw" "$hashes_dir"' RETURN

  extract_blocks_to "$raw" "${files[@]}"

  # Read NUL-delimited records, hash each block via temp file.
  # Append to per-hash log files: hashes_dir/<hash16>.log holds one line per
  # occurrence: "<file>\t<start_line>\t<block_len>".
  #
  # CRITICAL: do NOT use `cut -f` to split — `cut` is line-oriented and the
  # block field contains embedded newlines. Use bash parameter expansion to
  # split only the first 3 tabs as delimiters; the remainder (which may
  # contain tabs OR newlines) becomes the block.
  local file start_line block_len block hash hash_tmp rest
  while IFS= read -r -d '' record; do
    # record format: file\tstart\tlen\tblock_content (block may have \n + \t)
    file=${record%%$'\t'*}
    rest=${record#*$'\t'}
    start_line=${rest%%$'\t'*}
    rest=${rest#*$'\t'}
    block_len=${rest%%$'\t'*}
    block=${rest#*$'\t'}

    hash_tmp=$(mktemp)
    # printf %s is byte-faithful — does not strip trailing newlines from $block
    # in a way that affects hashing (printf %s emits exactly $block bytes).
    printf '%s' "$block" > "$hash_tmp"
    hash=$(sha1_for_file "$hash_tmp") || { rm -f "$hash_tmp"; continue; }
    rm -f "$hash_tmp"

    printf '%s\t%s\t%s\n' "$file" "$start_line" "$block_len" \
      >> "$hashes_dir/$hash.log"
  done < "$raw"

  # Emit findings: for each hash log, count DISTINCT files (within-file
  # duplicates do NOT count, per spec edge case).
  local hash_log
  for hash_log in "$hashes_dir"/*.log; do
    [[ -f "$hash_log" ]] || continue
    local distinct_files total_copies block_len locs hash_short
    distinct_files=$(awk -F'\t' '{print $1}' "$hash_log" | sort -u | wc -l)
    total_copies=$(wc -l < "$hash_log")
    if (( distinct_files >= 2 )); then
      block_len=$(awk -F'\t' 'NR==1{print $3}' "$hash_log")
      hash_short=$(basename "$hash_log" .log)
      # Build locations string: "fileA:line1; fileA:line2; fileB:line5"
      locs=$(awk -F'\t' '{printf "%s%s:%s", (NR>1?"; ":""), $1, $2}' "$hash_log")
      local tokens=$(( block_len / 4 ))
      local waste=$(( tokens * (total_copies - 1) ))
      printf -- "- duplicate block (sha1 %s, ~%d tokens × %d copies across %d files, ~%d wasted): %s\n" \
        "$hash_short" "$tokens" "$total_copies" "$distinct_files" "$waste" "$locs"
    fi
  done
}
```

Key correctness notes for the implementer:

1. **NUL-delimited records:** `awk` emits `\0` as record terminator. Bash `read -r -d ''` reads up to next NUL. CLAUDE.md is text — no embedded NULs. Safe.
2. **Real line numbers:** the `start_line` field is incremented per source line (counter advances on every line including blank-delimiter lines), so it's the actual file line where the block starts (not a paragraph index).
3. **Within-file dups suppressed:** the `distinct_files` count uses `sort -u` on file column — only flag when ≥ 2 distinct files share a hash. Same hash appearing twice in one file → distinct_files=1 → not flagged.
4. **Cross-platform sha1:** Linux uses `sha1sum`, macOS uses `shasum -a 1`. Both produce 40-char hex; `cut -c1-16` truncates.
5. **Temp file cleanup:** `trap '... rm ...' RETURN` cleans both the raw blocks file and the per-hash dir on function exit.
6. **Field splitting via parameter expansion (NOT `cut`):** `cut -f` is line-oriented. Block field contains embedded newlines (paragraphs span multiple source lines). `cut` would re-process every line of a multi-line block. `${record%%$'\t'*}` and `${record#*$'\t'}` split only on actual tab characters and treat the remainder as opaque — newline-safe.

In `main()`, after size findings:

```bash
  echo ""
  echo "## Duplication findings"
  echo ""
  local dup_output
  dup_output=$(scan_duplicates "${targets[@]}")
  if [[ -z "$dup_output" ]]; then
    echo "(none found)"
  else
    echo "$dup_output"
  fi
```

- [ ] **Step 5: Re-run tests**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: all current tests (~12) pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/context-audit.sh tests/scripts/context-audit.bats tests/_fixtures/context-audit/claude-md-dup-*.md
git commit -m "feat(context-audit): cross-file duplicate-block detection (≥200 chars)"
```

---

## Chunk 4: Staleness detection (date markers + dead refs)

### Task 4.1: Date-marker staleness with $SCRIBE_AUDIT_TODAY

**Files:**
- Modify: `scripts/context-audit.sh`
- Create: `tests/_fixtures/context-audit/claude-md-stale-date.md`
- Create: `tests/_fixtures/context-audit/claude-md-fresh-date.md`
- Modify: `tests/scripts/context-audit.bats`

- [ ] **Step 1: Generate staleness fixtures**

```bash
cat > tests/_fixtures/context-audit/claude-md-stale-date.md <<'EOF'
# Test fixture — stale date

## APPLIED LEARNING

- 2024-01-15 — old learning that should flag
EOF

cat > tests/_fixtures/context-audit/claude-md-fresh-date.md <<'EOF'
# Test fixture — fresh date

## CURRENT WORK

- 2026-04-01 — recent date, should NOT flag (relative to 2026-05-03)
EOF
```

- [ ] **Step 2: Write failing staleness tests**

Append:

```bash
@test "staleness: date >6mo old (vs SCRIBE_AUDIT_TODAY) → flagged" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-stale-date.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  assert_output --partial "Date markers"
  assert_output --partial "2024-01-15"
}

@test "staleness: date <6mo old → not flagged" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-fresh-date.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  refute_output --partial "2026-04-01"
}

@test "staleness: future date → flagged with 'future date — likely typo'" {
  cat > "$SANDBOX_DIR/CLAUDE.md" <<'EOF'
# Test fixture — future date

## Some section

- 2027-01-01 — typo, future
EOF
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  assert_output --partial "future date"
  assert_output --partial "2027-01-01"
}
```

- [ ] **Step 3: Run tests — expect 2 fails**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: 2 fails.

- [ ] **Step 4: Implement date-marker staleness**

Add to `scripts/context-audit.sh`:

```bash
# --- Staleness — date markers ---

# Cross-OS date arithmetic: convert YYYY-MM-DD to days-since-epoch.
date_to_days() {
  local d=$1
  case "$(detect_os)" in
    macos) date -j -f "%Y-%m-%d" "$d" "+%s" 2>/dev/null | awk '{print int($1/86400)}' ;;
    *)     date -d "$d" "+%s"             2>/dev/null | awk '{print int($1/86400)}' ;;
  esac
}

scan_stale_dates() {
  local today_days
  today_days=$(date_to_days "$TODAY")
  local stale_threshold_days=$(( today_days - 183 ))  # ~6 months

  for f in "$@"; do
    # Find every YYYY-MM-DD with line numbers
    grep -nE '\b[0-9]{4}-[0-9]{2}-[0-9]{2}\b' "$f" 2>/dev/null | \
    while IFS=: read -r lineno rest; do
      local d
      d=$(echo "$rest" | grep -oE '\b[0-9]{4}-[0-9]{2}-[0-9]{2}\b' | head -1)
      [[ -z "$d" ]] && continue
      local d_days
      d_days=$(date_to_days "$d")
      [[ -z "$d_days" ]] && continue

      # Future date check
      if (( d_days > today_days )); then
        echo "- ⚠️ future date — likely typo: $f:$lineno → $d"
        continue
      fi

      if (( d_days < stale_threshold_days )); then
        local heading
        heading=$(awk -v ln="$lineno" '
          /^#+ / { last=$0 }
          NR==ln { print (last==""?"(no heading)":last); exit }
        ' "$f")
        local age_months
        age_months=$(( (today_days - d_days) / 30 ))
        echo "- ⚠️ Date marker > 6mo: $f:$lineno → $d (~$age_months months) under \"$heading\""
      fi
    done
  done
}
```

In `main()`, after duplicates:

```bash
  echo ""
  echo "## Staleness findings"
  echo ""
  echo "### Date markers"
  echo ""
  local date_output
  date_output=$(scan_stale_dates "${targets[@]}")
  if [[ -z "$date_output" ]]; then
    echo "(none found)"
  else
    echo "$date_output"
  fi
```

- [ ] **Step 5: Run tests — expect pass**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: all (~14) pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/context-audit.sh tests/scripts/context-audit.bats tests/_fixtures/context-audit/claude-md-{stale,fresh}-date.md
git commit -m "feat(context-audit): date-marker staleness with SCRIBE_AUDIT_TODAY env override"
```

---

### Task 4.2: Dead-reference detection

**Files:**
- Modify: `scripts/context-audit.sh`
- Create: `tests/_fixtures/context-audit/claude-md-dead-ref.md`
- Modify: `tests/scripts/context-audit.bats`

- [ ] **Step 1: Generate dead-ref fixture**

```bash
cat > tests/_fixtures/context-audit/claude-md-dead-ref.md <<'EOF'
# Test fixture — dead refs

[real-link](./does-not-exist.md)
[external](https://example.com)
[mailto](mailto:user@example.com)
[http-mangled](http://handoff-2026-05-03-070623.md)
EOF
```

- [ ] **Step 2: Write failing dead-ref tests**

```bash
@test "deadref: missing local file → flagged" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-dead-ref.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  assert_output --partial "Dead references"
  assert_output --partial "does-not-exist.md"
}

@test "deadref: https URL → not flagged" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-dead-ref.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  # Make the local target exist so only URLs are left to scan.
  touch "$SANDBOX_DIR/does-not-exist.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  refute_output --partial "example.com"
}

@test "deadref: http-mangled local path (filename-shaped host) → flagged" {
  # Catches the spec's documented edge case: [foo.md](http://foo.md) where
  # the http:// "host" is just a filename ending in .md/.sh/.json/etc.
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/claude-md-dead-ref.md" \
     "$SANDBOX_DIR/CLAUDE.md"
  touch "$SANDBOX_DIR/does-not-exist.md"  # quiet the real dead-ref signal
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  assert_output --partial "http-mangled"
  assert_output --partial "handoff-2026-05-03-070623.md"
  # Real https://example.com URL with TLD-shaped host must still NOT flag.
  refute_output --partial "example.com"
}
```

- [ ] **Step 3: Run tests — expect fails**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: 2 fails.

- [ ] **Step 4: Implement dead-ref scan**

```bash
scan_dead_refs() {
  for f in "$@"; do
    local dir
    dir=$(dirname "$f")
    # Match markdown links to local file paths. Skip http/https/mailto.
    grep -nE '\]\(([^)]+\.(md|sh|json|toml|ts|tsx|js|py|rs))\)' "$f" 2>/dev/null | \
    while IFS=: read -r lineno rest; do
      # Extract every link target from the line
      echo "$rest" | grep -oE '\]\([^)]+\)' | sed 's/^](//;s/)$//' | \
      while IFS= read -r target; do
        # Skip URLs
        case "$target" in
          http://*|https://*|mailto:*) continue ;;
        esac
        # Resolve relative to file's dir
        local resolved
        if [[ "$target" = /* ]]; then
          resolved="$target"
        else
          resolved="$dir/$target"
        fi
        if [[ ! -e "$resolved" ]]; then
          echo "- ⚠️ Dead reference: $f:$lineno → $target"
        fi
      done
    done

    # Also catch http-mangled local refs (e.g. [foo.md](http://foo.md) where
    # host is just a filename — no slash after host).
    grep -nE '\]\(https?://[^/]+\.(md|sh|json|toml|ts|tsx|js|py|rs)\)' "$f" 2>/dev/null | \
    while IFS=: read -r lineno rest; do
      local target
      target=$(echo "$rest" | grep -oE 'https?://[^)]+' | head -1)
      echo "- ⚠️ Dead reference (http-mangled local path): $f:$lineno → $target"
    done
  done
}
```

In `main()`, after date-marker section:

```bash
  echo ""
  echo "### Dead references"
  echo ""
  local deadref_output
  deadref_output=$(scan_dead_refs "${targets[@]}")
  if [[ -z "$deadref_output" ]]; then
    echo "(none found)"
  else
    echo "$deadref_output"
  fi
```

- [ ] **Step 5: Run tests — expect pass**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: all (~16) pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/context-audit.sh tests/scripts/context-audit.bats tests/_fixtures/context-audit/claude-md-dead-ref.md
git commit -m "feat(context-audit): dead-reference scan + http-mangled local-path catch"
```

---

## Chunk 5: MCP audit + final report polish + skill + slash command

### Task 5.1: MCP token-estimate lookup table

**Files:**
- Create: `scripts/mcp-token-estimates.json`
- Modify: `scripts/context-audit.sh`
- Create: `tests/_fixtures/context-audit/mcp-config-known.json`
- Create: `tests/_fixtures/context-audit/mcp-config-unknown.json`
- Create: `tests/_fixtures/context-audit/mcp-config-empty.json`
- Create: `tests/_fixtures/context-audit/mcp-config-malformed.json`
- Modify: `tests/scripts/context-audit.bats`

- [ ] **Step 1: Author the curated lookup table**

```bash
cat > scripts/mcp-token-estimates.json <<'EOF'
{
  "version": 1,
  "updated": "2026-05-03",
  "estimates": {
    "stripe":      { "tokens": 12000, "notes": "Heavy when API key set" },
    "playwright":  { "tokens": 24000, "notes": "Heaviest common server" },
    "github":      { "tokens":  5000, "notes": "Always-on for most users" },
    "memory":      { "tokens":  3000, "notes": "Always-on for most users" },
    "filesystem":  { "tokens":  2000, "notes": "Lightweight" },
    "brave":       { "tokens":  2500, "notes": "Web search" },
    "brave-search":{ "tokens":  2500, "alias_of": "brave" },
    "slack":       { "tokens":  4000, "notes": "Channel/user listing scales" },
    "linear":      { "tokens":  6000, "notes": "Issue/team listing" },
    "sentry":      { "tokens":  3500, "notes": "Project listing" },
    "stripe-mcp":  { "tokens": 12000, "alias_of": "stripe" },
    "puppeteer":   { "tokens": 18000, "notes": "Heavier alt to playwright" },
    "fetch":       { "tokens":  1500, "notes": "Lightweight" },
    "git":         { "tokens":  2500, "notes": "Local git ops" },
    "google-maps": { "tokens":  3000, "notes": "Geocoding" },
    "postgres":    { "tokens":  4000, "notes": "Schema discovery scales" },
    "sqlite":      { "tokens":  2000, "notes": "Lightweight" },
    "everart":     { "tokens":  2500, "notes": "Image gen" },
    "youtube":     { "tokens":  3000, "notes": "Transcript + metadata" },
    "notion":      { "tokens":  5500, "notes": "Database listing scales" },
    "obsidian":    { "tokens":  2500, "notes": "Vault metadata" },
    "discord":     { "tokens":  4500, "notes": "Server/channel listing" },
    "telegram":    { "tokens":  4000, "notes": "Chat listing" },
    "aws":         { "tokens":  9000, "notes": "Many service tools" },
    "azure":       { "tokens":  9000, "notes": "Many service tools" },
    "gcp":         { "tokens":  9000, "notes": "Many service tools" },
    "kubernetes":  { "tokens":  6000, "notes": "Pod/service ops" },
    "docker":      { "tokens":  3500, "notes": "Container ops" },
    "redis":       { "tokens":  2000, "notes": "Lightweight" },
    "mongodb":     { "tokens":  3500, "notes": "Schema discovery" }
  }
}
EOF
```

- [ ] **Step 2: Generate MCP config fixtures**

```bash
cat > tests/_fixtures/context-audit/mcp-config-known.json <<'EOF'
{
  "mcpServers": {
    "stripe": { "command": "stripe-mcp" }
  }
}
EOF

cat > tests/_fixtures/context-audit/mcp-config-unknown.json <<'EOF'
{
  "mcpServers": {
    "custom-internal-tool": { "command": "node", "args": ["server.js"] }
  }
}
EOF

cat > tests/_fixtures/context-audit/mcp-config-empty.json <<'EOF'
{ "mcpServers": {} }
EOF

cat > tests/_fixtures/context-audit/mcp-config-malformed.json <<'EOF'
{ this is not valid JSON
EOF
```

- [ ] **Step 3: Write failing MCP tests**

```bash
@test "mcp: known server (stripe) → estimate from lookup table" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/mcp-config-known.json" \
     "$SANDBOX_DIR/.mcp.json"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  assert_output --partial "stripe"
  assert_output --partial "12000"
}

@test "mcp: unknown server → [unknown — connect to measure] honest fallback" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/mcp-config-unknown.json" \
     "$SANDBOX_DIR/.mcp.json"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_success
  assert_output --partial "custom-internal-tool"
  assert_output --partial "unknown"
}

@test "mcp: malformed JSON → exit 2 with named bad file" {
  cp "$CLAUDE_PLUGIN_ROOT/tests/_fixtures/context-audit/mcp-config-malformed.json" \
     "$SANDBOX_DIR/.mcp.json"
  run bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_failure 2
  assert_output --partial ".mcp.json"
}
```

- [ ] **Step 4: Run tests — expect 3 fails**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: 3 fails.

- [ ] **Step 5: Implement MCP audit**

Add to `scripts/context-audit.sh`:

```bash
# --- MCP audit ---

mcp_estimates_path() {
  # Plugin-relative — script ships next to mcp-token-estimates.json
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "$script_dir/mcp-token-estimates.json"
}

audit_mcp_config() {
  local config=$1 source_label=$2
  [[ ! -f "$config" ]] && return 0

  if ! command -v jq >/dev/null 2>&1; then
    echo "- ℹ️ jq not installed — skipping MCP audit (install jq for token estimates)"
    return 0
  fi

  # Validate JSON first; emit fatal on parse failure.
  if ! jq -e . "$config" >/dev/null 2>&1; then
    echo "ERROR: malformed JSON: $config" >&2
    exit 2
  fi

  local estimates_file
  estimates_file="$(mcp_estimates_path)"

  jq -r '.mcpServers // {} | keys[]' "$config" 2>/dev/null | \
  while IFS= read -r server; do
    local lower est_tokens alias_of
    lower=$(echo "$server" | tr '[:upper:]' '[:lower:]')
    est_tokens=$(jq -r --arg k "$lower" '.estimates[$k].tokens // empty' "$estimates_file" 2>/dev/null)
    alias_of=$(jq -r --arg k "$lower" '.estimates[$k].alias_of // empty' "$estimates_file" 2>/dev/null)

    if [[ -n "$alias_of" ]]; then
      est_tokens=$(jq -r --arg k "$alias_of" '.estimates[$k].tokens // empty' "$estimates_file" 2>/dev/null)
    fi

    if [[ -n "$est_tokens" ]]; then
      local sev_icon=""
      if (( est_tokens >= 15000 )); then sev_icon="🔴"
      elif (( est_tokens >= 5000 )); then sev_icon="⚠️"
      fi
      echo "| $server | $source_label | $est_tokens | $sev_icon |"
    else
      echo "| $server | $source_label | unknown — connect to measure | ℹ️ |"
    fi
  done
}
```

In `main()`, after staleness:

```bash
  if [[ $NO_MCP -eq 0 ]]; then
    echo ""
    echo "## MCP audit"
    echo ""
    echo "| Server | Source | Est. tokens | Status |"
    echo "|---|---|---|---|"

    if [[ $GLOBAL_ONLY -eq 0 ]]; then
      audit_mcp_config "$mcp_project" "project"
    fi
    if [[ $PROJECT_ONLY -eq 0 ]]; then
      if [[ -f "$mcp_global" ]]; then
        audit_mcp_config "$mcp_global" "global"
      else
        echo "| (no global config at $mcp_global) | global | unknown | ℹ️ |"
      fi
    fi
  fi
```

- [ ] **Step 6: Run tests — expect pass**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: all (~19) pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/context-audit.sh scripts/mcp-token-estimates.json tests/scripts/context-audit.bats tests/_fixtures/context-audit/mcp-config-*.json
git commit -m "feat(context-audit): MCP audit with curated lookup table + honest unknown fallback"
```

---

### Task 5.2: Top consumers + report footer + save logic

**Files:**
- Modify: `scripts/context-audit.sh`

- [ ] **Step 1: Refactor `main()` to final structure**

Top-consumers belongs INSIDE the `## Summary` section per spec §Report format. That requires computing all entries BEFORE rendering Summary (currently main() builds the summary in the same pass as size findings, so top-consumers can't be in summary without restructuring).

Replace the entire `main()` body with this final structure. Sections render in this fixed order: Summary (with top consumers) → Size → Duplication → Staleness → MCP → Footer → exit. Single `exit 1` at the very end if `HAS_CRITICAL` is set.

```bash
main() {
  local os
  os="$(detect_os)"

  # === Phase 1: Resolve targets ===
  local mcp_global mcp_project
  mcp_global="$(resolve_mcp_global_config "$os")"
  mcp_project="$(resolve_mcp_project_config)"

  if [[ $DEBUG_PATHS -eq 1 ]]; then
    echo "MCP global config: $mcp_global"
    echo "MCP project config: $mcp_project"
    return 0
  fi

  local -a targets
  mapfile -t targets < <(resolve_claude_md_targets "$PROJECT_ONLY" "$GLOBAL_ONLY")

  # === Phase 2: Compute all sizes (single pass, drives Summary + Size sections) ===
  local critical_count=0 warn_count=0 total_tokens=0
  local -a all_entries=()    # "tokens|path|severity" for ranking
  local -a size_lines=()     # "- <icon> <path> — <n> tokens (band)" for Size section

  local t tokens severity
  for t in "${targets[@]}"; do
    tokens=$(count_tokens_file "$t")
    severity=$(classify_size "$tokens")
    total_tokens=$(( total_tokens + tokens ))
    all_entries+=("$tokens|$t|$severity")
    case "$severity" in
      critical) critical_count=$((critical_count+1))
                HAS_CRITICAL=1
                size_lines+=("- 🔴 $t — $tokens tokens (≥15000 critical)") ;;
      warn)     warn_count=$((warn_count+1))
                size_lines+=("- ⚠️ $t — $tokens tokens (5000–14999 warn)") ;;
    esac
  done

  # === Phase 3: Header + OS-fallback note ===
  echo "# Context Audit — $TODAY"
  echo ""
  echo "**Scope:** $(scope_label) · **Targets scanned:** ${#targets[@]} · **Total estimated tokens:** $total_tokens"
  echo ""
  if [[ "$os" = "linux-fallback" ]]; then
    echo "_Note: OS detection fell back to Linux paths (OSTYPE=$OSTYPE unrecognized)._"
    echo ""
  fi
  echo "---"
  echo ""

  # === Phase 4: Summary section (with embedded top-3 consumers) ===
  echo "## Summary"
  echo ""
  echo "| Severity | Count |"
  echo "|---|---|"
  echo "| 🔴 Critical | $critical_count |"
  echo "| ⚠️ Warning  | $warn_count |"
  echo ""
  echo "Top consumers:"
  if [[ ${#all_entries[@]} -eq 0 ]]; then
    echo "1. (none)"
  else
    local rank=1
    printf '%s\n' "${all_entries[@]}" | sort -t'|' -k1 -nr | head -3 | \
    while IFS='|' read -r tk path sev; do
      local icon=""
      case "$sev" in critical) icon="🔴" ;; warn) icon="⚠️" ;; esac
      echo "$rank. $path — $tk tokens $icon"
      rank=$((rank+1))
    done
  fi

  # === Phase 5: Size findings ===
  echo ""
  echo "---"
  echo ""
  echo "## Size findings"
  echo ""
  if [[ ${#targets[@]} -eq 0 ]]; then
    echo "(no CLAUDE.md files found)"
  elif [[ ${#size_lines[@]} -eq 0 ]]; then
    echo "(no size issues found)"
  else
    printf '%s\n' "${size_lines[@]}"
  fi

  # === Phase 6: Duplication findings ===
  echo ""
  echo "## Duplication findings"
  echo ""
  local dup_output=""
  if (( ${#targets[@]} >= 2 )); then
    dup_output=$(scan_duplicates "${targets[@]}")
  fi
  if [[ -z "$dup_output" ]]; then
    echo "(none found)"
  else
    echo "$dup_output"
  fi

  # === Phase 7: Staleness findings ===
  echo ""
  echo "## Staleness findings"
  echo ""
  echo "### Date markers"
  echo ""
  local date_output
  date_output=$(scan_stale_dates "${targets[@]}")
  if [[ -z "$date_output" ]]; then echo "(none found)"; else echo "$date_output"; fi
  echo ""
  echo "### Dead references"
  echo ""
  local deadref_output
  deadref_output=$(scan_dead_refs "${targets[@]}")
  if [[ -z "$deadref_output" ]]; then echo "(none found)"; else echo "$deadref_output"; fi

  # === Phase 8: MCP audit ===
  if [[ $NO_MCP -eq 0 ]]; then
    echo ""
    echo "## MCP audit"
    echo ""
    echo "| Server | Source | Est. tokens | Status |"
    echo "|---|---|---|---|"
    if [[ $GLOBAL_ONLY -eq 0 ]]; then
      audit_mcp_config "$mcp_project" "project"
    fi
    if [[ $PROJECT_ONLY -eq 0 ]]; then
      if [[ -f "$mcp_global" ]]; then
        audit_mcp_config "$mcp_global" "global"
      else
        echo "| (no global config at $mcp_global) | global | unknown | ℹ️ |"
      fi
    fi
  fi

  # === Phase 9: Footer ===
  echo ""
  echo "---"
  echo ""
  echo "*Estimates ±15% (char/4 heuristic). Run \`/project-scribe:context-audit --no-save\` for stdout-only.*"

  # === Phase 10: Single deferred exit ===
  if (( HAS_CRITICAL > 0 )); then
    exit 1
  fi
}

# Helper for header scope label.
scope_label() {
  if   (( GLOBAL_ONLY ));  then echo "global only"
  elif (( PROJECT_ONLY )); then echo "project only"
  else                          echo "project + global"
  fi
}
```

This replaces every prior draft of `main()` from Chunks 1, 2, 3, 4. The earlier per-chunk `main()` snippets were intentionally incremental to keep TDD red-green tight; this is the consolidated end-state. When Chunk 5 Task 5.2 fires, the implementer paste-replaces the entire `main()` with the version above. All earlier tests still pass because the section order, severity logic, and exit codes are unchanged — only the rendering is consolidated.

- [ ] **Step 2: Manual smoke test**

Run on the scribe repo itself:

```bash
cd C:/Users/forty/.claude/plugins/marketplaces/project-scribe
bash scripts/context-audit.sh
```

Expected: clean markdown report. Document any issues found, fix them, re-run.

- [ ] **Step 3: Commit**

```bash
git add scripts/context-audit.sh
git commit -m "feat(context-audit): top-consumers ranking + report footer"
```

---

### Task 5.3: Skill + slash command

**Files:**
- Create: `skills/context-audit/SKILL.md`
- Create: `commands/context-audit.md`
- Create: `tests/skills/context-audit.bats`

- [ ] **Step 1: Author SKILL.md**

Frontmatter convention (verified against existing scribe SKILLs — `scribe-verify`, `scribe-status`, `xref-lint`, `base-audit`): only `name:` and `description:`. No `type:` field. Drop the `type:` line that earlier draft included.

```bash
mkdir -p skills/context-audit
cat > skills/context-audit/SKILL.md <<'EOF'
---
name: context-audit
description: Read-only diagnostic that scans CLAUDE.md (project + global) and MCP server configs for size, duplication, and staleness findings. Emits markdown report with concrete suggested patches. Triggers include "context audit", "/context-audit", "audit my context", "check token bloat", "what's eating my context", "/project-scribe:context-audit".
---

# /context-audit — Context Bloat Diagnostic

Read-only scan of CLAUDE.md targets + MCP server configs. Reports size / duplication / staleness findings with suggested fixes. Honesty contract: never mutates user config; ambiguous findings flagged as ambiguous, not silently guessed.

## When to invoke

- User asks "context audit", "/context-audit", "audit my context", "check token bloat".
- User reports hitting Max plan usage limits and wants to identify drain sources.
- After significant CLAUDE.md changes — sanity check no duplicates / stale dates introduced.

## What it does

1. Resolves CLAUDE.md targets: `$PWD/CLAUDE.md`, `$PWD/CLAUDE.local.md`, `$HOME/.claude/CLAUDE.md`, `$HOME/.claude/rules/**/*.md`.
2. Resolves MCP configs: `$PWD/.mcp.json` + OS-specific global `claude_desktop_config.json`.
3. Char/4 token-counts each. Classifies by 5k/15k thresholds.
4. Cross-file paragraph-block duplication scan (≥200 chars).
5. Staleness: date markers > 6mo + dead local-file references.
6. MCP server enumeration with curated lookup-table estimates.
7. Emits markdown report. Saves to `docs/status/context-audit-YYYY-MM-DD.md` unless `--no-save`.

## Flags

- `--no-save` — stdout only.
- `--global-only` — skip project paths.
- `--project-only` — skip global paths.
- `--no-mcp` — skip MCP audit.

## Procedure

1. Run the script from the project root, appending any flags the user passed
   to the slash command. Concrete invocation pattern Claude executes:

   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/scripts/context-audit.sh" <user-supplied-flags>
   ```

   The slash command shim (`commands/context-audit.md`) declares
   `argument-hint: "[--no-save] [--global-only|--project-only] [--no-mcp]"`.
   When the user invokes `/project-scribe:context-audit --no-mcp`, Claude
   substitutes `--no-mcp` literally into the bash command above. No `$@`
   forwarding — Claude does the substitution at invocation time.

2. Capture stdout — that IS the report.
3. If exit 0 + no critical findings → surface report.
4. If exit 1 → report has critical findings, surface verbatim. Do NOT auto-apply patches.
5. If exit 2 → script aborted (malformed config or missing $HOME). Surface stderr.
6. Unless `--no-save` was passed, save report to `docs/status/context-audit-YYYY-MM-DD.md`. Append `-HHMMSS` suffix on same-day re-runs to avoid silent overwrite.

## Honesty contract

- Read-only. Script never edits CLAUDE.md, .mcp.json, or claude_desktop_config.json.
- Unknown MCP servers reported as `[unknown — connect to measure]`, not silently guessed.
- Estimate accuracy ±15% (char/4 heuristic) — disclosed in report footer.

## Test stability env var

Tests pin `SCRIBE_AUDIT_TODAY=YYYY-MM-DD` so date-based fixtures don't rot. Same precedent as `SCRIBE_VERIFY_TIMEOUT` from v0.7.4.
EOF
```

- [ ] **Step 2: Author slash command shim**

```bash
cat > commands/context-audit.md <<'EOF'
---
description: Read-only context-bloat diagnostic — scans CLAUDE.md + MCP configs, reports size/dup/staleness findings with suggested patches.
argument-hint: "[--no-save] [--global-only|--project-only] [--no-mcp]"
---

Invoke the `context-audit` skill. Pass any provided flags through verbatim.
EOF
```

- [ ] **Step 3: Author skill contract tests**

```bash
cat > tests/skills/context-audit.bats <<'BATS'
#!/usr/bin/env bats

load '../_libs/bats-support/load'
load '../_libs/bats-assert/load'

setup() {
  PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
}

@test "skill: SKILL.md exists with required frontmatter (name + description, scribe convention)" {
  local skill_md="$PLUGIN_ROOT/skills/context-audit/SKILL.md"
  [ -f "$skill_md" ]
  run grep -E '^name: context-audit$' "$skill_md"; assert_success
  run grep -E '^description: '        "$skill_md"; assert_success
  # NOTE: scribe SKILL convention is name + description only. No `type:` field.
}

@test "skill: slash command file exists at commands/context-audit.md" {
  [ -f "$PLUGIN_ROOT/commands/context-audit.md" ]
}

@test "skill: scripts/context-audit.sh is executable" {
  [ -x "$PLUGIN_ROOT/scripts/context-audit.sh" ]
}
BATS
```

- [ ] **Step 4: Run skill tests**

Run: `bash tests/run.sh tests/skills/context-audit.bats`
Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add skills/context-audit/SKILL.md commands/context-audit.md tests/skills/context-audit.bats
git commit -m "feat(context-audit): SKILL.md + slash command shim + 3 contract tests"
```

---

### Task 5.4: $HOME-unset skip-with-TODO test

**Files:**
- Modify: `tests/scripts/context-audit.bats`

- [ ] **Step 1: Append skip-marked test**

```bash
@test "edge: \$HOME unset → graceful abort (skip — bats helpers depend on \$HOME)" {
  skip "SKIP: \$HOME-unset path requires bats helper rework — defer to v0.7.6"
  run env -u HOME bash -c 'cd "$1" && bash "$2"' _ "$SANDBOX_DIR" "$SCRIPT"
  assert_failure 2
}
```

- [ ] **Step 2: Run all tests**

Run: `bash tests/run.sh tests/scripts/context-audit.bats`
Expected: ~18 active pass, 1 skipped with reason.

- [ ] **Step 3: Commit**

```bash
git add tests/scripts/context-audit.bats
git commit -m "test(context-audit): skip-with-TODO for \$HOME-unset edge case"
```

---

## Chunk 6: Release packaging

### Task 6.1: Dogfood + DECISIONS entry

**Files:**
- Modify: `docs/DECISIONS.md`

- [ ] **Step 1: Dogfood on scribe repo itself**

```bash
cd C:/Users/forty/.claude/plugins/marketplaces/project-scribe
DOGFOOD_OUT=$(mktemp -t scribe-self-audit.XXXXXX.md)
bash scripts/context-audit.sh > "$DOGFOOD_OUT"
cat "$DOGFOOD_OUT"
```

(`mktemp` cross-platform — works on Windows-msys, macOS, Linux. Avoids `/tmp/` which doesn't exist on Windows.)

Expected: clean report. Look for any false positives or missed findings. Fix bugs found, then re-dogfood until output looks correct.

- [ ] **Step 2: Author DECISIONS entry**

Prepend to `docs/DECISIONS.md`:

```markdown
## 2026-05-03 — Context Audit skill: char/4 heuristic + curated MCP table + read-only

**Context:** Backlog item #3 from research synthesis. Brad signal 8/10. Universal user pain ("hitting Max plan usage limits"). Need a diagnostic, not a fixer.

**Decision:** Ship `/project-scribe:context-audit` as read-only skill backed by `scripts/context-audit.sh` + `scripts/mcp-token-estimates.json` curated lookup table. Char/4 token heuristic (matches `compact-decisions` precedent, ±15% accuracy footnoted). Hardcoded 5k/15k severity thresholds. Three finding types: size, duplication (≥200-char paragraph-block hash), staleness (date markers >6mo + dead local-file refs). MCP audit covers project + OS-specific global config. Skip-with-TODO on `$HOME`-unset edge case (bats helper limitation).

**Alternatives considered:**
- Multi-script split (`scripts/lib/audit-claude.sh` etc.) — speculative `scripts/lib/` invention, no second feature needs it yet. Rejected.
- tiktoken/Anthropic API token counting — adds Python or network dep. Rejected for ±15% acceptable in diagnostic.
- Auto-fix flag — violates "scribe is observation-only" anti-rec from research synthesis. Rejected.
- Hooks/skills audit in v0.7.5 — scope creep. Deferred to v0.7.6.

**Revisit when:** users complain about MCP estimate accuracy (indicates need for runtime probe), or hooks/skills auditing surfaces as common ask.
```

- [ ] **Step 3: Commit**

```bash
git add docs/DECISIONS.md
git commit -m "docs(decisions): v0.7.5 context-audit architecture decision"
```

---

### Task 6.2: CHANGELOG + plugin.json + README

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`
- Modify: `README.md`

- [ ] **Step 1: Prepend CHANGELOG v0.7.5 entry**

Read existing CHANGELOG.md format, then prepend:

```markdown
## [0.7.5] — 2026-05-03

### Added

- `/project-scribe:context-audit` — read-only diagnostic that scans CLAUDE.md (project + global) and MCP server configs for size / duplication / staleness findings. Emits markdown report with concrete suggested patches. Honors v0.7.4 honesty contract.
- `scripts/context-audit.sh` — heavy lifter (~500 lines).
- `scripts/mcp-token-estimates.json` — curated MCP token-cost lookup table (~30 entries, schema versioned, alias support).
- `skills/context-audit/SKILL.md` + `commands/context-audit.md` — skill + slash command shims.
- ~21 bats cases (~18 script + 3 skill contract; 1 skip-with-TODO for $HOME-unset).
- `SCRIBE_AUDIT_TODAY` env var for test-stable date-based fixtures (precedent from `SCRIBE_VERIFY_TIMEOUT`).

### Source

- Research synthesis backlog item #3 — Brad signal 8/10.
- Spec: `docs/superpowers/specs/2026-05-03-context-audit-design.md` (SHA `8396332`).
- Plan: `docs/superpowers/plans/2026-05-03-context-audit.md`.
```

- [ ] **Step 2: Bump plugin.json**

```bash
# Edit version field 0.7.4 → 0.7.5
```

- [ ] **Step 3: Bump README version badge**

Find line(s) referencing `v0.7.4` or `0.7.4` in README.md, update to `0.7.5`.

- [ ] **Step 4: Run full test suite**

```bash
bash tests/run.sh
```

Expected: all tests pass (existing v0.7.3 + v0.7.4 suites still green; v0.7.5 ~21 new cases pass).

- [ ] **Step 5: Commit (tag deferred to Task 6.4 Step 3 — after squash-merge)**

```bash
git add CHANGELOG.md .claude-plugin/plugin.json README.md
git commit -m "chore: bump v0.7.5 — context-audit"
```

**Do NOT tag here.** Squash-merge replaces the local commit SHA with a new merge-commit SHA on master. Tagging the pre-merge commit yields a tag pointing at an orphaned SHA. Tagging happens in Task 6.4 Step 3 after the merge lands on master.

---

### Task 6.3: Update STATE.md (Current focus + Last shipped)

**Files:**
- Modify: `docs/STATE.md`

- [ ] **Step 1: Refresh STATE.md (Current focus only — leave Last shipped to reconcile skill)**

Update `## Current focus` to reflect v0.7.5 ship + next backlog item #4 (token-budget tab).

**Do NOT manually edit `## Last shipped`.** `project-scribe:reconcile-project-state` runs at next session start and rewrites the block from `git log --oneline -10` automatically. Manual pre-populate would be wiped on next session AND risks pointing at orphaned pre-squash SHAs.

- [ ] **Step 2: Commit STATE update**

```bash
git add docs/STATE.md
git commit -m "docs(state): reconcile post-v0.7.5 ship"
```

---

### Task 6.4: PR + merge + push tag

**Files:** none (git ops only)

- [ ] **Step 1: Push branch + open PR**

```bash
git push -u origin <feature-branch>
gh pr create --title "v0.7.5: /project-scribe:context-audit" --body "$(cat <<'EOF'
## Summary

- Read-only diagnostic for CLAUDE.md (project + global) + MCP server token bloat
- Three finding types: size (5k/15k thresholds), cross-file duplication (≥200-char blocks), staleness (date markers >6mo + dead refs)
- ~21 bats cases (18 script + 3 skill contract; 1 skip-TODO)
- Curated MCP estimate table at `scripts/mcp-token-estimates.json` (~30 entries, alias support)
- Honors v0.7.4 honesty contract: read-only, ambiguous = ambiguous (not guessed)

## Source

- Research synthesis backlog #3 — Brad signal 8/10
- Spec: `docs/superpowers/specs/2026-05-03-context-audit-design.md`
- Plan: `docs/superpowers/plans/2026-05-03-context-audit.md`

## Test plan

- [x] `bash tests/run.sh` green locally (all v0.7.3 + v0.7.4 + v0.7.5 cases)
- [x] CI passes
- [x] Dogfooded on scribe repo itself, output reviewed
- [x] Manual smoke test: `--no-save`, `--global-only`, `--project-only`, `--no-mcp` flags
- [x] Manual exit-code check: 0 / 1 / 2 paths verified

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 2: Wait for CI green, then merge**

```bash
gh pr checks --watch
gh pr merge --squash --delete-branch
```

- [ ] **Step 3: Tag the merge commit on master, then push tag**

```bash
git checkout master
git pull
# Tag the merge commit that just landed (HEAD on master after pull).
git tag -a v0.7.5 -m "v0.7.5 — /project-scribe:context-audit (backlog #3, Brad 8/10)"
git push origin v0.7.5
```

Tag now points at the SHA actually present in master's history, not an orphaned pre-squash commit.

---

## Definition of done (mirrors spec)

1. ☐ All ~18 script bats cases + ~3 skill contract cases (~21 total) passing locally + in CI
2. ☐ `/project-scribe:context-audit` invokes cleanly on the scribe repo itself (dogfood)
3. ☐ Report saved to `docs/status/` with correct format
4. ☐ All four flags work as documented (`--no-save`, `--global-only`, `--project-only`, `--no-mcp`)
5. ☐ Three exit codes correctly emitted (0 / 1 / 2)
6. ☐ Cross-OS path resolution verified via OSTYPE mocking in bats
7. ☐ DECISIONS.md entry logged
8. ☐ CHANGELOG.md updated with v0.7.5 entry
9. ☐ `.claude-plugin/plugin.json` bumped 0.7.4 → 0.7.5
10. ☐ README.md version badge bumped
11. ☐ PR merged with CI green + tag `v0.7.5` pushed
