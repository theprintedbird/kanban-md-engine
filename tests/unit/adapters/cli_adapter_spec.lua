-- tests/unit/adapters/cli_adapter_spec.lua
-- Unit tests for CLI adapter functionality

_G._TEST = true

local CLIAdapter = require("kanban-md.adapters.cli")

-- CLIAdapter is a module singleton shared by every spec file in a `busted`
-- run, and tests further down this file deliberately move its cursor and fill
-- its internal buffer. Snapshot the as-loaded state here, at require time and
-- before any test body has run, so the "initialisation" assertions below
-- describe the module's actual initial state rather than whatever the most
-- recently executed test happened to leave behind (which made them fail under
-- `busted --shuffle`).
local initial_cursor_line, initial_cursor_col = CLIAdapter:get_cursor()
local initial_buffer_line_count = #CLIAdapter._buffer_lines

describe("CLIAdapter", function()
  describe("initialisation", function()
    it("should have correct adapter name", function()
      assert.equals("CLIAdapter", CLIAdapter.name)
    end)

    it("should initialise with default cursor position", function()
      assert.equals(1, initial_cursor_line)
      assert.equals(0, initial_cursor_col)
    end)

    it("should initialise with empty internal buffer", function()
      assert.equals(0, initial_buffer_line_count)
    end)

    it("should report no virtual text support", function()
      assert.is_false(CLIAdapter:supports_virtual_text())
    end)

    it("should have all required interface methods", function()
      assert.is_function(CLIAdapter.notify)
      assert.is_function(CLIAdapter.read_buffer)
      assert.is_function(CLIAdapter.write_buffer)
      assert.is_function(CLIAdapter.get_cursor)
      assert.is_function(CLIAdapter.set_cursor)
      assert.is_function(CLIAdapter.prompt_input)
      assert.is_function(CLIAdapter.prompt_select)
      assert.is_function(CLIAdapter.supports_virtual_text)
      assert.is_function(CLIAdapter.create_namespace)
      assert.is_function(CLIAdapter.set_extmark)
      assert.is_function(CLIAdapter.clear_namespace)
    end)
  end)

  describe("notify()", function()
    local old_stderr, old_stdout
    local captured_err, captured_out

    -- Capture both streams so each test can assert the exact bytes written to
    -- stderr *and* that nothing leaked onto stdout, which carries board data.
    before_each(function()
      captured_err, captured_out = {}, {}

      old_stderr = io.stderr
      io.stderr = {
        write = function(self, msg) table.insert(captured_err, msg) end,
        flush = function(self) end,
      }

      old_stdout = io.stdout
      io.stdout = {
        write = function(self, msg) table.insert(captured_out, msg) end,
        flush = function(self) end,
      }
    end)

    after_each(function()
      io.stderr = old_stderr
      io.stdout = old_stdout
    end)

    local function stderr_output()
      return table.concat(captured_err, "")
    end

    it("should prefix info level notifications with the info emoji", function()
      CLIAdapter:notify("Test info message", "info")

      assert.equals("ℹ️ Test info message\n", stderr_output())
    end)

    it("should prefix warn level notifications with the warning emoji", function()
      CLIAdapter:notify("Test warning", "warn")

      assert.equals("⚠️ Test warning\n", stderr_output())
    end)

    it("should prefix error level notifications with the error emoji", function()
      CLIAdapter:notify("Test error", "error")

      assert.equals("❌ Test error\n", stderr_output())
    end)

    it("should default to info level when level not specified", function()
      CLIAdapter:notify("Default level message")

      assert.equals("ℹ️ Default level message\n", stderr_output())
    end)

    it("should emit valid UTF-8 prefixes, not mojibake", function()
      CLIAdapter:notify("m", "info")
      CLIAdapter:notify("m", "warn")
      CLIAdapter:notify("m", "error")

      local output = stderr_output()

      -- U+FFFD (replacement character) and stray control bytes are the
      -- signature of the corruption these prefixes used to carry.
      assert.is_nil(output:find("�", 1, true))
      assert.is_nil(output:find("[%z\1-\9\11-\31]"))
    end)

    it("should use no prefix for an unrecognised level", function()
      CLIAdapter:notify("Mystery level", "trace")

      assert.equals(" Mystery level\n", stderr_output())
    end)

    it("should include newline at end of message", function()
      CLIAdapter:notify("Message with newline", "info")

      assert.is_not_nil(stderr_output():match("\n$"))
    end)

    it("should route every level to stderr, never stdout", function()
      CLIAdapter:notify("info msg", "info")
      CLIAdapter:notify("warn msg", "warn")
      CLIAdapter:notify("error msg", "error")

      assert.equals(3, #captured_err)
      assert.equals(0, #captured_out)
    end)
  end)

  describe("read_buffer()", function()
    local temp_file

    before_each(function()
      -- Reset internal buffer
      CLIAdapter._buffer_lines = {}
      temp_file = os.tmpname()
    end)

    after_each(function()
      if temp_file then
        os.remove(temp_file)
      end
    end)

    it("should read from file when file option provided", function()
      -- Write test content to file
      local f = io.open(temp_file, "w")
      f:write("Line 1\n")
      f:write("Line 2\n")
      f:write("Line 3\n")
      f:close()

      local lines = CLIAdapter:read_buffer(1, { file = temp_file })

      assert.equals(3, #lines)
      assert.equals("Line 1", lines[1])
      assert.equals("Line 2", lines[2])
      assert.equals("Line 3", lines[3])
    end)

    it("should store file content in internal buffer", function()
      local f = io.open(temp_file, "w")
      f:write("Stored line 1\n")
      f:write("Stored line 2\n")
      f:close()

      CLIAdapter:read_buffer(1, { file = temp_file })

      assert.equals(2, #CLIAdapter._buffer_lines)
      assert.equals("Stored line 1", CLIAdapter._buffer_lines[1])
      assert.equals("Stored line 2", CLIAdapter._buffer_lines[2])
    end)

    it("should read from internal buffer when no file specified", function()
      CLIAdapter._buffer_lines = { "Internal 1", "Internal 2", "Internal 3" }

      local lines = CLIAdapter:read_buffer(1, {})

      assert.equals(3, #lines)
      assert.equals("Internal 1", lines[1])
      assert.equals("Internal 2", lines[2])
      assert.equals("Internal 3", lines[3])
    end)

    it("should handle range selection with start and end", function()
      CLIAdapter._buffer_lines = { "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" }

      -- Read lines 2-4 (0-indexed: start=1 means line 2, _end=4 is exclusive so up to line 4)
      local lines = CLIAdapter:read_buffer(1, { start = 1, _end = 4 })

      -- Should return 3 lines: Line 2, Line 3, Line 4 (_end is exclusive like Neovim API)
      assert.equals(3, #lines)
      assert.equals("Line 2", lines[1])
      assert.equals("Line 3", lines[2])
      assert.equals("Line 4", lines[3])
    end)

    it("should handle start offset with -1 end (read to end)", function()
      CLIAdapter._buffer_lines = { "Line 1", "Line 2", "Line 3", "Line 4" }

      local lines = CLIAdapter:read_buffer(1, { start = 2, _end = -1 })

      assert.equals(2, #lines)
      assert.equals("Line 3", lines[1])
      assert.equals("Line 4", lines[2])
    end)

    it("should return empty table for non-existent file", function()
      local lines = CLIAdapter:read_buffer(1, { file = "/nonexistent/file.txt" })

      assert.equals(0, #lines)
    end)

    it("should handle empty file", function()
      local f = io.open(temp_file, "w")
      f:close()

      local lines = CLIAdapter:read_buffer(1, { file = temp_file })

      assert.equals(0, #lines)
    end)

    it("should handle file with trailing newline", function()
      local f = io.open(temp_file, "w")
      f:write("Line 1\n")
      f:write("Line 2\n")
      f:write("Line 3\n")
      f:close()

      local lines = CLIAdapter:read_buffer(1, { file = temp_file })

      -- Should read 3 lines (trailing newline creates no extra line)
      assert.equals(3, #lines)
    end)

    it("should handle file without trailing newline", function()
      local f = io.open(temp_file, "w")
      f:write("Line 1\n")
      f:write("Line 2\n")
      f:write("Line 3")
      f:close()

      local lines = CLIAdapter:read_buffer(1, { file = temp_file })

      assert.equals(3, #lines)
      assert.equals("Line 3", lines[3])
    end)
  end)

  describe("read_buffer() with opts.stdin", function()
    -- io.stdin is not readable under `busted`, so the branch is exercised by
    -- swapping in a stand-in with the one method the adapter uses (:lines()).
    -- The final test pipes through a real process instead, so the stand-in is
    -- checked against the real thing rather than trusted on its own.
    local real_stdin

    --- An io.stdin stand-in yielding the given lines.
    local function fake_stdin(lines)
      return {
        lines = function()
          local i = 0
          return function()
            i = i + 1
            return lines[i]
          end
        end,
      }
    end

    before_each(function()
      real_stdin = io.stdin
      CLIAdapter._buffer_lines = {}
    end)

    after_each(function()
      io.stdin = real_stdin
      CLIAdapter._buffer_lines = {}
    end)

    it("should read every line from stdin", function()
      io.stdin = fake_stdin({ "# Board", "", "###### To Do" })

      local lines = CLIAdapter:read_buffer(1, { stdin = true })

      assert.same({ "# Board", "", "###### To Do" }, lines)
    end)

    it("should store what it read in the internal buffer", function()
      io.stdin = fake_stdin({ "Line 1", "Line 2" })

      CLIAdapter:read_buffer(1, { stdin = true })

      assert.same({ "Line 1", "Line 2" }, CLIAdapter._buffer_lines)
      assert.equals(2, CLIAdapter:buf_line_count(1))
    end)

    it("should not set a buffer filename", function()
      CLIAdapter._buffer_filename = nil
      io.stdin = fake_stdin({ "Line 1" })

      CLIAdapter:read_buffer(1, { stdin = true })

      assert.is_nil(CLIAdapter:get_buffer_name(1))
    end)

    it("should return an empty table for empty stdin", function()
      io.stdin = fake_stdin({})

      assert.same({}, CLIAdapter:read_buffer(1, { stdin = true }))
    end)

    it("should honour a start/_end range over stdin content", function()
      io.stdin = fake_stdin({ "Line 1", "Line 2", "Line 3", "Line 4" })

      -- start is 0-indexed, _end is 1-indexed and inclusive.
      local lines = CLIAdapter:read_buffer(1, { stdin = true, start = 1, _end = 3 })

      assert.same({ "Line 2", "Line 3" }, lines)
    end)

    it("should prefer opts.file when both file and stdin are given", function()
      local temp_file = os.tmpname()
      local f = io.open(temp_file, "w")
      f:write("From the file\n")
      f:close()
      io.stdin = fake_stdin({ "From stdin" })

      local lines = CLIAdapter:read_buffer(1, { file = temp_file, stdin = true })

      os.remove(temp_file)
      assert.same({ "From the file" }, lines)
    end)

    it("should read a board piped into a real process", function()
      -- The stand-in above cannot show that io.stdin:lines() is the right call
      -- for an actual pipe; this does, in the CLI's primary input shape.
      local script = table.concat({
        "package.path = 'lua/?.lua;lua/?/init.lua;' .. package.path",
        "local a = require('kanban-md.adapters.cli')",
        "local lines = a:read_buffer(1, { stdin = true })",
        "io.stdout:write(#lines .. '|' .. table.concat(lines, ','))",
      }, "; ")

      -- $LUA lets a CI matrix point this at the interpreter under test; the
      -- test skips itself rather than failing where there is no standalone
      -- one on PATH (busted's own arg[-1] is a -e chunk, not a usable path).
      local interpreter = os.getenv("LUA") or "lua"
      local probe = io.popen(interpreter .. " -v 2>/dev/null", "r")
      local available = probe:read("*a") ~= ""
      probe:close()

      if not available then
        return pending("no standalone " .. interpreter .. " interpreter on PATH")
      end

      local command = string.format(
        "printf '%%s\\n' '# Board' '###### To Do' | %s -e %q 2>/dev/null",
        interpreter,
        script
      )

      local process = io.popen(command, "r")
      local output = process:read("*a")
      process:close()

      assert.equals("2|# Board,###### To Do", output)
    end)
  end)

  describe("write_buffer()", function()
    local temp_file
    local old_stderr

    before_each(function()
      CLIAdapter._buffer_lines = {}
      temp_file = os.tmpname()

      -- Suppress notifications
      old_stderr = io.stderr
      io.stderr = {
        write = function(self, ...) end,
        flush = function(self) end,
      }
    end)

    after_each(function()
      if temp_file then
        os.remove(temp_file)
      end
      io.stderr = old_stderr
    end)

    it("should write to file when file option provided", function()
      local lines = { "Output 1", "Output 2", "Output 3" }

      CLIAdapter:write_buffer(lines, { file = temp_file })

      -- Read back and verify
      local f = io.open(temp_file, "r")
      local content = f:read("*a")
      f:close()

      assert.is_not_nil(content:match("Output 1"))
      assert.is_not_nil(content:match("Output 2"))
      assert.is_not_nil(content:match("Output 3"))
    end)

    it("should write each line with newline separator", function()
      local lines = { "Line A", "Line B" }

      CLIAdapter:write_buffer(lines, { file = temp_file })

      local f = io.open(temp_file, "r")
      local content = f:read("*a")
      f:close()

      -- Count newlines
      local _, newline_count = content:gsub("\n", "")
      assert.equals(2, newline_count)
    end)

    it("should update internal buffer when no file specified", function()
      local lines = { "Internal A", "Internal B", "Internal C" }

      CLIAdapter:write_buffer(lines, {})

      assert.equals(3, #CLIAdapter._buffer_lines)
      assert.equals("Internal A", CLIAdapter._buffer_lines[1])
      assert.equals("Internal B", CLIAdapter._buffer_lines[2])
      assert.equals("Internal C", CLIAdapter._buffer_lines[3])
    end)

    it("should handle range replacement in internal buffer", function()
      CLIAdapter._buffer_lines = { "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" }

      -- Replace lines 2-3 (0-indexed: start=1, _end=3)
      local new_lines = { "New A", "New B" }
      CLIAdapter:write_buffer(new_lines, { start = 1, _end = 3 })

      -- Should now have: Line 1, New A, New B, Line 4, Line 5
      assert.equals(5, #CLIAdapter._buffer_lines)
      assert.equals("Line 1", CLIAdapter._buffer_lines[1])
      assert.equals("New A", CLIAdapter._buffer_lines[2])
      assert.equals("New B", CLIAdapter._buffer_lines[3])
      assert.equals("Line 4", CLIAdapter._buffer_lines[4])
      assert.equals("Line 5", CLIAdapter._buffer_lines[5])
    end)

    it("should append to internal buffer with start at end", function()
      CLIAdapter._buffer_lines = { "Existing 1", "Existing 2" }

      local new_lines = { "Appended 1", "Appended 2" }
      CLIAdapter:write_buffer(new_lines, { start = 2, _end = -1 })

      assert.equals(4, #CLIAdapter._buffer_lines)
      assert.equals("Existing 1", CLIAdapter._buffer_lines[1])
      assert.equals("Existing 2", CLIAdapter._buffer_lines[2])
      assert.equals("Appended 1", CLIAdapter._buffer_lines[3])
      assert.equals("Appended 2", CLIAdapter._buffer_lines[4])
    end)

    it("should handle empty line array", function()
      local lines = {}

      CLIAdapter:write_buffer(lines, { file = temp_file })

      local f = io.open(temp_file, "r")
      local content = f:read("*a")
      f:close()

      assert.equals("", content)
    end)

    it("should handle write failure for invalid path", function()
      local lines = { "Test line" }

      -- Should not crash, just notify error
      CLIAdapter:write_buffer(lines, { file = "/nonexistent/dir/file.txt" })

      -- Test passes if we reach here without error
      assert.is_true(true)
    end)

    it("should notify on successful file write", function()
      local notifications = {}
      io.stderr.write = function(self, msg)
        table.insert(notifications, msg)
      end

      local lines = { "Line 1", "Line 2" }
      CLIAdapter:write_buffer(lines, { file = temp_file })

      local output = table.concat(notifications, "")
      assert.is_not_nil(output:match("Wrote"))
      assert.is_not_nil(output:match("2 lines"))
    end)
  end)

  describe("cursor operations", function()
    before_each(function()
      -- Reset cursor
      CLIAdapter._cursor = { line = 1, col = 0 }
    end)

    it("should get current cursor position", function()
      CLIAdapter._cursor = { line = 5, col = 10 }

      local line, col = CLIAdapter:get_cursor()

      assert.equals(5, line)
      assert.equals(10, col)
    end)

    it("should set cursor position", function()
      CLIAdapter:set_cursor(15, 25)

      local line, col = CLIAdapter:get_cursor()

      assert.equals(15, line)
      assert.equals(25, col)
    end)

    it("should update cursor position multiple times", function()
      CLIAdapter:set_cursor(1, 0)
      assert.equals(1, (CLIAdapter:get_cursor()))

      CLIAdapter:set_cursor(5, 10)
      assert.equals(5, (CLIAdapter:get_cursor()))

      CLIAdapter:set_cursor(20, 5)
      assert.equals(20, (CLIAdapter:get_cursor()))
    end)

    it("should handle cursor at start of buffer", function()
      CLIAdapter:set_cursor(1, 0)

      local line, col = CLIAdapter:get_cursor()

      assert.equals(1, line)
      assert.equals(0, col)
    end)

    it("should allow arbitrary cursor positions", function()
      -- CLI adapter doesn't validate cursor position
      CLIAdapter:set_cursor(9999, 9999)

      local line, col = CLIAdapter:get_cursor()

      assert.equals(9999, line)
      assert.equals(9999, col)
    end)
  end)

  describe("prompt_input()", function()
    local old_stdin, old_stderr

    before_each(function()
      old_stdin = io.stdin
      old_stderr = io.stderr

      io.stderr = {
        write = function(self, ...) end,
        flush = function(self) end,
      }
    end)

    after_each(function()
      io.stdin = old_stdin
      io.stderr = old_stderr
    end)

    it("should call callback with user input", function()
      io.stdin = {
        read = function(self, format)
          return "User typed this"
        end,
      }

      local result = nil
      CLIAdapter:prompt_input("Enter text", nil, function(input)
        result = input
      end)

      assert.equals("User typed this", result)
    end)

    it("should use default value when input is empty", function()
      io.stdin = {
        read = function(self, format)
          return ""
        end,
      }

      local result = nil
      CLIAdapter:prompt_input("Enter text", "default value", function(input)
        result = input
      end)

      assert.equals("default value", result)
    end)

    it("should use default value when input is nil", function()
      io.stdin = {
        read = function(self, format)
          return nil
        end,
      }

      local result = nil
      CLIAdapter:prompt_input("Enter text", "fallback", function(input)
        result = input
      end)

      assert.equals("fallback", result)
    end)

    it("should override default with non-empty input", function()
      io.stdin = {
        read = function(self, format)
          return "override"
        end,
      }

      local result = nil
      CLIAdapter:prompt_input("Enter text", "default", function(input)
        result = input
      end)

      assert.equals("override", result)
    end)

    it("should handle callback being nil", function()
      io.stdin = {
        read = function(self, format)
          return "test"
        end,
      }

      -- Should not crash when callback is nil
      CLIAdapter:prompt_input("Prompt", nil, nil)

      assert.is_true(true)
    end)

    it("should display prompt to stderr", function()
      local stderr_output = {}
      io.stderr.write = function(self, msg)
        table.insert(stderr_output, msg)
      end

      io.stdin = {
        read = function(self, format)
          return "test"
        end,
      }

      CLIAdapter:prompt_input("Enter your name", nil, function() end)

      local output = table.concat(stderr_output, "")
      assert.is_not_nil(output:match("Enter your name"))
    end)
  end)

  describe("prompt_select()", function()
    local old_stdin, old_stderr

    before_each(function()
      old_stdin = io.stdin
      old_stderr = io.stderr

      io.stderr = {
        write = function(self, ...) end,
        flush = function(self) end,
      }
    end)

    after_each(function()
      io.stdin = old_stdin
      io.stderr = old_stderr
    end)

    it("should call callback with selected item", function()
      io.stdin = {
        read = function(self, format)
          return "2"
        end,
      }

      local items = { "Option A", "Option B", "Option C" }
      local selected_item, selected_idx

      CLIAdapter:prompt_select(items, {}, function(item, idx)
        selected_item = item
        selected_idx = idx
      end)

      assert.equals("Option B", selected_item)
      assert.equals(2, selected_idx)
    end)

    it("should return nil for invalid selection", function()
      io.stdin = {
        read = function(self, format)
          return "99"
        end,
      }

      local items = { "Option A", "Option B" }
      local selected_item, selected_idx

      CLIAdapter:prompt_select(items, {}, function(item, idx)
        selected_item = item
        selected_idx = idx
      end)

      assert.is_nil(selected_item)
      assert.is_nil(selected_idx)
    end)

    it("should return nil when user cancels with 0", function()
      io.stdin = {
        read = function(self, format)
          return "0"
        end,
      }

      local items = { "Option A", "Option B" }
      local selected_item, selected_idx

      CLIAdapter:prompt_select(items, {}, function(item, idx)
        selected_item = item
        selected_idx = idx
      end)

      assert.is_nil(selected_item)
      assert.is_nil(selected_idx)
    end)

    it("should return nil for non-numeric input", function()
      io.stdin = {
        read = function(self, format)
          return "abc"
        end,
      }

      local items = { "Option A" }
      local selected_item

      CLIAdapter:prompt_select(items, {}, function(item, idx)
        selected_item = item
      end)

      assert.is_nil(selected_item)
    end)

    it("should use custom format_item function", function()
      local stderr_output = {}
      io.stderr.write = function(self, msg)
        table.insert(stderr_output, msg)
      end

      io.stdin = {
        read = function(self, format)
          return "1"
        end,
      }

      local items = { { name = "Alice" }, { name = "Bob" } }

      CLIAdapter:prompt_select(items, {
        format_item = function(item)
          return "Name: " .. item.name
        end,
      }, function() end)

      local output = table.concat(stderr_output, "")
      assert.is_not_nil(output:match("Name: Alice"))
      assert.is_not_nil(output:match("Name: Bob"))
    end)

    it("should use custom prompt message", function()
      local stderr_output = {}
      io.stderr.write = function(self, msg)
        table.insert(stderr_output, msg)
      end

      io.stdin = {
        read = function(self, format)
          return "1"
        end,
      }

      local items = { "A", "B" }

      CLIAdapter:prompt_select(items, {
        prompt = "Choose your option:",
      }, function() end)

      local output = table.concat(stderr_output, "")
      assert.is_not_nil(output:match("Choose your option:"))
    end)

    it("should handle single item selection", function()
      io.stdin = {
        read = function(self, format)
          return "1"
        end,
      }

      local items = { "Only Option" }
      local selected_item

      CLIAdapter:prompt_select(items, {}, function(item, idx)
        selected_item = item
      end)

      assert.equals("Only Option", selected_item)
    end)
  end)

  describe("buffer management", function()
    it("should return fixed buffer number for CLI", function()
      local bufnr = CLIAdapter:get_current_buffer()
      assert.equals(1, bufnr)
    end)

    it("should return correct line count from internal buffer", function()
      CLIAdapter._buffer_lines = { "Line 1", "Line 2", "Line 3" }

      local count = CLIAdapter:buf_line_count(1)

      assert.equals(3, count)
    end)

    it("should return zero for empty buffer", function()
      CLIAdapter._buffer_lines = {}

      local count = CLIAdapter:buf_line_count(1)

      assert.equals(0, count)
    end)
  end)

  describe("virtual text operations (no-op)", function()
    it("should return nil for create_namespace", function()
      local ns = CLIAdapter:create_namespace("test")
      assert.is_nil(ns)
    end)

    it("should return nil for set_extmark", function()
      local id = CLIAdapter:set_extmark(1, 1, 0, 0, {})
      assert.is_nil(id)
    end)

    it("should not crash on clear_namespace", function()
      CLIAdapter:clear_namespace(1, 1)
      -- Test passes if we reach here
      assert.is_true(true)
    end)
  end)
end)
