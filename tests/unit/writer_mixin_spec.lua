-- tests/unit/writer_mixin_spec.lua
-- Tests for WriterMixin serialization functionality

require('polyfills.vim')

_G._TEST = true

local Board = require("kanban-md.board")
local config_module = require("kanban-md.config")

describe("WriterMixin serialization", function()
  -- Save original config and restore after each test
  local original_config

  before_each(function()
    original_config = vim.deepcopy(config_module.get())
  end)

  after_each(function()
    config_module.setup(original_config)
  end)

  describe("format_timestamp", function()
    local format_timestamp

    before_each(function()
      local WriterMixin = require("kanban-md.writer_mixin")
      format_timestamp = WriterMixin._private.format_timestamp
    end)

    it("should return nil for nil input", function()
      assert.is_nil(format_timestamp(nil))
    end)

    it("should format epoch timestamps by default", function()
      config_module.setup({ timestamp_format = "epoch" })
      local timestamp = 1609459200 -- 2021-01-01 00:00:00 UTC
      assert.are.equals("1609459200", format_timestamp(timestamp))
    end)

    it("should format ISO timestamps", function()
      config_module.setup({ timestamp_format = "iso" })
      local timestamp = 1609459200 -- 2021-01-01 00:00:00 UTC
      assert.are.equals("2021-01-01T00:00:00Z", format_timestamp(timestamp))
    end)

    it("should format date-only timestamps", function()
      config_module.setup({ timestamp_format = "date" })
      local timestamp = 1609459200 -- 2021-01-01 00:00:00 UTC
      assert.are.equals("2021-01-01", format_timestamp(timestamp))
    end)
  end)

  describe("format_property_value", function()
    local format_property_value

    before_each(function()
      local WriterMixin = require("kanban-md.writer_mixin")
      format_property_value = WriterMixin._private.format_property_value
    end)

    it("should format boolean values", function()
      assert.are.equals("true", format_property_value(true))
      assert.are.equals("false", format_property_value(false))
    end)

    it("should format regular numbers", function()
      assert.are.equals("42", format_property_value(42))
      assert.are.equals("3.14", format_property_value(3.14))
      assert.are.equals("0", format_property_value(0))
    end)

    it("should format timestamp numbers as timestamps", function()
      config_module.setup({ timestamp_format = "epoch" })
      local timestamp = 1609459200 -- 2021-01-01
      assert.are.equals("1609459200", format_property_value(timestamp))
    end)

    it("should format arrays", function()
      local array = {"tag1", "tag2", "tag3"}
      assert.are.equals("[tag1, tag2, tag3]", format_property_value(array))
    end)

    it("should format empty arrays", function()
      assert.are.equals("[]", format_property_value({}))
    end)

    it("should format strings", function()
      assert.are.equals("hello world", format_property_value("hello world"))
    end)

    it("should handle numeric arrays", function()
      local array = {1, 2, 3}
      assert.are.equals("[1, 2, 3]", format_property_value(array))
    end)
  end)

  describe("properties_to_comment", function()
    local properties_to_comment

    before_each(function()
      local WriterMixin = require("kanban-md.writer_mixin")
      properties_to_comment = WriterMixin._private.properties_to_comment
      config_module.setup({
        property_separator = ", ",
        use_multiline_comments = false
      })
    end)

    it("should return nil for nil properties", function()
      assert.is_nil(properties_to_comment(nil))
    end)

    it("should return nil for empty properties", function()
      assert.is_nil(properties_to_comment({}))
    end)

    it("should format single property", function()
      local props = { id = "abc123" }
      assert.are.equals("<!-- id: abc123 -->", properties_to_comment(props))
    end)

    it("should format multiple properties sorted by key", function()
      local props = { zebra = "z", alpha = "a", beta = "b" }
      assert.are.equals("<!-- alpha: a, beta: b, zebra: z -->", properties_to_comment(props))
    end)

    it("should add prefix when provided", function()
      local props = { wip_limit = 5 }
      -- Prefix is joined with a space, then properties are added with property_separator
      assert.are.equals("<!-- kanban:config wip_limit: 5 -->",
        properties_to_comment(props, "kanban:config"))
    end)

    it("should handle column:config prefix", function()
      local props = { wip_limit = 3, auto_assign = true }
      -- Exact: a loose ^<!-- column:config match would also accept a comma
      -- after the prefix, which is the one thing this must not emit.
      assert.are.equals("<!-- column:config auto_assign: true, wip_limit: 3 -->",
        properties_to_comment(props, "column:config"))
    end)

    it("should separate a prefix from the first property with a space, not the separator",
      function()
        -- SPEC.md 7.5: a comma directly after the kanban:config or column:config
        -- prefix is accepted on input; the writer does not emit one. The boundary
        -- is always a single space, whatever property_separator is set to.
        config_module.setup({ property_separator = " | " })
        local props = { alpha = "a", beta = "b" }

        for _, prefix in ipairs({ "kanban:config", "column:config" }) do
          local result = properties_to_comment(props, prefix)
          assert.are.equals("<!-- " .. prefix .. " alpha: a | beta: b -->", result)
          assert.is_nil(result:match(prefix .. "%s*[,|]"),
            "separator must not follow the " .. prefix .. " prefix")
        end
      end)

    it("should emit the prefix alone when every property is filtered out", function()
      -- Underscore-prefixed properties are ephemeral, so nothing is left to join
      -- and no dangling separator should appear after the prefix.
      local props = { _cursor_target = true, _scratch = "x" }
      assert.are.equals("<!-- kanban:config -->",
        properties_to_comment(props, "kanban:config"))
    end)

    it("should use custom property separator", function()
      config_module.setup({ property_separator = " | " })
      local props = { alpha = "a", beta = "b" }
      assert.are.equals("<!-- alpha: a | beta: b -->", properties_to_comment(props))
    end)

    it("should create multiline comment when threshold exceeded", function()
      config_module.setup({
        use_multiline_comments = true,
        multiline_threshold = 20,
        property_separator = ", "
      })
      local props = {
        very_long_property_name = "very_long_value",
        another_property = "another_value"
      }
      local result = properties_to_comment(props, "kanban:config")
      assert.is_table(result)
      assert.are.equals("<!-- kanban:config", result[1])
      assert.are.equals("-->", result[#result])
    end)
  end)

  describe("write_task", function()
    local write_task

    before_each(function()
      local WriterMixin = require("kanban-md.writer_mixin")
      write_task = WriterMixin._private.write_task
      config_module.setup({ task_indent = "" })
    end)

    it("should write simple task without properties", function()
      local task = { text = "Simple task" }
      assert.are.equals("- Simple task", write_task(task, "Todo"))
    end)

    it("should write task with properties", function()
      local task = {
        text = "Task with props",
        properties = { id = "task1", priority = "high" }
      }
      local result = write_task(task, "Todo")
      assert.is_true(result:match("^%- Task with props") ~= nil)
      assert.is_true(result:match("<!%-%- ") ~= nil)
      assert.is_true(result:match("id: task1") ~= nil)
    end)

    it("should handle task indent configuration", function()
      config_module.setup({ task_indent = "  " })
      local task = { text = "Indented task" }
      assert.are.equals("  - Indented task", write_task(task, "Todo"))
    end)

    it("should handle empty properties table", function()
      local task = {
        text = "Task",
        properties = {}
      }
      assert.are.equals("- Task", write_task(task, "Todo"))
    end)

    it("should handle TypeConverter objects", function()
      local task = {
        text = "Task",
        properties = {
          to_table = function(self)
            return { id = "converted" }
          end
        }
      }
      local result = write_task(task, "Todo")
      assert.is_true(result:match("id: converted") ~= nil)
    end)

    -- PLAN-config-fixes.md Task 2: write_task is the single source of truth
    -- for persisted card ids.
    it("preserves a user-authored id verbatim when persist_card_ids is false (regression)", function()
      config_module.setup({ task_indent = "", persist_card_ids = false })
      local task = {
        id = "card_generated_in_memory",
        text = "Task",
        properties = { id = "user-authored-id" }
      }
      local result = write_task(task, "Todo")
      assert.is_true(result:match("id: user%-authored%-id") ~= nil)
      assert.is_nil(result:match("card_generated_in_memory"), "in-memory task.id must not be written when persist_card_ids is false")
    end)

    it("writes task.id when persist_card_ids is true and there is no authored properties.id", function()
      config_module.setup({ task_indent = "", persist_card_ids = true })
      local task = {
        id = "card_generated_id",
        text = "Task",
        properties = {}
      }
      local result = write_task(task, "Todo")
      assert.is_true(result:match("id: card_generated_id") ~= nil)
    end)

    it("prefers the authored properties.id over task.id when persist_card_ids is true (properties.id is canonical)", function()
      config_module.setup({ task_indent = "", persist_card_ids = true })
      local task = {
        id = "stale-in-memory-id",
        text = "Task",
        properties = { id = "authored-canonical-id" }
      }
      local result = write_task(task, "Todo")
      assert.is_true(result:match("id: authored%-canonical%-id") ~= nil)
      assert.is_nil(result:match("stale%-in%-memory%-id"), "properties.id must win over a diverging task.id")
    end)
  end)

  describe("write_column", function()
    local write_column

    before_each(function()
      local WriterMixin = require("kanban-md.writer_mixin")
      write_column = WriterMixin._private.write_column
    end)

    it("should write column header", function()
      local column = { name = "Todo", cards = {} }
      local lines = write_column(column)
      assert.are.equals("###### Todo", lines[1])
    end)

    it("should write column with config", function()
      local column = {
        name = "In Progress",
        config = { wip_limit = 3 },
        cards = {}
      }
      local lines = write_column(column)
      assert.are.equals("###### In Progress", lines[1])
      assert.is_true(lines[2]:match("column:config") ~= nil)
      assert.is_true(lines[2]:match("wip_limit: 3") ~= nil)
    end)

    it("should write column with cards", function()
      config_module.setup({ blank_line_after_column_header = false })
      local column = {
        name = "Done",
        cards = {
          { text = "First task" },
          { text = "Second task" }
        }
      }
      local lines = write_column(column)
      assert.are.equals("###### Done", lines[1])
      assert.is_true(lines[2]:match("First task") ~= nil)
      assert.is_true(lines[3]:match("Second task") ~= nil)
    end)

    it("should handle empty cards array", function()
      local column = { name = "Empty", cards = {} }
      local lines = write_column(column)
      assert.are.equals(1, #lines)
      assert.are.equals("###### Empty", lines[1])
    end)

    it("should handle special column names", function()
      local archive = { name = "__ARCHIVE__", cards = {} }
      local lines = write_column(archive)
      assert.are.equals("###### __ARCHIVE__", lines[1])
    end)

    it("should add blank line after column header when config is true and there are cards", function()
      config_module.setup({ blank_line_after_column_header = true })
      local column = {
        name = "Todo",
        cards = {
          { text = "First task" }
        }
      }
      local lines = write_column(column)
      assert.are.equals("###### Todo", lines[1])
      assert.are.equals("", lines[2])
      assert.is_true(lines[3]:match("First task") ~= nil)
    end)

    it("should NOT add blank line after column header when config is false", function()
      config_module.setup({ blank_line_after_column_header = false })
      local column = {
        name = "Todo",
        cards = {
          { text = "First task" }
        }
      }
      local lines = write_column(column)
      assert.are.equals("###### Todo", lines[1])
      assert.is_true(lines[2]:match("First task") ~= nil)
    end)

    it("should NOT add blank line after column header for empty columns", function()
      config_module.setup({ blank_line_after_column_header = true })
      local column = {
        name = "Empty",
        cards = {}
      }
      local lines = write_column(column)
      assert.are.equals(1, #lines)
      assert.are.equals("###### Empty", lines[1])
    end)

    it("should add blank line after column config comment when there are cards", function()
      config_module.setup({ blank_line_after_column_header = true })
      local column = {
        name = "In Progress",
        config = { wip_limit = 3 },
        cards = {
          { text = "Task" }
        }
      }
      local lines = write_column(column)
      assert.are.equals("###### In Progress", lines[1])
      assert.is_true(lines[2]:match("column:config") ~= nil)
      assert.are.equals("", lines[3])
      assert.is_true(lines[4]:match("Task") ~= nil)
    end)
  end)

  describe("write()", function()
    it("should write minimal board", function()
      local board = Board:new()
      board.title = "Minimal Board"

      local lines = board:write()
      assert.are.equals("# Minimal Board", lines[1])
    end)

    it("should write board with columns", function()
      local board = Board:new()
      board:parse({
        "# Test Board",
        "",
        "###### Todo",
        "- Task one",
        "",
        "###### Done",
        "- Task two"
      })

      local lines = board:write()
      assert.are.equals("# Test Board", lines[1])

      -- Find column headers
      local has_todo = false
      local has_done = false
      for _, line in ipairs(lines) do
        if line == "###### Todo" then has_todo = true end
        if line == "###### Done" then has_done = true end
      end
      assert.is_true(has_todo)
      assert.is_true(has_done)
    end)

    it("should write board configuration", function()
      local board = Board:new()
      board:parse({
        "# Configured Board",
        "<!-- kanban:config wip_limit: 10 -->",
        "",
        "###### Todo"
      })

      local lines = board:write()

      local has_config = false
      for _, line in ipairs(lines) do
        if line:match("kanban:config") and line:match("wip_limit") then
          has_config = true
          break
        end
      end
      assert.is_true(has_config)
    end)

    it("should write archive section", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "###### Todo",
        "",
        "###### __ARCHIVE__",
        "- Archived task"
      })

      local lines = board:write()

      local has_archive = false
      for _, line in ipairs(lines) do
        if line == "###### __ARCHIVE__" then
          has_archive = true
          break
        end
      end
      assert.is_true(has_archive)
    end)

    it("should respect blank_line_after_title config", function()
      config_module.setup({ blank_line_after_title = true })
      local board = Board:new()
      board.title = "Test"

      local lines = board:write()
      assert.are.equals("# Test", lines[1])
      assert.are.equals("", lines[2])
    end)

    it("should respect blank_line_after_title = false", function()
      config_module.setup({ blank_line_after_title = false })
      local board = Board:new()
      board.title = "Test"
      board.columns = {{ name = "Todo", cards = {} }}

      local lines = board:write()
      assert.are.equals("# Test", lines[1])
      -- Next non-empty line should be column or config
      if lines[2] ~= "" then
        assert.is_true(lines[2]:match("^######") ~= nil or lines[2]:match("^<!%-%-") ~= nil)
      end
    end)

    it("should handle default untitled board", function()
      local board = Board:new()
      local lines = board:write()
      assert.are.equals("# Untitled Board", lines[1])
    end)
  end)

  describe("Configuration-driven behavior", function()
    it("should use different timestamp formats", function()
      local formats = {"epoch", "iso", "date"}

      for _, fmt in ipairs(formats) do
        config_module.setup({ timestamp_format = fmt })

        local board = Board:new()
        board:parse({
          "# Board",
          "",
          "###### Todo",
          "- Task <!-- todo: 1609459200 -->"
        })

        local lines = board:write()
        assert.is_not_nil(lines)
      end
    end)

    it("should respect blank_lines_between_sections", function()
      config_module.setup({ blank_lines_between_sections = true })

      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "###### Todo",
        "- Task",
        "",
        "###### Done",
        "- Done task"
      })

      local lines = board:write()

      -- Find the columns and check for blank lines between them
      local todo_idx, done_idx
      for i, line in ipairs(lines) do
        if line == "###### Todo" then todo_idx = i end
        if line == "###### Done" then done_idx = i end
      end

      if todo_idx and done_idx then
        -- There should be a blank line between sections
        local has_blank = false
        for i = todo_idx + 1, done_idx - 1 do
          if lines[i] == "" then
            has_blank = true
            break
          end
        end
        assert.is_true(has_blank)
      end
    end)

    it("should use custom property separator", function()
      config_module.setup({ property_separator = " | " })

      local board = Board:new()
      board:parse({
        "# Board",
        "<!-- kanban:config wip_limit: 5, auto_assign: true -->",
        "",
        "###### Todo"
      })

      local lines = board:write()
      local has_custom_sep = false
      for _, line in ipairs(lines) do
        if line:match(" | ") then
          has_custom_sep = true
          break
        end
      end
      assert.is_true(has_custom_sep)
    end)
  end)

  describe("Round-trip parsing", function()
    it("should normalise a comma after a config prefix away", function()
      -- SPEC.md 7.5: the comma form is legacy input the parser still accepts.
      -- Writing it back drops the comma, so a board authored either way
      -- converges on the space form.
      local input = {
        "# Comma Board",
        "",
        "<!-- kanban:config, wip_limit: 7 -->",
        "",
        "###### Todo",
        "",
        "<!-- column:config, wip_limit: 3 -->",
        "",
        "- A card",
        ""
      }

      local board = Board:new()
      board:parse(input)

      -- The comma form still parses
      assert.are.equals(7, board.config.wip_limit)
      assert.are.equals(3, board.columns[1].config.wip_limit)

      local output = board:write()
      local seen = {}
      for _, line in ipairs(output) do
        if line:match("config") then
          table.insert(seen, line)
          assert.is_nil(line:match("config,"),
            "writer must not emit a comma after the config prefix: " .. line)
        end
      end

      assert.are.equals("<!-- kanban:config wip_limit: 7 -->", seen[1])
      assert.are.equals("<!-- column:config wip_limit: 3 -->", seen[2])
    end)

    it("should preserve simple board structure", function()
      local input = {
        "# Simple Board",
        "",
        "###### Todo",
        "- First task",
        "- Second task",
        "",
        "###### Done",
        "- Completed task"
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      -- Parse again
      local board2 = Board:new()
      board2:parse(output)

      assert.are.equals(board.title, board2.title)
      assert.are.equals(#board.columns, #board2.columns)
    end)

    it("should preserve board configuration", function()
      local input = {
        "# Configured",
        "<!-- kanban:config wip_limit: 10 -->",
        "",
        "###### Todo"
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      local board2 = Board:new()
      board2:parse(output)

      assert.are.equals(board.config.wip_limit, board2.config.wip_limit)
    end)

    it("should write task properties in output", function()
      -- Simpler test - parse and write
      local board = Board:new()
      board:parse({
        "# Test",
        "",
        "###### Todo",
        "- Test task <!-- id: task1, priority: high -->"
      })

      -- Verify the properties were parsed
      assert.is_not_nil(board.columns[1].cards[1].properties)
      assert.are.equals("task1", board.columns[1].cards[1].properties.id)

      local lines = board:write()

      -- Check output contains task properties
      local found_properties = false
      for _, line in ipairs(lines) do
        if line:match("Test task") and line:match("id:") and line:match("task1") then
          found_properties = true
          break
        end
      end

      assert.is_true(found_properties, "Task properties should be in output")
    end)

    it("should preserve task properties", function()
      local input = {
        "# Board",
        "",
        "###### Todo",
        "- Task <!-- id: task1, priority: high -->"
      }

      local board = Board:new()
      board:parse(input)

      -- Verify first parse got the properties
      local task1 = board.columns[1].cards[1]
      assert.is_not_nil(task1.properties, "task1 should have properties")
      assert.are.equals("task1", task1.properties.id, "task1 should have id")

      local output = board:write()

      -- Check if output contains the properties
      local has_task_properties = false
      for _, line in ipairs(output) do
        if line:match("Task") and line:match("id:") then
          has_task_properties = true
          break
        end
      end
      assert.is_true(has_task_properties, "Output should contain task properties")

      local board2 = Board:new()
      board2:parse(output)

      local task2 = board2.columns[1].cards[1]
      assert.is_not_nil(task2.properties, "task2 should have properties after round-trip")

      assert.are.equals(task1.properties.id, task2.properties.id)
      assert.are.equals(task1.properties.priority, task2.properties.priority)
    end)

    it("should preserve column configuration", function()
      local input = {
        "# Board",
        "",
        "###### In Progress",
        "<!-- column:config wip_limit: 3 -->",
        "- Task"
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      local board2 = Board:new()
      board2:parse(output)

      assert.are.equals(board.columns[1].config.wip_limit, board2.columns[1].config.wip_limit)
    end)

    it("should handle complex board with all features", function()
      local input = {
        "# Complex Board",
        "<!-- kanban:config wip_limit: 15, cycle_time_unit: days -->",
        "",
        "###### Backlog",
        "- Task A <!-- id: a1, tags: [bug, urgent] -->",
        "- Task B <!-- id: a2 -->",
        "",
        "###### In Progress",
        "<!-- column:config wip_limit: 3 -->",
        "- Active task <!-- id: b1, started: 1609459200 -->",
        "",
        "###### Done",
        "- Completed <!-- id: c1, done: 1609459200 -->",
        "",
        "###### __ARCHIVE__",
        "- Old task <!-- id: d1, archived: 1609459200 -->"
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      local board2 = Board:new()
      board2:parse(output)

      assert.are.equals(board.title, board2.title)
      assert.are.equals(board.config.wip_limit, board2.config.wip_limit)
      assert.are.equals(#board.columns, #board2.columns)

      -- Check archive preserved
      assert.is_not_nil(board2.archive)
      assert.are.equals(#board.archive.cards, #board2.archive.cards)
    end)

    it("should preserve blank lines after column headers in round-trip", function()
      config_module.setup({ blank_line_after_column_header = true })

      local input = {
        "# Test Board",
        "",
        "###### Todo",
        "- Task one",
        "- Task two",
        "",
        "###### Done",
        "- Completed task"
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      -- Check that output has blank lines after column headers
      local todo_idx, done_idx
      for i, line in ipairs(output) do
        if line == "###### Todo" then todo_idx = i end
        if line == "###### Done" then done_idx = i end
      end

      assert.is_not_nil(todo_idx, "Should have Todo column")
      assert.is_not_nil(done_idx, "Should have Done column")
      assert.are.equals("", output[todo_idx + 1], "Should have blank line after Todo header")
      assert.are.equals("", output[done_idx + 1], "Should have blank line after Done header")

      -- Round-trip should preserve structure
      local board2 = Board:new()
      board2:parse(output)
      local output2 = board2:write()

      assert.are.equals(#output, #output2, "Round-trip should preserve line count")
    end)
  end)
  -- SPEC.md 7.8: "Underscore-prefixed properties are never serialised." Any
  -- property whose key begins with `_` is ephemeral, internal state and must
  -- not reach the markdown, at any of the three levels that carry properties
  -- (card, column:config, kanban:config). The filter lives in one place --
  -- properties_to_comment -- so these cases guard the contract each caller
  -- inherits, and the round-trip case guards the consequence the spec draws
  -- from it: re-parsing never resurrects such a property.
  describe("underscore-prefixed properties are never serialised", function()
    local write_task, properties_to_comment

    before_each(function()
      local WriterMixin = require("kanban-md.writer_mixin")
      write_task = WriterMixin._private.write_task
      properties_to_comment = WriterMixin._private.properties_to_comment
      config_module.setup({ task_indent = "", persist_card_ids = false })
    end)

    it("drops them from a card comment while keeping its ordinary properties", function()
      local task = {
        text = "Task",
        properties = { _scratch = "keep", _cursor_target = true, assignee = "alice" },
      }
      assert.are.equals("- Task <!-- assignee: alice -->", write_task(task, "Todo"))
    end)

    it("emits no comment at all when a card has nothing but underscore properties", function()
      local task = { text = "Task", properties = { _scratch = "keep" } }
      -- Not merely "no _scratch": an empty <!-- --> would also be wrong.
      assert.are.equals("- Task", write_task(task, "Todo"))
    end)

    it("only strips a leading underscore, not one anywhere in the key", function()
      local task = { text = "Task", properties = { due_date = "2026-01-01", _due = "x" } }
      -- The value is a string shaped like a date, so it is quoted to stay a string (SPEC.md 7.6)
      assert.are.equals('- Task <!-- due_date: "2026-01-01" -->', write_task(task, "Todo"))
    end)

    it("drops them from kanban:config and column:config comments", function()
      assert.are.equals("<!-- kanban:config show_stats: true -->",
        properties_to_comment({ _hidden = 1, show_stats = true }, "kanban:config"))
      assert.are.equals("<!-- column:config wip_limit: 3 -->",
        properties_to_comment({ _tmp = 2, wip_limit = 3 }, "column:config"))
    end)

    it("keeps them out of multi-line comments too", function()
      config_module.setup({ use_multiline_comments = true, multiline_threshold = 20 })
      local lines = properties_to_comment({
        _scratch = "internal",
        very_long_property_name = "very_long_value",
        another_property = "another_value",
      })
      assert.is_table(lines)
      assert.is_nil(table.concat(lines, "\n"):find("_scratch", 1, true))
    end)

    it("parses them into memory but loses them on write, so a re-parse cannot resurrect them", function()
      local input = {
        "# Board",
        "",
        "<!-- kanban:config _hidden: 1, show_stats: true -->",
        "",
        "###### Todo",
        "<!-- column:config _tmp: 2, wip_limit: 3 -->",
        "",
        "- A task <!-- _scratch: keep, assignee: alice -->",
        "",
      }

      local board = Board:new()
      board:parse(input)

      -- The parser is not the filter: it reads the properties like any other,
      -- so a host can put ephemeral state there deliberately.
      local card = board.columns[1].cards[1]
      assert.are.equals("keep", card.properties._scratch)

      local output = table.concat(board:write(), "\n")
      assert.is_nil(output:find("_scratch", 1, true))
      assert.is_nil(output:find("_hidden", 1, true))
      assert.is_nil(output:find("_tmp", 1, true))

      local board2 = Board:new()
      board2:parse(board:write())

      local card2 = board2.columns[1].cards[1]
      assert.is_nil(card2.properties._scratch)
      -- The properties that share those comments are untouched.
      assert.are.equals("alice", card2.properties.assignee)
      assert.are.equals(3, board2.columns[1].config.wip_limit)
    end)
  end)
end)
