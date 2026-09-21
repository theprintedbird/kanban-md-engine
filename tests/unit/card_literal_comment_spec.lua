require('polyfills.vim')

local Board = require('kanban-md.board')

-- A card's property block is the *last* HTML comment on the line. A literal
-- HTML comment inside the card text used to truncate the card at that comment,
-- because the match was non-greedy and stopped at the first "<!--".
describe("Cards containing a literal HTML comment", function()
  local function parse(markdown)
    local board = Board:new()
    board:parse(markdown)
    return board
  end

  it("keeps text after a literal comment when a property block follows", function()
    local board = parse(
      "# B\n\n###### Todo\n\n- Use a <!-- comment --> in your card <!-- complexity: 2 -->\n\n###### Done\n")
    local card = board.columns[1].cards[1]

    assert.are.equal("Use a <!-- comment --> in your card", card.text)
    assert.are.equal(2, card.properties.complexity)
  end)

  it("keeps a literal comment that is not followed by a property block", function()
    local board = parse(
      "# B\n\n###### Todo\n\n- Explain the <!-- kanban:config --> syntax\n\n###### Done\n")

    assert.are.equal("Explain the <!-- kanban:config --> syntax", board.columns[1].cards[1].text)
  end)

  it("round-trips a literal comment through the writer", function()
    local board = parse(
      "# B\n\n###### Todo\n\n- Use a <!-- comment --> in your card <!-- complexity: 2 -->\n\n###### Done\n")
    local written = table.concat(board:write(), "\n")

    assert.is_not_nil(written:match("%- Use a <!%-%- comment %-%-> in your card <!%-%-"))
  end)

  it("still reads the property block of an ordinary card", function()
    local board = parse("# B\n\n###### Todo\n\n- Plain card <!-- complexity: 5 -->\n\n###### Done\n")
    local card = board.columns[1].cards[1]

    assert.are.equal("Plain card", card.text)
    assert.are.equal(5, card.properties.complexity)
  end)
end)
