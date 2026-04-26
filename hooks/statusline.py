#!/usr/bin/env python3
"""project-scribe statusline.

Reads Claude Code statusline JSON from stdin, extracts current context
percentage and session cost, writes the percentage to a sidecar file
(~/.claude/.scribe-context) for the userprompt-context-warn hook to read,
and prints a colored bar + cost to stdout for terminal users.

Replaces the previous jq-based shell statusline so the plugin works on
machines without jq installed (Python 3 is already required by Claude
Code itself).

Output format (matches the prior shell version exactly):
    CTX [████░░░░░░] 42% $0.13
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import time
from pathlib import Path


CTX_FILE = Path.home() / ".claude" / ".scribe-context"


def write_context_file(pct: int) -> None:
    """Atomically write '<pct>\\n<unix-ts>\\n' to CTX_FILE.

    Best-effort: any IO error is swallowed so a sidecar failure never
    breaks the visible statusline.
    """
    try:
        CTX_FILE.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_path = tempfile.mkstemp(
            prefix=".scribe-context.", dir=str(CTX_FILE.parent)
        )
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(f"{pct}\n{int(time.time())}\n")
        os.replace(tmp_path, CTX_FILE)
    except OSError:
        pass


def render_bar(pct: int) -> str:
    """10-cell bar matching prior shell version. pct is 0-100."""
    pct = max(0, min(100, pct))
    filled = pct // 10
    return "█" * filled + "░" * (10 - filled)


def color_for(pct: int) -> str:
    """ANSI color matching prior shell thresholds."""
    if pct >= 80:
        return "\x1b[0;31m"
    if pct >= 50:
        return "\x1b[0;33m"
    return "\x1b[0;32m"


def format_cost(raw) -> str:
    try:
        v = float(raw)
    except (TypeError, ValueError):
        return "$0.00"
    return f"${v:.2f}"


def main() -> int:
    # Force utf-8 output. Windows defaults stdout to cp1252 which can't
    # encode the bar glyphs (U+2588, U+2591) or ANSI escape sequences
    # cleanly. reconfigure() is Python 3.7+.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass

    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    cw = payload.get("context_window") or {}
    used = cw.get("used_percentage")
    if used is None:
        return 0

    try:
        pct = int(round(float(used)))
    except (TypeError, ValueError):
        return 0

    write_context_file(pct)

    bar = render_bar(pct)
    color = color_for(pct)
    cost = format_cost((payload.get("cost") or {}).get("total_cost_usd", 0))

    reset = "\x1b[0m"
    cyan = "\x1b[36m"
    sys.stdout.write(f"{color}CTX [{bar}] {pct}%{reset} {cyan}{cost}{reset}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
