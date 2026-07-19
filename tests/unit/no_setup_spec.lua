-- tests/unit/no_setup_spec.lua
-- Exercises kanban-md purely as a library: this spec deliberately does NOT
-- call require('helpers.setup').setup() (i.e. no kanban-md.cli setup(), no
-- CLIAdapter registration, no class-level ULID on_create triggers on
-- Board/Column/Card). It only pulls in the vim.* shims needed to load the
-- modules outside Neovim.
--
-- This is the path a bare `require('kanban-md.board')` consumer is on
-- before ever calling setup() -- see plan Task 10 ("no test exercises the
-- engine without setup(), the pure-library path").
require('polyfills.vim')

local Board = require('kanban-md.board')

describe("kanban-md as a pure library (setup() never called)", function()
  it("parses and writes a simple board without requiring setup()", function()
    local markdown = table.concat({
      "# Pure Library Board",
      "",
      "###### Todo",
      "",
      "- First task",
      "- Second task",
      "",
      "###### Done",
      "",
      "- Finished task",
      "",
    }, "\n")

    local board = Board:new()
    board:parse(markdown)

    assert.are.equal("Pure Library Board", board.title)
    assert.are.equal(2, #board.columns)
    assert.are.equal("Todo", board.columns[1].name)
    assert.are.equal("Done", board.columns[2].name)

    assert.are.equal(2, #board.columns[1].cards)
    assert.are.equal("First task", board.columns[1].cards[1].text)
    assert.are.equal("Second task", board.columns[1].cards[2].text)
    assert.are.equal(1, #board.columns[2].cards)
    assert.are.equal("Finished task", board.columns[2].cards[1].text)

    -- Cards parsed without setup() have no id: there is no class-level
    -- on_create trigger to generate one (Card, unlike Board/Column, has no
    -- fallback id generation of its own). This is current expected
    -- behaviour for the pure-library path, not a bug under test here --
    -- callers who want ids opt in via require('helpers.setup').setup()
    -- (or register their own on_create trigger).
    assert.is_nil(board.columns[1].cards[1].id)
    assert.is_nil(board.columns[1].cards[2].id)
    assert.is_nil(board.columns[2].cards[1].id)

    local written = table.concat(board:write(), "\n")
    assert.is_true(written:find("Pure Library Board", 1, true) ~= nil)
    assert.is_true(written:find("First task", 1, true) ~= nil)
    assert.is_true(written:find("Finished task", 1, true) ~= nil)

    -- write() round-trips through parse() again to the same structure.
    local board2 = Board:new()
    board2:parse(written)

    assert.are.equal(board.title, board2.title)
    assert.are.equal(#board.columns, #board2.columns)
    for i, column in ipairs(board.columns) do
      assert.are.equal(column.name, board2.columns[i].name)
      assert.are.equal(#column.cards, #board2.columns[i].cards)
      for j, card in ipairs(column.cards) do
        assert.are.equal(card.text, board2.columns[i].cards[j].text)
      end
    end
  end)
end)
