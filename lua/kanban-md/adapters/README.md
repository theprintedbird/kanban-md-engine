# Adapter Interface

This directory contains the adapter interface and platform-specific implementations for kanban-md. The adapter pattern allows the core engine to remain platform-agnostic whilst supporting different environments (Neovim, CLI, web, etc.).

## Architecture

```
┌─────────────────────────────────────────┐
│   Application Layer                      │  ← Platform-specific (Neovim/Obsidian/Web)
│   (commands, UI, keybindings)           │
├─────────────────────────────────────────┤
│   Adapter Interface (Strategy Pattern)   │  ← Pluggable implementations
│   - notify()                             │
│   - read_buffer() / write_buffer()      │
│   - prompt_input() / prompt_select()    │
│   - cursor operations                    │
└─────────────────────────────────────────┘
```

## Files

- **`interface.lua`** - Abstract adapter interface with method contracts
- **`neovim.lua`** - Neovim-specific implementation (uses `vim.*` APIs)
- **`cli.lua`** - Command-line interface implementation (uses `io.*` and `print`)
- **`USAGE_EXAMPLE.lua`** - Comprehensive examples of implementing and using adapters
- **`README.md`** - This file

## Quick Start

### Using an Existing Adapter

TODO update this

```lua
local NeovimAdapter = require('kanban-md.adapters.neovim')
local adapter = NeovimAdapter.new()

-- User feedback
adapter:notify("Task completed!", "info")

-- Buffer operations
local lines = adapter:read_buffer()
adapter:write_buffer({ "# New Board", "###### To Do" })

-- Cursor operations
local line, col = adapter:get_cursor()
adapter:set_cursor(5, 0)

-- UI prompts
adapter:prompt_input("Task name:", "New task", function(input)
  print("User entered:", input)
end)

adapter:prompt_select({ "To Do", "In Progress", "Done" }, {
  prompt = "Select column:",
}, function(item, idx)
  print("User selected:", item, "at index", idx)
end)
```

### Creating a New Adapter

```lua
local Adapter = require('kanban-md.adapters.interface')

local MyAdapter = Adapter.new({
  -- Required: User feedback
  notify = function(self, message, level)
    -- Implementation here
  end,

  -- Required: Buffer I/O
  read_buffer = function(self)
    -- Return array of strings (lines)
  end,

  write_buffer = function(self, lines)
    -- Write array of strings to buffer/file
  end,

  -- Required: Cursor management
  get_cursor = function(self)
    -- Return line, col (1-indexed line, 0-indexed col)
  end,

  set_cursor = function(self, line, col)
    -- Set cursor position
  end,

  -- Required: UI prompts
  prompt_input = function(self, prompt, default, callback)
    -- Prompt user for input, call callback(input)
  end,

  prompt_select = function(self, items, opts, callback)
    -- Prompt user to select from items, call callback(item, idx)
  end,

  -- Optional: Virtual text support
  supports_virtual_text = function(self)
    return true  -- Override if you support virtual text
  end,

  create_namespace = function(self, name)
    -- Return namespace ID if supported, nil otherwise
  end,

  set_extmark = function(self, bufnr, ns, line, col, opts)
    -- Set virtual text if supported, return extmark ID or nil
  end,

  clear_namespace = function(self, bufnr, ns)
    -- Clear virtual text if supported
  end,
})
```

## Method Reference

### Required Methods

#### `notify(message, level)`
Display a message to the user.

**Parameters:**
- `message` (string): The message to display
- `level` (string|nil): Severity level: `"info"`, `"warn"`, `"error"` (default: `"info"`)

**Example:**
```lua
adapter:notify("Task moved to Done column", "info")
adapter:notify("WIP limit exceeded!", "warn")
adapter:notify("Failed to parse board", "error")
```

---

#### `read_buffer()`
Read the current buffer/file contents.

**Returns:**
- `table`: Array of strings, one per line

**Example:**
```lua
local lines = adapter:read_buffer()
-- lines = { "# My Board", "###### To Do", "- Task 1" }
```

---

#### `write_buffer(lines)`
Write lines to the current buffer/file.

**Parameters:**
- `lines` (table): Array of strings to write

**Example:**
```lua
adapter:write_buffer({
  "# Updated Board",
  "###### Done",
  "- Completed task",
})
```

---

#### `get_cursor()`
Get the current cursor position.

**Returns:**
- `number`: 1-indexed line number
- `number`: 0-indexed column number

**Example:**
```lua
local line, col = adapter:get_cursor()
-- line = 5, col = 10
```

---

#### `set_cursor(line, col)`
Set the cursor position.

**Parameters:**
- `line` (number): 1-indexed line number
- `col` (number): 0-indexed column number

**Example:**
```lua
adapter:set_cursor(5, 10)  -- Move to line 5, column 10
```

---

#### `prompt_input(prompt, default, callback)`
Prompt the user for text input.

**Parameters:**
- `prompt` (string): The prompt message to display
- `default` (string|nil): Default value for input
- `callback` (function): Callback receiving the input: `function(input)`

**Example:**
```lua
adapter:prompt_input("Task name:", "New task", function(input)
  print("User entered:", input)
end)
```

---

#### `prompt_select(items, opts, callback)`
Prompt the user to select from a list of items.

**Parameters:**
- `items` (table): Array of items to choose from
- `opts` (table|nil): Options table with optional fields:
  - `prompt` (string): Custom prompt message
  - `format_item` (function): Custom formatting function
- `callback` (function): Callback receiving selected item and index: `function(item, idx)`

**Example:**
```lua
adapter:prompt_select(
  { "To Do", "In Progress", "Done" },
  { prompt = "Select column:" },
  function(item, idx)
    print("Selected:", item, "at index", idx)
  end
)
```

### Optional Methods

#### `supports_virtual_text()`
Check if the adapter supports virtual text/extmark operations.

**Returns:**
- `boolean`: `true` if virtual text is supported, `false` otherwise

**Default:** Returns `false`

---

#### `create_namespace(name)`
Create a namespace for virtual text (only if supported).

**Parameters:**
- `name` (string): Namespace identifier

**Returns:**
- `number|nil`: Platform-specific namespace identifier, or `nil` if unsupported

**Default:** Returns `nil`

---

#### `set_extmark(bufnr, ns, line, col, opts)`
Set virtual text at a specific position (only if supported).

**Parameters:**
- `bufnr` (number): Buffer number
- `ns` (number): Namespace ID
- `line` (number): 0-indexed line number
- `col` (number): 0-indexed column number
- `opts` (table): Options table with `virt_text`, `virt_text_pos`, etc.

**Returns:**
- `number|nil`: Extmark identifier, or `nil` if unsupported

**Default:** Returns `nil`

---

#### `clear_namespace(bufnr, ns)`
Clear all virtual text in a namespace (only if supported).

**Parameters:**
- `bufnr` (number): Buffer number
- `ns` (number): Namespace ID

**Default:** No-op

## Implementation Guide

### Step 1: Define Your Adapter

Create a new file in `lua/kanban-md/adapters/` (e.g., `myplatform.lua`):

```lua
local Adapter = require('kanban-md.adapters.interface')

local MyPlatformAdapter = {}

function MyPlatformAdapter.new()
  return Adapter.new({
    notify = function(self, message, level)
      -- Your implementation
    end,

    read_buffer = function(self)
      -- Your implementation
    end,

    -- ... implement all required methods
  })
end

return MyPlatformAdapter
```

### Step 2: Implement Required Methods

All seven required methods must be implemented:
1. `notify(message, level)`
2. `read_buffer()`
3. `write_buffer(lines)`
4. `get_cursor()`
5. `set_cursor(line, col)`
6. `prompt_input(prompt, default, callback)`
7. `prompt_select(items, opts, callback)`

If you forget a method, `Adapter.new()` will throw an error at creation time.

### Step 3: (Optional) Implement Virtual Text Methods

If your platform supports inline text display (like Neovim's extmarks), override:
1. `supports_virtual_text()` - Return `true`
2. `create_namespace(name)` - Return namespace ID
3. `set_extmark(bufnr, ns, line, col, opts)` - Set virtual text
4. `clear_namespace(bufnr, ns)` - Clear virtual text

### Step 4: Inject Your Adapter

TODO update this
In your application code:

```lua
local MyPlatformAdapter = require('kanban-md.adapters.myplatform')
local kanban = require('kanban-md')

kanban.setup({
  adapter = MyPlatformAdapter.new(),
  -- ... other config
})
```

## Testing Your Adapter

Create a test file in `tests/unit/adapters/`:

```lua
local MyAdapter = require('kanban-md.adapters.myplatform')

describe("MyPlatformAdapter", function()
  local adapter

  before_each(function()
    adapter = MyAdapter.new()
  end)

  it("implements all required methods", function()
    local is_valid, err = require('kanban-md.adapters.interface').validate(adapter)
    assert.is_true(is_valid)
    assert.is_nil(err)
  end)

  it("can notify users", function()
    -- Test notify implementation
    adapter:notify("Test message", "info")
  end)

  it("can read and write buffers", function()
    local lines = adapter:read_buffer()
    assert.is_table(lines)

    adapter:write_buffer({ "line 1", "line 2" })
  end)

  -- ... more tests
end)
```

## Platform-Specific Examples

### Neovim Adapter

Uses Neovim's built-in APIs:

```lua
notify = function(self, message, level)
  vim.notify(message, vim.log.levels[string.upper(level or "info")])
end

read_buffer = function(self)
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end
```

### CLI Adapter

Uses standard Lua I/O:

```lua
notify = function(self, message, level)
  local emoji = { info = "ℹ️", warn = "⚠️", error = "❌" }
  print(string.format("%s %s", emoji[level or "info"], message))
end

read_buffer = function(self)
  local lines = {}
  for line in io.lines() do
    table.insert(lines, line)
  end
  return lines
end
```

### Web Adapter (Conceptual)

Uses browser APIs:

```lua
notify = function(self, message, level)
  -- Assuming Lua compiled to JS (e.g., via Fengari)
  js.global:alert(message)
  -- Or use a toast library
end

read_buffer = function(self)
  local content = js.global.document:getElementById("editor").value
  return string.split(content, "\n")
end
```

## Validation

The adapter interface includes automatic validation:

```lua
local Adapter = require('kanban-md.adapters.interface')

-- This will error if methods are missing:
local adapter = Adapter.new({
  notify = function(self, msg, lvl) print(msg) end,
  -- Missing other methods!
})
-- Error: "Adapter missing required method: read_buffer"

-- Manual validation:
local is_valid, err = Adapter.validate(my_adapter)
if not is_valid then
  print("Validation error:", err)
end
```

## Benefits

1. **Platform Independence**: Core engine works anywhere Lua runs
2. **Clear Contracts**: Interface defines exact method signatures
3. **Runtime Validation**: Automatic checks ensure correctness
4. **Optional Features**: Virtual text support is opt-in
5. **Easy Testing**: Mock adapters for unit tests

## See Also

- `interface.lua` - Full interface implementation with LuaCATS annotations
- `USAGE_EXAMPLE.lua` - Runnable examples demonstrating all concepts
- `neovim.lua` - Reference implementation for Neovim
- `cli.lua` - Reference implementation for CLI usage
