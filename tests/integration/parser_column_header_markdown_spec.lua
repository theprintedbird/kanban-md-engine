-- tests/integration/parser_column_header_markdown_spec.lua
-- Integration test for column header markdown preservation
require('polyfills.vim')

describe("Column header markdown preservation", function()
  local Board

  before_each(function()
    Board = require("kanban-md.board")
  end)

  it("should preserve markdown between column header and first card", function()
    local content = [[# Test Board

###### Backlog

To Do - Medium Term

Language-Agnostic Infrastructure

- First card <!-- backlog: 1763431283 -->
- Second card <!-- backlog: 1763431283 -->

###### In Progress

- Active card <!-- in_progress: 1763431283 -->
]]

    local board = Board:new()
    board:parse(content)

    -- Check that the Backlog column has header_markdown
    local backlog = board:get_column_by_name("Backlog")
    assert.is_not_nil(backlog)
    assert.is_not_nil(backlog.header_markdown)
    assert.are.equal(5, #backlog.header_markdown)
    assert.are.equal("", backlog.header_markdown[1])  -- blank line
    assert.are.equal("To Do - Medium Term", backlog.header_markdown[2])
    assert.are.equal("", backlog.header_markdown[3])  -- blank line
    assert.are.equal("Language-Agnostic Infrastructure", backlog.header_markdown[4])
    assert.are.equal("", backlog.header_markdown[5])  -- blank line before the first card

    -- Check that cards are parsed correctly
    assert.are.equal(2, #backlog.cards)
    assert.are.equal("First card", backlog.cards[1].text)
    assert.are.equal("Second card", backlog.cards[2].text)

    -- Check that In Progress column has header_markdown with just a blank line
    local in_progress = board:get_column_by_name("In Progress")
    assert.is_not_nil(in_progress)
    assert.is_not_nil(in_progress.header_markdown)
    assert.are.equal(1, #in_progress.header_markdown)
    assert.are.equal("", in_progress.header_markdown[1])
    assert.are.equal(1, #in_progress.cards)
  end)

  it("should write header markdown before cards", function()
    local content = [[# Test Board

###### Backlog

Section Title

Some description text

- Card 1 <!-- backlog: 1763431283 -->
- Card 2 <!-- backlog: 1763431283 -->
]]

    local board = Board:new()
    board:parse(content)

    -- Write back
    local written_lines = board:write()
    local written_content = table.concat(written_lines, "\n")

    -- Verify that header markdown appears before cards
    assert.is_truthy(written_content:match("###### Backlog"))
    assert.is_truthy(written_content:match("Section Title"))
    assert.is_truthy(written_content:match("Some description text"))

    -- Check order: header -> markdown -> cards
    local header_pos = written_content:find("###### Backlog")
    local section_pos = written_content:find("Section Title")
    local card1_pos = written_content:find("- Card 1")

    assert.is_truthy(header_pos < section_pos, "Header should come before section title")
    assert.is_truthy(section_pos < card1_pos, "Section title should come before cards")
  end)

  it("should preserve header markdown on round-trip", function()
    local content = [[# Test Board

###### Backlog

To Do - Medium Term

Language-Agnostic Infrastructure

- Create composite action <!-- backlog: 1763431283 -->

###### Ready

###### Done
]]

    local board = Board:new()
    board:parse(content)

    -- Write back
    local written_lines = board:write()
    local written_content = table.concat(written_lines, "\n")

    -- Parse again
    local board2 = Board:new()
    board2:parse(written_content)

    -- Check that header_markdown is preserved
    local backlog2 = board2:get_column_by_name("Backlog")
    assert.is_not_nil(backlog2)
    assert.is_not_nil(backlog2.header_markdown)

    -- Verify content
    local found_medium = false
    local found_infrastructure = false
    for _, line in ipairs(backlog2.header_markdown) do
      if line:match("To Do %- Medium Term") then
        found_medium = true
      end
      if line:match("Language%-Agnostic Infrastructure") then
        found_infrastructure = true
      end
    end
    assert.is_truthy(found_medium, "Should find 'To Do - Medium Term' in header markdown")
    assert.is_truthy(found_infrastructure, "Should find 'Language-Agnostic Infrastructure' in header markdown")
  end)

  it("should handle empty columns without header markdown", function()
    local content = [[# Test Board

###### Backlog

###### Ready

###### Done
]]

    local board = Board:new()
    board:parse(content)

    local backlog = board:get_column_by_name("Backlog")
    local ready = board:get_column_by_name("Ready")
    local done = board:get_column_by_name("Done")

    assert.is_not_nil(backlog)
    assert.is_not_nil(ready)
    assert.is_not_nil(done)

    -- Empty columns should not have header_markdown
    assert.is_nil(backlog.header_markdown)
    assert.is_nil(ready.header_markdown)
    assert.is_nil(done.header_markdown)
  end)

  it("should not confuse header markdown with inter-card markdown", function()
    local content = [[# Test Board

###### Backlog

Header text

- Card 1 <!-- backlog: 1 -->

Inter-card text

- Card 2 <!-- backlog: 2 -->
]]

    local board = Board:new()
    board:parse(content)

    local backlog = board:get_column_by_name("Backlog")
    assert.is_not_nil(backlog)

    -- Header markdown should only contain "Header text" and blank line
    assert.is_not_nil(backlog.header_markdown)
    local has_header_text = false
    for _, line in ipairs(backlog.header_markdown) do
      if line:match("Header text") then
        has_header_text = true
      end
      -- Should NOT contain inter-card text
      assert.is_falsy(line:match("Inter%-card text"))
    end
    assert.is_truthy(has_header_text, "Should have header text")

    -- Should have 2 cards
    assert.are.equal(2, #backlog.cards)
  end)
end)
