-- tests/unit/adapters/cli_error_paths_spec.lua
-- The CLI's error paths: input it cannot read, output it cannot write, and
-- input that is readable but is not the board the caller expected.
--
-- Everything the adapter reports goes to stderr, so each test captures both
-- streams: what was said, and that nothing leaked onto stdout, which carries
-- board data.
require('polyfills.vim')

local Board = require('kanban-md.board')
local CLIAdapter = require('kanban-md.adapters.cli')

local INFO_PREFIX = "\226\132\185\239\184\143 "   -- U+2139 U+FE0F
local WARN_PREFIX = "\226\154\160\239\184\143 "   -- U+26A0 U+FE0F
local ERROR_PREFIX = "\226\157\140 "              -- U+274C

describe("CLI error paths", function()
  local real_stderr, real_stdout
  local captured_err, captured_out

  before_each(function()
    captured_err, captured_out = {}, {}

    real_stderr, real_stdout = io.stderr, io.stdout
    io.stderr = {
      write = function(_, text) table.insert(captured_err, text) end,
      flush = function() end,
    }
    io.stdout = {
      write = function(_, text) table.insert(captured_out, text) end,
      flush = function() end,
    }

    CLIAdapter._buffer_lines = {}
    CLIAdapter._buffer_filename = nil
  end)

  after_each(function()
    io.stderr, io.stdout = real_stderr, real_stdout
    CLIAdapter._buffer_lines = {}
    CLIAdapter._buffer_filename = nil
  end)

  local function stderr_output()
    return table.concat(captured_err)
  end

  local function stdout_output()
    return table.concat(captured_out)
  end

  describe("unreadable input", function()
    it("returns no lines and reports the failure at error level", function()
      local lines = CLIAdapter:read_buffer(1, { file = "/nonexistent/dir/board.md" })

      assert.same({}, lines)
      assert.equals(
        ERROR_PREFIX .. "Failed to read file: /nonexistent/dir/board.md " ..
        "(/nonexistent/dir/board.md: No such file or directory)\n",
        stderr_output()
      )
    end)

    it("says nothing on stdout", function()
      CLIAdapter:read_buffer(1, { file = "/nonexistent/dir/board.md" })

      assert.equals("", stdout_output())
    end)

    it("leaves the internal buffer and filename as they were", function()
      CLIAdapter._buffer_lines = { "Previously read line" }
      CLIAdapter._buffer_filename = "/tmp/previous.md"

      CLIAdapter:read_buffer(1, { file = "/nonexistent/dir/board.md" })

      assert.same({ "Previously read line" }, CLIAdapter._buffer_lines)
      assert.equals("/tmp/previous.md", CLIAdapter:get_buffer_name(1))
    end)

    it("reports a directory given where a file was expected", function()
      -- io.open() succeeds on a directory; the failure comes at the first read.
      local lines = CLIAdapter:read_buffer(1, { file = "lua" })

      assert.same({}, lines)
      assert.matches("^" .. ERROR_PREFIX .. "Failed to read file: lua %(", stderr_output())
      assert.equals("", stdout_output())
    end)
  end)

  describe("unwritable output", function()
    it("reports the failure at error level and writes nothing", function()
      CLIAdapter:write_buffer({ "# Board" }, { file = "/nonexistent/dir/board.md" })

      assert.matches(
        "^" .. ERROR_PREFIX .. "Failed to write file: /nonexistent/dir/board%.md %(",
        stderr_output()
      )
      assert.equals("", stdout_output())
    end)

    it("does not report a successful write as a failure", function()
      local temp_file = os.tmpname()

      CLIAdapter:write_buffer({ "# Board" }, { file = temp_file })
      os.remove(temp_file)

      assert.equals(INFO_PREFIX .. "Wrote 1 lines to " .. temp_file .. "\n", stderr_output())
    end)
  end)

  describe("empty input", function()
    it("parses an empty line list into an empty board", function()
      local board = Board:new()

      board:parse({})

      assert.equals(0, #board.columns)
      assert.equals("Untitled Board", board.title)
    end)

    it("writes an empty board back without raising", function()
      local board = Board:new()
      board:parse({})

      local lines = board:write()

      assert.equals("# Untitled Board", lines[1])
    end)

    it("reads an empty file as no lines", function()
      local temp_file = os.tmpname()
      io.open(temp_file, "w"):close()

      local lines = CLIAdapter:read_buffer(1, { file = temp_file })

      os.remove(temp_file)
      assert.same({}, lines)
      assert.equals("", stderr_output())
    end)

    it("calculates stats and validates an empty board", function()
      local board = Board:new()
      board:parse({})

      board:calculate_stats()

      assert.is_true(board:validate())
    end)
  end)

  describe("input that is not a board", function()
    it("parses prose without raising and without inventing columns", function()
      local board = Board:new()

      board:parse({ "Just some prose", "", "and a second paragraph" })

      assert.equals(0, #board.columns)
      assert.equals("Untitled Board", board.title)
    end)

    it("keeps the prose, so writing it back does not destroy the file", function()
      local board = Board:new()
      board:parse({ "Just some prose", "", "and a second paragraph" })

      local written = table.concat(board:write(), "\n")

      assert.is_truthy(written:find("Just some prose", 1, true))
      assert.is_truthy(written:find("and a second paragraph", 1, true))
    end)

    it("parses a board with no title", function()
      local board = Board:new()

      board:parse({ "###### To Do", "- A card" })

      assert.equals(1, #board.columns)
      assert.equals(1, #board.columns[1].cards)
    end)
  end)

  describe("malformed board config", function()
    it("keeps a non-numeric wip_limit and reports it instead of raising", function()
      local board = Board:new()
      board:parse({ "# Board", "<!-- kanban:config wip_limit: none -->", "###### To Do", "- A card" })

      board:calculate_stats()
      local valid = board:validate()

      assert.equals("none", board.config.wip_limit)
      assert.is_true(valid)
      assert.same({ "Ignoring non-numeric board wip_limit 'none'" }, board.validation.warnings)
    end)

    it("reports a non-numeric column wip_limit against the column", function()
      local board = Board:new()
      board:parse({ "# Board", "###### To Do", "<!-- column:config wip_limit: lots -->", "- A card" })

      board:calculate_stats()
      board:validate()

      assert.same(
        { "Ignoring non-numeric wip_limit 'lots' on column 'To Do'" },
        board.validation.warnings
      )
    end)

    it("preserves the authored value through a round trip", function()
      local board = Board:new()
      board:parse({ "# Board", "<!-- kanban:config wip_limit: none -->", "###### To Do" })

      local written = table.concat(board:write(), "\n")

      assert.is_truthy(written:find("wip_limit: none", 1, true))
    end)

    it("accepts a quoted number as a number", function()
      local board = Board:new()
      board:parse({ "# Board", '<!-- kanban:config wip_limit: "7" -->', "###### To Do" })

      board:calculate_stats()
      board:validate()

      assert.equals(7, board.config.wip_limit)
      assert.same({}, board.validation.warnings)
    end)

    it("still enforces a numeric limit", function()
      local board = Board:new()
      board:parse({ "# Board", "<!-- kanban:config wip_limit: 1 -->", "###### To Do", "- One", "- Two" })

      board:calculate_stats()
      local valid = board:validate()

      assert.is_false(valid)
      assert.same({ "Board WIP limit exceeded: 2/1" }, board.validation.warnings)
    end)

    it("does not warn when there is no wip_limit at all", function()
      local board = Board:new()
      board:parse({ "# Board", "###### To Do", "- A card" })

      board:calculate_stats()
      board:validate()

      assert.same({}, board.validation.warnings)
    end)
  end)

  describe("notify levels", function()
    it("uses the documented prefix for each level", function()
      CLIAdapter:notify("info message", "info")
      CLIAdapter:notify("warn message", "warn")
      CLIAdapter:notify("error message", "error")

      assert.equals(
        INFO_PREFIX .. "info message\n" ..
        WARN_PREFIX .. "warn message\n" ..
        ERROR_PREFIX .. "error message\n",
        stderr_output()
      )
      assert.equals("", stdout_output())
    end)
  end)
end)
