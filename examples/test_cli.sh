#!/bin/bash
# Test script to run CLI example via standalone Lua or Neovim's Lua interpreter
# This demonstrates that the core engine works with the CLI adapter

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default to standalone Lua if available, otherwise use Neovim
MODE="${1:-auto}"
LUA_EXECUTABLE="/opt/local/bin/lua"

# Auto-detect mode
if [ "$MODE" = "auto" ]; then
  if [ -x "$LUA_EXECUTABLE" ]; then
    MODE="lua"
  else
    MODE="nvim"
  fi
fi

cd "$PROJECT_ROOT"

if [ "$MODE" = "lua" ]; then
  if [ ! -x "$LUA_EXECUTABLE" ]; then
    echo "Error: Standalone Lua not found at $LUA_EXECUTABLE"
    echo "Install via: sudo port install lua54"
    echo "Or run with: $0 nvim"
    exit 1
  fi

  echo "Testing CLI adapter with standalone Lua..."
  echo "Interpreter: $LUA_EXECUTABLE"
  echo ""

  # Set up Lua package path to find the plugin modules
  export LUA_PATH="$PROJECT_ROOT/lua/?.lua;$PROJECT_ROOT/lua/?/init.lua;;"

  # Run the CLI example through standalone Lua
  "$LUA_EXECUTABLE" "$SCRIPT_DIR/cli_example.lua" 2>&1

else
  echo "Error: Invalid mode '$MODE'"
  echo "Usage: $0 [auto|lua|nvim]"
  echo "  auto - Auto-detect (prefer standalone Lua)"
  echo "  lua  - Use standalone Lua at $LUA_PATH"
  echo "  nvim - Use Neovim headless mode"
  exit 1
fi

echo ""
echo "Test completed!"
