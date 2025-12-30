-- Test that timestamps are automatically added when auto_timestamp is enabled (default behavior)
require('polyfills.vim')
local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local config = require('kanban-md.config')

describe("Auto-timestamp default behavior", function()
  before_each(function()
    -- Reset to default config
    config.reset()
  end)

  describe("with default config (auto_timestamp = true)", function()
    it("should add timestamp when card is initially placed in a column", function()
      -- Create a board and columns
      local board = Board:new()
      local todo_col = board:add_column("todo", "Todo")

      -- Trigger auto-registration (normally called after parsing or setup)
      board:auto_register_triggers()

      -- Create a new card
      local card = Card:new("card-1", "Test task")

      -- Add card to Todo column (initial placement)
      todo_col:add_card(card)

      -- Card should automatically have a timestamp for the Todo column
      assert.is_not_nil(card.properties.todo, "Card should have 'todo' timestamp after initial placement")
      assert.is_number(card.properties.todo)
    end)

    it("should add timestamps when card moves between columns", function()
      local board = Board:new()
      local todo_col = board:add_column("todo", "Todo")
      local in_progress_col = board:add_column("in_progress", "In Progress")

      board:auto_register_triggers()

      local card = Card:new("card-2", "Test task")
      todo_col:add_card(card)

      local todo_timestamp = card.properties.todo
      assert.is_not_nil(todo_timestamp, "Card should have 'todo' timestamp")

      -- Move to In Progress
      board:move_card(card, todo_col, in_progress_col)

      -- Should have both timestamps
      assert.is_not_nil(card.properties.todo, "Card should still have 'todo' timestamp")
      assert.is_not_nil(card.properties.in_progress, "Card should have 'in_progress' timestamp")
      assert.are.equal(todo_timestamp, card.properties.todo, "Original 'todo' timestamp should be unchanged")
    end)

    it("should work for all columns", function()
      local board = Board:new()
      local col1 = board:add_column("backlog", "Backlog")
      local col2 = board:add_column("ready", "Ready")
      local col3 = board:add_column("done", "Done")

      board:auto_register_triggers()

      local card = Card:new("card-3", "Test task")

      -- Test each column
      col1:add_card(card)
      assert.is_not_nil(card.properties.backlog, "Card should have 'backlog' timestamp")

      board:move_card(card, col1, col2)
      assert.is_not_nil(card.properties.ready, "Card should have 'ready' timestamp")

      board:move_card(card, col2, col3)
      assert.is_not_nil(card.properties.done, "Card should have 'done' timestamp")
    end)
  end)

  describe("when auto_timestamp is disabled", function()
    it("should NOT add timestamps when board config sets auto_timestamp = false", function()
      local board = Board:new()
      board.config.auto_timestamp = false

      local todo_col = board:add_column("todo", "Todo")
      board:auto_register_triggers()

      local card = Card:new("card-4", "Test task")
      todo_col:add_card(card)

      -- Card should NOT have a timestamp
      assert.is_nil(card.properties.todo, "Card should NOT have 'todo' timestamp when auto_timestamp is disabled")
    end)

    it("should NOT add timestamps when plugin config is disabled", function()
      -- Disable at plugin level
      config.setup({ auto_timestamp = false })

      local board = Board:new()
      local todo_col = board:add_column("todo", "Todo")
      board:auto_register_triggers()

      local card = Card:new("card-5", "Test task")
      todo_col:add_card(card)

      -- Card should NOT have a timestamp
      assert.is_nil(card.properties.todo, "Card should NOT have 'todo' timestamp when plugin auto_timestamp is disabled")
    end)
  end)

  describe("board-level config overrides plugin-level config", function()
    it("should respect board.config.auto_timestamp = true even if plugin default is false", function()
      -- Disable at plugin level
      config.setup({ auto_timestamp = false })

      local board = Board:new()
      board.config.auto_timestamp = true  -- Override at board level

      local todo_col = board:add_column("todo", "Todo")
      board:auto_register_triggers()

      local card = Card:new("card-6", "Test task")
      todo_col:add_card(card)

      -- Card SHOULD have a timestamp because board config overrides plugin config
      assert.is_not_nil(card.properties.todo, "Card should have 'todo' timestamp when board config enables it")
    end)

    it("should respect board.config.auto_timestamp = false even if plugin default is true", function()
      -- Enable at plugin level (default)
      config.setup({ auto_timestamp = true })

      local board = Board:new()
      board.config.auto_timestamp = false  -- Override at board level

      local todo_col = board:add_column("todo", "Todo")
      board:auto_register_triggers()

      local card = Card:new("card-7", "Test task")
      todo_col:add_card(card)

      -- Card should NOT have a timestamp because board config overrides plugin config
      assert.is_nil(card.properties.todo, "Card should NOT have 'todo' timestamp when board config disables it")
    end)
  end)
end)
