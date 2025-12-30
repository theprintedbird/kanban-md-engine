# Standalone Lua Test Runner Migration

## Overview

Migrate the test suite from Neovim headless mode with Plenary.nvim to standalone Lua with busted test framework. This will improve test execution speed, better isolate core functionality, and simplify CI/CD.

## Motivation

**Current State:**
- Tests run in Neovim headless mode using Plenary.nvim
- Neovim startup overhead slows test execution
- Core functionality tests coupled with Neovim runtime
- Requires full Neovim installation for CI/CD

**Target State:**
- Core tests run in standalone Lua (`/opt/local/bin/lua`)
- Neovim-specific tests (virtual text, cursor positioning) remain in headless mode
- Faster test iteration during development
- Clearer separation between core and platform-specific code
- Simplified CI/CD (standalone Lua only for most tests)

**Evidence This Works:**
- `examples/cli_example.lua` successfully runs entire core engine in standalone Lua
- CLI adapter (`lua/kanban-md/adapters/cli.lua`) provides platform abstraction
- Core utilities (`lua/kanban-md/utils/table.lua`) are pure Lua
- ~80% of tests already use only core APIs

## Architecture

### Test Framework: busted

**Why busted:**
- Nearly identical API to Plenary: `describe()`, `it()`, `before_each()`, `after_each()`
- Drop-in replacement for most test code
- Mature, widely-used Lua test framework
- Good CLI test runner with watch mode, filtering, and coverage
- Assertion library similar to Plenary's

**Installation:**

```
luarocks install busted
```

### Test Categories

**Standalone Lua Tests (busted):**
- All unit tests in `tests/unit/` except `virtual_text_spec.lua`
- Most integration tests in `tests/integration/` except `cursor_positioning_spec.lua` and `writer_neovim_adapter_spec.lua`
- All E2E tests in `tests/e2e/`
- Total: ~35 test files

**Neovim Headless Tests (Plenary):**
- `tests/unit/virtual_text_spec.lua` - Uses Neovim virtual text APIs
- `tests/integration/cursor_positioning_spec.lua` - Uses Neovim cursor APIs
- `tests/integration/writer_neovim_adapter_spec.lua` - Uses Neovim buffer APIs
- `tests/manual-tests/*` - Manual Neovim integration tests
- Total: ~3 test files

### Vim Polyfills

Create `tests/polyfills/vim.lua` to provide pure Lua implementations of Neovim utility functions used in tests:

```lua
-- Polyfill for vim.* functions used in tests
local table_utils = require('kanban-md.utils.table')

_G.vim = {
  -- Table utilities
  deepcopy = table_utils.deepcopy,

  tbl_contains = function(tbl, value)
    for _, v in ipairs(tbl) do
      if v == value then return true end
    end
    return false
  end,

  tbl_count = function(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
  end,

  tbl_extend = function(behavior, ...)
    local tables = {...}
    local result = {}
    for _, tbl in ipairs(tables) do
      for k, v in pairs(tbl) do
        if behavior == "force" or result[k] == nil then
          result[k] = v
        end
      end
    end
    return result
  end,

  -- Vim functions
  fn = {
    getcwd = function()
      return os.getenv("PWD") or io.popen("pwd"):read("*l")
    end
  }
}

return _G.vim
```

## Implementation Plan

### Phase 1: Foundation (Setup & Proof of Concept)

**Estimated Time: 1-2 hours**

#### 1.1 Install busted
```bash
luarocks install busted
```

Verify installation:
```bash
busted --version
```

#### 1.2 Create Vim Polyfills

Create `tests/polyfills/vim.lua` with the implementation above.

Test the polyfill:
```bash
/opt/local/bin/lua -e "package.path='./lua/?.lua;./lua/?/init.lua;./tests/?.lua;'..package.path; require('polyfills.vim'); print(vim.tbl_contains({1,2,3}, 2))"
```

Expected output: `true`

#### 1.3 Convert Proof of Concept Test

Choose a simple test file with minimal dependencies: `tests/unit/card_spec.lua`

Changes needed:
1. Remove Plenary imports
2. Add polyfill import at top: `require('polyfills.vim')`
3. Update any Plenary-specific assertions (if any)

Run with busted:
```bash
cd /Users/iainb/Projects/ThePrintedBird/nvim-plugins/kanban-md
busted tests/unit/card_spec.lua
```

### Phase 2: Core Unit Tests Migration

**Estimated Time: 3-4 hours**

Migrate all unit tests except `virtual_text_spec.lua`:

#### Test Files to Migrate (18 files):
- `tests/unit/adapters/cli_adapter_spec.lua`
- `tests/unit/board_validate_dependencies_spec.lua`
- `tests/unit/card_spec.lua`
- `tests/unit/column_helpers_spec.lua`
- `tests/unit/column_type_resolver_spec.lua`
- `tests/unit/config_dependency_refactor_spec.lua`
- `tests/unit/config_triggers_spec.lua`
- `tests/unit/detection_strategy_spec.lua`
- `tests/unit/id_persistence_spec.lua`
- `tests/unit/parser_content_blocks_spec.lua`
- `tests/unit/stats_formatting_spec.lua`
- `tests/unit/stats_metrics_spec.lua`
- `tests/unit/triggerable_spec.lua`
- `tests/unit/type_converter_spec.lua`
- `tests/unit/utils_string_spec.lua`
- `tests/unit/utils_table_spec.lua`
- `tests/unit/workflow_engine_spec.lua`
- `tests/unit/writer_content_blocks_spec.lua`
- `tests/unit/writer_mixin_spec.lua`

#### Migration Steps for Each File:

1. **Add polyfill import at top:**
   ```lua
   require('polyfills.vim')
   ```

2. **Remove Plenary imports** (if any):
   ```lua
   -- DELETE: local plenary = require('plenary.test_harness')
   ```

3. **Update test structure** (should be compatible already):
   - `describe()` → stays the same
   - `it()` → stays the same
   - `before_each()` → stays the same
   - `after_each()` → stays the same

4. **Update assertions** (mostly compatible):
   - `assert.equals(a, b)` → `assert.are.equal(a, b)` (busted style)
   - `assert.same(a, b)` → stays the same
   - `assert.is_true(x)` → `assert.is_true(x)` or `assert.truthy(x)`
   - `assert.is_false(x)` → `assert.is_false(x)` or `assert.falsy(x)`
   - `assert.is_nil(x)` → `assert.is_nil(x)`

5. **Run test:**
   ```bash
   busted tests/unit/TESTFILE_spec.lua
   ```

### Phase 3: Integration Tests Migration

**Estimated Time: 2-3 hours**

Migrate integration tests except `cursor_positioning_spec.lua`:

#### Test Files to Migrate (15 files):
- `tests/integration/auto_complexity_spec.lua`
- `tests/integration/auto_timestamp_spec.lua`
- `tests/integration/board_spec.lua`
- `tests/integration/card_spec.lua`
- `tests/integration/cli_usage_spec.lua`
- `tests/integration/column_spec.lua`
- `tests/integration/column_type_spec.lua`
- `tests/integration/content_preservation_spec.lua`
- `tests/integration/dependency_validation_spec.lua`
- `tests/integration/force_complete_command_spec.lua`
- `tests/integration/selective_bypass_spec.lua`
- `tests/integration/state_transitions_spec.lua`
- `tests/integration/subtask_validation_spec.lua`
- `tests/integration/timestamp_on_initial_placement_spec.lua`
- `tests/integration/writer_cli_adapter_spec.lua`

Follow same migration steps as Phase 2.

### Phase 3.5: E2E Tests Migration

**Estimated Time: 30 mins**

Migrate end-to-end scenario tests:

#### Test Files to Migrate (2 files):
- `tests/e2e/realistic_scenarios_spec.lua`
- `tests/e2e/triggers_spec.lua`

Follow same migration steps as Phase 2.

### Phase 4: Test Runner & Automation

**Estimated Time: 1-2 hours**

#### 4.1 Create Standalone Test Runner Script

Create `run_tests_standalone.sh` and run busted from it.

Make executable:
```bash
chmod +x run_tests_standalone.sh
```

#### 4.2 Tag Neovim-Only Tests

Add tags to Neovim-specific test files:

In `tests/unit/virtual_text_spec.lua`:
```lua
describe("Virtual Text #neovim-only", function()
  -- existing tests
end)
```

In `tests/integration/cursor_positioning_spec.lua`:
```lua
describe("Cursor Positioning #neovim-only", function()
  -- existing tests
end)
```

#### 4.3 Create busted Configuration

Create `.busted` in project root:

```lua
return {
  _all = {
    coverage = false,
    lpath = "lua/?.lua;lua/?/init.lua",
    pattern = "_spec%.lua$",
    ROOT = {"tests/"},
  },
  default = {
    verbose = true,
    exclude_tags = {"neovim-only"},
  },
  unit = {
    ROOT = {"tests/unit/"},
  },
  integration = {
    ROOT = {"tests/integration/"},
  },
  e2e = {
    ROOT = {"tests/e2e/"},
  },
}
```

### Phase 5: Update Neovim Tests

**Estimated Time: 30 mins**

Keep Neovim tests for virtual text and cursor positioning:

#### 5.1 Update `tests/run_tests.sh`

Modify to only run Neovim-specific tests:

```bash
#!/usr/bin/env zsh

# Neovim headless test runner (for Neovim-specific features only)
# Use run_tests_standalone.sh for core tests

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

# Install plenary if needed
PLENARY_PATH="$HOME/Library/Caches/kanban-md/plenary.nvim"
if [ ! -d "$PLENARY_PATH" ]; then
    echo "Installing plenary.nvim..."
    mkdir -p "$(dirname "$PLENARY_PATH")"
    git clone https://github.com/nvim-lua/plenary.nvim "$PLENARY_PATH"
fi

# Run Neovim-specific tests only
echo "Running Neovim-specific tests..."

nvim --headless \
     --cmd "set rtp+=$PLENARY_PATH,$PROJECT_ROOT" \
     -c "lua _G._TEST = true" \
     -c "PlenaryBustedFile tests/unit/virtual_text_spec.lua" \
     -c "PlenaryBustedFile tests/integration/cursor_positioning_spec.lua" \
     -c "PlenaryBustedFile tests/integration/writer_neovim_adapter_spec.lua" \
     -c "quit"
```

### Phase 6: Documentation & Makefile

**Estimated Time: 1 hour**

#### 6.1 Update Makefile

Create/update `Makefile`:

```makefile
.PHONY: test test-standalone test-neovim test-unit test-integration test-file

# Default: run all tests (standalone + Neovim)
test: test-standalone test-neovim

# Run core tests with standalone Lua (fast)
test-standalone:
	@./run_tests_standalone.sh

# Run Neovim-specific tests (slow)
test-neovim:
	@./tests/run_tests.sh

# Run only unit tests
test-unit:
	@busted --helper=tests/polyfills/vim.lua tests/unit

# Run only integration tests
test-integration:
	@busted --helper=tests/polyfills/vim.lua tests/integration

# Run only E2E tests
test-e2e:
	@busted --helper=tests/polyfills/vim.lua tests/e2e

# Run specific test file
# Usage: make test-file FILE=tests/unit/parser_spec.lua
test-file:
	@busted --helper=tests/polyfills/vim.lua $(FILE)

# Watch mode (requires busted watch feature)
test-watch:
	@busted --helper=tests/polyfills/vim.lua --watch tests/unit tests/integration

# Coverage (if needed)
test-coverage:
	@busted --helper=tests/polyfills/vim.lua --coverage tests/unit tests/integration
```

#### 6.2 Update Documentation

Update `CLAUDE.md` testing section:

```markdown
### Test Framework

The project uses two test approaches:

**Standalone Lua Tests (Primary):**
- Framework: busted
- Runner: `./run_tests_standalone.sh`
- Coverage: All core functionality (parser, writer, board, actions, stats, triggers)
- Files: `tests/unit/*` (except virtual_text), `tests/integration/*` (except cursor_positioning, writer_neovim_adapter), `tests/e2e/*`
- Speed: Fast (no Neovim overhead)

**Neovim Headless Tests (Neovim-Specific Features):**
- Framework: Plenary.nvim
- Runner: `./tests/run_tests.sh`
- Coverage: Virtual text display, cursor positioning, Neovim adapter
- Files: `tests/unit/virtual_text_spec.lua`, `tests/integration/cursor_positioning_spec.lua`, `tests/integration/writer_neovim_adapter_spec.lua`
- Speed: Slower (Neovim startup overhead)

### Running Tests

**All tests:**
```bash
make test
```

**Standalone tests only (fast):**
```bash
./run_tests_standalone.sh
# or
make test-standalone
```

**Neovim tests only:**
```bash
./tests/run_tests.sh
# or
make test-neovim
```

**Specific test file:**
```bash
make test-file FILE=tests/unit/parser_spec.lua
```

**Watch mode (auto-run on file changes):**
```bash
make test-watch
```

**Requirements:**
- Standalone tests: Lua (`/opt/local/bin/lua`), busted (`luarocks install busted`)
- Neovim tests: Neovim, Plenary.nvim (auto-installed to `~/Library/Caches/kanban-md/plenary.nvim`)
```

#### 6.3 Create README for tests directory

Create `tests/README.md`:

```markdown
# Test Suite

## Structure

- `unit/` - Unit tests for individual modules (standalone Lua)
- `integration/` - Integration tests for workflows (standalone Lua + some Neovim-only)
- `e2e/` - End-to-end scenario tests (standalone Lua)
- `manual-tests/` - Manual Neovim integration tests (Neovim only)
- `polyfills/` - Pure Lua implementations of Neovim utilities

## Test Categories

### Standalone Lua Tests
Run with `busted` in standalone Lua environment (no Neovim).

**Tagged:** (no tag) or `#standalone`
**Files:** Most tests in `unit/`, `integration/`, `e2e/`
**Run:** `./run_tests_standalone.sh` or `make test-standalone`

### Neovim-Only Tests
Run with Plenary in Neovim headless mode.

**Tagged:** `#neovim-only`
**Files:**
- `unit/virtual_text_spec.lua` - Virtual text display
- `integration/cursor_positioning_spec.lua` - Cursor positioning
- `integration/writer_neovim_adapter_spec.lua` - Neovim buffer adapter

**Run:** `./tests/run_tests.sh` or `make test-neovim`

## Writing Tests

### Standalone Tests (Most Tests)

```lua
require('polyfills.vim')  -- Add at top of file

describe("MyModule", function()
  local MyModule

  before_each(function()
    MyModule = require('kanban-md.my_module')
  end)

  it("does something", function()
    local result = MyModule.do_thing()
    assert.are.equal("expected", result)
  end)
end)
```

### Neovim Tests

```lua
describe("Virtual Text #neovim-only", function()
  -- Use vim.api.* freely
  it("displays virtual text", function()
    vim.api.nvim_buf_set_virtual_text(...)
  end)
end)
```

## Assertions

Busted provides comprehensive assertions:

```lua
assert.are.equal(expected, actual)     -- Equality
assert.are.same(expected, actual)      -- Deep equality (tables)
assert.is_true(value)                  -- Boolean true
assert.is_false(value)                 -- Boolean false
assert.is_nil(value)                   -- Nil check
assert.truthy(value)                   -- Any truthy value
assert.falsy(value)                    -- Nil or false
assert.has_error(fn, pattern)          -- Error matching pattern
```

## Running Tests

See Makefile targets:
- `make test` - All tests (standalone + Neovim)
- `make test-standalone` - Standalone tests only (fast)
- `make test-neovim` - Neovim tests only
- `make test-unit` - Unit tests only
- `make test-integration` - Integration tests only
- `make test-e2e` - E2E tests only
- `make test-file FILE=path` - Single test file
- `make test-watch` - Watch mode
```

## Validation & Success Criteria

### Success Criteria

1. ✅ All core tests run in standalone Lua without Neovim
2. ✅ Test execution time reduced by >50% (no Neovim startup)
3. ✅ Virtual text and cursor tests still run in Neovim headless
4. ✅ All tests pass with same coverage as before
5. ✅ CI/CD updated to run both test modes
6. ✅ Documentation updated with clear instructions

### Validation Steps

After migration, verify:

```bash
# 1. All standalone tests pass
./run_tests_standalone.sh
echo "Exit code: $?"  # Should be 0

# 2. Neovim tests still work
./tests/run_tests.sh
echo "Exit code: $?"  # Should be 0

# 3. Makefile targets work
make test-unit
make test-integration
make test-file FILE=tests/unit/parser_spec.lua

# 4. Watch mode works (manual check - press Ctrl+C to exit)
make test-watch

# 5. Test count matches
busted --list tests/unit tests/integration tests/e2e | wc -l
# Compare to previous test count from Plenary

# 6. Coverage is maintained (optional)
make test-coverage
```

## Migration Checklist

### Phase 1: Foundation ✓/✗

- [x] Install busted: `luarocks install busted`
- [x] Verify busted installation: `busted --version`
- [x] Create `tests/polyfills/vim.lua`
- [x] Test polyfill: `lua -e "require('polyfills.vim'); print(vim.tbl_contains({1,2,3}, 2))"`
- [x] Convert proof of concept test: `tests/unit/card_spec.lua`
- [x] Run POC test: `busted tests/unit/card_spec.lua`
- [x] Verify POC test passes

### Phase 2: Unit Tests Migration ✓/✗

Unit tests (standalone):
- [x] `tests/unit/adapters/cli_adapter_spec.lua`
- [x] `tests/unit/board_validate_dependencies_spec.lua`
- [x] `tests/unit/card_spec.lua`
- [x] `tests/unit/column_helpers_spec.lua`
- [x] `tests/unit/column_type_resolver_spec.lua`
- [x] `tests/unit/config_dependency_refactor_spec.lua`
- [x] `tests/unit/config_triggers_spec.lua`
- [x] `tests/unit/detection_strategy_spec.lua`
- [x] `tests/unit/id_persistence_spec.lua`
- [x] `tests/unit/parser_content_blocks_spec.lua`
- [x] `tests/unit/stats_formatting_spec.lua`
- [x] `tests/unit/stats_metrics_spec.lua`
- [x] `tests/unit/triggerable_spec.lua`
- [x] `tests/unit/type_converter_spec.lua`
- [x] `tests/unit/utils_string_spec.lua`
- [x] `tests/unit/utils_table_spec.lua`
- [x] `tests/unit/workflow_engine_spec.lua`
- [x] `tests/unit/writer_content_blocks_spec.lua`
- [x] `tests/unit/writer_mixin_spec.lua`

Unit tests (Neovim-only, skip for now):
- [ ] `tests/unit/virtual_text_spec.lua` (already tagged #neovim-only)

Verification:
- [x] Run all unit tests: `busted tests/unit --exclude-tags=neovim-only`
- [x] All unit tests pass

### Phase 3: Integration Tests Migration ✓/✗

Integration tests (standalone):
- [x] `tests/integration/auto_complexity_spec.lua`
- [x] `tests/integration/auto_timestamp_spec.lua`
- [x] `tests/integration/board_spec.lua`
- [x] `tests/integration/card_spec.lua`
- [x] `tests/integration/cli_usage_spec.lua`
- [x] `tests/integration/column_spec.lua`
- [x] `tests/integration/column_type_spec.lua`
- [x] `tests/integration/content_preservation_spec.lua`
- [x] `tests/integration/dependency_validation_spec.lua`
- [x] `tests/integration/force_complete_command_spec.lua`
- [x] `tests/integration/selective_bypass_spec.lua`
- [x] `tests/integration/state_transitions_spec.lua`
- [x] `tests/integration/subtask_validation_spec.lua`
- [x] `tests/integration/timestamp_on_initial_placement_spec.lua`
- [x] `tests/integration/writer_cli_adapter_spec.lua`

Integration tests (Neovim-only, skip for now):
- [x] `tests/integration/cursor_positioning_spec.lua` (already tagged #neovim-only)
- [x] `tests/integration/writer_neovim_adapter_spec.lua` (already tagged #neovim-only)

Verification:
- [x] Run all integration tests: `busted tests/integration --exclude-tags=neovim-only`
- [x] All integration tests pass

### Phase 3.5: E2E Tests Migration ✓/✗

E2E tests (standalone):
- [x] `tests/e2e/realistic_scenarios_spec.lua`
- [x] `tests/e2e/triggers_spec.lua`

Verification:
- [x] Run all E2E tests: `busted tests/e2e`
- [x] All E2E tests pass

### Phase 4: Test Runner & Automation ✓/✗

- [x] Create `run_tests_standalone.sh`
- [x] Make executable: `chmod +x run_tests_standalone.sh`
- [x] Test runner: `./run_tests_standalone.sh`
- [x] Tag Neovim tests: Add `#neovim-only` to `virtual_text_spec.lua`
- [x] Tag Neovim tests: Add `#neovim-only` to `cursor_positioning_spec.lua`
- [x] Create `.busted` configuration file
- [x] Test busted config: `busted --list`

### Phase 5: Update Neovim Tests ✓/✗

- [x] Update `tests/run_tests.sh` to only run Neovim tests
- [x] Test Neovim runner: `./tests/run_tests.sh`
- [x] Verify virtual text tests still pass
- [x] Verify cursor positioning tests still pass

### Phase 6: Documentation & Makefile ✓/✗

- [x] Create/update `Makefile`
- [ ] Test Makefile targets:
  - [x] `make test`
  - [x] `make test-standalone`
  - [x] `make test-neovim`
  - [x] `make test-unit`
  - [x] `make test-integration`
  - [x] `make test-e2e`
  - [x] `make test-file FILE=tests/unit/parser_content_blocks_spec.lua`
- [x] Update `CLAUDE.md` testing section
- [x] Create `tests/README.md`
- [x] Update main `README.md` if needed

### Final Validation ✓/✗

- [x] Run all tests: `make test`
- [x] Run standalone only: `make test-standalone`
- [x] Run Neovim only: `make test-neovim`
- [x] Verify test count unchanged
- [x] Verify all tests pass
- [x] Verify test execution time reduced

## Notes

- **No backwards compatibility needed** - Clean migration, no legacy support required
- **Parallel execution** - busted supports parallel test execution with `--shuffle` flag
- **Coverage** - busted can generate coverage reports with `--coverage` flag
- **Watch mode** - Some busted plugins provide watch functionality for auto-running tests on file changes
- **CI/CD** - Update CI configuration to run `make test` instead of old test command

## Troubleshooting

### Common Issues

**Issue: Module not found**
```
Solution: Check LUA_PATH includes ./lua/?.lua and ./lua/?/init.lua
```

**Issue: vim.* function not defined**
```
Solution: Add require('polyfills.vim') at top of test file
```

**Issue: Assertion syntax error**
```
Solution: Update from Plenary syntax (assert.equals) to busted syntax (assert.are.equal)
```

**Issue: Test fails in standalone but passes in Neovim**
```
Solution: Check for hidden Neovim API usage - may need to tag as #neovim-only
```

## Future Enhancements

- [ ] Add test coverage reporting with luacov
- [ ] Add test performance profiling
- [ ] Add parallel test execution for faster runs
- [ ] Add test fixtures directory for shared test data
- [ ] Add test helpers module for common test utilities
- [ ] Integrate with CI/CD for automated testing
- [ ] Add pre-commit hook to run tests
