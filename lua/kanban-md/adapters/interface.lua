--- Abstract Adapter Interface
--- Defines the contract that all platform adapters must implement.
--- Uses Lua metatables to enforce method implementation and provide validation.
---
--- @class Adapter
--- @field notify function Display a message to the user
--- @field read_buffer function Read current buffer/file contents
--- @field write_buffer function Write lines to buffer/file
--- @field get_cursor function Get current cursor position
--- @field set_cursor function Set cursor position
--- @field prompt_input function Prompt user for text input
--- @field prompt_select function Prompt user to select from options
local Adapter = {}
Adapter.__index = Adapter

--- Create an error message for unimplemented methods
--- @param method_name string The name of the method that wasn't implemented
--- @param adapter table|nil Optional adapter instance to identify the adapter type
--- @return string error_message
local function not_implemented(method_name, adapter)
  local adapter_info = ""
  if adapter then
    -- Try to get a useful identifier for the adapter
    local adapter_type = type(adapter)
    if adapter_type == "table" then
      -- Check for common identifier fields
      if adapter.name then
        adapter_info = string.format(" (adapter: %s)", adapter.name)
      elseif adapter._type then
        adapter_info = string.format(" (adapter type: %s)", adapter._type)
      else
        -- Try to identify by metatable
        local mt = getmetatable(adapter)
        if mt and mt.__name then
          adapter_info = string.format(" (adapter: %s)", mt.__name)
        end
      end
    end
  end

  return string.format(
    "Abstract method '%s' must be implemented by adapter%s. " ..
    "This adapter did not provide an implementation.",
    method_name,
    adapter_info
  )
end

--- User Feedback: Display a notification message
--- @param message string The message to display
--- @param level string|nil Severity level: "info", "warn", "error" (default: "info")
--- @return nil
function Adapter:notify(message, level)
	error(not_implemented("notify", self))
end

--- @return integer
function Adapter:get_current_buffer()
	return false -- not implemented
end

--- @param bufnr number Buffer number (0 for current buffer)
--- @return integer
function Adapter:buf_line_count(bufnr)
	return false -- not implemented
end

--- Buffer I/O: Read the current buffer/file contents
--- @param bufnr number Buffer number (0 for current buffer)
--- @param opts table|nil Optional arguments: {start: number, _end: number} (defaults: start=0, _end=-1)
--- @return table lines Array of strings, one per line
function Adapter:read_buffer(bufnr, opts)
  error(not_implemented("read_buffer", self))
end

--- Buffer I/O: Write lines to the current buffer/file
--- @param lines table Array of strings to write
--- @param opts table|nil Optional arguments: {bufnr: number, start: number, _end: number} (defaults: bufnr=current, start=0, _end=-1)
--- @return nil
function Adapter:write_buffer(lines, opts)
  error(not_implemented("write_buffer", self))
end

--- Cursor Management: Get current cursor position
--- @return number line 1-indexed line number
--- @return number col 0-indexed column number
function Adapter:get_cursor()
  error(not_implemented("get_cursor", self))
end

--- Cursor Management: Set cursor position
--- @param line number 1-indexed line number
--- @param col number 0-indexed column number
--- @return nil
function Adapter:set_cursor(line, col)
  error(not_implemented("set_cursor", self))
end

--- UI Prompts: Prompt user for text input
--- @param prompt string The prompt message to display
--- @param default string|nil Default value for input
--- @param callback function Callback receiving the input: function(input)
--- @return nil
function Adapter:prompt_input(prompt, default, callback)
  error(not_implemented("prompt_input", self))
end

--- UI Prompts: Prompt user to select from a list of items
--- @param items table Array of items to choose from
--- @param opts table|nil Options table with optional 'prompt' and 'format_item' fields
--- @param callback function Callback receiving selected item and index: function(item, idx)
--- @return nil
function Adapter:prompt_select(items, opts, callback)
  error(not_implemented("prompt_select", self))
end

--- Optional: Virtual Text Support
--- Some adapters (like Neovim) support virtual text/extmarks for inline display.
--- Other adapters (CLI, web) may not support this and should return false.
---
--- @return boolean true if adapter supports virtual text operations
function Adapter:supports_virtual_text()
  return false  -- Default: not supported
end

--- Optional: Create a namespace for virtual text (only if supported)
--- @param name string Namespace identifier
--- @return number|nil namespace_id Platform-specific namespace identifier, or nil if unsupported
function Adapter:create_namespace(name)
  return nil  -- Default: not supported
end

--- Optional: Set virtual text at a specific position (only if supported)
--- @param bufnr number Buffer number
--- @param ns number Namespace ID
--- @param line number 0-indexed line number
--- @param col number 0-indexed column number
--- @param opts table Options table with 'virt_text', 'virt_text_pos', etc.
--- @return number|nil extmark_id Extmark identifier, or nil if unsupported
function Adapter:set_extmark(bufnr, ns, line, col, opts)
  return nil  -- Default: not supported
end

--- Optional: Clear all virtual text in a namespace (only if supported)
--- @param bufnr number Buffer number
--- @param ns number Namespace ID
--- @return nil
function Adapter:clear_namespace(bufnr, ns)
  -- Default: no-op
end

--- Validate that an adapter implements all required methods
--- @param adapter table The adapter instance to validate
--- @return boolean is_valid
--- @return string|nil error_message
function Adapter.validate(adapter)
  local required_methods = {
    "notify",
    "read_buffer",
    "write_buffer",
    "get_cursor",
    "set_cursor",
    "prompt_input",
    "prompt_select",
  }

  for _, method in ipairs(required_methods) do
    if type(adapter[method]) ~= "function" then
      return false, string.format("Adapter missing required method: %s", method)
    end
  end

  return true, nil
end

--- Create a new adapter instance (for inheritance)
--- This is called by concrete adapters to establish the prototype chain.
---
--- @param implementation table Table containing method implementations
--- @return table adapter New adapter instance with interface methods
---
--- @usage
--- local MyAdapter = Adapter.new({
---   notify = function(self, message, level)
---     print(string.format("[%s] %s", level or "info", message))
---   end,
---   -- ... other implementations
--- })
function Adapter.new(implementation)
  local instance = implementation or {}
  setmetatable(instance, Adapter)

  -- Validate that required methods are implemented
  local is_valid, error_message = Adapter.validate(instance)
  if not is_valid then
    error(error_message)
  end

  return instance
end

return Adapter
