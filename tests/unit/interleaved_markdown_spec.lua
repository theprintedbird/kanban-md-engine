-- tests/unit/interleaved_markdown_spec.lua
-- Prose and blank lines between two cards of a column stay where they were
-- written (SPEC.md sections 5.2 and 7.2).

-- Load vim polyfill first
require('polyfills.vim')

_G._TEST = true

local Board = require("kanban-md.board")
local Card = require("kanban-md.card")
local config_module = require("kanban-md.config")

describe("Prose between cards", function()
  local original_config

  before_each(function()
    original_config = vim.deepcopy(config_module.get())
    config_module.setup({
      blank_line_after_column_header = false,
      blank_lines_between_sections = false,
      blank_line_after_title = false,
      -- A timestamp written on each move would hide the layout being compared.
      auto_timestamp = false,
      persist_card_ids = false,
    })
  end)

  after_each(function()
    config_module.setup(original_config)
  end)

  local function round_trip(lines)
    local board = Board:new()
    board:parse(lines)
    return board:write()
  end

  -- Parse, move the card with `text` into `to`, and write: one save.
  local function move_and_write(lines, text, to)
    local board = Board:new()
    board:parse(lines)
    for _, column in ipairs(board.columns) do
      for _, card in ipairs(column.cards) do
        if card.text == text then
          board:move_card(card, column, board:get_column_by_name(to))
          return board:write()
        end
      end
    end
    error("no card " .. text)
  end

  local input = {
    "# Board",
    "###### Col A",
    "- Task 1",
    "",
    "Prose between cards.",
    "",
    "- Task 2",
    "- Task 3",
    "",
    "###### Col B",
    "- Task 4",
  }

  it("writes the prose back between the cards it was written between", function()
    assert.same(input, round_trip(input))
  end)

  it("is stable over a second round trip", function()
    assert.same(input, round_trip(round_trip(input)))
  end)

  it("keeps blank lines between two cards in place", function()
    local spaced = {
      "# Board",
      "###### Col A",
      "- Task 1",
      "",
      "- Task 2",
      "",
      "",
      "- Task 3",
      "###### Col B",
    }
    assert.same(spaced, round_trip(spaced))
  end)

  it("keeps prose between cards in the archive in place", function()
    local archived = {
      "# Board",
      "###### Col A",
      "###### __ARCHIVE__",
      "- Task 1",
      "Archived in March.",
      "- Task 2",
    }
    assert.same(archived, round_trip(archived))
  end)

  it("leaves the prose where it was when the card above it moves out", function()
    assert.same({
      "# Board",
      "###### Col A",
      "",
      "Prose between cards.",
      "",
      "- Task 2",
      "- Task 3",
      "",
      "###### Col B",
      "- Task 4",
      "- Task 1",
    }, move_and_write(input, "Task 1", "Col B"))
  end)

  it("keeps the prose in its column when the card below it moves out", function()
    assert.same({
      "# Board",
      "###### Col A",
      "- Task 1",
      "",
      "Prose between cards.",
      "",
      "- Task 3",
      "",
      "###### Col B",
      "- Task 4",
      "- Task 2",
    }, move_and_write(input, "Task 2", "Col B"))
  end)

  it("puts the prose after the last card when every card below it has left", function()
    local there = move_and_write(input, "Task 2", "Col B")
    assert.same({
      "# Board",
      "###### Col A",
      "- Task 1",
      "",
      "Prose between cards.",
      "",
      "",
      "###### Col B",
      "- Task 4",
      "- Task 2",
      "- Task 3",
    }, move_and_write(there, "Task 3", "Col B"))
  end)

  it("puts a card added to the column below the prose", function()
    local board = Board:new()
    board:parse(input)
    board:get_column_by_name("Col A"):add_card(Card:new("card_5", "Task 5", {}))
    local output = board:write()
    assert.same({ "Prose between cards.", "", "- Task 2", "- Task 3", "- Task 5" },
      { output[5], output[6], output[7], output[8], output[9] })
  end)

  it("anchors the prose afresh on every parse", function()
    local there = move_and_write(input, "Task 2", "Col B")
    local back = move_and_write(there, "Task 2", "Col A")
    -- The card returns to the end of the column, below Task 3; the prose
    -- was written above Task 3 by then, so that is where it stays.
    assert.same({
      "# Board",
      "###### Col A",
      "- Task 1",
      "",
      "Prose between cards.",
      "",
      "- Task 3",
      "- Task 2",
      "",
      "###### Col B",
      "- Task 4",
    }, back)
  end)

  describe("with blank_line_after_column_header", function()
    before_each(function()
      config_module.setup({ blank_line_after_column_header = true })
    end)

    it("adds no blank line of its own above prose that becomes the first thing in the column", function()
      local spaced = {
        "# Board",
        "###### Col A",
        "",
        "- Task 1",
        "",
        "- Task 2",
        "###### Col B",
      }
      -- Both blank lines were authored, so both stay; the setting's blank
      -- line is already there and is not added a third time.
      local expected = { "###### Col A", "", "", "- Task 2", "###### Col B" }
      local there = move_and_write(spaced, "Task 1", "Col B")
      assert.same(expected, { there[2], there[3], there[4], there[5], there[6] })

      local again = round_trip(there)
      assert.same(expected, { again[2], again[3], again[4], again[5], again[6] })
    end)
  end)
end)
