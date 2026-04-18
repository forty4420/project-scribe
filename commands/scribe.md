---
description: Dashboard readout from docs/STATE.md — current focus, last shipped, next up.
---

Read `docs/STATE.md` from the current project root.

Extract and display these three sections, verbatim, nothing else:

1. Current focus
2. Last shipped
3. Next up

Format as a compact block. No prose commentary. No suggestions. Just the data.

If `docs/STATE.md` doesn't exist, respond: `Project-scribe not initialized. Run init-project-scribe to enable.`

If the file exists but any of the three sections is missing, report: `STATE.md is incomplete — run update-project-state to rebuild.`
