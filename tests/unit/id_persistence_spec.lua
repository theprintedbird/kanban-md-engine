-- Test ID persistence when persist_card_ids is enabled
require('polyfills.vim')

describe("ID Persistence with persist_card_ids", function()
  local Board, Card, kanban_md

  before_each(function()
    Board = require("kanban-md.board")
    Card = require("kanban-md.card")
    kanban_md = require("kanban-md.cli")
  end)

  after_each(function()
    -- Reset config to defaults
    local config_module = require("kanban-md.config")
    config_module.reset()
  end)

  it("should sync card.id to card.properties.id when persist_card_ids is true", function()
    -- Enable persist_card_ids and setup plugin (registers triggers)
    kanban_md.setup({ persist_card_ids = true, auto_id = true })

    -- Create a card without an ID (should trigger ID generation)
    local card = Card:new(nil, "Test card", {})

    -- Verify ID was generated on card.id
    assert.is_not_nil(card.id)
    assert.is_string(card.id)
    assert.is_true(#card.id > 0)

    -- Verify ID was synced to card.properties.id
    assert.are.equals(card.id, card.properties.id)
  end)

  it("should NOT sync card.id to card.properties.id when persist_card_ids is false", function()
    -- Disable persist_card_ids (default)
    kanban_md.setup({ persist_card_ids = false, auto_id = true })

    -- Create a card without an ID
    local card = Card:new(nil, "Test card", {})

    -- Verify ID was generated on card.id
    assert.is_not_nil(card.id)
    assert.is_string(card.id)

    -- Verify ID was NOT synced to card.properties.id
    assert.is_nil(card.properties.id)
  end)

  it("should persist IDs in markdown when persist_card_ids is true", function()
    -- Enable persist_card_ids
    kanban_md.setup({ persist_card_ids = true, auto_id = true })

    -- Create a board with a card
    local board = Board:new()
    board.title = "Test Board"

    -- Add a column
    board:add_new_column("Todo")
    local todo_column = board:get_column_by_name("Todo")

    -- Add a card (ID should be generated)
    local card = Card:new(nil, "Test task", {})
    table.insert(todo_column.cards, card)

    -- Store the generated ID
    local original_id = card.id
    assert.is_not_nil(original_id)

    -- Write board to markdown
    local markdown_lines = board:write()
    local markdown = table.concat(markdown_lines, "\n")

    -- Verify ID appears in markdown
    assert.is_true(markdown:find(original_id) ~= nil, "ID should appear in markdown")
    assert.is_true(markdown:find("id: " .. original_id) ~= nil, "ID should be in properties comment")

    -- Parse it back
    local board2 = Board:new()
    board2:parse(markdown)

    -- Get the card from parsed board
    local todo_column2 = board2:get_column_by_name("Todo")
    assert.are.equals(1, #todo_column2.cards)
    local parsed_card = todo_column2.cards[1]

    -- Verify ID persisted through round-trip
    assert.are.equals(original_id, parsed_card.id)
    assert.are.equals(original_id, parsed_card.properties.id)
  end)

  it("should NOT persist IDs in markdown when persist_card_ids is false", function()
    -- Disable persist_card_ids
    kanban_md.setup({ persist_card_ids = false, auto_id = true })

    -- Create a board with a card
    local board = Board:new()
    board.title = "Test Board"

    -- Add a column
    board:add_new_column("Todo")
    local todo_column = board:get_column_by_name("Todo")

    -- Add a card (ID should be generated but not persisted)
    local card = Card:new(nil, "Test task", {})
    table.insert(todo_column.cards, card)

    -- Store the generated ID
    local original_id = card.id
    assert.is_not_nil(original_id)

    -- Write board to markdown
    local markdown_lines = board:write()
    local markdown = table.concat(markdown_lines, "\n")

    -- Verify ID does NOT appear in markdown
    assert.is_false(markdown:find("id:") ~= nil, "ID should not appear in markdown")

    -- Parse it back
    local board2 = Board:new()
    board2:parse(markdown)

    -- Get the card from parsed board
    local todo_column2 = board2:get_column_by_name("Todo")
    assert.are.equals(1, #todo_column2.cards)
    local parsed_card = todo_column2.cards[1]

    -- Verify NEW ID was generated (different from original)
    assert.is_not_nil(parsed_card.id)
    assert.not_equals(original_id, parsed_card.id, "Should generate new ID since it wasn't persisted")
  end)

  it("should handle cards with pre-existing IDs correctly", function()
    -- Enable persist_card_ids
    kanban_md.setup({ persist_card_ids = true, auto_id = true })

    -- Create a card WITH an existing ID
    local existing_id = "card_existing123"
    local card = Card:new(existing_id, "Test card", {})

    -- Verify the existing ID is preserved
    assert.are.equals(existing_id, card.id)

    -- When persist_card_ids is true, it should sync to properties
    assert.are.equals(existing_id, card.properties.id)
  end)
end)
