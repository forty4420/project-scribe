---
name: decision-prompt
description: Proactive skill — detects rule-shaped statements in conversation and offers to log them to DECISIONS.md before they're lost. Use when the user answers a judgment question with strong-language ruling (never/always/defer/override), explicitly vetoes an approach, or picks between options with stated reason. One yes/no prompt per decision moment. Don't re-debate. Don't batch. Complement to log-decision skill (which is reactive — user has to ask).
---

# decision-prompt — catch rule-shaped moments automatically

**The problem this solves:** scribe has `docs/DECISIONS.md` and a `log-decision` skill, but users rarely remember to say "log a decision." Durable rulings die in chat. Three months later the same decision gets re-debated.

**The fix:** you (the agent) watch for rule-shaped moments in real time and offer to log them. One prompt, one keystroke, done. Cognitive load stays on you, not the user.

## When to invoke (proactive triggers)

Watch the user's messages. Offer to log when you see:

1. **Strong modal verbs as a ruling:** "never X", "always Y", "must Z", "only W"
2. **Explicit veto of your proposal:** "no, don't do that", "we're not going to X", "stop doing Y"
3. **Option-pick with stated reason:** user picks A over B and gives a reason (the reason is the decision)
4. **Deferral with scope:** "defer X until Y", "not in this session", "revisit after Z"
5. **Constraint naming:** "no users yet so breaking changes are fine", "solo dev so skip the migration path"
6. **Scope cut:** "drop that feature", "we're not building X", "X is someone else's problem"

**Skip these (not rule-shaped):**

- Chit-chat, exploratory thinking, brainstorming
- Questions the user asks YOU without a stated position
- Answers about implementation details that'll change in a week
- Opinions about code style unless they're a hard rule

## How to offer

The whole thing is ONE message. Not a conversation. Not an explanation.

```
This sounds rule-shaped: "<one-line paraphrase of the decision>"
Log to docs/DECISIONS.md? (y/n)
```

That's it. If user says **y**:
- Invoke the `log-decision` skill with the paraphrased rule + the reason they gave
- Don't re-ask for context — use what's already in conversation

If user says **n**:
- Drop it. Move on. Don't re-prompt on the same decision.

If user says something else (elaborates, changes mind, etc.):
- Treat as "n". Don't push.

## Rules of engagement

**One prompt per decision moment.** If the user declines, don't offer again for the same decision. If they make 3 decisions in one message, that's 3 prompts — but only once each.

**Don't batch.** If 4 decisions happen across a 10-message stretch, offer them as they happen, not as a summary at the end. Batching loses the "right now" framing.

**Paraphrase tightly.** Target: under 15 words. Match the user's phrasing when possible — if they said "no users yet so breaking changes OK," use those words.

**Include the WHY when it was given.** "Defer Vitest — manual smoke is enough pre-release" is better than just "Defer Vitest."

**Don't re-debate.** If the user makes a decision you think is wrong, the decision-prompt is not the place to argue. Log first, argue separately if at all.

**Don't prompt for your own observations.** Only user rulings get logged. If you noticed something and want to save it, that's memory territory, not DECISIONS.md.

## Examples

**Good — log this:**

> User: "No users yet, so breaking changes are fine. Skip migration paths."
>
> You: "This sounds rule-shaped: *'No users yet — breaking changes OK, no migration paths.'* Log to docs/DECISIONS.md? (y/n)"

**Good — log this:**

> User: "Don't propose Electron again. We're Tauri-only."
>
> You: "This sounds rule-shaped: *'Rust + Tauri stack is locked — don't propose Electron or alternatives.'* Log? (y/n)"

**Skip — not rule-shaped:**

> User: "Hmm, maybe we should check if that's still the case."
>
> You: (don't offer — exploratory, no ruling)

**Skip — ephemeral:**

> User: "Fix the typo on line 42 of chat.rs."
>
> You: (don't offer — task, not rule)

## What this skill does NOT do

- Does not write to DECISIONS.md directly — that's `log-decision`'s job
- Does not modify any other file
- Does not re-read DECISIONS.md to check for duplicates (log-decision handles dedup)
- Does not scan past messages for missed decisions — forward-only

## Interaction with log-decision

- **decision-prompt** is proactive — you invoke it by watching conversation
- **log-decision** is reactive — user or decision-prompt invokes it to do the actual write

When decision-prompt gets a "y", it calls log-decision with the paraphrased rule and the reason. log-decision handles the file write + dedup + formatting.

## When NOT to prompt

- User is in the middle of a longer thought — wait until they pause
- Decision is about to be undone in the same message ("let's do X... actually no, Y")
- You're already mid-task on something else — finish, then offer
- Session has been pure implementation for 20+ turns with no judgment calls — you're in execution mode, not decision mode

## Memory over time

If the user consistently says "no, don't log that" to a particular pattern, stop offering on that pattern. Save a feedback memory noting the pattern they don't want logged. If they accept consistently on another pattern, you're calibrated right.
