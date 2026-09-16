-- tests/unit/complexity_demo_fixture_spec.lua
-- Promoted from the old tests/manual-tests/test_complexity_demo.lua, which
-- nothing ever ran. Exercises tests/fixtures/boards/complexity_demo.md: a
-- board that mixes H6 kanban columns with an H2 documentation section and
-- carries explicit complexity properties, including fenced markdown examples
-- that look like kanban syntax but are not (see parser_code_fence_spec).
require('polyfills.vim')

local Board = require('kanban-md.board')

local function read_fixture(path)
  local file = assert(io.open(path, "r"), "Could not open " .. path)
  local content = file:read("*all")
  file:close()
  return content
end

describe("complexity_demo.md fixture", function()
  local content

  before_each(function()
    content = read_fixture("tests/fixtures/boards/complexity_demo.md")
  end)

  it("parses the explicit complexity properties", function()
    local board = Board:new()
    board:parse(content)

    local todo = board.columns[1]
    assert.are.equal("To Do", todo.name)

    assert.are.equal("Simple task", todo.cards[1].text)
    assert.is_nil(todo.cards[1].properties.complexity)

    assert.are.equal("Medium task", todo.cards[2].text)
    assert.are.equal(3, todo.cards[2].properties.complexity)

    assert.are.equal("Complex task", todo.cards[3].text)
    assert.are.equal(5, todo.cards[3].properties.complexity)
  end)

  it("ignores the kanban syntax inside the documentation's code fences", function()
    local board = Board:new()
    board:parse(content)

    assert.are.equal(3, #board.columns)
    assert.are.equal("To Do", board.columns[1].name)
    assert.are.equal("In Progress", board.columns[2].name)
    assert.are.equal("Done", board.columns[3].name)
  end)

  it("preserves complexity through a write/parse cycle", function()
    local board = Board:new()
    board:parse(content)

    local reparsed = Board:new()
    reparsed:parse(table.concat(board:write(), "\n"))

    local todo = reparsed.columns[1]
    assert.is_nil(todo.cards[1].properties.complexity)
    assert.are.equal(3, todo.cards[2].properties.complexity)
    assert.are.equal(5, todo.cards[3].properties.complexity)
  end)
end)
