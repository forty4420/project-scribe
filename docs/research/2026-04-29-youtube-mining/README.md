# YouTube Mining Run — 2026-04-29

Research artifacts that drove the v0.7.2+ upgrade backlog.

## How this was produced

Ran the scout-video pipeline (yt-dlp → Groq qwen3-32b → local rank → Claude synthesis) at `C:/Users/forty/Downloads/scout/`. Two topic searches:

| Topic | Videos analyzed | Signal range |
|-------|----------------|--------------|
| `claude code plugin best practices` | 13 | 7-9/10 |
| `claude code handoff session` | 12 | 8-9/10 |

Total Groq token cost: 138k of 450k daily free-tier cap.
Total Claude synthesis cost: ~6k tokens (Max plan, trivial).
Total dollar cost: $0.

## Files in this directory

| File | What it is |
|------|------------|
| `synthesized-recommendations.md` | Primary synthesis: 8 upgrade ideas with rationale, anti-recommendations, source citations. Read this first. |
| `topic-1-plugin-best-practices.md` | Per-video leaderboard for topic 1 — top repos, tools, techniques, install commands, source video summaries with signal scores |
| `topic-2-handoff-session.md` | Same shape for topic 2 |
| `topic-1-aggregated.json` | Machine-readable rollup for topic 1 — every extracted repo URL, tool name, technique, command |
| `topic-2-aggregated.json` | Same for topic 2 |

## Why these are checked into the scribe repo

The original artifacts live at `C:/Users/forty/Downloads/scout/results/topics/` — outside this repo, on volatile path. Without an in-repo copy the research could vanish (laptop reformat, scout dir cleared, machine swap) and the upgrade plan loses its provenance.

Anyone reading the v0.7.2 test-harness plan or any subsequent backlog item should be able to trace the recommendation back to the actual videos that surfaced it.

## Refreshing the research

To re-run with new topics:

```bash
cd C:/Users/forty/Downloads/scout
bash scripts/video/run_pipeline.sh "<your topic>" 15
# Output lands in results/topics/<slug>.{fetched,extracted,aggregated,leaderboard}.{json,md}
```

Then synthesize in a fresh Claude Code session reading the aggregated.json files, and copy artifacts into a new dated subdirectory here: `docs/research/<YYYY-MM-DD>-<run-name>/`.

## Backlog tracking

The 14-item backlog derived from this run is appended to [`docs/superpowers/plans/2026-04-30-bash-test-harness.md`](../../superpowers/plans/2026-04-30-bash-test-harness.md). When an item gets picked up, give it its own plan file under `docs/superpowers/plans/` and link back here in its "Research source" section.
