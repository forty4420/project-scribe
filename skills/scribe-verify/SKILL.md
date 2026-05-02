---
name: scribe-verify
description: Read-only verification gate. Runs the project's verify command, parses STATE.md "Last shipped" top entry, checks git drift since the claimed SHA, and emits a markdown report with suggested fixes. Triggers include "scribe-verify", "/scribe-verify", "verify ship claim", "is STATE.md current", "drift check", "did the last ship actually pass".
---

# Scribe verify

Read-only diagnostic. Catches "lying-by-omission" — STATE.md claims a ship
that broke tests, has commits since the claimed SHA, or references a SHA
that no longer exists.

## Hard rules — never violate

- **Read-only.** Never edit STATE.md, never commit, never modify any
  scribe state. The script writes nothing back to the repo.
- **No silent guessing on ambiguous fuzzy SHA match.** If multiple
  candidates resolve from a version label, abort drift checks and report
  the candidate list — let the user resolve.
- **Bail with a report (not silently) if STATE.md missing, no verify
  command resolvable, or no parseable Last shipped block.** Exit 2 with
  a markdown error pointing at the fix.

## When to invoke

- User says "scribe-verify", "/scribe-verify", "verify ship claim",
  "is STATE.md current", "did the last ship actually pass", "drift check"
- Before claiming a release in conversation ("just shipped v0.7.4" → run
  this first to confirm).
- After the auto-handoff skill writes a session bundle (verifies the
  shipped claim before the user closes the session).

## Pre-flight

The helper script handles all gates. Just invoke it and surface the
output verbatim.

## Execution

Invoke:

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/scribe-verify.sh"
```

Exit codes:

- **0** — all green (verify passed, claimed SHA = HEAD, tree clean)
- **1** — drift detected (verify failed, commits ahead of claim,
  uncommitted changes, claimed SHA missing, or ambiguous fuzzy match)
- **2** — config missing (no STATE.md, no verify command resolvable, no
  parseable Last shipped block)

## Surface output

Print the script's stdout verbatim to the user. Do not editorialize, do
not summarize, do not add commentary. The report is the deliverable.

If exit code is non-zero, the report itself explains what went wrong and
what to fix — that is the contract. Trust the report.

## Configuration

Set `SCRIBE_VERIFY_TIMEOUT` (seconds) in the environment to override the
default 300s timeout for slow test suites. Example:

```bash
SCRIBE_VERIFY_TIMEOUT=900 /project-scribe:scribe-verify
```
