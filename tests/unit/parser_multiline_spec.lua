require('polyfills.vim')

local Board = require('kanban-md.board')

describe("Parser - Multi-line list items", function()
  describe("Single-line cards (no regression)", function()
    it("should parse single-line cards as before", function()
      local content = [[
# Test Board

###### TODO

- Simple card
- Another simple card
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.is_not_nil(todo_col)
      assert.equals(2, #todo_col.cards)
      assert.equals("Simple card", todo_col.cards[1].text)
      assert.equals("Another simple card", todo_col.cards[2].text)
      assert.is_nil(todo_col.cards[1].content_lines)
      assert.is_nil(todo_col.cards[2].content_lines)
    end)
  end)

  describe("Two-line card (basic continuation)", function()
    it("should parse a card with one continuation line", function()
      local content = [[
# Test Board

###### TODO

- Card with continuation
  this is a continuation
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.is_not_nil(todo_col)
      assert.equals(1, #todo_col.cards)

      local card = todo_col.cards[1]
      assert.equals("Card with continuation", card.text)
      assert.is_not_nil(card.content_lines)
      assert.equals(2, #card.content_lines)
      assert.equals("- Card with continuation", card.content_lines[1])
      assert.equals("  this is a continuation", card.content_lines[2])
    end)
  end)

  describe("Multi-line card (3+ continuation lines)", function()
    it("should parse a card with multiple continuation lines", function()
      local content = [[
# Test Board

###### TODO

- Card with many lines
  continuation 1
  continuation 2
  continuation 3
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(1, #todo_col.cards)

      local card = todo_col.cards[1]
      assert.equals("Card with many lines", card.text)
      assert.equals(4, #card.content_lines)
      assert.equals("- Card with many lines", card.content_lines[1])
      assert.equals("  continuation 1", card.content_lines[2])
      assert.equals("  continuation 2", card.content_lines[3])
      assert.equals("  continuation 3", card.content_lines[4])
    end)
  end)

  describe("Multiple cards with continuations", function()
    it("should parse multiple cards with mixed continuation patterns", function()
      local content = [[
# Test Board

###### TODO

- Card 1
  with continuation
- Card 2
- Card 3
  with multiple
  continuation lines
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(3, #todo_col.cards)

      -- Card 1: multiline
      assert.equals("Card 1", todo_col.cards[1].text)
      assert.equals(2, #todo_col.cards[1].content_lines)

      -- Card 2: single line
      assert.equals("Card 2", todo_col.cards[2].text)
      assert.is_nil(todo_col.cards[2].content_lines)

      -- Card 3: multiline
      assert.equals("Card 3", todo_col.cards[3].text)
      assert.equals(3, #todo_col.cards[3].content_lines)
    end)
  end)

  describe("Column documentation before cards", function()
    it("should preserve column documentation before first card", function()
      local content = [[
# Test Board

###### TODO

This is column documentation

- First card
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(1, #todo_col.cards)
      assert.equals("First card", todo_col.cards[1].text)

      -- Check column header_markdown for documentation
      assert.is_not_nil(todo_col.header_markdown)
      local found_doc = false
      for _, line in ipairs(todo_col.header_markdown) do
        if line:match("This is column documentation") then
          found_doc = true
          break
        end
      end
      assert.is_true(found_doc)
    end)
  end)

  describe("Column documentation after cards (blank line separator)", function()
    it("should preserve column documentation after cards with blank line", function()
      local content = [[
# Test Board

###### TODO

- First card

This is documentation after a blank line
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(1, #todo_col.cards)

      -- Check content blocks for documentation
      local found_doc = false
      for _, block in ipairs(board.content_blocks) do
        if block.type == "markdown" then
          local content_str = table.concat(block.lines or {}, "\n")
          if content_str:match("This is documentation after a blank line") then
            found_doc = true
            break
          end
        end
      end
      assert.is_true(found_doc)
    end)
  end)

  describe("Column documentation between cards", function()
    it("should preserve column documentation between cards", function()
      local content = [[
# Test Board

###### TODO

- Card 1

Some documentation here

- Card 2
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(2, #todo_col.cards)

      -- Check content blocks for documentation
      local found_doc = false
      for _, block in ipairs(board.content_blocks) do
        if block.type == "markdown" then
          local content_str = table.concat(block.lines or {}, "\n")
          if content_str:match("Some documentation here") then
            found_doc = true
            break
          end
        end
      end
      assert.is_true(found_doc)
    end)
  end)

  describe("Cards with inline properties AND continuation lines", function()
    it("should parse properties on first line and preserve continuations", function()
      local content = [[
# Test Board

###### TODO

- Card with properties <!-- complexity: 5 -->
  this is a continuation
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(1, #todo_col.cards)

      local card = todo_col.cards[1]
      assert.equals("Card with properties", card.text)
      assert.equals(5, card.properties.complexity)
      assert.equals(2, #card.content_lines)
      -- First line should have properties removed in content_lines
      assert.equals("- Card with properties", card.content_lines[1])
    end)
  end)

  describe("Edge case: blank line within list breaks to documentation", function()
    it("should treat content after blank line as documentation", function()
      local content = [[
# Test Board

###### TODO

- Card 1
  continuation

Not a continuation (blank line above)
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(1, #todo_col.cards)

      local card = todo_col.cards[1]
      assert.equals("Card 1", card.text)
      assert.equals(2, #card.content_lines)

      -- "Not a continuation" should be in markdown blocks
      local found_doc = false
      for _, block in ipairs(board.content_blocks) do
        if block.type == "markdown" then
          local content_str = table.concat(block.lines or {}, "\n")
          if content_str:match("Not a continuation") then
            found_doc = true
            break
          end
        end
      end
      assert.is_true(found_doc)
    end)
  end)

  describe("Edge case: card followed immediately by column header", function()
    it("should finalize card when next column starts", function()
      local content = [[
# Test Board

###### TODO

- Card in TODO
###### Done

- Card in Done
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      local done_col = board:get_column_by_name("Done")

      assert.equals(1, #todo_col.cards)
      assert.equals(1, #done_col.cards)
      assert.equals("Card in TODO", todo_col.cards[1].text)
      assert.equals("Card in Done", done_col.cards[1].text)
    end)
  end)

  describe("Tab indentation support", function()
    it("should parse continuation lines with tab indentation", function()
      local content = [[
# Test Board

###### TODO

- Card with tab continuation
	this line starts with a tab
	and this one too
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(1, #todo_col.cards)

      local card = todo_col.cards[1]
      assert.equals("Card with tab continuation", card.text)
      assert.is_not_nil(card.content_lines)
      assert.equals(3, #card.content_lines)
      assert.equals("- Card with tab continuation", card.content_lines[1])
      assert.equals("\tthis line starts with a tab", card.content_lines[2])
      assert.equals("\tand this one too", card.content_lines[3])
    end)

    it("should handle mixed tab and space indentation", function()
      local content = [[
# Test Board

###### TODO

- Card with mixed indentation
  space indented line
	tab indented line
  another space line
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(1, #todo_col.cards)

      local card = todo_col.cards[1]
      assert.equals(4, #card.content_lines)
    end)
  end)

  describe("get_full_text() method", function()
    it("should return single line text for single-line cards", function()
      local content = [[
# Test Board

###### TODO

- Simple card
]]
      local board = Board:new()
      board:parse(content)

      local card = board:get_column_by_name("TODO").cards[1]
      assert.equals("Simple card", card:get_full_text())
    end)

    it("should return all lines joined for multi-line cards", function()
      local content = [[
# Test Board

###### TODO

- Card with continuation
  line 2
  line 3
]]
      local board = Board:new()
      board:parse(content)

      local card = board:get_column_by_name("TODO").cards[1]
      local expected = "- Card with continuation\n  line 2\n  line 3"
      assert.equals(expected, card:get_full_text())
    end)
  end)
end)
