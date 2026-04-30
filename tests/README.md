# scribe tests

bats-core based test harness for project-scribe hooks + high-leverage skills.

## Setup

```bash
git submodule update --init --recursive
```

## Run all tests

```bash
bash tests/run.sh
```

## Run a single file

```bash
bash tests/run.sh tests/hooks/session-start.bats
```

## Layout

- `tests/_libs/` — vendored bats-core + helpers (git submodules)
- `tests/_helpers/` — sandbox, fixtures, env mocks
- `tests/hooks/` — hook script tests (one .bats per hook)
- `tests/skills/` — skill contract tests (markdown skills tested via their declared side effects)
- `tests/integration/` — multi-hook end-to-end flows

## Adding tests for a new skill

1. Read the skill's SKILL.md — find what files/state it modifies
2. Create `tests/skills/<skill-name>.bats`
3. Use `sandbox::create` + `fixtures::seed_*` in setup
4. Assert on the *contract* (what files exist, what content), not the AI's exact wording

## Platform support

- Linux + macOS: native
- Windows: run via Git Bash or WSL. CI runs on Ubuntu only.
