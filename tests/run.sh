#!/usr/bin/env bash
# Local test runner. Wraps bats-core with project-aware paths.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BATS="$PROJECT_ROOT/tests/_libs/bats-core/bin/bats"

if [ ! -x "$BATS" ]; then
  echo "bats not found at $BATS — run: git submodule update --init --recursive" >&2
  exit 2
fi

cd "$PROJECT_ROOT"

# Run all .bats files under tests/ unless specific path given
if [ $# -gt 0 ]; then
  exec "$BATS" "$@"
else
  exec "$BATS" --recursive tests/hooks tests/skills tests/integration tests/scripts
fi
