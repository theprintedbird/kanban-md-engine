# Test Suite

## Overview

This test suite uses a dual-framework approach: **Busted** for standalone Lua tests and **Plenary.nvim** for Neovim-specific features.

## Structure

```
tests/
├── unit/                  # Unit tests for individual modules
│   ├── parser_*.lua      # Parser functionality
│   ├── writer_*.lua      # Writer functionality
│   ├── stats_*.lua       # Statistics calculation
│   ├── virtual_text_spec.lua  # Virtual text (Neovim-only)
│   └── ...
├── integration/           # Integration tests for workflows
│   ├── board_spec.lua    # Board operations
│   ├── cursor_positioning_spec.lua  # Cursor positioning (Neovim-only)
│   ├── writer_neovim_adapter_spec.lua  # Neovim adapter (Neovim-only)
│   └── ...
├── e2e/                   # End-to-end scenario tests
│   ├── realistic_scenarios_spec.lua
│   └── triggers_spec.lua
├── polyfills/             # Pure Lua implementations of Neovim utilities
│   └── vim.lua           # vim.* function polyfills
├── run_tests.lua         # Neovim test runner (finds #neovim-only tests)
```

## Test Categories

### Standalone Lua Tests

Run with `busted` in standalone Lua environment (no Neovim).

**Tagged:** (no tag) or explicitly exclude `#neovim-only`
**Files:** ~35 test files covering core functionality
**Run:** `./tests/run_tests_standalone.sh` or `make test-standalone`

These tests use `tests/polyfills/vim.lua` to provide pure Lua implementations of Neovim utility functions like:
- `vim.deepcopy()`
- `vim.tbl_contains()`
- `vim.tbl_count()`
- `vim.tbl_extend()`
- `vim.fn.getcwd()`

### Neovim-Only Tests

Run with Plenary in Neovim headless mode.

**Tagged:** `#neovim-only` (in describe block)
**Files:**
- `unit/virtual_text_spec.lua` - Virtual text display using Neovim APIs
- `integration/cursor_positioning_spec.lua` - Cursor positioning using Neovim APIs
- `integration/writer_neovim_adapter_spec.lua` - Neovim buffer adapter

**Run:** `./tests/run_tests.sh` or `make test-neovim`

## Running Tests

### Quick Start

```bash
# Run all tests (standalone + Neovim)
make test

# Run only standalone tests (fast)
make test-standalone

# Run only Neovim tests
make test-neovim
```

### By Category

```bash
# Unit tests only
make test-unit

# Integration tests only
make test-integration

# E2E tests only
make test-e2e
```

### Specific Files

```bash
# Via Makefile
make test-file FILE=tests/unit/parser_content_blocks_spec.lua

# Via busted directly
busted tests/unit/parser_content_blocks_spec.lua
busted tests/integration/board_spec.lua
```

### Using Busted Directly

```bash
# Run all tests (uses .busted config)
busted

# Run tests in specific directory
busted tests/unit
busted tests/integration
busted tests/e2e

# Run tests matching a pattern
busted --pattern=parser

# Run with verbose output
busted --verbose

# List all tests
busted --list
```

## Writing Tests

### Standalone Tests (Most Tests)

Add `require('polyfills.vim')` at the top of the file to access Neovim utility functions:

```lua
require('polyfills.vim')

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

Tag the describe block with `#neovim-only`:

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
-- Equality
assert.are.equal(expected, actual)     -- Simple equality
assert.are.same(expected, actual)      -- Deep equality (tables)

-- Boolean checks
assert.is_true(value)                  -- Must be boolean true
assert.is_false(value)                 -- Must be boolean false
assert.truthy(value)                   -- Any truthy value (not nil or false)
assert.falsy(value)                    -- Nil or false

-- Nil checks
assert.is_nil(value)                   -- Must be nil
assert.is_not_nil(value)               -- Must not be nil

-- Error handling
assert.has_error(fn, pattern)          -- Function throws error matching pattern
assert.has_no_error(fn)                -- Function does not throw error

-- String patterns
assert.matches(pattern, str)           -- String matches pattern
```

## Configuration

### .busted File

The `.busted` file in the project root configures Busted:

```lua
return {
  _all = {
    coverage = false,
    lpath = "lua/?.lua;lua/?/init.lua;tests/?.lua;tests/?/init.lua",
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

This configuration:
- Sets Lua module paths (including polyfills)
- Defines test file pattern (`*_spec.lua`)
- Excludes `#neovim-only` tests by default
- Provides named test suites

## Test Isolation

### Before/After Hooks

```lua
describe("MyModule", function()
  local original_config

  before_each(function()
    -- Save state before each test
    original_config = vim.deepcopy(Config.defaults)
  end)

  after_each(function()
    -- Restore state after each test
    Config.defaults = original_config
  end)

  it("modifies config", function()
    -- Test can safely modify config
    Config.defaults.wip_limit = 10
  end)
end)
```

### Temporary Files

For file I/O tests, use temporary files instead of git stash:

```lua
local function write_temp_file()
  local tmpfile = os.tmpname()
  local file = io.open(tmpfile, "w")
  file:write("# Test Board\n")
  file:close()
  return tmpfile
end

it("reads board from file", function()
  local tmpfile = write_temp_file()

  -- Test file operations
  local content = read_file(tmpfile)
  assert.are.equal("# Test Board\n", content)

  -- Clean up
  os.remove(tmpfile)
end)
```

## Debugging Tests

### Running Single Tests

```bash
# Run specific test file with verbose output
busted --verbose tests/unit/parser_spec.lua
```

### Using Print Statements

```lua
it("debugs a complex operation", function()
  local result = complex_operation()
  print("Result:", vim.inspect(result))  -- Pretty-print tables
  assert.are.equal("expected", result.field)
end)
```

### Filter by Test Name

```bash
# Run only tests matching "parser"
busted --filter=parser

# Run only tests matching "Complete Workflow"
busted --filter="Complete Workflow"
```

## CI/CD Integration

The test suite is designed for CI/CD environments:

```bash
# Install dependencies
luarocks install busted

# Run all tests
make test

# Check exit code
if [ $? -eq 0 ]; then
  echo "All tests passed"
else
  echo "Tests failed"
  exit 1
fi
```

## Troubleshooting

### Common Issues

**Issue: Module not found**
```
Solution: Check that .busted lpath includes lua/?.lua and tests/?.lua
```

**Issue: vim.* function not defined**
```
Solution: Add require('polyfills.vim') at top of test file
```

**Issue: Test fails in standalone but passes in Neovim**
```
Solution: Check for hidden Neovim API usage - may need to tag as #neovim-only
```

**Issue: Assertion syntax error**
```
Solution: Use Busted syntax (assert.are.equal) not Plenary syntax (assert.equals)
```

## Performance

Test execution times (approximate):

- **Standalone tests:** ~2-3 seconds (675 tests)
- **Neovim tests:** ~5-10 seconds (3 test files)
- **Total:** ~7-13 seconds

The standalone Lua tests are significantly faster due to avoiding Neovim startup overhead.

## Test Coverage

Current coverage:

- **Unit tests:** 19 files (456 tests)
- **Integration tests:** 15 files (199 tests)
- **E2E tests:** 2 files (20 tests)
- **Total:** 36 standalone test files

All core functionality (parser, writer, board, actions, stats, triggers) is tested in standalone Lua for maximum speed.
