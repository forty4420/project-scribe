---
name: redact-decision
description: Scrub the body of a past DECISIONS.md entry while preserving title, date, and four-field shape. For PII, leaked secrets, or compliance deletion requests. Keeps audit trail (git log + [REDACTED] marker). Triggers include "redact decision", "/redact <entry>", "scrub that decision entry", "remove sensitive info from DECISIONS".
---

# Redact a DECISIONS.md entry

**Why this exists:** DECISIONS.md is append-only by convention. But sometimes an entry contains something that must not live in the file: a leaked credential, real user data, an NDA violation, or content subject to a deletion request. `git filter-repo` rewrites history — too heavy, breaks every clone. Manual edit breaks the append-only invariant silently. This skill offers a structured middle ground.

**What it does:** replaces the Context / Decision / How to apply / Revisit when bodies of a single entry with `[REDACTED YYYY-MM-DD — reason: <one-liner>]`. Keeps the `## YYYY-MM-DD — <title>` heading and the four-field structure so indexers, cross-references, and audit tools still parse. Git history still holds the pre-redaction content for anyone with repo access, matching the Managed Agents Memory `redact` API design (audit trail preserved, content scrubbed at head).

## When to invoke

- Explicit: "redact that decision", "/redact <date or title>", "scrub <entry>".
- Security trigger: you notice a DECISIONS entry contains what looks like a live secret, API key, password, or PII. Flag first, don't redact without confirmation.
- Compliance trigger: user reports an NDA, GDPR erasure, or legal-hold request that names specific content.

Never redact silently. Always confirm the target entry + reason.

## Pre-flight

1. Locate `docs/DECISIONS.md`. Missing → report "project-scribe not initialized" and STOP.
2. Identify the target entry. Accept any of: entry date (`2026-04-18`), title fragment, line number, or "the last decision about X". If ambiguous, list candidates and ask.
3. Show the matched entry in full. Confirm with user: "redact this one? (y/n)".
4. Ask for the redaction reason. One short line. Will be written into the entry.

## Redaction format

Original:

```markdown
## 2026-04-18 — Some decision

**Context:** Sensitive content here...

**Decision:** Sensitive content here...

**How to apply:** ...

**Revisit when:** ...
```

After redaction:

```markdown
## 2026-04-18 — Some decision

**Context:** [REDACTED 2026-04-24 — reason: leaked API key scrubbed per security rotation]

**Decision:** [REDACTED 2026-04-24 — reason: leaked API key scrubbed per security rotation]

**How to apply:** [REDACTED 2026-04-24 — reason: leaked API key scrubbed per security rotation]

**Revisit when:** [REDACTED 2026-04-24 — reason: leaked API key scrubbed per security rotation]
```

Heading + field names stay. Bodies replaced. Date in the marker is redaction date, not original entry date.

**Partial redaction:** if only one field is sensitive (e.g., only Context leaks a secret), redact only that field. Ask which fields to scrub. Default is all four if unsure.

## Safety gates

- Require explicit user "y" before writing. No silent redaction.
- Before write, preview the final file diff. User approves diff.
- Never redact more than one entry per invocation. Multiple entries = multiple calls.
- Never touch entries in `docs/DECISIONS-archive-*.md` without a separate confirmation. Archives are historical record.
- If git working tree is dirty with unrelated changes, warn before staging.

## Execution

1. Read DECISIONS.md.
2. Locate target entry by heading match.
3. Replace field bodies per the format above.
4. Write file.
5. Show the diff.

## Commit offer

Security-sensitive commits. Explicit staging only.

```
docs(scribe): redact decision <YYYY-MM-DD> — <short reason>
```

Stage:
```
git add docs/DECISIONS.md
```

Warn user:

> Git history still contains the pre-redaction content. If the sensitive data must be removed from history too, run `git filter-repo` separately — this skill only scrubs the current head.

For a leaked credential: **rotate the credential first, then redact.** Tell the user this before committing. Rotation is the real fix; redaction is cleanup.

## Reversing a redaction

Can't. Once committed, use `git revert` to restore the entry, or look up the content in prior git history. Redaction is one-way at the file level.

## Don't

- Do not delete the entry heading. Cross-references (status memos, other decisions, git commits) point at it by date + title.
- Do not rewrite redacted content "from memory" to approximate the original. Leave it redacted.
- Do not redact archived decisions without explicit confirmation.
- Do not use this skill for honest edits or corrections. Reversing a decision creates a new entry (see log-decision "Reversing a decision" section). Redaction is for content that must disappear.
- Do not batch redactions. One entry per invocation forces deliberate review.

## Interaction with other skills

- `log-decision`: unaffected. Redacted entries still count for dedup and cross-reference.
- `compact-decisions`: redacted entries can be archived normally. Archive carries the redacted form forward.
- `base-audit`: may lose enforcement signal if a rule's body is redacted. Warn user if the target entry looks load-bearing for current code rules; suggest logging a new decision that restates the rule in non-sensitive form before redacting the old one.
