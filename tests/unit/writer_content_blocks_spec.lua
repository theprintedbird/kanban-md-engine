-- tests/unit/writer_content_blocks_spec.lua
-- Tests for content blocks writing functionality
require('polyfills.vim')

_G._TEST = true

local Board = require("kanban-md.board")
local ContentBlock = require("kanban-md.content_block")
local config_module = require("kanban-md.config")

describe("Writer content blocks", function()
  local original_config

  before_each(function()
    original_config = vim.deepcopy(config_module.get())
  end)

  after_each(function()
    config_module.setup(original_config)
  end)

  describe("preserving preamble text", function()
    it("should write preamble text before columns", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "This is preamble text.",
        "",
        "###### Todo",
        "- Task"
      })

      local lines = board:write()

      -- Find preamble text in output
      local has_preamble = false
      for _, line in ipairs(lines) do
        if line:match("This is preamble text") then
          has_preamble = true
          break
        end
      end

      assert.is_true(has_preamble, "Preamble text should be in output")
    end)

    it("should write preamble in correct position after title", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "Preamble here.",
        "",
        "###### Todo",
        "- Task"
      })

      local lines = board:write()

      -- Verify order: title, then preamble, then column
      local title_idx, preamble_idx, column_idx

      for i, line in ipairs(lines) do
        if line == "# Board" then
          title_idx = i
        elseif line:match("Preamble here") then
          preamble_idx = i
        elseif line == "###### Todo" then
          column_idx = i
        end
      end

      assert.is_not_nil(title_idx, "Should have title")
      assert.is_not_nil(preamble_idx, "Should have preamble")
      assert.is_not_nil(column_idx, "Should have column")

      assert.is_true(title_idx < preamble_idx, "Title should come before preamble")
      assert.is_true(preamble_idx < column_idx, "Preamble should come before column")
    end)
  end)

  describe("preserving H2-H5 sections", function()
    it("should write H2 sections as markdown", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "## Instructions",
        "",
        "Follow these steps.",
        "",
        "###### Todo",
        "- Task"
      })

      local lines = board:write()

      -- Check for H2 section
      local has_h2 = false
      local has_content = false

      for _, line in ipairs(lines) do
        if line == "## Instructions" then
          has_h2 = true
        elseif line:match("Follow these steps") then
          has_content = true
        end
      end

      assert.is_true(has_h2, "H2 header should be preserved")
      assert.is_true(has_content, "H2 content should be preserved")
    end)

    it("should preserve multiple H2-H5 sections", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "## Section H2",
        "Content.",
        "",
        "### Section H3",
        "More content.",
        "",
        "###### Todo",
        "- Task"
      })

      local lines = board:write()

      local has_h2 = false
      local has_h3 = false

      for _, line in ipairs(lines) do
        if line == "## Section H2" then
          has_h2 = true
        elseif line == "### Section H3" then
          has_h3 = true
        end
      end

      assert.is_true(has_h2, "H2 section should be preserved")
      assert.is_true(has_h3, "H3 section should be preserved")
    end)
  end)

  describe("writing columns with H6", function()
    it("should write columns using H6 headers", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "###### Todo",
        "- Task one"
      })

      local lines = board:write()

      local has_h6 = false
      for _, line in ipairs(lines) do
        if line == "###### Todo" then
          has_h6 = true
          break
        end
      end

      assert.is_true(has_h6, "Column should use H6 header")
    end)

    it("should write multiple columns with H6", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "###### Todo",
        "- Task one",
        "",
        "###### Done",
        "- Task two"
      })

      local lines = board:write()

      local has_todo = false
      local has_done = false

      for _, line in ipairs(lines) do
        if line == "###### Todo" then
          has_todo = true
        elseif line == "###### Done" then
          has_done = true
        end
      end

      assert.is_true(has_todo, "Todo column should have H6 header")
      assert.is_true(has_done, "Done column should have H6 header")
    end)

    it("should write special columns with H6", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "###### Todo",
        "- Task",
        "",
        "###### __ARCHIVE__",
        "- Archived task"
      })

      local lines = board:write()

      local has_archive_h6 = false
      for _, line in ipairs(lines) do
        if line == "###### __ARCHIVE__" then
          has_archive_h6 = true
          break
        end
      end

      assert.is_true(has_archive_h6, "Archive should use H6 header")
    end)
  end)

  describe("preserving markdown after card operations", function()
    it("should preserve documentation after adding a card", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "Documentation here.",
        "",
        "###### Todo",
        "- Existing task",
        "",
        "## Notes",
        "Important notes."
      })

      -- Add a new card
      local todo_col = board:get_column_by_name("Todo")
      local Card = require("kanban-md.card")
      local new_card = Card:new(nil, "New task")
      todo_col:add_card(new_card)

      local lines = board:write()

      -- Check documentation is still there
      local has_doc = false
      local has_notes = false

      for _, line in ipairs(lines) do
        if line:match("Documentation here") then
          has_doc = true
        elseif line:match("Important notes") then
          has_notes = true
        end
      end

      assert.is_true(has_doc, "Documentation should be preserved after adding card")
      assert.is_true(has_notes, "Notes should be preserved after adding card")
    end)

    it("should preserve documentation after moving a card", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "Preamble text.",
        "",
        "###### Todo",
        "- Task to move <!-- id: task1 -->",
        "",
        "###### Done"
      })

      -- Move card from Todo to Done
      local todo_col = board:get_column_by_name("Todo")
      local done_col = board:get_column_by_name("Done")
      local card = todo_col.cards[1]

      board:move_card(card, todo_col, done_col)

      local lines = board:write()

      -- Check preamble is still there
      local has_preamble = false
      for _, line in ipairs(lines) do
        if line:match("Preamble text") then
          has_preamble = true
          break
        end
      end

      assert.is_true(has_preamble, "Preamble should be preserved after moving card")
    end)

    it("should preserve documentation after removing a card", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "## Important",
        "Keep this text.",
        "",
        "###### Todo",
        "- Task one",
        "- Task two"
      })

      -- Remove first card
      local todo_col = board:get_column_by_name("Todo")
      table.remove(todo_col.cards, 1)

      local lines = board:write()

      -- Check documentation is still there
      local has_important = false
      local has_text = false

      for _, line in ipairs(lines) do
        if line == "## Important" then
          has_important = true
        elseif line:match("Keep this text") then
          has_text = true
        end
      end

      assert.is_true(has_important, "H2 section should be preserved after removing card")
      assert.is_true(has_text, "Documentation text should be preserved after removing card")
    end)
  end)

  describe("round-trip consistency", function()
    it("should maintain structure after parse-write-parse cycle", function()
      local input = {
        "# Board",
        "",
        "Description here.",
        "",
        "## Instructions",
        "Follow steps.",
        "",
        "###### Todo",
        "- Task one",
        "",
        "## Notes",
        "Some notes.",
        "",
        "###### Done",
        "- Task two"
      }

      local board1 = Board:new()
      board1:parse(input)

      local output = board1:write()

      local board2 = Board:new()
      board2:parse(output)

      -- Verify structure is maintained
      assert.are.equals(board1.title, board2.title)
      assert.are.equals(#board1.columns, #board2.columns)
      -- Note: board2 may have more content blocks due to whitespace preservation
      -- This is correct behavior - we preserve trailing whitespace now
      assert.is_true(#board2.content_blocks >= #board1.content_blocks, "Should maintain or increase blocks (whitespace preservation)")

      -- Verify specific content
      local output_text = table.concat(output, "\n")
      assert.is_not_nil(output_text:match("Description here"), "Description should survive round-trip")
      assert.is_not_nil(output_text:match("## Instructions"), "Instructions section should survive")
      assert.is_not_nil(output_text:match("## Notes"), "Notes section should survive")
    end)

    it("should preserve blank lines in round-trip", function()
      local input = {
        "# Board",
        "",
        "Paragraph one.",
        "",
        "",
        "Paragraph two.",
        "",
        "###### Todo",
        "- Task"
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      -- Check that multiple blank lines are represented
      local blank_count = 0
      local after_para_one = false

      for i, line in ipairs(output) do
        if line:match("Paragraph one") then
          after_para_one = true
        elseif after_para_one and line == "" then
          blank_count = blank_count + 1
        elseif after_para_one and line:match("Paragraph two") then
          break
        end
      end

      -- Should have at least one blank line between paragraphs
      assert.is_true(blank_count >= 1, "Should preserve blank lines between paragraphs")
    end)

    it("should handle complex nested markdown in round-trip", function()
      local input = {
        "# Sprint Board",
        "",
        "## Overview",
        "",
        "This is a sprint board with:",
        "",
        "- Bullet one",
        "- Bullet two",
        "",
        "### Details",
        "",
        "More details here.",
        "",
        "###### Backlog",
        "- Task A",
        "- Task B",
        "",
        "## Rules",
        "",
        "1. Rule one",
        "2. Rule two",
        "",
        "###### In Progress",
        "- Task C",
        "",
        "###### Done",
        "- Task D",
        "",
        "## Statistics",
        "",
        "Average cycle time: 3 days"
      }

      local board = Board:new()
      board:parse(input)
      local output = board:write()

      local output_text = table.concat(output, "\n")

      -- Verify all sections preserved
      assert.is_not_nil(output_text:match("## Overview"), "Overview should be preserved")
      assert.is_not_nil(output_text:match("### Details"), "Details subsection should be preserved")
      assert.is_not_nil(output_text:match("## Rules"), "Rules section should be preserved")
      assert.is_not_nil(output_text:match("## Statistics"), "Statistics section should be preserved")
      assert.is_not_nil(output_text:match("Bullet one"), "Bullet lists should be preserved")
      assert.is_not_nil(output_text:match("Rule one"), "Numbered lists should be preserved")
      assert.is_not_nil(output_text:match("###### Backlog"), "Columns should use H6")
      assert.is_not_nil(output_text:match("###### In Progress"), "Columns should use H6")
      assert.is_not_nil(output_text:match("###### Done"), "Columns should use H6")
    end)
  end)

  describe("fallback to write_legacy for programmatic boards", function()
    it("should use write_legacy when content_blocks is empty", function()
      local board = Board:new()
      board.title = "Programmatic Board"

      -- Manually add columns without parsing (no content blocks)
      local Column = require("kanban-md.column")
      local col = Column:new(nil, "Todo")
      table.insert(board.columns, col)

      -- content_blocks should be empty
      assert.are.equals(0, #board.content_blocks)

      local lines = board:write()

      -- Should still write the board using legacy method
      assert.is_not_nil(lines)
      assert.is_true(#lines > 0)

      -- Should have title
      local has_title = false
      for _, line in ipairs(lines) do
        if line == "# Programmatic Board" then
          has_title = true
          break
        end
      end

      assert.is_true(has_title, "Should write title even without content blocks")
    end)

    it("should write columns with H6 in legacy mode", function()
      local board = Board:new()
      board.title = "Test"

      local Column = require("kanban-md.column")
      local todo = Column:new(nil, "Todo")
      local done = Column:new(nil, "Done")

      table.insert(board.columns, todo)
      table.insert(board.columns, done)

      local lines = board:write()

      -- Check that columns use H6 even in legacy mode
      local has_todo_h6 = false
      local has_done_h6 = false

      for _, line in ipairs(lines) do
        if line == "###### Todo" then
          has_todo_h6 = true
        elseif line == "###### Done" then
          has_done_h6 = true
        end
      end

      assert.is_true(has_todo_h6, "Legacy mode should use H6 for Todo")
      assert.is_true(has_done_h6, "Legacy mode should use H6 for Done")
    end)
  end)

  describe("preserving markdown between columns", function()
    it("should write markdown that appears between columns", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "###### Todo",
        "- Task one",
        "",
        "Note between columns.",
        "",
        "###### Done",
        "- Task two"
      })

      local lines = board:write()

      -- Find the note between columns
      local todo_idx, note_idx, done_idx

      for i, line in ipairs(lines) do
        if line == "###### Todo" then
          todo_idx = i
        elseif line:match("Note between columns") then
          note_idx = i
        elseif line == "###### Done" then
          done_idx = i
        end
      end

      assert.is_not_nil(todo_idx, "Should have Todo column")
      assert.is_not_nil(note_idx, "Should have note")
      assert.is_not_nil(done_idx, "Should have Done column")

      assert.is_true(todo_idx < note_idx, "Todo should come before note")
      assert.is_true(note_idx < done_idx, "Note should come before Done")
    end)

    it("should handle multiple markdown blocks between columns", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "###### Todo",
        "- Task",
        "",
        "First note.",
        "",
        "Second note.",
        "",
        "###### Done"
      })

      local lines = board:write()

      local has_first = false
      local has_second = false

      for _, line in ipairs(lines) do
        if line:match("First note") then
          has_first = true
        elseif line:match("Second note") then
          has_second = true
        end
      end

      assert.is_true(has_first, "First note should be preserved")
      assert.is_true(has_second, "Second note should be preserved")
    end)
  end)

  describe("preserving markdown after columns", function()
    it("should write markdown that appears after last column", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "###### Todo",
        "- Task",
        "",
        "###### Done",
        "- Done task",
        "",
        "## Footer",
        "",
        "This is footer content."
      })

      local lines = board:write()

      -- Check footer is present
      local has_footer = false
      local has_content = false

      for _, line in ipairs(lines) do
        if line == "## Footer" then
          has_footer = true
        elseif line:match("footer content") then
          has_content = true
        end
      end

      assert.is_true(has_footer, "Footer section should be preserved")
      assert.is_true(has_content, "Footer content should be preserved")
    end)

    it("should maintain order of trailing markdown", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "###### Todo",
        "- Task",
        "",
        "## Section One",
        "Content one.",
        "",
        "## Section Two",
        "Content two."
      })

      local lines = board:write()

      local sec_one_idx, sec_two_idx

      for i, line in ipairs(lines) do
        if line == "## Section One" then
          sec_one_idx = i
        elseif line == "## Section Two" then
          sec_two_idx = i
        end
      end

      assert.is_not_nil(sec_one_idx, "Section One should exist")
      assert.is_not_nil(sec_two_idx, "Section Two should exist")
      assert.is_true(sec_one_idx < sec_two_idx, "Section One should come before Section Two")
    end)
  end)
end)
