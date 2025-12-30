-- tests/integration/writer_cli_adapter_spec.lua
-- Integration tests for writer operations with CLIAdapter
-- Ensures CLIAdapter handles write operations correctly in standalone Lua environment

require('polyfills.vim')

local Board = require("kanban-md.board")
local Card = require("kanban-md.card")
local Column = require("kanban-md.column")
local CLIAdapter = require("kanban-md.adapters.cli")
local config_module = require("kanban-md.config")
local adapter_registry = require("kanban-md.adapter_registry")

describe("Writer CLIAdapter integration", function()
  local original_config
  local original_adapter

  before_each(function()
    original_config = vim.deepcopy(config_module.get())
    config_module.setup({ persist_card_ids = true })

    -- Save original adapter
    original_adapter = _G.adapter

    -- Set CLIAdapter as the global adapter
    _G.adapter = CLIAdapter
    adapter_registry.set_adapter(CLIAdapter)
  end)

  after_each(function()
    config_module.setup(original_config)

    -- Restore original adapter
    _G.adapter = original_adapter
    if original_adapter then
      adapter_registry.set_adapter(original_adapter)
    end
  end)

  describe("CLIAdapter write operations", function()
    it("should write simple board to internal buffer", function()
      local board = Board:new()
      board:parse({
        "# Simple Board",
        "",
        "###### Todo",
        "- Task 1 <!-- id: t1 -->",
        "- Task 2 <!-- id: t2 -->",
        "",
        "###### Done",
        "- Task 3 <!-- id: t3 -->"
      })

      -- Clear CLI adapter's internal buffer
      CLIAdapter._buffer_lines = {}

      -- Write board using adapter
      local lines = board:write()
      CLIAdapter:write_buffer(lines, {}) -- Write to internal buffer

      -- Verify internal buffer contents
      local buffer_text = table.concat(CLIAdapter._buffer_lines, "\n")

      assert.is_not_nil(buffer_text:match("# Simple Board"))
      assert.is_not_nil(buffer_text:match("###### Todo"))
      assert.is_not_nil(buffer_text:match("###### Done"))
      assert.is_not_nil(buffer_text:match("Task 1"))
      assert.is_not_nil(buffer_text:match("Task 2"))
      assert.is_not_nil(buffer_text:match("Task 3"))
    end)

    it("should write complex board to temp file", function()
      local board = Board:new()
      board:parse({
        "# Complex Board",
        "",
        "## Documentation",
        "This is important context.",
        "",
        "###### Backlog",
        "- Feature A <!-- id: feat-a, priority: P0, complexity: 5 -->",
        "",
        "###### In Progress",
        "<!-- column:config wip_limit: 2 -->",
        "- Feature B <!-- id: feat-b, assignee: Alice -->",
        "",
        "###### Done",
        "- Feature C <!-- id: feat-c -->",
        "",
        "## Notes",
        "Review weekly."
      })

      -- Generate temp file path
      local temp_file = os.tmpname()

      -- Write board to file using adapter
      local lines = board:write()
      CLIAdapter:write_buffer(lines, { file = temp_file })

      -- Read file contents
      local f = io.open(temp_file, "r")
      assert.is_not_nil(f, "Should create temp file")

      local content = f:read("*a")
      f:close()

      -- Verify all content preserved
      assert.is_not_nil(content:match("# Complex Board"))
      assert.is_not_nil(content:match("## Documentation"))
      assert.is_not_nil(content:match("This is important context"))
      assert.is_not_nil(content:match("## Notes"))
      assert.is_not_nil(content:match("Review weekly"))

      -- Verify columns and cards
      assert.is_not_nil(content:match("###### Backlog"))
      assert.is_not_nil(content:match("###### In Progress"))
      assert.is_not_nil(content:match("###### Done"))
      assert.is_not_nil(content:match("feat%-a"))
      assert.is_not_nil(content:match("feat%-b"))
      assert.is_not_nil(content:match("feat%-c"))

      -- Clean up
      os.remove(temp_file)
    end)

    it("should handle cursor tracking in CLI mode", function()
      -- CLI adapter maintains simple cursor tracking
      CLIAdapter:set_cursor(5, 10)

      local line, col = CLIAdapter:get_cursor()

      assert.equals(5, line)
      assert.equals(10, col)

      -- Modify cursor
      CLIAdapter:set_cursor(3, 0)

      line, col = CLIAdapter:get_cursor()

      assert.equals(3, line)
      assert.equals(0, col)
    end)

    it("should handle board modifications via file roundtrip", function()
      local board = Board:new()
      board:parse({
        "# Project Board",
        "###### Todo",
        "- Task A <!-- id: ta -->",
        "###### Done"
      })

      local temp_file = os.tmpname()

      -- Write initial board
      local lines = board:write()
      CLIAdapter:write_buffer(lines, { file = temp_file })

      -- Modify board
      local todo = board:get_column_by_name("Todo")
      local done = board:get_column_by_name("Done")
      local task_a = board:find_task("ta")

      board:move_card(task_a, todo, done)

      local new_task = Card:new("tb", "Task B")
      todo:add_card(new_task)

      -- Write modified board
      lines = board:write()
      CLIAdapter:write_buffer(lines, { file = temp_file })

      -- Read back and verify
      local f = io.open(temp_file, "r")
      local content = f:read("*a")
      f:close()

      assert.is_not_nil(content:match("Task B"))
      assert.is_not_nil(content:match("ta"))

      -- Clean up
      os.remove(temp_file)
    end)

    it("should write board with properties and preserve them", function()
      local board = Board:new()
      board:parse({
        "# Feature Board",
        "",
        "###### Ready",
        "- Feature 1 <!-- id: f1, complexity: 3, assignee: Alice -->",
        "- Feature 2 <!-- id: f2, priority: high, tags: frontend, backend -->",
        "",
        "###### Complete",
        "<!-- column:config is_completion_state: true -->",
        "- Feature 0 <!-- id: f0, completed: 1234567890 -->"
      })

      local temp_file = os.tmpname()
      local lines = board:write()
      CLIAdapter:write_buffer(lines, { file = temp_file })

      -- Read back
      local f = io.open(temp_file, "r")
      local content = f:read("*a")
      f:close()

      -- Verify properties preserved
      assert.is_not_nil(content:match("complexity"))
      assert.is_not_nil(content:match("assignee"))
      assert.is_not_nil(content:match("priority"))
      assert.is_not_nil(content:match("tags"))
      assert.is_not_nil(content:match("completed"))

      -- Verify column config preserved
      assert.is_not_nil(content:match("is_completion_state"))

      os.remove(temp_file)
    end)

    it("should handle empty columns", function()
      local board = Board:new()
      board:parse({
        "# Empty Columns Board",
        "",
        "###### Backlog",
        "",
        "###### Todo",
        "",
        "###### Done"
      })

      CLIAdapter._buffer_lines = {}
      local lines = board:write()
      CLIAdapter:write_buffer(lines, {})

      local content = table.concat(CLIAdapter._buffer_lines, "\n")

      assert.is_not_nil(content:match("# Empty Columns Board"))
      assert.is_not_nil(content:match("###### Backlog"))
      assert.is_not_nil(content:match("###### Todo"))
      assert.is_not_nil(content:match("###### Done"))
    end)

    it("should preserve markdown documentation sections", function()
      local board = Board:new()
      board:parse({
        "# Documentation Board",
        "",
        "## Overview",
        "This is the project overview.",
        "",
        "### Details",
        "More detailed information here.",
        "",
        "###### Tasks",
        "- Task 1",
        "",
        "## Footer",
        "Additional notes at the end."
      })

      local temp_file = os.tmpname()
      local lines = board:write()
      CLIAdapter:write_buffer(lines, { file = temp_file })

      local f = io.open(temp_file, "r")
      local content = f:read("*a")
      f:close()

      -- All documentation should be preserved
      assert.is_not_nil(content:match("## Overview"))
      assert.is_not_nil(content:match("This is the project overview"))
      assert.is_not_nil(content:match("### Details"))
      assert.is_not_nil(content:match("More detailed information here"))
      assert.is_not_nil(content:match("## Footer"))
      assert.is_not_nil(content:match("Additional notes at the end"))

      os.remove(temp_file)
    end)
  end)

  describe("CLIAdapter-specific features", function()
    it("should support writing to stdout (simulated)", function()
      local board = Board:new()
      board:parse({
        "# Stdout Board",
        "###### Tasks",
        "- Task 1"
      })

      -- Write to internal buffer (simulates stdout)
      CLIAdapter._buffer_lines = {}
      local lines = board:write()
      CLIAdapter:write_buffer(lines, {})

      assert.is_true(#CLIAdapter._buffer_lines > 0)
      local content = table.concat(CLIAdapter._buffer_lines, "\n")
      assert.is_not_nil(content:match("# Stdout Board"))
    end)

    it("should support multiple sequential writes", function()
      local board = Board:new()
      board:parse({
        "# Multi-write Board",
        "###### Todo",
        "- Initial task"
      })

      local temp_file1 = os.tmpname()
      local temp_file2 = os.tmpname()

      -- First write
      local lines = board:write()
      CLIAdapter:write_buffer(lines, { file = temp_file1 })

      -- Modify board
      local todo = board:get_column_by_name("Todo")
      local new_task = Card:new("t2", "Second task")
      todo:add_card(new_task)

      -- Second write
      lines = board:write()
      CLIAdapter:write_buffer(lines, { file = temp_file2 })

      -- Verify both files
      local f1 = io.open(temp_file1, "r")
      local content1 = f1:read("*a")
      f1:close()

      local f2 = io.open(temp_file2, "r")
      local content2 = f2:read("*a")
      f2:close()

      -- First file should have only initial task
      assert.is_not_nil(content1:match("Initial task"))
      assert.is_nil(content1:match("Second task"))

      -- Second file should have both tasks
      assert.is_not_nil(content2:match("Initial task"))
      assert.is_not_nil(content2:match("Second task"))

      os.remove(temp_file1)
      os.remove(temp_file2)
    end)
  end)
end)
