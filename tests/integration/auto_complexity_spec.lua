-- Test that complexity is automatically added when use_complexity is enabled
require('polyfills.vim')
local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local config = require('kanban-md.config')

describe("Auto-complexity behavior", function()
  before_each(function()
    -- Reset to default config
    config.reset()
  end)

  describe("cards created outside any board", function()
    it("should NOT get auto-complexity even when use_complexity is enabled", function()
      config.setup({ use_complexity = true, default_complexity = 3 })

      local card = Card:new(nil, "Standalone card", {})

      assert.is_nil(card.properties.complexity,
        "A card with no board context should not get auto-complexity")
    end)
  end)

  describe("with default config (use_complexity = false)", function()
    it("should NOT add complexity when disabled (default)", function()
      local board = Board:new()
      local todo_col = board:add_column("todo", "Todo")

      board:auto_register_triggers()

      local card = Card:new("card-1", "Test task")
      todo_col:add_card(card)

      -- Card should NOT have complexity when use_complexity is false (default)
      assert.is_nil(card.properties.complexity, "Card should NOT have complexity when use_complexity is false")
    end)
  end)

  describe("when use_complexity is enabled at plugin level", function()
    it("should add default complexity when card is initially placed in a column", function()
      -- Enable at plugin level
      config.setup({ use_complexity = true, default_complexity = 2 })

      local board = Board:new()
      local todo_col = board:add_column("todo", "Todo")

      board:auto_register_triggers()

      local card = Card:new("card-2", "Test task")
      todo_col:add_card(card)

      -- Card should automatically have complexity
      assert.is_not_nil(card.properties.complexity, "Card should have complexity when use_complexity is enabled")
      assert.are.equal(2, card.properties.complexity, "Card should have default_complexity value (2)")
    end)

    it("should NOT override existing complexity", function()
      config.setup({ use_complexity = true, default_complexity = 3 })

      local board = Board:new()
      local todo_col = board:add_column("todo", "Todo")

      board:auto_register_triggers()

      -- Create card with existing complexity
      local card = Card:new("card-3", "Test task", { complexity = 5 })
      todo_col:add_card(card)

      -- Card should keep its original complexity
      assert.are.equal(5, card.properties.complexity, "Card should keep existing complexity (5), not use default (3)")
    end)

    it("should work when card moves between columns", function()
      config.setup({ use_complexity = true, default_complexity = 1 })

      local board = Board:new()
      local todo_col = board:add_column("todo", "Todo")
      local in_progress_col = board:add_column("in_progress", "In Progress")

      board:auto_register_triggers()

      -- Card without complexity
      local card = Card:new("card-4", "Test task")
      todo_col:add_card(card)

      assert.are.equal(1, card.properties.complexity, "Card should have complexity after initial placement")

      -- Move to another column
      board:move_card(card, todo_col, in_progress_col)

      -- Complexity should still be 1 (not changed on move)
      assert.are.equal(1, card.properties.complexity, "Card should keep same complexity after moving")
    end)
  end)

  describe("board-level config overrides plugin-level config", function()
    it("should respect board.config.use_complexity = true even if plugin default is false", function()
      -- Disable at plugin level (default)
      config.setup({ use_complexity = false })

      local board = Board:new()
      board.config.use_complexity = true  -- Override at board level
      board.config.default_complexity = 4

      local todo_col = board:add_column("todo", "Todo")
      board:auto_register_triggers()

      local card = Card:new("card-5", "Test task")
      todo_col:add_card(card)

      -- Card SHOULD have complexity because board config overrides plugin config
      assert.is_not_nil(card.properties.complexity, "Card should have complexity when board config enables it")
      assert.are.equal(4, card.properties.complexity, "Card should use board's default_complexity (4)")
    end)

    it("should respect board.config.use_complexity = false even if plugin default is true", function()
      -- Enable at plugin level
      config.setup({ use_complexity = true, default_complexity = 2 })

      local board = Board:new()
      board.config.use_complexity = false  -- Override at board level

      local todo_col = board:add_column("todo", "Todo")
      board:auto_register_triggers()

      local card = Card:new("card-6", "Test task")
      todo_col:add_card(card)

      -- Card should NOT have complexity because board config overrides plugin config
      assert.is_nil(card.properties.complexity, "Card should NOT have complexity when board config disables it")
    end)

    it("should use board.config.default_complexity over plugin config", function()
      -- Set plugin default to 1
      config.setup({ use_complexity = true, default_complexity = 1 })

      local board = Board:new()
      board.config.use_complexity = true
      board.config.default_complexity = 10  -- Different from plugin default

      local todo_col = board:add_column("todo", "Todo")
      board:auto_register_triggers()

      local card = Card:new("card-7", "Test task")
      todo_col:add_card(card)

      -- Should use board's default (10), not plugin default (1)
      assert.are.equal(10, card.properties.complexity, "Card should use board's default_complexity (10), not plugin's (1)")
    end)

    it("should fall back to plugin default_complexity if board.config.use_complexity is true but default_complexity is not set", function()
      config.setup({ use_complexity = true, default_complexity = 7 })

      local board = Board:new()
      board.config.use_complexity = true
      -- Don't set board.config.default_complexity

      local todo_col = board:add_column("todo", "Todo")
      board:auto_register_triggers()

      local card = Card:new("card-8", "Test task")
      todo_col:add_card(card)

      -- Should fall back to plugin default (7)
      assert.are.equal(7, card.properties.complexity, "Card should use plugin's default_complexity (7) when board doesn't specify one")
    end)
  end)

  describe("with parsed boards containing config", function()
    it("should parse board config correctly but not auto-add to already-parsed cards", function()
      local content = [[
# Test Board
<!-- kanban:config use_complexity: true, default_complexity: 3 -->

###### To Do
- Task without complexity
- Task with complexity <!-- complexity: 5 -->
]]

      local board = Board:new()
      board:parse(content)

      -- Board config should be parsed
      assert.are.equal(true, board.config.use_complexity, "Board config should have use_complexity = true")
      assert.are.equal(3, board.config.default_complexity, "Board config should have default_complexity = 3")

      -- Cards parsed from markdown should only have what's in the markdown
      -- (Auto-add only happens when cards are added via UI, not during parsing)
      local card1 = board.columns[1].cards[1]
      assert.is_nil(card1.properties.complexity, "Parsed card without complexity should remain nil")

      -- Card with explicit complexity should keep it
      local card2 = board.columns[1].cards[2]
      assert.are.equal(5, card2.properties.complexity, "Card with complexity should keep its value (5)")
    end)

    it("should auto-add complexity to new cards added after parsing", function()
      local content = [[
# Test Board
<!-- kanban:config use_complexity: true, default_complexity: 3 -->

###### To Do
- Existing task
]]

      local board = Board:new()
      board:parse(content)

      -- Now add a new card to the parsed board
      local new_card = Card:new("card-new", "New task")
      board.columns[1]:add_card(new_card)

      -- The new card should get auto-complexity because the board has use_complexity enabled
      assert.are.equal(3, new_card.properties.complexity, "New card added after parsing should get auto-complexity")

      -- Existing parsed card should not have complexity
      local existing_card = board.columns[1].cards[1]
      assert.is_nil(existing_card.properties.complexity, "Existing parsed card should not have auto-added complexity")
    end)

    it("should not add complexity when board config sets use_complexity to false", function()
      local content = [[
# Test Board
<!-- kanban:config use_complexity: false -->

###### To Do
- Task without complexity
]]

      local board = Board:new()
      board:parse(content)

      local card = board.columns[1].cards[1]
      assert.is_nil(card.properties.complexity, "Card should NOT have complexity when board disables it")
    end)

    it("should persist complexity through write/parse cycle", function()
      -- Enable complexity
      config.setup({ use_complexity = true, default_complexity = 2 })

      local board = Board:new()
      board.config.use_complexity = true
      board.config.default_complexity = 2
      board.title = "Test Board"

      local todo_col = board:add_column("todo", "Todo")
      board:auto_register_triggers()

      -- Add card without complexity
      local card = Card:new("card-9", "Test task")
      todo_col:add_card(card)

      assert.are.equal(2, card.properties.complexity, "Card should have auto-added complexity (2)")

      -- Write and re-parse
      local lines = board:write()
      local board2 = Board:new()
      board2:parse(lines)

      -- Check complexity persisted
      local card_parsed = board2.columns[1].cards[1]
      assert.are.equal(2, card_parsed.properties.complexity, "Complexity should persist through write/parse cycle")
    end)
  end)
end)
