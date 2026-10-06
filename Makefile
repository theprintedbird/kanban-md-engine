# Makefile for Kanban plugin

.PHONY: test test-standalone test-unit test-integration test-e2e test-file \
	test-container container-build ci-local ci-local-list test-shuffle test-tap test-perf coverage lint lint-container lint-workflows \
	test-each-file smoke clean check-deps version help

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

# Run every spec file in its own busted process.
#
# `busted` and `make test-shuffle` both load the whole suite into one process,
# so a spec that only passes because an earlier file required something --
# tests/polyfills/vim, a config setup, a registered adapter -- still passes.
# Shuffling reorders the tests, not the loading. One process per file is the
# only check for that, and it reports every offender rather than stopping at
# the first.
test-each-file:
	@failed=""; total=0; \
	for spec in $$(find tests -name '*_spec.lua' | sort); do \
		total=$$((total + 1)); \
		if busted "$$spec" >/dev/null 2>&1; then \
			printf '.'; \
		else \
			printf 'F'; \
			failed="$$failed $$spec"; \
		fi; \
	done; \
	echo ""; \
	if [ -n "$$failed" ]; then \
		echo "Specs that fail in isolation:"; \
		for spec in $$failed; do \
			echo "  $$spec"; \
			busted "$$spec" 2>&1 | sed 's/^/    /'; \
		done; \
		exit 1; \
	fi; \
	echo "$$total spec files pass on their own."

# Run the suite with TAP output, for tooling that consumes test results.
# TAP_FILE=<path> also writes the output to a file.
test-tap:
	@TAP=1 tests/run_tests_standalone.sh

# Run the per-operation performance regression specs. Deliberately a
# separate target from `coverage`: luacov's per-line debug hook costs the
# calibration workload about 10x and board parsing about 40x, so timings
# taken under it are meaningless and the specs skip themselves. Note that
# `make test` runs them too -- this target is for measuring them alone.
# KANBAN_PERF_TOLERANCE=<n> widens every budget on a noisy machine.
test-perf:
	@echo "Running performance regression tests..."
	@busted tests/integration/performance_spec.lua

# Run the suite under luacov and print the summary. There is deliberately no
# threshold: the number is there to be looked at, not to fail the build.
coverage:
	@echo "Running tests with coverage..."
	@busted --coverage
	@luacov
	@sed -n '/^Summary/,$$p' luacov.report.out

# Lint with luacheck. A clean run is the baseline: .luacheckrc documents the
# warning families that are deliberately muted.
lint:
	@if ! command -v luacheck >/dev/null 2>&1; then \
		echo "Error: luacheck not found (luarocks install luacheck,"; \
		echo "       or run 'make lint-container' to use the Alpine image)"; \
		exit 1; \
	fi
	@luacheck lua scripts tests

# Lint inside the Alpine test image, which already carries luacheck. Useful
# when the host toolchain cannot build luacheck's C dependencies.
lint-container: container-build
	@$(CONTAINER_ENGINE) run --rm -v "$(CURDIR)":/src:ro -w /src $(CONTAINER_IMAGE) luacheck lua scripts tests

# Lint the GitHub Actions workflows: zizmor for security findings, actionlint
# for expression/type errors and (when shellcheck is on PATH) the run: blocks.
# Both run even if the first fails, so one pass reports everything. CI pins
# the versions in .github/workflows/ci.yml.
lint-workflows:
	@missing=""; \
	for tool in zizmor actionlint; do \
		command -v $$tool >/dev/null 2>&1 || missing="$$missing $$tool"; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "Error: not found on PATH:$$missing"; \
		echo "       (pipx install zizmor actionlint-py, or your package manager)"; \
		exit 1; \
	fi
	@command -v shellcheck >/dev/null 2>&1 || \
		echo "Note: shellcheck not found; actionlint will skip the run: blocks"
	@status=0; \
	zizmor --offline .github || status=1; \
	actionlint || status=1; \
	exit $$status

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

# Run examples/cli_example.lua end to end through a standalone interpreter.
# It is the only thing exercising the example, and the only test that proves
# the engine works from a bare `lua` with nothing but LUA_PATH set.
# LUA=<interpreter> picks one; the script falls back to whatever is on PATH.
smoke:
	@examples/test_cli.sh

# Set the engine version everywhere it is recorded.
# Usage: make version VERSION=0.2.0 [DRY_RUN=1]
version:
	@if [ -z "$(VERSION)" ]; then \
		echo "Usage: make version VERSION=<x.y.z> [DRY_RUN=1]"; \
		echo "Current version: $$(lua scripts/update-version.lua --current)"; \
		exit 1; \
	fi
	@lua scripts/update-version.lua "$(VERSION)" $(if $(DRY_RUN),--dry-run,)

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
#
# Everything removed here is either in the working tree or a per-run directory
# named kanban-md-tests-* by tests/helpers/tempfiles.lua or kanban-md-example.*
# by examples/test_cli.sh, both of which remove their own; the globs here are
# for a run that was killed before it could. There is deliberately no glob over anything the engine did
# not create: `rm -rf /tmp/lua_*` used to live here, and it would happily take
# another process's files with it.
clean:
	@echo "Cleaning up test artifacts..."
	@rm -f *.tmp test_*.md
	@rm -f luacov.stats.out luacov.report.out busted-tap*.txt
	@rm -rf $${TMPDIR:-/tmp}/kanban-md-tests-* /tmp/kanban-md-tests-*
	@rm -rf $${TMPDIR:-/tmp}/kanban-md-example.* /tmp/kanban-md-example.*

# Help
help:
	@echo "Available targets:"
	@echo "  test              - Run all tests (equivalent to standalone)"
	@echo "  test-standalone   - Run standalone Lua tests only (fast)"
	@echo "  test-unit         - Run unit tests only"
	@echo "  test-integration  - Run integration tests only"
	@echo "  test-e2e          - Run E2E tests only"
	@echo "  test-shuffle      - Run all tests in a random order (SEED=<n> to repeat one)"
	@echo "  test-each-file    - Run every spec file in its own process (catches load-order deps)"
	@echo "  test-tap          - Run all tests with TAP output (TAP_FILE=<path> to save)"
	@echo "  test-perf         - Run the performance regression specs only (no coverage)"
	@echo "  coverage          - Run tests under luacov and print the summary"
	@echo "  smoke             - Run the CLI example end to end (LUA=<interpreter>)"
	@echo "  lint              - Run luacheck"
	@echo "  lint-container    - Run luacheck inside the Alpine test image"
	@echo "  lint-workflows    - Lint the GitHub Actions workflows with zizmor and actionlint"
	@echo "  test-file FILE=<path> - Run a specific test file"
	@echo "  container-build   - Build the Alpine test image (LUA_VERSION=5.1|5.3|5.4|jit)"
	@echo "  test-container    - Run the full suite inside the Alpine test image"
	@echo "  ci-local          - Run the GitHub Actions workflows locally with act"
	@echo "  ci-local-list     - List the jobs act can see"
	@echo "  version VERSION=<x.y.z> - Set the version in every file that records it (DRY_RUN=1 to preview)"
	@echo "  check-deps        - Check if required dependencies are installed"
	@echo "  clean             - Clean up test artifacts"
	@echo "  help              - Show this help"
