#!/usr/bin/env zsh

# run_tests.sh - Run Kanban plugin tests using Neovim and Plenary

# Get the directory of this script
SCRIPT_DIR="${0:A:h}"

# Set XDG_CACHE_HOME if not set
if [ -z "$XDG_CACHE_HOME" ]; then
	XDG_CACHE_HOME="$HOME/Library/Caches"
fi

PLENARY_PATH="$XDG_CACHE_HOME/kanban-md/plenary.nvim"

echo "Running Kanban plugin tests..."
echo "Project directory: $SCRIPT_DIR"/..
echo "Plenary path: $PLENARY_PATH"

# Install plenary if not available
if [ ! -d "$PLENARY_PATH" ]; then
	echo "Installing plenary.nvim to $PLENARY_PATH..."
	mkdir -p "$(dirname "$PLENARY_PATH")"
	git clone https://github.com/nvim-lua/plenary.nvim "$PLENARY_PATH"
fi

# Check if plenary is available
if ! nvim --headless --cmd "set rtp+=$PLENARY_PATH" -c "lua require('plenary')" -c "quit" 2>/dev/null; then
	echo "ERROR: plenary.nvim is not working properly"
	echo "Path: $PLENARY_PATH"
	exit 1
fi

# Run the tests using Neovim headless mode
nvim --headless --cmd "set rtp+=$PLENARY_PATH,\"$SCRIPT_DIR\"" -c "lua require('tests.run_tests')" -c "quit"

echo "Tests completed!"
