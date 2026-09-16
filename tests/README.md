# Test Suite

## Overview

This test suite uses a dual-framework approach: **Busted** for standalone Lua tests.

## Structure

```
tests
├── README.md
├── e2e
│   ├── realistic_scenarios_spec.lua
│   └── triggers_spec.lua
├── fixtures
│   ├── boards
│   │   ├── board_auto_move.md
│   │   ├── board_complex.md
│   │   ├── board_custom.md
│   │   ├── board_edge.md
│   │   ├── board_simple.md
│   │   ├── complexity_demo.md
│   │   └── test_basic_config.md
│   ├── boards.lua
│   └── multiline_board.md
├── helpers
│   └── mocks.lua
├── integration
│   ├── auto_complexity_spec.lua
│   ├── auto_timestamp_spec.lua
│   ├── board_spec.lua
│   ├── card_spec.lua
│   ├── cli_usage_spec.lua
│   ├── column_spec.lua
│   ├── column_type_spec.lua
│   ├── content_preservation_spec.lua
│   ├── dependency_validation_spec.lua
│   ├── force_complete_command_spec.lua
│   ├── parser_column_header_markdown_spec.lua
│   ├── selective_bypass_spec.lua
│   ├── state_transitions_spec.lua
│   ├── subtask_validation_spec.lua
│   ├── timestamp_on_initial_placement_spec.lua
│   └── writer_cli_adapter_spec.lua
├── polyfills
│   └── vim.lua
├── run_tests_standalone.sh
└── unit
    ├── adapters
    │   └── cli_adapter_spec.lua
    ├── blank_line_preservation_spec.lua
    ├── board_validate_dependencies_spec.lua
    ├── card_spec.lua
    ├── column_helpers_spec.lua
    ├── column_type_resolver_spec.lua
    ├── config_dependency_refactor_spec.lua
    ├── complexity_demo_fixture_spec.lua
    ├── config_triggers_spec.lua
    ├── detection_strategy_spec.lua
    ├── id_persistence_spec.lua
    ├── parser_content_blocks_spec.lua
    ├── parser_multiline_spec.lua
    ├── parser_properties_spec.lua
    ├── stats_formatting_spec.lua
    ├── stats_metrics_spec.lua
    ├── triggerable_spec.lua
    ├── type_converter_spec.lua
    ├── utils_string_spec.lua
    ├── utils_table_spec.lua
    ├── workflow_engine_spec.lua
    ├── writer_content_blocks_spec.lua
    ├── writer_mixin_spec.lua
    └── writer_multiline_spec.lua

10 directories, 65 files
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

Moved to the Neovim plugin that utilises this engine.

## Running Tests

### Quick Start

```bash
# Run all tests (equivalent to standalone)
make test

# Run only standalone tests
make test-standalone

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

**Issue: Assertion syntax error**
```
Solution: Use Busted syntax (assert.are.equal) not Plenary syntax (assert.equals)
```

## Performance

Test execution times ~2-3 seconds (675 tests)

## Test Coverage

Current coverage:

- **Unit tests:** 19 files (456 tests)
- **Integration tests:** 15 files (199 tests)
- **E2E tests:** 2 files (20 tests)
- **Total:** 36 standalone test files

All core functionality (parser, writer, board, actions, stats, triggers) is tested in standalone Lua for maximum speed.
