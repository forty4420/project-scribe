# project-scribe

A Claude Code plugin that keeps your project's context, plans, and decisions from getting lost across sessions.

**Two modes in one plugin:**

- **Indexing mode** (always on) — tracks project state, decisions, specs, and plans. Works for any project.
- **Guardrails mode** (opt-in) — enforces architectural rules like "base vs plugin" boundaries. For modular / plugin / framework projects.

The indexing half is for everyone. The guardrails half is for projects where "what counts as base code" is a real rule that matters.

---

## Do I need guardrails?

Quick decision tree:

| Your project | Mode |
|---|---|
| Monolith app, simple CRUD, solo side project | **Indexing only** |
| Modular framework, plugin system, strict "core vs extension" rules | **Both** |
| Not sure | Start with indexing. Add guardrails later if you need them. |

If you don't have an explicit "this folder is off-limits for new features" rule, you don't need guardrails. Scribe still tracks your state, decisions, and sessions — you just skip the extra enforcement layer.

---

## Install

```bash
# From this plugin's repo (Linux / macOS):
ln -s "$(pwd)" ~/.claude/plugins/project-scribe

# Windows:
mklink /J "%USERPROFILE%\.claude\plugins\project-scribe" "C:\path\to\project-scribe"

# Restart Claude Code.
```

---

## Per-project setup

Inside any project:

```
> init project scribe
```

Claude runs the `init-project-scribe` skill. It asks:
1. Project name + current focus
2. Where specs and plans live
3. Any locked architectural rules
4. **Enable base-scope guardrails?** (y/N) — this is the mode toggle

Answer **no** → indexing mode only. Files created: `CLAUDE.md`, `docs/STATE.md`, `docs/DECISIONS.md`, plus a status memo template. That's it.

Answer **yes** → indexing + guardrails. Additional files: `docs/BASE_ALLOWLIST.md`, three hook scripts in `.claude/hooks/`, deny block in `.claude/settings.json`, git pre-commit hook. See [docs/guardrails.md](docs/guardrails.md) for the full stack.

You can enable guardrails later by re-running `init project scribe` or by manually creating `BASE_ALLOWLIST.md` + copying the hook templates.

---

## Indexing mode — what you get

Files in your project:

- **`docs/STATE.md`** — one-page dashboard: current focus, last shipped (auto-reconciled against `git log`), next up, deferred, specs + plans index.
- **`docs/DECISIONS.md`** — append-only log of architectural / scope / rules-of-engagement decisions made in conversation.
- **`docs/status/`** — per-spec implementation memos with a consistent shape.
- **`CLAUDE.md`** — auto-loaded by Claude Code at session start; points at the map.

Skills and commands (all available in indexing mode):

| Skill / Command | What it does |
|---|---|
| `init-project-scribe` | One-shot bootstrap |
| `reconcile-project-state` | Auto-fires at session start; updates STATE.md "Last shipped" from `git log` |
| `update-project-state` | End-of-ship refresh — prompts for new Current focus / Next up / Deferred, rebuilds indexes |
| `log-decision` | Append a 4-field entry to DECISIONS.md |
| `deferred-rollup` | Read-only query across all status memos |
| `auto-handoff` (`/handoff`) | Write a session handoff memo at context breakpoints |
| `/scribe` | Dashboard readout from STATE.md |

Works for any project type, any architecture, solo or team.

---

## Guardrails mode — what you get (on top of indexing)

Additional enforcement:

- **Permission-layer deny** (`.claude/settings.json`) — hard wall against writes to forbidden paths. No "Allow always" prompt ever offered; writes are rejected at permission layer.
- **PreToolUse hook** — fires before any Write/Edit; blocks new files in locked dirs or net-new base directories.
- **Pre-commit hook** — git-level gate; rejects commits that stage violations. Cannot be bypassed by Claude Code — git runs it.
- **SessionStart hook** — three jobs at session start: (1) injects base-scope rules into Claude's context, (2) canary checks all guardrail files still exist, (3) working-tree scan flags uncommitted drift from prior sessions.

Additional skills:

| Skill / Command | What it does |
|---|---|
| `base-audit` (`/audit`) | Scans current diff against BASE_ALLOWLIST before commit |
| `unlock-base` (`/unlock-base`) | Temporarily removes deny rules for rare legitimate edits to locked dirs |
| `lock-base` (`/lock-base`) | Restores deny rules after an unlock session |
| `auto-handoff` | Adds Step 0 drift pre-flight — flags uncommitted violations in the handoff doc |

Full design + threat model: **[docs/guardrails.md](docs/guardrails.md)**.

### Recommended companion: `cc-restart`

`unlock-base` and `lock-base` need a Claude Code restart for settings changes to take effect. If you have the [`cc-restart`](https://github.com/forty4420/cc-restart) plugin installed, they offer a one-command restart. Without it, they print manual restart instructions. Not required, but smoother.

### Watch-out for user-global `permissions.allow`

If your user-global `~/.claude/settings.json` has `Write(*)`, `Edit(*)`, or `NotebookEdit(*)` in `permissions.allow`, those pre-approve writes BEFORE hooks and deny rules are consulted — silently defeating the guardrail. Remove those three entries from user-global allow; keep `Bash(*)`, `Read(*)`, etc. as-is.

---

## Switching modes later

**Indexing → add guardrails:**
1. Re-run `init project scribe` and answer "yes" to guardrails prompt, OR
2. Manually create `docs/BASE_ALLOWLIST.md`, copy hook templates from `~/.claude/plugins/project-scribe/skills/init-project-scribe/templates/base-scope-guard/`, wire into `.claude/settings.json` + `.git/hooks/pre-commit`.

**Guardrails → remove:**
1. Delete `docs/BASE_ALLOWLIST.md` — guardrail skills fail-open when this file is missing and silently skip.
2. Remove the `permissions.deny` block from `.claude/settings.json`.
3. Remove `.git/hooks/pre-commit` (or replace with your own).
4. SessionStart hook will stop injecting base-scope rules automatically (it checks for the allowlist).

Indexing side keeps working either way.

---

## License

MIT
