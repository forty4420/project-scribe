# Scout Video — claude code handoff session

Sources: 12 videos analyzed.

## Top GitHub Repos

- **[https://github.com/EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin)** (1x) — Plugin for enhancing Claude Code with engineering workflows
  - Sources: [Dan Vega](https://youtu.be/NAWKFRaR0Sk)
- **[https://github.com/anthropics/claude-quickstarts](https://github.com/anthropics/claude-quickstarts)** (1x) — Anthropic's open-source harness for long-running coding agents
  - Sources: [Cole Medin](https://youtu.be/usQ2HBTTWxs)
- **[https://github.com/chongdashu/cc-statusline](https://github.com/chongdashu/cc-statusline)** (1x) — User's custom statusline configuration
  - Sources: [Chong-U — AI Oriented Dev](https://youtu.be/mywRejDDgUg)
- **[https://github.com/coleam00/context-engineering-intro](https://github.com/coleam00/context-engineering-intro)** (1x) — Agent team skill resource for customizing Claude Code agent teams
  - Sources: [Cole Medin](https://youtu.be/-1K_ZWDKpU0)
- **[https://github.com/glittercowboy/get-shit-done](https://github.com/glittercowboy/get-shit-done)** (1x) — Community project for autonomous agent workflows
  - Sources: [Dan Vega](https://youtu.be/NAWKFRaR0Sk)
- **[https://github.com/steveyegge/beads](https://github.com/steveyegge/beads)** (1x) — Workflow automation framework for AI agents
  - Sources: [Dan Vega](https://youtu.be/NAWKFRaR0Sk)

## Tools / Skills / Plugins Mentioned

- **Claude Code** `service` (3x) — AI coding assistant used in the harness
- **/context** `command` (2x) — Visualizes context window usage and token allocation
- **CLAUDE.md** `file` (2x) — Repository-level instructions that bloat context if not optimized
- **/compact** `command` (1x) — Manually compacts context with custom instructions for prioritization
- **/init** `cli` (1x) — Generates CLAUDE.md by analyzing repository structure and key files
- **/plugins** `command` (1x) — Access Claude plugins store
- **/rename** `command` (1x) — Rename sessions for organization
- **/stats** `command` (1x) — View token usage and session statistics
- **@ references** `feature` (1x) — Enables selective context loading of specific files/directories
- **Anthropic Harness** `library` (1x) — Framework for coordinating long-running coding agents
- **Antigravity** `service` (1x) — AI coding agent that implements design outputs
- **Ask Tool** `plugin` (1x) — Allows users to ask questions and interact with Claude Code sessions from the mobile app
- **Beads** `service` (1x) — Workflow automation framework for AI agents
- **CLI (Command Line Interface)** `tool` (1x) — Reduces token usage by only loading when called
- **Claude Agent SDK** `library` (1x) — Programmatic interface for interacting with Claude Code
- **Claude CLI** `cli` (1x) — Command-line tool for setting up Claude API credentials
- **Claude Chat** `service` (1x) — Translates technical requirements into design language for Claude Design
- **Claude Code Remote Control** `service` (1x) — Officially enables controlling a Claude Code session on a laptop from a mobile device
- **Claude Code Tasks** `service` (1x) — Automated task execution for AI development workflows
- **Claude Code Web** `service` (1x) — Web-based coding environment with GitHub/Vercel integration
- **Claude Code iOS** `service` (1x) — Mobile coding environment synced with web version
- **Claude Design** `service` (1x) — AI design tool for generating website layouts and design systems
- **Context Audit skill** `skill` (1x) — Analyzes and optimizes Claude Code setup to reduce context bloat
- **Cursor** `cli` (1x) — IDE for running Claude Code workflows
- **Double escape (esc esc)** `workflow` (1x) — Rewind conversation to previous messages
- **GSD** `service` (1x) — Community project for autonomous agent workflows
- **MCP server** `service` (1x) — Loads tool definitions into context, increasing token usage
- **Ralph** `service` (1x) — Workflow automation tool for AI agents
- **T-Mux** `cli` (1x) — Terminal multiplexer for split-pane multi-agent collaboration
- **claude —dangerously-skip-permissions** `cli` (1x) — Enable YOLO mode (skip permissions)

## Key Techniques

- (1x) Creating PRDs (Product Requirements Documents) for task planning
- (1x) Using task dependencies with blocked/blocked-by relationships
- (1x) Implementing sub-agents for context window management
- (1x) Upfront planning to improve AI agent output quality
- (1x) Capturing learnings in Claude MD and skills files for workflow refinement
- (1x) Test-driven development for AI coding agents
- (1x) Feature list JSON with 200+ test cases
- (1x) Git-based version control integration
- (1x) Context window priming between agent sessions
- (1x) Regression testing between features
- (1x) Create a self-background markdown file for context
- (1x) Use /init to generate Claude Code configuration
- (1x) Run slash commands to spawn sub-agents for automation
- (1x) Track metrics in weekly check-ins
- (1x) Automate journaling with daily check-ins
- (1x) Use competitor analysis for content research
- (1x) Analyze brain dumps/notes with mind map visualization
- (1x) Disconnect unused MCP servers to reduce context bloat
- (1x) Replace MCP servers with CLIs for 40% token savings
- (1x) Optimize Claude.md by removing contradictions and using progressive disclosure

## Install Commands Spotted

```
claude setup --token
```
```
Create a markdown file named 'background on yourself' in a Claude Code folder
```
```
/init in Claude Code to generate config
```
```
Run /weekly check-in, /daily check-in, /newsletter researcher, /brain dump analysis commands
```
```
Install T-Mux
```
```
Install iTerm 2
```
```
/remote-control
```
```
claude —resume
```
```
/context
```
```
/stats
```
```
/rename "your name"
```
```
claude —dangerously-skip-permissions
```
```
/plugins
```

## Source Videos

- **[Claude Code Tasks: Stop Babysitting Your AI Agent](https://youtu.be/NAWKFRaR0Sk)** _signal 9/10_
  - Channel: Dan Vega · 20260206
  - Claude Code Tasks enable autonomous AI agent execution of development plans by splitting projects into prioritized tasks, reducing manual oversight and context window limitations.
- **[Master Context in Claude Code in 5 Minutes](https://youtu.be/I1EGbrH5Xdk)** _signal 9/10_
  - Channel: GritAI Studio · 20260205
  - The video explains context engineering in Claude Code, emphasizing techniques to maintain focus and avoid hallucinations by managing context window usage effectively.
- **[Claude Code's Agent Teams Are Insane - Multiple AI Agents Coding Together in Real Time](https://youtu.be/-1K_ZWDKpU0)** _signal 9/10_
  - Channel: Cole Medin · 20260209
  - Claude Code's Agent Teams enable multiple AI agents to collaborate in real-time on coding tasks, offering a more integrated and communicative approach compared to isolated subagents.
- **[How to Use CLAUDE.md in Claude Code in 5 Minutes](https://youtu.be/h7QJL2_gEXA)** _signal 9/10_
  - Channel: GritAI Studio · 20260125
  - CLAUDE.md provides persistent memory for Claude Code, enabling it to understand project architecture, coding standards, and past debugging lessons. The video explains how to set it up and use it effectively.
- **[I Forced Claude to Code for 24 Hours NONSTOP, Here's What Happened](https://youtu.be/usQ2HBTTWxs)** _signal 8/10_
  - Channel: Cole Medin · 20251204
  - The video explores Anthropic's open-source harness for long-running AI coding agents, testing Claude Code's ability to build a functional application (claw.ai clone) over 24 hours using test-driven development and context-window management.
- **[How I use Claude Code to automate my entire life (5 tricks)](https://youtu.be/wfiv67NixCY)** _signal 8/10_
  - Channel: Alex Finn · 20250730
  - The video demonstrates how to use Claude Code for non-coding automation tasks like weekly check-ins, daily journaling, content research, and note analysis by setting up a custom AI agent system.
- **[I Stopped Hitting Claude Code Usage Limits (Here's How)](https://youtu.be/9ToOfgZ4qqQ)** _signal 8/10_
  - Channel: Brad | AI & Automation · 20260410
  - The video explains how to reduce Claude Code usage limits by eliminating context bloat through techniques like disconnecting unused MCP servers, replacing them with CLIs, optimizing Claude.md files, and using a free Context Audit skill to identify inefficiencies.
- **[Ship from Anywhere: Claude Code Web + iOS Mobile (and a Secret Command!)](https://youtu.be/mywRejDDgUg)** _signal 8/10_
  - Channel: Chong-U — AI Oriented Dev · 20251023
  - The video demonstrates Anthropic's Claude Code Web and iOS app for remote coding with GitHub/Vercel integration, showcasing live sync, bug fixes, PR creation, and a secret '--teleport' command.
- **[Claude Code on your Phone is OFFICIAL (it changes  everything)](https://youtu.be/ocQ7ZKhHU5Q)** _signal 8/10_
  - Channel: NetworkChuck · 20260226
  - Anthropic's official Remote Control feature for Claude Code allows users to start and control coding sessions on their laptop from their phone, solving the problem the creator previously hacked together with a DIY solution.
- **[Claude Code Worktrees in 7 Minutes](https://youtu.be/z_VI51k-tn0)** _signal 8/10_
  - Channel: Developers Digest · 20260221
  - Anthropic's Git worktrees in Claude Code enable parallel branch editing via isolated CLI sessions and subagents, allowing developers to make simultaneous changes without conflicts.
- **[Claude Design: Code-Driven vs Blind Handoff — Which Approach Wins?](https://youtu.be/jbU8IVJJt7I)** _signal 8/10_
  - Channel: Use AI with Tech Dad · 20260428
  - The video compares two approaches to using Claude Design: code-driven (which causes bias and high token usage) vs. the Blind Handoff method (using Claude Chat as an interpreter for non-designers). The Blind Handoff yields better results with 57% lower token consumption.
- **[Claude Code just had a MAJOR update. Here's how to use it.](https://youtu.be/Cb49pGTSigI)** _signal 8/10_
  - Channel: Alex Finn · 20251222
  - The video highlights 10 major updates to Claude Code, including session resuming, context management, Ultra Think mode, and custom memories, aimed at improving developer workflow and efficiency.
