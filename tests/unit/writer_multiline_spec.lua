require('polyfills.vim')

local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local Column = require('kanban-md.column')

describe("Writer - Multi-line list items", function()
  describe("Write single-line card (no regression)", function()
    it("should write single-line cards as before", function()
      local board = Board:new()
      board.title = "Test Board"
      local col = Column:new("TODO")
      local card = Card:new(nil, "Simple card", {})
      col:add_card(card)
      board:add_column(col)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      assert.is_not_nil(output_text:match("- Simple card"))
      -- Should not have content_lines
      assert.is_nil(card.content_lines)
    end)
  end)

  describe("Write multi-line card", function()
    it("should write all content lines in order", function()
      local board = Board:new()
      board.title = "Test Board"
      local col = Column:new("TODO")
      local card = Card:new(nil, "Card with continuation", {})
      card.content_lines = {
        "- Card with continuation",
        "  line 2",
        "  line 3"
      }
      col:add_card(card)
      board:add_column(col)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      assert.is_not_nil(output_text:match("- Card with continuation"))
      assert.is_not_nil(output_text:match("  line 2"))
      assert.is_not_nil(output_text:match("  line 3"))
    end)
  end)

  describe("Write card with properties and continuations", function()
    it("should write properties on first line and preserve continuations", function()
      local board = Board:new()
      board.title = "Test Board"

      local col = Column:new("TODO")
      local card = Card:new(nil, "Card text", { complexity = 5, priority = "high" })
      card.content_lines = {
        "- Card text",
        "  continuation line"
      }
      col:add_card(card)
      board:add_column(col)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- Properties should be on first line
      assert.is_not_nil(output_text:match("- Card text <!%-%-"))
      assert.is_not_nil(output_text:match("complexity: 5"))
      assert.is_not_nil(output_text:match("priority: high"))
      -- Continuation should be on separate line
      assert.is_not_nil(output_text:match("  continuation line"))
    end)
  end)

  describe("Preserve indentation of continuation lines", function()
    it("should preserve exact indentation from content_lines", function()
      local board = Board:new()
      board.title = "Test Board"
      local col = Column:new("TODO")
      local card = Card:new(nil, "Card", {})
      card.content_lines = {
        "- Card",
        "  two spaces",
        "    four spaces",
        "      six spaces"
      }
      col:add_card(card)
      board:add_column(col)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      assert.is_not_nil(output_text:match("  two spaces"))
      assert.is_not_nil(output_text:match("    four spaces"))
      assert.is_not_nil(output_text:match("      six spaces"))
    end)
  end)

  describe("Multi-line property comments with multi-line cards", function()
    it("should handle multi-line properties on first line", function()
      local board = Board:new()
      board.title = "Test Board"
      board.config.persist_card_ids = true

      local col = Column:new("TODO")
      local card = Card:new("card-123", "Card", {
        complexity = 5,
        tags = {"tag1", "tag2", "tag3"},
        assignee = "person"
      })
      card.content_lines = {
        "- Card",
        "  continuation"
      }
      col:add_card(card)
      board:add_column(col)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      -- First line should have properties (may wrap)
      assert.is_not_nil(output_text:match("- Card <!%-%-"))
      -- Continuation should be separate
      assert.is_not_nil(output_text:match("  continuation"))
    end)
  end)

  describe("Mixed single and multi-line cards", function()
    it("should correctly write both types in same column", function()
      local board = Board:new()
      board.title = "Test Board"
      local col = Column:new("TODO")

      -- Single-line card
      local card1 = Card:new(nil, "Single", {})
      col:add_card(card1)

      -- Multi-line card
      local card2 = Card:new(nil, "Multi", {})
      card2.content_lines = {
        "- Multi",
        "  with continuation"
      }
      col:add_card(card2)

      -- Another single-line
      local card3 = Card:new(nil, "Another single", {})
      col:add_card(card3)

      board:add_column(col)

      local output = board:write()
      local output_text = table.concat(output, "\n")

      assert.is_not_nil(output_text:match("- Single"))
      assert.is_not_nil(output_text:match("- Multi"))
      assert.is_not_nil(output_text:match("  with continuation"))
      assert.is_not_nil(output_text:match("- Another single"))
    end)
  end)

  describe("Edited text on a multi-line card", function()
    local original = [[
# Test Board

###### TODO

- Old title <!-- priority: high -->
  continuation
]]

    it("writes card.text rather than the parsed first line", function()
      local board = Board:new()
      board:parse(original)
      local card = board:get_column_by_name("TODO").cards[1]
      card.text = "New title"

      local output_text = table.concat(board:write(), "\n")

      assert.is_not_nil(output_text:find("- New title <!-- priority: high -->\n  continuation", 1, true))
      assert.is_nil(output_text:find("Old title", 1, true))
    end)

    it("reflects the edit in get_full_text()", function()
      local board = Board:new()
      board:parse(original)
      local card = board:get_column_by_name("TODO").cards[1]
      card.text = "New title"

      assert.equals("- New title\n  continuation", card:get_full_text())
    end)

    it("applies task_indent to the first line, as for a single-line card", function()
      local board = Board:new()
      board.title = "Test Board"
      board.config.task_indent = "  "
      local col = Column:new("TODO")
      local card = Card:new(nil, "Multi", {})
      card.content_lines = { "- Multi", "    continuation" }
      col:add_card(card)
      board:add_column(col)

      local output = board:write()

      local index
      for i, line in ipairs(output) do
        if line == "  - Multi" then index = i end
      end
      assert.is_not_nil(index)
      assert.equals("    continuation", output[index + 1])
    end)
  end)

  describe("Round-trip fidelity", function()
    it("should preserve exact content through parse-write cycle", function()
      local original = [[
# Test Board

###### TODO

- Card 1
  with continuation
  and more
- Card 2
]]
      local board = Board:new()
      board:parse(original)

      local output = board:write()

      -- Parse again to compare
      local board2 = Board:new()
      board2:parse(output)

      local col1 = board:get_column_by_name("TODO")
      local col2 = board2:get_column_by_name("TODO")

      assert.equals(#col1.cards, #col2.cards)
      assert.equals(col1.cards[1].text, col2.cards[1].text)
      assert.equals(col1.cards[2].text, col2.cards[2].text)

      -- Check content_lines preservation
      assert.equals(#col1.cards[1].content_lines, #col2.cards[1].content_lines)
      for i = 1, #col1.cards[1].content_lines do
        assert.equals(col1.cards[1].content_lines[i], col2.cards[1].content_lines[i])
      end
    end)
  end)
end)
