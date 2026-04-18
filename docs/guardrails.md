# Base-scope guardrails — design + threat model

This doc explains the optional guardrails mode of project-scribe. Skip it if you only want indexing.

## What problem does this solve?

Some projects have a hard architectural rule: **"this folder is core, that folder is off-limits for new features."** Examples:

- Plugin systems: core stays lean, features extend via plugins
- Frameworks: library code is stable, applications are separate
- Game engines: engine vs game content
- Any project where Rule X says "don't put Y in folder Z"

Without enforcement, these rules drift. A contributor (or an AI agent) takes a shortcut — "just this once" — and the boundary erodes. Six months later, your "plugin-based" project has half its features hard-coded in core.

Guardrails give you **automated enforcement** so the rule holds even when nobody's watching. Five layers, each catching a different failure mode.

---

## The stack (five layers)

### 1. Permission-layer deny (`.claude/settings.json`)

A hard wall. Tells Claude Code: "never write to these directories, period."

```json
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "deny": [
      "Write(src-tauri/src/persona/**)",
      "Edit(src-tauri/src/persona/**)",
      "NotebookEdit(src-tauri/src/persona/**)"
    ]
  }
}
```

Claude Code rejects the write **before** running any hooks or showing any prompt. No "Allow always" button. No bypass. The cleanest block in the stack.

Scoped to directories you've listed in `docs/BASE_ALLOWLIST.md` as "NOT allowed."

### 2. PreToolUse hook (`.claude/hooks/pretooluse_base_guard.sh`)

Runs before every Write / Edit / NotebookEdit. Checks the target path against `BASE_ALLOWLIST.md`:

- Locked dir (NOT-allowed list)? → emit deny, show helpful message pointing at `/unlock-base`.
- New top-level dir under guarded prefix that isn't on known-good list? → emit deny, suggest plugin path.
- New path inside a known guarded dir but not on allowlist? → emit deny, require BASE_ALLOWLIST entry.
- Path in known-good infrastructure dir (tests, hooks, assets)? → silent pass.

**Known limitation:** under some Claude Code permission modes, the JSON `permissionDecision: deny` signal from hooks is not always honored at runtime. The deny message still appears, but the file may land on disk. The permission-layer deny (layer 1) and pre-commit hook (layer 3) are the hard backstops. Treat this hook as advisory + educational — it tells you *why* a path is wrong, even if the block isn't always enforced at the live-write layer.

### 3. Pre-commit hook (`.git/hooks/pre-commit`)

Git-level gate. Runs when you (or Claude) type `git commit`. Scans every newly-added file:

- Hard violation (locked dir) → exit 1, reject commit.
- New top-level dir under guarded prefix, not on known-good list → exit 1, reject commit.
- New path inside guarded subdir, not on allowlist → exit 1, reject commit with "NEEDS REVIEW."
- Everything else → pass.

**Cannot be ignored by Claude Code — git runs it, not Claude.** This is the real last-line-of-defense for drift that slips past the live-write guard.

Bypass: `git commit --no-verify`. Accepted residual risk — you'd be doing it on purpose.

### 4. SessionStart hook (`.claude/hooks/sessionstart_inject_rules.sh`)

Runs at the start of every Claude Code session. Three jobs:

**a) Inject rules into context.** Prints the "NOT allowed" section of `BASE_ALLOWLIST.md` into the session so Claude sees the locked paths immediately — not after reading CLAUDE.md.

**b) Canary health check.** Verifies the guardrail files still exist and are wired:
- `.git/hooks/pre-commit` present and executable?
- `.claude/hooks/pretooluse_base_guard.sh` present?
- `.claude/settings.json` has a `permissions.deny` block?

If any missing / corrupted → loud **GUARDRAIL HEALTH WARNING** banner at session start. Eliminates silent-failure mode.

**c) Working-tree drift scan.** Runs the pre-commit logic against `git status --porcelain` (untracked + unstaged). If drift is sitting in the working copy from a prior session, surfaces an **UNCOMMITTED BASE-SCOPE DRIFT DETECTED** banner. Prevents the "bad file survives session switches unnoticed" failure.

### 5. Base-audit skill (`/audit`)

Manual-invoke skill. Scans the current diff against `BASE_ALLOWLIST.md` + VISION rules. Use before claiming work is complete, before handoff, before commit.

`auto-handoff` skill includes a Step 0 pre-flight that runs audit logic automatically before writing a handoff doc — so session transfers surface uncommitted drift.

---

## Unlock / lock workflow

Sometimes you legitimately need to edit a locked directory — usually during a migration out of base. The `/unlock-base` and `/lock-base` skills handle this:

```
> /unlock-base
```

1. Backs up `.claude/settings.json` to `.claude/settings.locked.json`.
2. Removes the `permissions.deny` block.
3. Offers a restart (settings need restart to take effect). Uses `cc-restart` if installed.

Edit what you need. Then:

```
> /lock-base
```

1. Restores `.claude/settings.json` from the backup.
2. Deletes the backup.
3. Offers a restart.

The backup file (`settings.locked.json`) is auto-added to `.gitignore` — it's a transient state marker, not committed.

---

## BASE_ALLOWLIST.md — the source of truth

Single file drives all five layers. Format:

```markdown
## Rust backend — allowed in `src-tauri/src/`

### Directories
- `agents/` — sub-agent orchestration
- `audio/` — mic capture, player
- ...

### Files
- `chat.rs` — Provider trait
- `main.rs` — Tauri entry
- ...

## Rust backend — **NOT allowed** in `src-tauri/src/`

- `persona/` — violates VISION §6.4. Extract to plugin.
- `providers/` — violates VISION §6.2. Extract to plugin.
- `tools/` — violates VISION §6.3. Extract to plugin.
```

Hooks parse the `## ... allowed` and `## ... NOT allowed` headers and pull the backtick-quoted paths. Add a new path to "NOT allowed" to lock it. Move from "NOT allowed" to "allowed" to unlock via the normal path (vs `/unlock-base` which is a temporary override).

**Never hand-edit without logging a decision first.** The flow:
1. Write a `docs/DECISIONS.md` entry explaining why the path is / isn't base.
2. Update `BASE_ALLOWLIST.md`.
3. Commit both together.

---

## Threat model — what each layer catches

| Scenario | Caught by |
|---|---|
| **A.** Naive drift: AI writes to known-bad dir (`persona/`) | Layer 1 (permission deny) — silent bounce, no prompt |
| **B.** Subtle drift: new file in allowed dir that implements plugin behavior | Layer 5 (`/audit` skill) — requires human judgment |
| **C.** Outside-prefix drift: AI invents new top-level dir (`src-tauri/daemons/`) | Layer 2 (PreToolUse advisory) + Layer 3 (pre-commit hard block) |
| **D.** Bypass: `git commit --no-verify` | Not caught — accepted residual risk |
| **E.** Cross-session drift: bad file from prior session sitting uncommitted | Layer 4 (working-tree scan) banner at session start |
| **F.** Hook deactivation: settings corrupted or git hook deleted | Layer 4 (canary) banner at session start |

**Residual risk (accepted):**
- `git commit --no-verify` bypasses the hard backstop. Solo-dev / trust-based workflow.
- Editing `.claude/settings.json` or `BASE_ALLOWLIST.md` to self-grant permission — no meta-guard. Solo-dev, no adversarial threat model.
- Subtle plugin-behavior drift inside allowed dirs — human review only.

**Not yet implemented:**
- Server-side check (GitHub Actions on push) for teams pushing to a shared remote. Would close the `--no-verify` gap.

---

## Quick mental model

> **Wall + advisor + commit gate + health monitor + drift scanner.**

- **Wall** (permission deny) blocks known-bad paths instantly.
- **Advisor** (PreToolUse hook) tells Claude *why* a path is wrong — may or may not block in the moment.
- **Commit gate** (pre-commit hook) is the hard last-line before code enters history.
- **Health monitor** (SessionStart canary) screams if any layer is broken.
- **Drift scanner** (SessionStart working-tree scan) screams if drift survived a session.

If any single layer breaks, the others still catch the common cases. If all five break, you have bigger problems than drift.

---

## Should I enable this?

**Enable if:**
- Your project has a formal "core vs extension" rule you want to preserve.
- You're building a framework, plugin system, or any codebase where contributors (AI or human) will be tempted to shortcut past architectural boundaries.
- You've been burned before by drift — shortcuts accumulating until the rule is meaningless.

**Skip if:**
- You're building a monolith or simple app. The overhead isn't worth it.
- Your architecture is still fluid; locking the boundaries prematurely creates friction.
- Nobody on the project (human or AI) is likely to violate the rule anyway.

Indexing mode is enough for most projects. Guardrails pay off when the cost of drift is high and the temptation to drift is real.
