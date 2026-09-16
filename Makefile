# Makefile for Kanban plugin

.PHONY: test test-standalone test-unit test-integration test-e2e test-file \
	test-container container-build ci-local ci-local-list test-shuffle \
	clean check-deps help

# Container engine used by the test-container targets. Podman is preferred;
# set CONTAINER_ENGINE=docker to override.
CONTAINER_ENGINE ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null)

# Socket act should talk to. Podman exposes a Docker-compatible API on the
# machine's socket; an existing DOCKER_HOST always wins.
ACT_DOCKER_HOST = $(shell \
	if [ -n "$$DOCKER_HOST" ]; then echo "$$DOCKER_HOST"; \
	elif command -v podman >/dev/null 2>&1; then \
		sock=$$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null | tail -1); \
		[ -n "$$sock" ] && echo "unix://$$sock"; \
	fi)

# Lua version baked into the test image: 5.1, 5.3, 5.4 or jit.
LUA_VERSION ?= 5.4
CONTAINER_IMAGE ?= kanban-md-engine-test:$(LUA_VERSION)

# Default target: run all tests (standalone)
all: test

# Run all tests (standalone Lua)
test: test-standalone

# Run core tests with standalone Lua (fast)
test-standalone:
	@echo "Running standalone Lua tests (busted)..."
	@busted

# Run the suite in a random order to surface order dependencies between specs.
# SEED=<n> reproduces a particular ordering.
test-shuffle:
	@seed=$${SEED:-$$(date +%s)}; \
	echo "Running with --shuffle --seed=$$seed"; \
	busted --shuffle --seed="$$seed"

# Run only unit tests
test-unit:
	@echo "Running unit tests..."
	@busted tests/unit

# Run only integration tests
test-integration:
	@echo "Running integration tests..."
	@busted tests/integration

# Run only E2E tests
test-e2e:
	@echo "Running E2E tests..."
	@busted tests/e2e

# Build the Alpine test image
container-build:
	@if [ -z "$(CONTAINER_ENGINE)" ]; then \
		echo "Error: neither podman nor docker found on PATH"; \
		exit 1; \
	fi
	@echo "Building $(CONTAINER_IMAGE) with $(CONTAINER_ENGINE) (Lua $(LUA_VERSION))..."
	@$(CONTAINER_ENGINE) build \
		-f docker/Dockerfile.alpine \
		--build-arg LUA_VERSION=$(LUA_VERSION) \
		-t $(CONTAINER_IMAGE) .

# Run the full suite inside the Alpine test image
test-container: container-build
	@echo "Running tests in $(CONTAINER_IMAGE)..."
	@$(CONTAINER_ENGINE) run --rm $(CONTAINER_IMAGE)

# Run the GitHub Actions workflows locally with act.
# Under Podman, act talks to the machine's API socket; DOCKER_HOST is derived
# automatically unless it is already set.
ci-local:
	@if ! command -v act >/dev/null 2>&1; then \
		echo "Error: act not found on PATH (see https://github.com/nektos/act)"; \
		exit 1; \
	fi
	@echo "Running workflows with act..."
	@DOCKER_HOST="$(ACT_DOCKER_HOST)" act $(ACT_ARGS)

# List the jobs act can see, without running them
ci-local-list:
	@DOCKER_HOST="$(ACT_DOCKER_HOST)" act --list

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

# Clean up any test artifacts
clean:
	@echo "Cleaning up test artifacts..."
	@rm -f *.tmp test_*.md
	@rm -rf /tmp/lua_*

# Help
help:
	@echo "Available targets:"
	@echo "  test              - Run all tests (equivalent to standalone)"
	@echo "  test-standalone   - Run standalone Lua tests only (fast)"
	@echo "  test-unit         - Run unit tests only"
	@echo "  test-integration  - Run integration tests only"
	@echo "  test-e2e          - Run E2E tests only"
	@echo "  test-shuffle      - Run all tests in a random order (SEED=<n> to repeat one)"
	@echo "  test-file FILE=<path> - Run a specific test file"
	@echo "  container-build   - Build the Alpine test image (LUA_VERSION=5.1|5.3|5.4|jit)"
	@echo "  test-container    - Run the full suite inside the Alpine test image"
	@echo "  ci-local          - Run the GitHub Actions workflows locally with act"
	@echo "  ci-local-list     - List the jobs act can see"
	@echo "  ci-local          - Run the GitHub Actions workflows locally with act"
	@echo "  ci-local-list     - List the jobs act can see"
	@echo "  check-deps        - Check if required dependencies are installed"
	@echo "  clean             - Clean up test artifacts"
	@echo "  help              - Show this help"
