---
name: log-decision
description: Use when the user asks to log a decision, save a rule, record a trade-off, or when you recognize a rule-shaped statement in the conversation ("no users yet", "always do X for Y", "defer Z until W") and want to capture it. Appends a 4-field entry to the top of docs/DECISIONS.md.
---

# Log a project decision

Append-only decision log. Never edit past entries.

## When to invoke

- User explicit ask: "log this decision", "record that rule", "save as decision", "log it".
- Auto-propose (but don't write until user confirms): when the user makes a statement that sounds like a durable rule, ask: "that sounds like a durable decision — log it?"
  - Rule-shaped statements include: scope boundaries ("no X until Y"), technical constants ("always use A for B"), priorities ("Z is not shipping in v1"), trade-offs ("we accept <cost> because <reason>").

## Pre-flight

1. Check for `docs/DECISIONS.md`. If missing → suggest running init-project-scribe first.
2. Confirm the user wants to log this (if auto-proposed — do not write without confirmation).

## Gather the 4 fields

Plain-language prompt, one at a time or in one block depending on user preference:

1. **Title** — short, 3-8 words. Example: "Break things freely until first external user"
2. **Context** — why this decision was needed. 2-4 sentences. Example: "Solo dev, pre-release, no installed base. Every migration/deprecation cycle we add now is premature."
3. **Decision** — what was decided. 2-4 sentences. Example: "No migration paths, no deprecation cycles. Rename and delete freely. Config keys can change schema."
4. **Revisit when** — what condition would make this stale. 1 sentence. Example: "First non-Michael user installs."

If the user wants to skip Revisit-when, default to "Revisit when this decision feels wrong."

## Format the entry

```markdown
## YYYY-MM-DD — <Title>

**Context:** <context text>

**Decision:** <decision text>

**Revisit when:** <revisit text>
```

Date = today's date in ISO format.

## Insert into DECISIONS.md

1. Read `docs/DECISIONS.md`.
2. Find the first `## ` heading (the most recent decision) OR the end of the preamble (if no decisions yet).
3. Insert the new entry immediately above the first heading (so newest is on top).
4. Save.

## Commit offer

Offer:

```
docs(scribe): log decision — <title>
```

User can decline; file stays modified.

## Reversing a decision

If the user wants to reverse a past decision, do NOT edit the past entry. Create a new entry:

```markdown
## YYYY-MM-DD — Reverses YYYY-MM-DD: <original title>

**Context:** <what changed>

**Decision:** <new decision>

**Revisit when:** <condition>
```

And mention the original date in the title. The log tells the story chronologically.
