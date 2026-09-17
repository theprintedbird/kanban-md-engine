#!/usr/bin/env bash
# Smoke test: run the CLI example via a standalone Lua interpreter.
# This demonstrates that the core engine works with the CLI adapter, and is run
# in CI as the only thing exercising examples/cli_example.lua.
#
# The example writes the modified board to KANBAN_EXAMPLE_OUTPUT, which is
# pointed at a temporary directory here and removed on exit, so a run never
# leaves the working tree dirty.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  echo "Usage: $0 [interpreter]"
  echo "  interpreter - Lua interpreter to use (default: \$LUA, or the first"
  echo "                of lua, lua5.4, lua5.3, lua5.1, luajit found on PATH)"
}

# Resolve the interpreter: an explicit argument wins, then $LUA, then PATH.
LUA_EXECUTABLE="${1:-${LUA:-}}"

if [ -z "$LUA_EXECUTABLE" ]; then
  for candidate in lua lua5.4 lua5.3 lua5.1 luajit; do
    if command -v "$candidate" >/dev/null 2>&1; then
      LUA_EXECUTABLE="$candidate"
      break
    fi
  done
fi

if [ -z "$LUA_EXECUTABLE" ] || ! command -v "$LUA_EXECUTABLE" >/dev/null 2>&1; then
  echo "Error: no Lua interpreter found." >&2
  echo "Install Lua, or set LUA to the interpreter you want to use." >&2
  usage >&2
  exit 1
fi

cd "$PROJECT_ROOT"

echo "Testing CLI adapter with standalone Lua..."
echo "Interpreter: $(command -v "$LUA_EXECUTABLE")"
echo ""

# Set up Lua package path to find the plugin modules
export LUA_PATH="$PROJECT_ROOT/lua/?.lua;$PROJECT_ROOT/lua/?/init.lua;;"

# Everything the run produces goes in here, and goes away with it.
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kanban-md-example.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

export KANBAN_EXAMPLE_OUTPUT="$TEMP_DIR/sample_board_modified.md"

# A developer may have run the example by hand before now; only a file that
# appears during this run says the override was ignored.
TRACKED_OUTPUT_EXISTED=no
if [ -e "$SCRIPT_DIR/sample_board_modified.md" ]; then
  TRACKED_OUTPUT_EXISTED=yes
fi

# Run the CLI example through standalone Lua
"$LUA_EXECUTABLE" "$SCRIPT_DIR/cli_example.lua" 2>&1

# The example prints its way through every step, so an exception would already
# have failed the run; check the board it claims to have written really is one.
if [ ! -s "$KANBAN_EXAMPLE_OUTPUT" ]; then
  echo "Error: the example wrote no board to $KANBAN_EXAMPLE_OUTPUT" >&2
  exit 1
fi

if ! grep -q '^###### ' "$KANBAN_EXAMPLE_OUTPUT"; then
  echo "Error: $KANBAN_EXAMPLE_OUTPUT has no columns in it" >&2
  exit 1
fi

if [ "$TRACKED_OUTPUT_EXISTED" = "no" ] && [ -e "$SCRIPT_DIR/sample_board_modified.md" ]; then
  echo "Error: the example wrote into the working tree as well" >&2
  exit 1
fi

echo ""
echo "Test completed!"
