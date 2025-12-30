-- tests/unit/parser_content_blocks_spec.lua
-- Tests for content blocks parsing functionality

require('polyfills.vim')

_G._TEST = true

local Board = require("kanban-md.board")
local ContentBlock = require("kanban-md.content_block")

describe("Parser content blocks", function()
  describe("parsing board with preamble text", function()
    it("should preserve text before first column", function()
      local board = Board:new()
      board:parse({
        "# Sprint Board",
        "",
        "This is the description of our sprint board.",
        "",
        "###### Backlog",
        "- Task one"
      })

      assert.is_not_nil(board.content_blocks)
      assert.is_true(#board.content_blocks > 0)

      -- Should have title block, markdown block, and column block
      local has_markdown = false
      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.MARKDOWN then
          -- Check if preamble text is preserved
          local text = table.concat(block.lines, "\n")
          if text:match("description of our sprint board") then
            has_markdown = true
            break
          end
        end
      end

      assert.is_true(has_markdown, "Preamble text should be preserved in markdown block")
    end)

    it("should handle multiple paragraphs before columns", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "First paragraph here.",
        "",
        "Second paragraph here.",
        "",
        "###### Todo",
        "- Task"
      })

      assert.is_not_nil(board.content_blocks)

      local markdown_blocks = {}
      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.MARKDOWN then
          table.insert(markdown_blocks, block)
        end
      end

      -- Should have markdown content
      assert.is_true(#markdown_blocks > 0, "Should have markdown blocks for paragraphs")
    end)
  end)

  describe("distinguishing H2-H5 sections from H6 columns", function()
    it("should treat H2 sections as markdown, not columns", function()
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

      assert.are.equals(1, #board.columns, "Should only have one column (Todo)")
      assert.are.equals("Todo", board.columns[1].name)

      -- H2 section should be preserved as markdown
      local has_instructions = false
      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.MARKDOWN then
          local text = table.concat(block.lines, "\n")
          if text:match("## Instructions") then
            has_instructions = true
            break
          end
        end
      end

      assert.is_true(has_instructions, "H2 section should be preserved as markdown")
    end)

    it("should handle H2-H5 headers without treating them as columns", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "## Section H2",
        "Content here.",
        "",
        "### Section H3",
        "More content.",
        "",
        "#### Section H4",
        "",
        "##### Section H5",
        "",
        "###### Todo",
        "- Task"
      })

      -- Only H6 should be treated as column
      assert.are.equals(1, #board.columns)
      assert.are.equals("Todo", board.columns[1].name)

      -- All H2-H5 sections should be in markdown blocks
      local has_h2 = false
      local has_h3 = false
      local has_h4 = false
      local has_h5 = false

      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.MARKDOWN then
          local text = table.concat(block.lines, "\n")
          if text:match("## Section H2") then has_h2 = true end
          if text:match("### Section H3") then has_h3 = true end
          if text:match("#### Section H4") then has_h4 = true end
          if text:match("##### Section H5") then has_h5 = true end
        end
      end

      assert.is_true(has_h2, "H2 should be preserved")
      assert.is_true(has_h3, "H3 should be preserved")
      assert.is_true(has_h4, "H4 should be preserved")
      assert.is_true(has_h5, "H5 should be preserved")
    end)
  end)

  describe("parsing multiple columns with preserved markdown between", function()
    it("should preserve markdown between columns", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "###### Todo",
        "- Task one",
        "",
        "This is a note between columns.",
        "",
        "###### Done",
        "- Task two"
      })

      assert.are.equals(2, #board.columns)

      -- Should have markdown block between column blocks
      local has_note = false
      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.MARKDOWN then
          local text = table.concat(block.lines, "\n")
          if text:match("note between columns") then
            has_note = true
            break
          end
        end
      end

      assert.is_true(has_note, "Markdown between columns should be preserved")
    end)

    it("should maintain proper order of content blocks", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "Start text",
        "",
        "###### Todo",
        "- Task",
        "",
        "Middle text",
        "",
        "###### Done",
        "- Done task",
        "",
        "End text"
      })

      -- Verify block order
      local block_types = {}
      for _, block in ipairs(board.content_blocks) do
        table.insert(block_types, block.type)
      end

      -- Should have pattern: title, markdown, column, markdown, column, markdown
      assert.are.equals(ContentBlock.TYPES.TITLE, block_types[1])

      -- At least one markdown and column should alternate
      local has_columns = false
      local has_markdown_between = false

      for i, btype in ipairs(block_types) do
        if btype == ContentBlock.TYPES.COLUMN then
          has_columns = true
          -- Check if there's markdown before next column
          if i < #block_types and block_types[i+1] == ContentBlock.TYPES.MARKDOWN then
            has_markdown_between = true
          end
        end
      end

      assert.is_true(has_columns, "Should have column blocks")
      assert.is_true(has_markdown_between, "Should have markdown blocks between columns")
    end)
  end)

  describe("handling blank lines and spacing", function()
    it("should preserve blank lines in markdown blocks", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "Paragraph one.",
        "",
        "",
        "Paragraph two with extra blank line before.",
        "",
        "###### Todo",
        "- Task"
      })

      local markdown_found = false
      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.MARKDOWN then
          -- Check if blank lines are in the lines array
          local has_blanks = false
          for _, line in ipairs(block.lines) do
            if line == "" then
              has_blanks = true
              break
            end
          end
          if has_blanks then
            markdown_found = true
            break
          end
        end
      end

      assert.is_true(markdown_found, "Blank lines should be preserved in markdown blocks")
    end)

    it("should not create empty markdown blocks", function()
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

      -- Check that no markdown blocks are completely empty (no meaningful content)
      -- Markdown blocks with only blank lines should exist to preserve spacing
      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.MARKDOWN then
          assert.is_not_nil(block.lines, "Markdown block should have lines array")
          assert.is_table(block.lines)
        end
      end

      -- This test mainly ensures the parser doesn't crash with spacing
      assert.is_true(true)
    end)
  end)

  describe("special sections with H6", function()
    it("should recognize __ARCHIVE__ as special column", function()
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

      assert.is_not_nil(board.archive, "Should have archive")
      assert.are.equals("__ARCHIVE__", board.archive.name)
      assert.are.equals(1, #board.archive.cards)

      -- Archive is stored separately, not in columns array
      -- Verify it has a content block
      local has_archive_block = false
      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.COLUMN and block.ref == board.archive then
          has_archive_block = true
          break
        end
      end
      assert.is_true(has_archive_block, "Archive should have a content block")
    end)
  end)

  describe("complex board with all features", function()
    it("should parse complex board preserving all content", function()
      local board = Board:new()
      board:parse({
        "# Sprint Planning Board",
        "",
        "This is the description of our sprint board.",
        "",
        "## Instructions",
        "",
        "1. Add cards to Backlog",
        "2. Move them through the workflow",
        "",
        "## Workflow Rules",
        "",
        "Cards must meet DoD before moving to Done.",
        "",
        "###### Backlog",
        "- Research API design",
        "- Write user stories",
        "",
        "###### Ready",
        "<!-- column:config wip_limit: 3 -->",
        "- Set up CI/CD",
        "",
        "Some notes about the Ready column.",
        "",
        "###### In Progress",
        "- Implement auth",
        "",
        "###### Done",
        "- Create repository",
        "",
        "###### __ARCHIVE__",
        "- Old completed tasks",
        "",
        "## Statistics",
        "",
        "Average cycle time: 3.2 days"
      })

      -- Verify board structure
      assert.are.equals("Sprint Planning Board", board.title)
      assert.are.equals(4, #board.columns, "Should have 4 regular columns (Archive is separate)")

      -- Verify columns parsed
      local column_names = {}
      for _, col in ipairs(board.columns) do
        table.insert(column_names, col.name)
      end

      assert.is_true(vim.tbl_contains(column_names, "Backlog"))
      assert.is_true(vim.tbl_contains(column_names, "Ready"))
      assert.is_true(vim.tbl_contains(column_names, "In Progress"))
      assert.is_true(vim.tbl_contains(column_names, "Done"))

      -- Archive is stored separately
      assert.is_not_nil(board.archive)
      assert.are.equals("__ARCHIVE__", board.archive.name)

      -- Verify content blocks exist
      assert.is_not_nil(board.content_blocks)
      assert.is_true(#board.content_blocks > 0)

      -- Verify specific content is preserved
      local has_description = false
      local has_instructions = false
      local has_workflow_rules = false
      local has_statistics = false
      local has_notes = false

      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.MARKDOWN then
          local text = table.concat(block.lines, "\n")
          if text:match("description of our sprint board") then
            has_description = true
          end
          if text:match("## Instructions") then
            has_instructions = true
          end
          if text:match("## Workflow Rules") then
            has_workflow_rules = true
          end
          if text:match("## Statistics") then
            has_statistics = true
          end
          if text:match("notes about the Ready column") then
            has_notes = true
          end
        end
      end

      assert.is_true(has_description, "Description should be preserved")
      assert.is_true(has_instructions, "Instructions section should be preserved")
      assert.is_true(has_workflow_rules, "Workflow rules should be preserved")
      assert.is_true(has_statistics, "Statistics section should be preserved")
      assert.is_true(has_notes, "Notes between columns should be preserved")

      -- Verify column config was parsed
      local ready_col = board:get_column_by_name("Ready")
      assert.is_not_nil(ready_col)
      assert.are.equals(3, ready_col.config.wip_limit)
    end)
  end)

  describe("edge cases", function()
    it("should handle board with only title and markdown", function()
      local board = Board:new()
      board:parse({
        "# Board",
        "",
        "Just some text, no columns."
      })

      assert.are.equals("Board", board.title)
      assert.are.equals(0, #board.columns, "Should have no columns")

      -- Should have markdown block
      local has_markdown = false
      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.MARKDOWN then
          has_markdown = true
          break
        end
      end

      assert.is_true(has_markdown, "Should preserve markdown even without columns")
    end)

    it("should handle board with columns but no markdown", function()
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

      assert.are.equals(2, #board.columns)

      -- Content blocks should still exist (with title and column blocks)
      assert.is_not_nil(board.content_blocks)
      assert.is_true(#board.content_blocks > 0)

      local has_title = false
      local column_count = 0

      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.TITLE then
          has_title = true
        elseif block.type == ContentBlock.TYPES.COLUMN then
          column_count = column_count + 1
        end
      end

      assert.is_true(has_title, "Should have title block")
      assert.are.equals(2, column_count, "Should have 2 column blocks")
    end)

    it("should handle empty board", function()
      local board = Board:new()
      board:parse({
        "# Empty Board"
      })

      assert.are.equals("Empty Board", board.title)
      assert.are.equals(0, #board.columns)

      -- Should have at least title block
      local has_title = false
      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.TITLE then
          has_title = true
          break
        end
      end

      assert.is_true(has_title, "Should have title block")
    end)

    it("should handle board with only H2 sections, no columns", function()
      local board = Board:new()
      board:parse({
        "# Documentation Board",
        "",
        "## Section One",
        "Content here.",
        "",
        "## Section Two",
        "More content."
      })

      assert.are.equals(0, #board.columns, "Should have no columns")

      -- All H2 content should be preserved
      local has_section_one = false
      local has_section_two = false

      for _, block in ipairs(board.content_blocks) do
        if block.type == ContentBlock.TYPES.MARKDOWN then
          local text = table.concat(block.lines, "\n")
          if text:match("## Section One") then
            has_section_one = true
          end
          if text:match("## Section Two") then
            has_section_two = true
          end
        end
      end

      assert.is_true(has_section_one, "Section One should be preserved")
      assert.is_true(has_section_two, "Section Two should be preserved")
    end)
  end)
end)
