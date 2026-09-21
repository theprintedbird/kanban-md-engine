-- tests/unit/blank_line_preservation_spec.lua
-- Tests for blank line preservation in parse→write cycles

-- Load vim polyfill first
require('polyfills.vim')

_G._TEST = true

local Board = require("kanban-md.board")
local config_module = require("kanban-md.config")

describe("Blank line preservation", function()
  local original_config

  before_each(function()
    original_config = vim.deepcopy(config_module.get())
  end)

  after_each(function()
    config_module.setup(original_config)
  end)

  describe("trailing blank lines between columns", function()
    it("should preserve single blank line between columns", function()
      config_module.setup({
        blank_line_after_column_header = false,
        blank_lines_between_sections = false,
        blank_line_after_title = false,
      })

      local input = {
        "# Board",
        "###### Col A",
        "- Task 1",
        "",
        "###### Col B",
        "- Task 2",
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      assert.equals(#input, #output, "Line count should be preserved")

      -- Round-trip test
      local board2 = Board:new()
      board2:parse(output)
      local output2 = board2:write()

      assert.equals(#output, #output2, "Second round-trip should be stable")
    end)

    it("should preserve multiple blank lines between columns", function()
      config_module.setup({
        blank_line_after_column_header = false,
        blank_lines_between_sections = false,
        blank_line_after_title = false,
      })

      local input = {
        "# Board",
        "###### Col A",
        "- Task 1",
        "",
        "",
        "",
        "###### Col B",
        "- Task 2",
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      assert.equals(#input, #output, "Line count should be preserved")

      -- Check that we have 3 blank lines
      local blank_count = 0
      for i = 4, 6 do
        if output[i] == "" then
          blank_count = blank_count + 1
        end
      end
      assert.equals(3, blank_count, "Should have 3 blank lines after Task 1")
    end)

    it("should preserve blank lines between all columns", function()
      config_module.setup({
        blank_line_after_column_header = false,
        blank_lines_between_sections = false,
        blank_line_after_title = false,
      })

      local input = {
        "# Board",
        "###### Col A",
        "- Task 1",
        "",
        "",
        "###### Col B",
        "- Task 2",
        "",
        "###### Col C",
        "- Task 3",
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      assert.equals(#input, #output)

      -- Second cycle
      local board2 = Board:new()
      board2:parse(output)
      local output2 = board2:write()

      assert.equals(#output, #output2, "Output should be stable")
    end)
  end)

  describe("header markdown (blank lines after column header)", function()
    it("should preserve blank line between header and first task", function()
      config_module.setup({
        blank_line_after_column_header = false,
        blank_lines_between_sections = false,
        blank_line_after_title = false,
      })

      local input = {
        "# Board",
        "###### Col A",
        "",
        "- Task 1",
      }

      local board = Board:new()
      board:parse(input)

      -- Check that header_markdown was captured
      assert.is_not_nil(board.columns[1].header_markdown)
      assert.equals(1, #board.columns[1].header_markdown)

      local output = board:write()

      assert.equals(#input, #output)
    end)

    it("should not duplicate blank line when config adds one", function()
      config_module.setup({
        blank_line_after_column_header = true,
        blank_lines_between_sections = false,
        blank_line_after_title = false,
      })

      local input = {
        "# Board",
        "###### Col A",
        "",
        "- Task 1",
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      -- Check that we only have one blank line after header
      assert.equals("###### Col A", output[2])
      assert.equals("", output[3])
      assert.equals("- Task 1", output[4])

      -- Round-trip should be stable
      local board2 = Board:new()
      board2:parse(output)
      local output2 = board2:write()

      assert.equals(#output, #output2)
    end)

    it("should preserve the blank line between column prose and the first card", function()
      config_module.setup({
        blank_line_after_column_header = true,
        blank_lines_between_sections = false,
        blank_line_after_title = false,
      })

      local input = {
        "# Board",
        "###### Col A",
        "",
        "Some prose about this column.",
        "",
        "- Task 1",
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      assert.same(input, output)

      -- Round-trip should be stable
      local board2 = Board:new()
      board2:parse(output)
      assert.same(output, board2:write())
    end)
  end)

  describe("interaction with config settings", function()
    it("should respect blank_line_after_column_header when no header_markdown", function()
      config_module.setup({
        blank_line_after_column_header = true,
        blank_lines_between_sections = false,
        blank_line_after_title = false,
      })

      local input = {
        "# Board",
        "###### Col A",
        "- Task 1",
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      -- Config should add blank line
      assert.equals("###### Col A", output[2])
      assert.equals("", output[3])
      assert.equals("- Task 1", output[4])
    end)

    it("should preserve trailing blanks even with blank_lines_between_sections", function()
      config_module.setup({
        blank_line_after_column_header = true,
        blank_lines_between_sections = true,
        blank_line_after_title = true,
      })

      local input = {
        "# Board",
        "",
        "",
        "###### Col A",
        "",
        "- Task 1",
        "",
        "",
        "###### Col B",
        "",
        "- Task 2",
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      -- First cycle might adjust based on config
      local board2 = Board:new()
      board2:parse(output)
      local output2 = board2:write()

      -- Second cycle should be stable
      assert.equals(#output, #output2, "Output should stabilize after first cycle")

      -- Third cycle to verify
      local board3 = Board:new()
      board3:parse(output2)
      local output3 = board3:write()

      assert.equals(#output2, #output3, "Output should remain stable")
    end)
  end)

  describe("edge cases", function()
    it("should handle column with no tasks", function()
      config_module.setup({
        blank_line_after_column_header = false,
        blank_lines_between_sections = false,
        blank_line_after_title = false,
      })

      local input = {
        "# Board",
        "###### Col A",
        "",
        "###### Col B",
        "- Task 1",
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      -- The blank line after empty column should be preserved
      assert.equals("# Board", output[1])
      assert.equals("###### Col A", output[2])
      assert.equals("", output[3])
      assert.equals("###### Col B", output[4])
      assert.equals("- Task 1", output[5])

      -- Verify line count matches input
      assert.equals(#input, #output)
    end)

    it("should handle trailing blanks at end of file", function()
      config_module.setup({
        blank_line_after_column_header = false,
        blank_lines_between_sections = false,
        blank_line_after_title = false,
      })

      local input = {
        "# Board",
        "###### Col A",
        "- Task 1",
        "",
        "",
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      -- Trailing blanks at end should be preserved
      assert.equals(#input, #output)
      assert.equals("", output[4])
      assert.equals("", output[5])
    end)
  end)
end)
