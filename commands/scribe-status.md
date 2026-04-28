---
description: Read-only diagnostic — reports decay-system + Stop-hook health for the current scribe-enabled project. Lists every memory file with last_used / hits / decay score / status bucket. Never modifies anything.
---

Invoke the `scribe-status` skill.

The skill will:
1. Resolve the memory dir for the current project via the standard slug rule.
2. If `docs/STATE.md` is missing, bail silent (project not scribe-enabled).
3. If the memory dir is missing, report that and still check Stop-hook registration.
4. Otherwise enumerate every `*.md` memory file and compute its decay score and status bucket using the same formula as `compact-memory` Pass 0.
5. Report bump-log freshness (entries + last mtime, "firing within 24h" flag).
6. Confirm the Stop hook is registered in `hooks/hooks.json` and cross-check against bump-log activity.

Read-only. No writes anywhere — no memory edits, no `.bump-log` mutation, no hook config changes.
