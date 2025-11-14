--- CLI Adapter Implementation
--- Provides a command-line interface adapter for kanban-md
--- Uses simple print/io for user interaction, suitable for standalone Lua execution
---
--- @class CLIAdapter : Adapter
local Adapter = require("kanban-md.adapters.interface")

--- Internal state for CLI adapter
local CLIAdapter = Adapter.new({
  name = "CLIAdapter",

  --- Cursor tracking for CLI adapter (simple line tracking)
  _cursor = { line = 1, col = 0 },

  --- Buffer storage (for in-memory buffer operations)
  _buffer_lines = {},

  --- Buffer filename tracking
  _buffer_filename = nil,

  --- User Feedback: Display a notification message with emoji prefixes
  --- @param message string The message to display
  --- @param level string|nil Severity level: "info", "warn", "error" (default: "info")
  --- @return nil
  notify = function(self, message, level)
    level = level or "info"
    local prefix = ""

    -- Select emoji prefix based on level
    if level == "info" then
      prefix = "9 "
    elseif level == "warn" then
      prefix = "� "
    elseif level == "error" then
      prefix = "L"
    end

    -- Print to stderr for better separation from data output
    io.stderr:write(prefix .. " " .. message .. "\n")
    io.stderr:flush()
  end,

  --- Get the current buffer number (always returns 1 for CLI)
  --- @return integer
  get_current_buffer = function(self)
    return 1 -- CLI only has one "buffer"
  end,

  --- Get buffer name/filename
  --- @param bufnr number Buffer number (ignored in CLI)
  --- @return string|nil The filename if available
  get_buffer_name = function(self, bufnr)
    return self._buffer_filename or nil
  end,

  --- Get buffer line count
  --- @param bufnr number Buffer number (ignored in CLI)
  --- @return integer
  buf_line_count = function(self, bufnr)
    return #self._buffer_lines
  end,

  --- Buffer I/O: Read buffer contents from file or internal storage
  --- @param bufnr number Buffer number (ignored in CLI)
  --- @param opts table|nil Optional arguments: {start: number, _end: number, file: string}
  --- @return table lines Array of strings, one per line
  read_buffer = function(self, bufnr, opts)
    opts = opts or {}
    local start = opts.start or 0 -- 0-indexed
    local _end = opts._end or -1
    local file = opts.file

    local lines = {}

    -- Read from file if specified
    if file then
      local f, err = io.open(file, "r")
      if not f then
        self:notify("Failed to read file: " .. file .. " (" .. err .. ")", "error")
        return {}
      end

      for line in f:lines() do
        table.insert(lines, line)
      end
      f:close()

      -- Store in internal buffer and filename for potential modifications
      self._buffer_lines = lines
      self._buffer_filename = file
    elseif opts.stdin then
      -- Read from stdin if specified
      for line in io.stdin:lines() do
        table.insert(lines, line)
      end
      self._buffer_lines = lines
    else
      -- Use internal buffer
      lines = self._buffer_lines
    end

    -- Handle range selection (Lua uses 1-indexed, but API uses 0-indexed)
    local result = {}
    local actual_start = start + 1 -- Convert to 1-indexed
    local actual_end = _end

    if actual_end == -1 then
      actual_end = #lines
    end

    for i = actual_start, actual_end do
      table.insert(result, lines[i] or "")
    end

    return result
  end,

  --- Buffer I/O: Write lines to file, stdout, or internal storage
  --- @param lines table Array of strings to write
  --- @param opts table|nil Optional arguments: {bufnr: number, start: number, _end: number, file: string, stdout: boolean}
  --- @return nil
  write_buffer = function(self, lines, opts)
    opts = opts or {}
    local file = opts.file
    local to_stdout = opts.stdout

    if to_stdout then
      -- Write to stdout
      for _, line in ipairs(lines) do
        io.stdout:write(line .. "\n")
      end
      io.stdout:flush()
    elseif file then
      -- Write to file
      local f, err = io.open(file, "w")
      if not f then
        self:notify("Failed to write file: " .. file .. " (" .. err .. ")", "error")
        return
      end

      for _, line in ipairs(lines) do
        f:write(line .. "\n")
      end
      f:close()
      self:notify("Wrote " .. #lines .. " lines to " .. file, "info")
    else
      -- Update internal buffer (handling range replacement)
      local start = opts.start or 0
      local _end = opts._end or -1

      -- Convert to 1-indexed
      local actual_start = start + 1
      local actual_end = _end == -1 and #self._buffer_lines or _end

      -- Remove old lines in range
      for i = actual_end, actual_start, -1 do
        table.remove(self._buffer_lines, i)
      end

      -- Insert new lines
      for i, line in ipairs(lines) do
        table.insert(self._buffer_lines, actual_start + i - 1, line)
      end
    end
  end,

  --- Cursor Management: Get current cursor position
  --- @return number line 1-indexed line number
  --- @return number col 0-indexed column number
  get_cursor = function(self)
    return self._cursor.line, self._cursor.col
  end,

  --- Cursor Management: Set cursor position
  --- @param line number 1-indexed line number
  --- @param col number 0-indexed column number
  --- @return nil
  set_cursor = function(self, line, col)
    self._cursor.line = line
    self._cursor.col = col
  end,

  --- UI Prompts: Prompt user for text input using readline
  --- @param prompt string The prompt message to display
  --- @param default string|nil Default value for input
  --- @param callback function Callback receiving the input: function(input)
  --- @return nil
  prompt_input = function(self, prompt, default, callback)
    -- Display prompt to stderr (keeps stdout clean for data)
    io.stderr:write(prompt)
    if default then
      io.stderr:write(" [" .. default .. "]")
    end
    io.stderr:write(": ")
    io.stderr:flush()

    -- Read from stdin
    local input = io.stdin:read("*l")

    -- Use default if input is empty
    if not input or input == "" then
      input = default
    end

    -- Call callback with result
    if callback then
      callback(input)
    end
  end,

  --- UI Prompts: Prompt user to select from a list using numbered menu
  --- @param items table Array of items to choose from
  --- @param opts table|nil Options table with optional 'prompt' and 'format_item' fields
  --- @param callback function Callback receiving selected item and index: function(item, idx)
  --- @return nil
  prompt_select = function(self, items, opts, callback)
    opts = opts or {}
    local prompt = opts.prompt or "Select one of:"
    local format_item = opts.format_item or tostring

    -- Display prompt and numbered options
    io.stderr:write(prompt .. "\n")
    for i, item in ipairs(items) do
      io.stderr:write(string.format("  %d) %s\n", i, format_item(item)))
    end
    io.stderr:write("Enter number (or 0 to cancel): ")
    io.stderr:flush()

    -- Read selection
    local input = io.stdin:read("*l")
    local selection = tonumber(input)

    -- Validate selection
    if not selection or selection < 0 or selection > #items then
      -- Invalid selection or cancellation
      if callback then
        callback(nil, nil)
      end
      return
    end

    if selection == 0 then
      -- User cancelled
      if callback then
        callback(nil, nil)
      end
      return
    end

    -- Valid selection
    if callback then
      callback(items[selection], selection)
    end
  end,

  --- Optional: Virtual text is not supported in CLI
  --- @return boolean false
  supports_virtual_text = function(self)
    return false
  end,

  --- Optional: No-op for namespace creation
  --- @param name string Namespace identifier
  --- @return nil
  create_namespace = function(self, name)
    return nil
  end,

  --- Optional: No-op for extmark setting
  --- @param bufnr number Buffer number
  --- @param ns number Namespace ID
  --- @param line number 0-indexed line number
  --- @param col number 0-indexed column number
  --- @param opts table Options table
  --- @return nil
  set_extmark = function(self, bufnr, ns, line, col, opts)
    return nil
  end,

  --- Optional: No-op for namespace clearing
  --- @param bufnr number Buffer number
  --- @param ns number Namespace ID
  --- @return nil
  clear_namespace = function(self, bufnr, ns)
    -- No-op
  end,
})

return CLIAdapter
