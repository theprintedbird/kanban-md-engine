require('polyfills.vim')
local Board = require("kanban-md.board")
local Card = require("kanban-md.card")
local config = require("kanban-md.config")

describe("Selective Bypass Integration", function()
  local original_config

  before_each(function()
    -- Save original config
    original_config = vim.deepcopy(config.get())
  end)

  after_each(function()
    -- Restore original config
    config.setup(original_config)
  end)

  describe("Force Complete with Dependency Bypass", function()
    it("bypasses dependency checks when using move_card_with_bypass", function()
      config.setup({
        dependency_validation = "strict",
        subtask_validation = false,
        auto_timestamp = false
      })

      local board = Board:new()
      board.title = "Test Board"

      -- Create columns using board method
      local todo = board:add_column("todo", "Todo")
      local done = board:add_column("done", "Done")
      done.config.is_completion_state = true

      -- Create cards with dependency
      local blocking_card = Card:new("card1", "Blocking task", {})
      local dependent_card = Card:new("card2", "Dependent task", { depends_on = { "card1" } })

      -- Add cards before registering triggers
      todo:add_card(blocking_card)
      todo:add_card(dependent_card)

      -- Register triggers after cards are added
      board:auto_register_triggers()

      -- Normal move should fail (blocking card not done)
      local success = pcall(function()
        board:move_card(dependent_card, todo, done)
      end)
      assert.is_false(success)

      -- Move with bypass should succeed
      local bypass_success = pcall(function()
        board:move_card_with_bypass(dependent_card, todo, done, { "dependency" })
      end)
      assert.is_true(bypass_success)

      -- Verify card moved
      assert.are.equals(1, #todo.cards)
      assert.are.equals(1, #done.cards)
      assert.are.equals("card2", done.cards[1].id)
    end)
  end)

  describe("Force Complete with Subtask Bypass", function()
    it("bypasses subtask checks when using move_card_with_bypass", function()
      config.setup({
        dependency_validation = false,
        subtask_validation = "strict",
        auto_timestamp = false
      })

      local board = Board:new()
      board.title = "Test Board"

      -- Create columns using board method
      local todo = board:add_column("todo", "Todo")
      local done = board:add_column("done", "Done")
      done.config.is_completion_state = true

      -- Create parent card with incomplete subtasks
      local subtask = Card:new("subtask1", "Subtask", {})
      local parent_card = Card:new("parent1", "Parent task", { subtasks = { "subtask1" } })

      -- Add cards before registering triggers
      todo:add_card(subtask)
      todo:add_card(parent_card)

      -- Register triggers after cards are added
      board:auto_register_triggers()

      -- Normal move should fail (subtask not done)
      local success = pcall(function()
        board:move_card(parent_card, todo, done)
      end)
      assert.is_false(success)

      -- Move with bypass should succeed
      local bypass_success = pcall(function()
        board:move_card_with_bypass(parent_card, todo, done, { "subtask" })
      end)
      assert.is_true(bypass_success)

      -- Verify card moved
      assert.are.equals(1, #todo.cards)
      assert.are.equals(1, #done.cards)
      assert.are.equals("parent1", done.cards[1].id)
    end)
  end)

  describe("Force Complete PRESERVES WIP Limits", function()
    it("does NOT bypass WIP limit validation", function()
      config.setup({
        dependency_validation = "strict",
        subtask_validation = false,
        auto_timestamp = false
      })

      local board = Board:new()
      board.title = "Test Board"

      -- Create columns with WIP limit using board method
      local todo = board:add_column("todo", "Todo")
      local done = board:add_column("done", "Done")
      done.config.is_completion_state = true
      done.config.wip_limit = 1

      -- Create cards
      local blocking_card = Card:new("card1", "Blocking task", {})
      local dependent_card = Card:new("card2", "Dependent task", { depends_on = { "card1" } })
      local existing_done_card = Card:new("card3", "Already done", {})

      -- Add cards before registering triggers
      todo:add_card(blocking_card)
      todo:add_card(dependent_card)
      done:add_card(existing_done_card)

      -- Register triggers after cards are added
      board:auto_register_triggers()

      -- Move with bypass should fail due to WIP limit
      local success, err = pcall(function()
        board:move_card_with_bypass(dependent_card, todo, done, { "dependency" })
      end)

      assert.is_false(success)
      assert.truthy(string.match(err, "WIP limit"))
    end)
  end)

  describe("Force Complete with Multiple Bypass Categories", function()
    it("bypasses both dependency and subtask checks", function()
      config.setup({
        dependency_validation = "strict",
        subtask_validation = "strict",
        auto_timestamp = false
      })

      local board = Board:new()
      board.title = "Test Board"

      -- Create columns using board method
      local todo = board:add_column("todo", "Todo")
      local done = board:add_column("done", "Done")
      done.config.is_completion_state = true

      -- Create complex card with both dependencies and subtasks
      local blocking_card = Card:new("card1", "Blocking task", {})
      local subtask = Card:new("subtask1", "Subtask", {})
      local complex_card = Card:new("card2", "Complex task", {
        depends_on = { "card1" },
        subtasks = { "subtask1" }
      })

      -- Add cards before registering triggers
      todo:add_card(blocking_card)
      todo:add_card(subtask)
      todo:add_card(complex_card)

      -- Register triggers after cards are added
      board:auto_register_triggers()

      -- Normal move should fail (both checks)
      local success = pcall(function()
        board:move_card(complex_card, todo, done)
      end)
      assert.is_false(success)

      -- Move with both bypasses should succeed
      local bypass_success = pcall(function()
        board:move_card_with_bypass(complex_card, todo, done, { "dependency", "subtask" })
      end)
      assert.is_true(bypass_success)

      -- Verify card moved
      assert.are.equals(2, #todo.cards)
      assert.are.equals(1, #done.cards)
      assert.are.equals("card2", done.cards[1].id)
    end)
  end)

  describe("Bypass Metadata System", function()
    it("correctly identifies bypassable triggers", function()
      config.setup({
        dependency_validation = "strict",
        subtask_validation = false,
        auto_timestamp = false
      })

      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("todo", "Todo")
      board:auto_register_triggers()

      -- Check trigger metadata
      assert.truthy(todo.trigger_metadata)
      assert.truthy(todo.trigger_metadata["on_checking"])
      assert.truthy(todo.trigger_metadata["on_checking"]["dependencies"])

      local dep_metadata = todo.trigger_metadata["on_checking"]["dependencies"]
      assert.is_true(dep_metadata.bypassable)
      assert.are.equals("dependency", dep_metadata.category)
    end)

    it("marks subtask triggers as bypassable", function()
      config.setup({
        dependency_validation = false,
        subtask_validation = "strict",
        auto_timestamp = false
      })

      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("todo", "Todo")
      board:auto_register_triggers()

      -- Check trigger metadata
      assert.truthy(todo.trigger_metadata)
      assert.truthy(todo.trigger_metadata["on_checking"])
      assert.truthy(todo.trigger_metadata["on_checking"]["subtasks"])

      local subtask_metadata = todo.trigger_metadata["on_checking"]["subtasks"]
      assert.is_true(subtask_metadata.bypassable)
      assert.are.equals("subtask", subtask_metadata.category)
    end)
  end)

  describe("Custom Triggers Not Bypassed", function()
    it("does not bypass custom validation triggers", function()
      config.setup({
        dependency_validation = "strict",
        subtask_validation = false,
        auto_timestamp = false
      })

      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("todo", "Todo")
      local done = board:add_column("done", "Done")
      done.config.is_completion_state = true

      -- Create card with dependency
      local blocking_card = Card:new("card1", "Blocking task", {})
      local blocked_card = Card:new("card2", "BLOCKED task", { depends_on = { "card1" } })

      -- Add cards before registering triggers
      todo:add_card(blocking_card)
      todo:add_card(blocked_card)

      -- Register triggers after cards are added
      board:auto_register_triggers()

      -- Add custom validation trigger (not bypassable)
      done:register_on_checking("custom_check", function(column, context)
        if context.card.text:match("^BLOCKED") then
          error("Cannot move blocked cards")
        end
      end)

      -- Move with bypass should still fail due to custom trigger
      local success, err = pcall(function()
        board:move_card_with_bypass(blocked_card, todo, done, { "dependency" })
      end)

      assert.is_false(success)
      assert.truthy(string.match(err, "Cannot move blocked cards"))
    end)
  end)
end)
