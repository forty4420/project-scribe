---
name: decision-prompt
description: Proactive skill — detects DURABLE rule-shaped statements in conversation and surfaces a non-blocking reminder to log them to DECISIONS.md. Filters out spec-internal decisions, ephemeral preferences, and implementation details. Uses sticky reminder pattern so the flag survives into the next turn if user doesn't respond immediately. Complement to log-decision skill (the reactive writer).
---

# decision-prompt — catch durable rules without interrupting flow

**The problem this solves:** `docs/DECISIONS.md` only grows when users remember to say "log this." Durable rulings die in chat. Three months later the same decision gets re-debated.

**The fix:** agent watches for rule-shaped moments in real time, surfaces a non-blocking flag at the top of the response, and re-surfaces it in the next turn if the user didn't act. Max two reminders, then drop.

## The durability filter — WHAT counts as a rule

**DECISIONS.md is for things you'd want to know about in 6 months.** Not every choice. Only surface a flag when the statement passes ALL of these tests:

1. **Holds across future specs/features** — architectural commitment, not this-feature-only
2. **Has a named trade-off or rejected alternative** — "X because Y (rejected Z because W)"
3. **Could be re-debated later** without this record — someone in 6 months won't know why

**Durable — surface a flag:**

- Architectural commitments: "all tools are MCP servers", "Rust + Tauri locked", "no cloud relay ever"
- Rejected alternatives with reasons: "in-process plugins considered + rejected because process isolation matters"
- Trade-offs with named cost/benefit: "IPC overhead accepted because human-speed calls"
- Scope/user rules: "no users yet, break freely", "solo-dev pre-release"
- Technical constants that'll outlive this spec: "UI always debounces at 150ms"

**Not durable — SKIP, don't surface:**

- Implementation details inside a spec ("MCP client uses `rmcp` crate") — spec handles this
- Option-picks internal to the current design ("single generic `mcp_call` vs per-tool commands") — spec documents
- Task-level picks ("we'll write file_mcp first") — ephemeral
- Preferences about communication style, tone, formatting — memory territory, not DECISIONS
- Code style opinions unless locked project-wide
- Anything the user will revisit next session anyway

**The "if in doubt → skip" principle.** Better to miss a flag than pollute DECISIONS.md with spec-internal noise. Missing rules can always be logged retroactively when someone says "wait, that's a rule — log it." Bad rules are harder to remove than missing rules are to add.

**User override always wins.** If the user says "log it" / "save that rule" / "that's a rule" about something you didn't flag, log it without argument. Their judgment overrides this filter.

## The sticky reminder pattern — WHEN to prompt

Blocking prompts mid-brainstorm break flow. The user is answering a real question; a rule-log question on top makes them choose what to address. Instead:

**Turn 1 (detect):** surface a non-blocking flag at the TOP of the response, then continue with the real work below.

```
**[?] Possible rule:** *"<one-line paraphrase>"* — say "log it" to save.

<... rest of response: answer their question, ask next question, etc. ...>
```

**Turn 2 (re-surface if no action):** if the user's next message didn't mention logging, re-surface at the top.

```
**[?] Still pending:** log *"<paraphrase>"*? (y/n/skip)

<... rest of response ...>
```

**Turn 3 (drop):** if still no action, stop mentioning. If the user wanted it, they'd have said so.

**Bounded — max 2 reminders, then permanent drop.** Never nag past that for the same rule.

## How to respond to action

**User says "log it" / "y" / "save that rule":**
- Invoke `log-decision` skill with the paraphrased rule + the reason (extract from conversation)
- Confirm inline: `Logged: <title>`
- Don't block the real work — do this alongside whatever else they asked

**User says "n" / "skip" / "no":**
- Drop it permanently. Don't re-offer this rule in later turns.

**User says something else (elaborates, changes mind, ignores):**
- Ignore = re-surface next turn (one more time, per sticky pattern)
- Elaborates the rule = update the paraphrase, re-surface with new wording
- Changes mind = treat as "skip"

## Rules of engagement

**Paraphrase tightly.** Target: under 20 words. Match user's phrasing when possible. Include the WHY when given.

**One flag per decision.** If user makes 3 durable rules in one message, 3 flags at top — stacked, each one-liner.

**Don't re-debate.** decision-prompt is not the place to argue whether the user is right. Log first, argue separately if at all.

**Don't prompt for your own observations.** Only user rulings get considered. If you noticed something worth saving, that's memory territory.

**Non-blocking means non-blocking.** Never put the flag in a position that forces the user to address it before the real work. Top of response, tagged with `[?]`, done. Real work below.

## Examples

**Durable — surface a flag:**

> User: "Tauri only. No Electron ever."
>
> You:
> ```
> **[?] Possible rule:** *"Rust + Tauri locked; never propose Electron or alternatives."* Say "log it" to save.
>
> Got it. Continuing with the Tauri-based approach. Next question...
> ```

**Not durable — skip:**

> User: "Use the `rmcp` crate for the MCP client."
>
> You: (don't flag — implementation detail, belongs in spec, not DECISIONS.md)

**Not durable — skip:**

> User: "Let's go with option A for now."
>
> You: (don't flag — option-pick internal to current design, no stated reason, no architectural commitment)

**Sticky re-surface:**

> Turn 1 — User: "No users yet so breaking changes OK."
> You (turn 1): surface flag at top, continue work.
> Turn 2 — User responds to your question but ignores the flag.
> You (turn 2): re-surface flag with `[?] Still pending`, continue work.
> Turn 3 — User still doesn't address.
> You (turn 3): drop it silently. No more mentions.

## What this skill does NOT do

- Does not write to DECISIONS.md directly — that's `log-decision`'s job
- Does not modify any other file
- Does not re-read DECISIONS.md to check for duplicates (log-decision handles dedup)
- Does not scan past messages for missed decisions — forward-only
- Does not nag past the 2-reminder limit

## Interaction with log-decision

- **decision-prompt** is proactive — you invoke it by watching conversation
- **log-decision** is reactive — user or decision-prompt invokes it to do the actual write

When decision-prompt gets a log confirmation, it calls log-decision with the paraphrased rule and the reason. log-decision handles the file write + dedup + formatting.

## Memory over time

Calibrate against the project. If the user consistently says "skip" to a particular pattern, stop flagging on that pattern. Save a feedback memory noting the skip pattern. If they accept consistently on another pattern, the filter is calibrated right.
