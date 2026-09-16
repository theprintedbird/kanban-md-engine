-- tests/unit/parser_code_fence_spec.lua
-- Fenced code blocks are literal markdown: nothing inside a fence is kanban
-- syntax, however much it looks like a column header, a card or a property
-- comment.
require('polyfills.vim')

local Board = require('kanban-md.board')

local function parse(markdown)
  local board = Board:new()
  board:parse(markdown)
  return board
end

describe("Parser - fenced code blocks", function()
  it("does not read H6 headers inside a fence as columns", function()
    local board = parse(table.concat({
      "# Docs Board",
      "",
      "###### To Do",
      "- Real card",
      "",
      "## Usage",
      "",
      "```markdown",
      "###### Example Column",
      "- Example card <!-- complexity: 3 -->",
      "```",
      "",
    }, "\n"))

    assert.are.equal(1, #board.columns)
    assert.are.equal("To Do", board.columns[1].name)
    assert.are.equal(1, #board.columns[1].cards)
    assert.are.equal("Real card", board.columns[1].cards[1].text)
  end)

  it("does not read list items inside a fence as cards", function()
    local board = parse(table.concat({
      "# Docs Board",
      "",
      "###### To Do",
      "- Real card",
      "",
      "```markdown",
      "- Fenced task <!-- complexity: 5 automatically -->",
      "```",
      "",
    }, "\n"))

    assert.are.equal(1, #board.columns[1].cards)
    assert.are.equal("Real card", board.columns[1].cards[1].text)
  end)

  it("does not read a board title inside a fence", function()
    local board = parse(table.concat({
      "# Real Title",
      "",
      "```markdown",
      "# Fenced Title",
      "```",
      "",
    }, "\n"))

    assert.are.equal("Real Title", board.title)
  end)

  it("does not apply config comments inside a fence", function()
    local board = parse(table.concat({
      "# Docs Board",
      "<!-- kanban:config wip_limit: 7 -->",
      "",
      "```markdown",
      "<!-- kanban:config wip_limit: 99 -->",
      "```",
      "",
    }, "\n"))

    assert.are.equal(7, board.config.wip_limit)
  end)

  it("preserves fenced content verbatim through a write cycle", function()
    local source = table.concat({
      "# Docs Board",
      "",
      "###### To Do",
      "- Real card",
      "",
      "## Usage",
      "",
      "```markdown",
      "###### Example Column",
      "- Example card <!-- complexity: 3 -->",
      "```",
      "",
    }, "\n")

    local written = table.concat(parse(source):write(), "\n")

    assert.matches("```markdown", written, 1, true)
    assert.matches("###### Example Column", written, 1, true)
    assert.matches("- Example card <!-- complexity: 3 -->", written, 1, true)

    -- And re-parsing the output still finds exactly one column.
    assert.are.equal(1, #parse(written).columns)
  end)

  it("handles tilde fences", function()
    local board = parse(table.concat({
      "# Docs Board",
      "",
      "###### To Do",
      "- Real card",
      "",
      "~~~markdown",
      "###### Example Column",
      "~~~",
      "",
    }, "\n"))

    assert.are.equal(1, #board.columns)
  end)

  it("only closes a fence with a matching marker", function()
    local board = parse(table.concat({
      "# Docs Board",
      "",
      "###### To Do",
      "- Real card",
      "",
      "```markdown",
      "~~~",
      "###### Still Fenced",
      "```",
      "",
      "###### Second Column",
      "- Second card",
      "",
    }, "\n"))

    assert.are.equal(2, #board.columns)
    assert.are.equal("To Do", board.columns[1].name)
    assert.are.equal("Second Column", board.columns[2].name)
  end)

  -- CommonMark: an unclosed fence runs to the end of the document. So a
  -- stray ``` hides the columns below it from the board model. The content
  -- itself is still preserved verbatim, so writing the board back does not
  -- lose it, and closing the fence brings the columns back.
  it("treats an unclosed fence as running to the end of the file", function()
    local source = table.concat({
      "# Docs Board",
      "",
      "###### To Do",
      "- Real card",
      "",
      "```markdown",
      "",
      "###### Hidden Column",
      "- Hidden card",
      "",
    }, "\n")

    local board = parse(source)

    assert.are.equal(1, #board.columns)
    assert.are.equal("To Do", board.columns[1].name)

    -- Nothing is lost on the way back out.
    local written = table.concat(board:write(), "\n")
    assert.matches("###### Hidden Column", written, 1, true)
    assert.matches("- Hidden card", written, 1, true)
  end)

  it("keeps a fence inside a card's continuation lines with the card", function()
    local board = parse(table.concat({
      "# Docs Board",
      "",
      "###### To Do",
      "- Card with code",
      "  ```lua",
      "  -- not a card",
      "  local x = 1",
      "  ```",
      "- Second card",
      "",
    }, "\n"))

    local cards = board.columns[1].cards
    assert.are.equal(2, #cards)
    assert.are.equal("Card with code", cards[1].text)
    assert.are.equal("Second card", cards[2].text)
    -- content_lines includes the card's own first line, then the fence.
    assert.are.same({
      "- Card with code",
      "  ```lua",
      "  -- not a card",
      "  local x = 1",
      "  ```",
    }, cards[1].content_lines)
  end)
end)
