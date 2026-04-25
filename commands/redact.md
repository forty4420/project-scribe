---
description: Redact a DECISIONS.md entry body while keeping its heading, date, and four-field shape. For leaked secrets, PII, or compliance deletion requests. Audit trail stays in git history.
---

Invoke the `redact-decision` skill.

Pass any hint about the target entry (date, title fragment, or "the one about X"). The skill will:

1. Locate the entry, show it in full, confirm.
2. Ask for the redaction reason (one line).
3. Ask which fields to scrub (default: all four).
4. Replace the field bodies with `[REDACTED YYYY-MM-DD — reason: <one-liner>]`, preserving headings and structure.
5. Show the diff, wait for approval.
6. Offer a scoped commit.

**Before redacting a leaked credential: rotate it first.** The skill will remind you. Redaction is cleanup; rotation is the real fix.

Git history still holds the pre-redaction content. For full history scrubbing, `git filter-repo` is a separate step.
