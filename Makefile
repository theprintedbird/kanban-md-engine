# Makefile for Kanban plugin

.PHONY: test test-standalone test-neovim test-unit test-integration test-e2e test-file clean check-deps help

# Default target: run all tests (standalone + Neovim)
all: test

# Run all tests (standalone Lua + Neovim headless)
test: test-standalone test-neovim

# Run core tests with standalone Lua (fast)
test-standalone:
	@echo "Running standalone Lua tests (busted)..."
	@busted

# Run only unit tests
test-unit:
	@echo "Running unit tests..."
	@busted tests/unit --exclude-tags=neovim-only

# Run only integration tests
test-integration:
	@echo "Running integration tests..."
	@busted tests/integration --exclude-tags=neovim-only

# Run only E2E tests
test-e2e:
	@echo "Running E2E tests..."
	@busted tests/e2e

# Run a specific test file
# Usage: make test-file FILE=tests/unit/parser_content_blocks_spec.lua
test-file:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make test-file FILE=<path_to_test_file>"; \
		echo "Examples:"; \
		echo "  make test-file FILE=tests/unit/parser_content_blocks_spec.lua"; \
		echo "  make test-file FILE=tests/integration/board_spec.lua"; \
		echo "  make test-file FILE=tests/e2e/realistic_scenarios_spec.lua"; \
		exit 1; \
	fi
	@if [ -f "$(FILE)" ]; then \
		echo "Running test file: $(FILE)"; \
		busted "$(FILE)"; \
	else \
		echo "Error: Test file not found: $(FILE)"; \
		exit 1; \
	fi

# Validate that dependencies are installed
check-deps:
	@echo "Checking dependencies..."
	@echo -n "Checking busted... "; \
	if command -v busted >/dev/null 2>&1; then \
		echo "✓ found"; \
	else \
		echo "✗ not found"; \
		echo "Install with: luarocks install busted"; \
		exit 1; \
	fi
	@echo -n "Checking Neovim... "; \
	if command -v nvim >/dev/null 2>&1; then \
		echo "✓ found"; \
	else \
		echo "✗ not found"; \
		echo "Install Neovim for Neovim-specific tests"; \
	fi
	@echo -n "Checking plenary.nvim... "; \
	if [ -d "$$HOME/Library/Caches/kanban-md/plenary.nvim" ]; then \
		echo "✓ found"; \
	else \
		echo "✗ not found (will be auto-installed when running Neovim tests)"; \
	fi

# Clean up any test artifacts
clean:
	@echo "Cleaning up test artifacts..."
	@rm -f *.tmp test_*.md
	@rm -rf /tmp/lua_*

# Help
help:
	@echo "Available targets:"
	@echo "  test              - Run all tests (standalone + Neovim)"
	@echo "  test-standalone   - Run standalone Lua tests only (fast)"
	@echo "  test-unit         - Run unit tests only"
	@echo "  test-integration  - Run integration tests only"
	@echo "  test-e2e          - Run E2E tests only"
	@echo "  test-file FILE=<path> - Run a specific test file"
	@echo "  check-deps        - Check if required dependencies are installed"
	@echo "  clean             - Clean up test artifacts"
	@echo "  help              - Show this help"
