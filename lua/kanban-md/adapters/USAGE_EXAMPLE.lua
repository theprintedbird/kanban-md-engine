--- Example: How to Implement and Use the Adapter Interface
--- This file demonstrates the abstract interface pattern in Lua

local Adapter = require('kanban-md.adapters.interface')

--------------------------------------------------------------------------------
-- Example 1: Creating a Simple Print Adapter
--------------------------------------------------------------------------------

local PrintAdapter = Adapter.new({
  notify = function(self, message, level)
    local prefix = string.format("[%s]", level or "INFO")
    print(prefix, message)
  end,

  read_buffer = function(self)
    -- Simulate reading from a file
    return {
      "# My Kanban Board",
      "###### To Do",
      "- Task 1",
      "- Task 2",
    }
  end,

  write_buffer = function(self, lines)
    print("Writing buffer:")
    for i, line in ipairs(lines) do
      print(string.format("%3d | %s", i, line))
    end
  end,

  get_cursor = function(self)
    return 1, 0  -- Line 1, column 0
  end,

  set_cursor = function(self, line, col)
    print(string.format("Cursor moved to line %d, col %d", line, col))
  end,

  prompt_input = function(self, prompt, default, callback)
    io.write(prompt .. " [" .. (default or "") .. "]: ")
    local input = io.read()
    if input == "" then input = default end
    callback(input)
  end,

  prompt_select = function(self, items, opts, callback)
    local prompt_text = opts and opts.prompt or "Select an option"
    print(prompt_text)

    for i, item in ipairs(items) do
      print(string.format("  %d. %s", i, item))
    end

    io.write("Choice: ")
    local choice = tonumber(io.read())

    if choice and choice >= 1 and choice <= #items then
      callback(items[choice], choice)
    else
      callback(nil, nil)
    end
  end,
})

--------------------------------------------------------------------------------
-- Example 2: Using the Adapter
--------------------------------------------------------------------------------

print("\n=== Example 2: Using PrintAdapter ===\n")

-- User feedback
PrintAdapter:notify("Board loaded successfully", "info")
PrintAdapter:notify("WIP limit exceeded!", "warn")

-- Buffer operations
local lines = PrintAdapter:read_buffer()
print("\nRead lines:", #lines)

PrintAdapter:write_buffer({
  "# Updated Board",
  "###### Done",
  "- Completed task",
})

-- Cursor operations
local line, col = PrintAdapter:get_cursor()
print(string.format("\nCurrent cursor: line %d, col %d", line, col))
PrintAdapter:set_cursor(5, 10)

--------------------------------------------------------------------------------
-- Example 3: What Happens if You Miss a Method?
--------------------------------------------------------------------------------

print("\n=== Example 3: Incomplete Adapter (will error) ===\n")

local success, err = pcall(function()
  local BadAdapter = Adapter.new({
    notify = function(self, message, level)
      print(message)
    end,
    -- Missing read_buffer, write_buffer, etc!
  })
end)

if not success then
  print("Error creating BadAdapter:", err)
  -- Expected output: "Adapter missing required method: read_buffer"
end

--------------------------------------------------------------------------------
-- Example 4: Calling Abstract Methods Directly
--------------------------------------------------------------------------------

print("\n=== Example 4: Calling Base Adapter (will error) ===\n")

local BaseAdapter = {}
setmetatable(BaseAdapter, Adapter)

success, err = pcall(function()
  BaseAdapter:notify("This won't work")
end)

if not success then
  print("Error calling abstract method:", err)
  -- Expected: "Abstract method 'notify' must be implemented by adapter..."
end

--------------------------------------------------------------------------------
-- Example 5: Optional Methods (Virtual Text)
--------------------------------------------------------------------------------

print("\n=== Example 5: Optional Methods ===\n")

-- PrintAdapter doesn't override virtual text methods, so they use defaults
print("Supports virtual text:", PrintAdapter:supports_virtual_text())  -- false
print("Namespace ID:", PrintAdapter:create_namespace("test"))  -- nil

-- But we can override them if we want:
local FancyAdapter = Adapter.new({
  notify = function(self, msg, lvl) print(msg) end,
  read_buffer = function(self) return {} end,
  write_buffer = function(self, lines) end,
  get_cursor = function(self) return 1, 0 end,
  set_cursor = function(self, line, col) end,
  prompt_input = function(self, prompt, default, callback) callback("input") end,
  prompt_select = function(self, items, opts, callback) callback(items[1], 1) end,

  -- Override optional methods
  supports_virtual_text = function(self)
    return true
  end,

  create_namespace = function(self, name)
    print("Creating namespace:", name)
    return 42  -- Return a fake namespace ID
  end,
})

print("\nFancyAdapter supports virtual text:", FancyAdapter:supports_virtual_text())
print("FancyAdapter namespace ID:", FancyAdapter:create_namespace("fancy"))

print("\n=== All examples complete ===\n")
