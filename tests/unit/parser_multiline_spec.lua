require('polyfills.vim')

local Board = require('kanban-md.board')
local adapter_registry = require('kanban-md.adapter_registry')
local CLIAdapter = require('kanban-md.adapters.cli')

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

      -- The documentation is held by the column, above the card it precedes
      assert.same({
        { before = todo_col.cards[2], lines = { "", "Some documentation here", "" } },
      }, todo_col.interleaved_markdown)
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

  describe("Nested lists", function()
    -- An indented list item straight after a card is a nested list in the
    -- card's content, not a new card. Before this was fixed each sub-item
    -- became a card of its own, and saving the board gave every one of them
    -- a fresh id.
    local content = [[
# Test Board
<!-- kanban:config persist_card_ids: true -->

###### TODO

- Card with a nested list <!-- id: card_parent -->
    The card's description:
      - first sub-item
      - second sub-item
          - a deeper item
    More description.
- Next card <!-- id: card_next -->
]]

    it("keeps indented list items as continuation lines of the card", function()
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(2, #todo_col.cards)

      local card = todo_col.cards[1]
      assert.equals("Card with a nested list", card.text)
      assert.equals("card_parent", card.properties.id)
      assert.same({
        "- Card with a nested list",
        "    The card's description:",
        "      - first sub-item",
        "      - second sub-item",
        "          - a deeper item",
        "    More description.",
      }, card.content_lines)

      assert.equals("Next card", todo_col.cards[2].text)
      assert.equals("card_next", todo_col.cards[2].properties.id)
    end)

    it("survives a write and re-parse without new cards or ids", function()
      local board = Board:new()
      board:parse(content)
      local written = board:write()

      local reparsed = Board:new()
      reparsed:parse(written)

      local todo_col = reparsed:get_column_by_name("TODO")
      assert.equals(2, #todo_col.cards)
      assert.equals("card_parent", todo_col.cards[1].properties.id)
      assert.equals(6, #todo_col.cards[1].content_lines)
      assert.equals("card_next", todo_col.cards[2].properties.id)
      assert.same(written, reparsed:write())
    end)

    it("still reads an unindented list item after a nested list as a new card", function()
      local board = Board:new()
      board:parse([[
# Test Board

###### TODO

- Card 1
  - sub-item
- Card 2
]])

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(2, #todo_col.cards)
      assert.same({ "- Card 1", "  - sub-item" }, todo_col.cards[1].content_lines)
      assert.equals("Card 2", todo_col.cards[2].text)
    end)
  end)

  describe("Blank lines inside a card", function()
    -- As in CommonMark, a blank line followed by an indented line does not end
    -- the card, so a card can hold several paragraphs. Before this was fixed
    -- the indented text after a blank line became column prose, any list item
    -- in it became a new card with a fresh id, and the write moved the prose
    -- below the column's last card.
    local content = [[
# Test Board
<!-- kanban:config persist_card_ids: true -->

###### TODO

- Card with paragraphs <!-- id: card_parent -->
    **Why**
    - a reason

    **What to build**
    1. A step, with sub-steps:
       - a sub-step

    **Tests**
    - a test
- Next card <!-- id: card_next -->
]]

    it("keeps indented content after a blank line in the card", function()
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(2, #todo_col.cards)
      assert.same({
        "- Card with paragraphs",
        "    **Why**",
        "    - a reason",
        "",
        "    **What to build**",
        "    1. A step, with sub-steps:",
        "       - a sub-step",
        "",
        "    **Tests**",
        "    - a test",
      }, todo_col.cards[1].content_lines)
      assert.equals("card_next", todo_col.cards[2].properties.id)
    end)

    it("writes the card back exactly as authored", function()
      local board = Board:new()
      board:parse(content)

      assert.equals(content, table.concat(board:write(), "\n") .. "\n")
    end)

    it("leaves a blank line before the next card outside the card", function()
      local board = Board:new()
      board:parse([[
# Test Board

###### TODO

- Card 1
  continuation

- Card 2
]])

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(2, #todo_col.cards)
      assert.same({ "- Card 1", "  continuation" }, todo_col.cards[1].content_lines)
    end)

    it("still ends the card at an unindented line after a blank line", function()
      local board = Board:new()
      board:parse([[
# Test Board

###### TODO

- Card 1

Column prose
  indented prose
]])

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(1, #todo_col.cards)
      assert.is_nil(todo_col.cards[1].content_lines)
    end)
  end)

  describe("Indented cards", function()
    -- A card written with a task_indent is a sibling of the card above it,
    -- not part of its content: continuation is judged against the card's own
    -- indentation, not the left margin.
    it("reads consecutive indented cards as separate cards", function()
      local board = Board:new()
      board:parse([[
# Test Board

###### TODO

  - Card 1
    continuation
  - Card 2

  - Card 3
]])

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(3, #todo_col.cards)
      assert.same({ "  - Card 1", "    continuation" }, todo_col.cards[1].content_lines)
      assert.equals("Card 2", todo_col.cards[2].text)
      assert.equals("Card 3", todo_col.cards[3].text)
    end)

    it("counts a tab as indentation to the next multiple of four", function()
      local board = Board:new()
      board:parse("###### TODO\n\n  - Card 1\n\tcontinuation\n   - Card 2\n")

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(1, #todo_col.cards)
      assert.same({ "  - Card 1", "\tcontinuation", "   - Card 2" }, todo_col.cards[1].content_lines)
    end)
  end)

  describe("Edge case: empty list item", function()
    -- features/multiline-lists.md, "Empty Cards": a bullet with nothing after
    -- it is CommonMark-valid but gives a card no usable text. The decision
    -- was to break with CommonMark, keep the line as documentation rather
    -- than a card (unchanged parsing behaviour), and report it through the
    -- adapter at warn level. CLAUDE.md is explicit that this must be asserted
    -- as the exact emitted string, including the CLI adapter's emoji prefix,
    -- not merely that parsing did not error.
    local old_stderr
    local captured_err
    local previous_adapter

    before_each(function()
      captured_err = {}
      old_stderr = io.stderr
      io.stderr = {
        write = function(_, msg) table.insert(captured_err, msg) end,
        flush = function() end,
      }

      previous_adapter = adapter_registry.has_adapter() and adapter_registry.get_adapter() or nil
      adapter_registry.set_adapter(CLIAdapter)
    end)

    after_each(function()
      io.stderr = old_stderr
      adapter_registry.set_adapter(previous_adapter)
    end)

    local function stderr_output()
      return table.concat(captured_err, "")
    end

    it("warns with the exact adapter-prefixed string for a bare dash", function()
      local content = [[
# Test Board

###### TODO

-
  continuation

]]
      local board = Board:new()
      board:parse(content)

      assert.equals("⚠️ List items may not start with a blank line\n", stderr_output())
    end)

    it("warns for a dash followed only by whitespace", function()
      local content = [[
# Test Board

###### TODO

-
  continuation

]]
      local board = Board:new()
      board:parse(content)

      assert.equals("⚠️ List items may not start with a blank line\n", stderr_output())
    end)

    it("keeps the bare-dash line as column documentation, not a card", function()
      local content = [[
# Test Board

###### TODO

-
  continuation

- Real card
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(1, #todo_col.cards)
      assert.equals("Real card", todo_col.cards[1].text)
    end)

    it("does not warn for an empty item in a card's nested list", function()
      local content = [[
# Test Board

###### TODO

- Card with a nested list
  - sub-item
  -
]]
      local board = Board:new()
      board:parse(content)

      local todo_col = board:get_column_by_name("TODO")
      assert.equals(1, #todo_col.cards)
      assert.equals(3, #todo_col.cards[1].content_lines)
      assert.equals("", stderr_output())
    end)

    it("says nothing when no adapter is registered", function()
      adapter_registry.set_adapter(nil)

      local content = [[
# Test Board

###### TODO

-
  continuation
]]
      local board = Board:new()

      assert.has_no.errors(function()
        board:parse(content)
      end)
      assert.equals("", stderr_output())
    end)
  end)
end)
