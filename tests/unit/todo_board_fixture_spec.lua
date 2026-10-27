-- tests/unit/todo_board_fixture_spec.lua
-- Regression cover for a real board. tests/fixtures/boards/todo_multi_paragraph_card.md
-- is this project's TODO.kanban.md as it stood when the bug was found: the
-- "Add an on_update trigger" card holds several paragraphs separated by blank
-- lines, with nested lists. Each write used to split it, turning the text after
-- each blank line into column prose and every list item after that prose into
-- a new card with a fresh id.
require('polyfills.vim')

local Board = require('kanban-md.board')

local function read_fixture(path)
  local file = assert(io.open(path, "r"), "Could not open " .. path)
  local content = file:read("*a")
  file:close()
  return content
end

local ON_UPDATE_ID = "card_01M5XM5JDXD78Y24AVQV43NQ5K"

local function card_ids(board)
  local ids = {}
  for _, column in ipairs(board.columns) do
    for _, card in ipairs(column.cards) do
      table.insert(ids, card.properties.id)
    end
  end
  return ids
end

describe("TODO board with a multi-paragraph card", function()
  local content

  before_each(function()
    content = read_fixture("tests/fixtures/boards/todo_multi_paragraph_card.md")
  end)

  it("parses the multi-paragraph card as one card", function()
    local board = Board:new()
    board:parse(content)

    local card = board:find_task(ON_UPDATE_ID)
    assert.is_not_nil(card)
    assert.equals(
      "Add an on_update trigger point and Board:update_card so card text and property edits go through the engine",
      card.text)
    assert.equals(3, card.properties.complexity)

    -- From the first continuation line to the last, blank lines and all
    assert.equals(71, #card.content_lines)
    assert.equals("    **Why**", card.content_lines[2])
    assert.equals("       - Find the card's column (card.column holds the column id; the archive counts). Raise an error if the ",
      card.content_lines[24])
    assert.equals("    The on_stay drift would be worth its own card on the engine board.", card.content_lines[71])
  end)

  it("has no card without an authored id", function()
    local board = Board:new()
    board:parse(content)

    local backlog = board:get_column_by_name("Backlog")
    assert.equals(6, #backlog.cards)
    for _, card in ipairs(backlog.cards) do
      assert.is_string(card.properties.id)
    end
  end)

  it("keeps every card and id through a write and re-parse", function()
    local board = Board:new()
    board:parse(content)
    local written = board:write()

    local reparsed = Board:new()
    reparsed:parse(written)

    assert.same(card_ids(board), card_ids(reparsed))
    assert.same(board:find_task(ON_UPDATE_ID).content_lines, reparsed:find_task(ON_UPDATE_ID).content_lines)
    assert.same(written, reparsed:write())
  end)

  it("changes only the card's property comment placement on write", function()
    local board = Board:new()
    board:parse(content)
    local written = table.concat(board:write(), "\n")

    -- SPEC 7.8: a standalone property comment is re-emitted inline
    local expected = content:gsub(
      "go through the engine\n<!%-%- complexity: 3, id: " .. ON_UPDATE_ID .. " %-%->",
      "go through the engine <!-- complexity: 3, id: " .. ON_UPDATE_ID .. " -->")
    local backlog_written = written:match("###### Backlog.-###### Ready")
    local backlog_expected = expected:match("###### Backlog.-###### Ready")
    assert.equals(backlog_expected, backlog_written)
  end)
end)
