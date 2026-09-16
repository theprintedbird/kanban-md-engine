#!/usr/bin/env bash
# Test script to run the CLI example via a standalone Lua interpreter.
# This demonstrates that the core engine works with the CLI adapter.

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

# Run the CLI example through standalone Lua
"$LUA_EXECUTABLE" "$SCRIPT_DIR/cli_example.lua" 2>&1

echo ""
echo "Test completed!"
