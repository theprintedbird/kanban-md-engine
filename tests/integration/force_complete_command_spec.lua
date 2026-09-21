-- tests/integration/force_complete_command_spec.lua
-- Integration tests for KanbanForceCompleteCard command

require('polyfills.vim')
local test_clock = require('helpers.clock')

describe("Force Complete Command", function()
  local Board = require("kanban-md.board")
  local Column = require("kanban-md.column")
  local Card = require("kanban-md.card")
  local config = require("kanban-md.config")
  local column_helper = require("kanban-md.helpers.column")
  local clock

  -- config is a module singleton and config.setup() merges rather than
  -- replaces, so without the reset either side these strict validation modes
  -- would be inherited from -- and then leaked to -- whatever else the run
  -- loads into the same Lua state.
  before_each(function()
    config.reset()
    config.setup({
      dependency_validation = "strict",
      subtask_validation = "strict",
      auto_timestamp = true,
      confirm_destructive = false, -- Disable confirmation for tests
    })
    clock = test_clock.install()
  end)

  after_each(function()
    config.reset()
    clock.restore()
  end)

  describe("Command finds completion column correctly", function()
    it("should find completion column marked with is_completion_state", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local doing = board:add_column("col_doing", "Doing")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      local card = Card:new(nil, "Test card", {})
      todo:add_card(card)

      -- Find completion column
      local done_column = nil
      for _, col in ipairs(board.columns) do
        if column_helper.is_completion_column(col, board) then
          done_column = col
          break
        end
      end

      assert.is_not_nil(done_column)
      assert.are.equals("Done", done_column.name)
    end)

    it("should find last column as completion column if none explicitly marked", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local doing = board:add_column("col_doing", "Doing")
      local done = board:add_column("col_done", "Done")

      local card = Card:new(nil, "Test card", {})
      todo:add_card(card)

      -- Find completion column (should be last)
      local done_column = nil
      for _, col in ipairs(board.columns) do
        if column_helper.is_completion_column(col, board) then
          done_column = col
          break
        end
      end

      assert.is_not_nil(done_column)
      assert.are.equals("Done", done_column.name)
    end)
  end)

  describe("Bypasses dependency checks", function()
    it("should complete card even with incomplete dependencies", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local doing = board:add_column("col_doing", "Doing")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      -- Register dependency triggers
      board:auto_register_triggers()

      -- Create cards with dependency
      local dependency = Card:new("dep-1", "Dependency card", {})
      local dependent = Card:new("card-1", "Dependent card", { depends_on = {"dep-1"} })

      todo:add_card(dependency)
      doing:add_card(dependent)

      -- Normal move should fail
      local success = pcall(function()
        board:move_card(dependent, doing, done)
      end)
      assert.is_false(success)

      -- Force complete should succeed by bypassing dependency check
      success = pcall(function()
        board:move_card_with_bypass(dependent, doing, done, {"dependency", "subtask"})
      end)
      assert.is_true(success)
      assert.are.equals(1, #done.cards)
      assert.are.equals("Dependent card", done.cards[1].text)
    end)

    it("should complete card with multiple incomplete dependencies", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      -- Register dependency triggers
      board:auto_register_triggers()

      -- Create cards with multiple dependencies
      local dep1 = Card:new("dep-1", "Dependency 1", {})
      local dep2 = Card:new("dep-2", "Dependency 2", {})
      local dependent = Card:new("card-1", "Dependent card", { depends_on = {"dep-1", "dep-2"} })

      todo:add_card(dep1)
      todo:add_card(dep2)
      todo:add_card(dependent)

      -- Normal move should fail
      local success = pcall(function()
        board:move_card(dependent, todo, done)
      end)
      assert.is_false(success)

      -- Force complete should succeed
      success = pcall(function()
        board:move_card_with_bypass(dependent, todo, done, {"dependency"})
      end)
      assert.is_true(success)
      assert.are.equals(1, #done.cards)
    end)
  end)

  describe("Bypasses subtask checks", function()
    it("should complete parent card even with incomplete subtasks", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local doing = board:add_column("col_doing", "Doing")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      -- Register subtask triggers
      board:auto_register_triggers()

      -- Create cards with subtask relationship
      local subtask = Card:new("subtask-1", "Subtask card", {})
      local parent = Card:new("parent-1", "Parent card", { subtasks = {"subtask-1"} })

      todo:add_card(subtask)
      doing:add_card(parent)

      -- Normal move should fail
      local success = pcall(function()
        board:move_card(parent, doing, done)
      end)
      assert.is_false(success)

      -- Force complete should succeed by bypassing subtask check
      success = pcall(function()
        board:move_card_with_bypass(parent, doing, done, {"dependency", "subtask"})
      end)
      assert.is_true(success)
      assert.are.equals(1, #done.cards)
      assert.are.equals("Parent card", done.cards[1].text)
    end)

    it("should complete parent card with multiple incomplete subtasks", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      -- Register subtask triggers
      board:auto_register_triggers()

      -- Create cards with multiple subtasks
      local sub1 = Card:new("sub-1", "Subtask 1", {})
      local sub2 = Card:new("sub-2", "Subtask 2", {})
      local parent = Card:new("parent-1", "Parent card", { subtasks = {"sub-1", "sub-2"} })

      todo:add_card(sub1)
      todo:add_card(sub2)
      todo:add_card(parent)

      -- Normal move should fail
      local success = pcall(function()
        board:move_card(parent, todo, done)
      end)
      assert.is_false(success)

      -- Force complete should succeed
      success = pcall(function()
        board:move_card_with_bypass(parent, todo, done, {"subtask"})
      end)
      assert.is_true(success)
      assert.are.equals(1, #done.cards)
    end)
  end)

  describe("DOES NOT bypass WIP limits", function()
    it("should fail when completion column WIP limit is exceeded", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true
      done.config.wip_limit = 1

      -- Register dependency triggers
      board:auto_register_triggers()

      -- Add one card to done (at WIP limit)
      local existing = Card:new("existing-1", "Existing card", {})
      done:add_card(existing)

      -- Try to force complete another card with dependency
      local dep = Card:new("dep-1", "Dependency", {})
      local dependent = Card:new("card-1", "Dependent card", { depends_on = {"dep-1"} })
      todo:add_card(dep)
      todo:add_card(dependent)

      -- Force complete should fail due to WIP limit
      local success, err = pcall(function()
        board:move_card_with_bypass(dependent, todo, done, {"dependency", "subtask"})
      end)

      assert.is_false(success)
      assert.is_not_nil(err:match("WIP limit"))
    end)

    it("should respect column WIP limits even when bypassing dependencies", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true
      done.config.wip_limit = 0  -- Set WIP limit to 0 before registering triggers

      -- Register dependency triggers (this will also register WIP triggers)
      board:auto_register_triggers()

      -- Try to force complete a card with dependency when done column WIP is 0
      local dep = Card:new("dep-1", "Dependency", {})
      local dependent = Card:new("card-1", "Dependent card", { depends_on = {"dep-1"} })
      todo:add_card(dep)
      todo:add_card(dependent)

      -- Force complete should fail due to done column WIP limit of 0
      local success, err = pcall(function()
        board:move_card_with_bypass(dependent, todo, done, {"dependency", "subtask"})
      end)

      assert.is_false(success)
      assert.is_not_nil(err:match("WIP limit"))
    end)
  end)

  describe("DOES NOT bypass custom triggers", function()
    it("should respect custom validation triggers", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      -- Register dependency triggers
      board:auto_register_triggers()

      -- Add custom trigger (not marked as bypassable)
      done:register_on_checking("custom_validation", function(column, context)
        if context.card.text:match("forbidden") then
          error("Cards with 'forbidden' text cannot enter Done")
        end
      end)

      -- Create card with dependency and forbidden text
      local dep = Card:new("dep-1", "Dependency", {})
      local dependent = Card:new("card-1", "forbidden card", { depends_on = {"dep-1"} })
      todo:add_card(dep)
      todo:add_card(dependent)

      -- Force complete should fail due to custom trigger
      local success, err = pcall(function()
        board:move_card_with_bypass(dependent, todo, done, {"dependency", "subtask"})
      end)

      assert.is_false(success)
      assert.is_not_nil(err:match("forbidden"))
    end)
  end)

  describe("Timestamp handling", function()
    it("should add completion timestamp when auto_timestamp is enabled", function()
      config.setup({ auto_timestamp = true })

      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      -- Register dependency triggers
      board:auto_register_triggers()

      -- Create card with dependency
      local dep = Card:new("dep-1", "Dependency", {})
      local dependent = Card:new("card-1", "Dependent card", { depends_on = {"dep-1"} })
      todo:add_card(dep)
      todo:add_card(dependent)

      -- Let the timestamp trigger (registered by auto_register_triggers above)
      -- set the completion timestamp; advance the clock first so "recent" is
      -- an exact, deliberate delta rather than a same-second coincidence.
      local before_time = clock.now()
      clock.advance(test_clock.HOUR)

      -- Force complete
      board:move_card_with_bypass(dependent, todo, done, {"dependency"})

      -- Verify timestamp exists and reflects the trigger firing after the advance
      assert.is_not_nil(dependent.properties.done)
      assert.are.equal(before_time + test_clock.HOUR, dependent.properties.done)
    end)
  end)

  describe("Error handling", function()
    it("should handle card not in completion column check", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      local card = Card:new("card-1", "Card", {})
      done:add_card(card)

      -- Check if card is already in completion column
      local already_complete = column_helper.is_completion_column(done, board)
      assert.is_true(already_complete)
    end)

    it("should handle missing explicit completion column and use last column", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local doing = board:add_column("col_doing", "Doing")
      local review = board:add_column("col_review", "Review")
      -- No completion column explicitly marked

      -- Try to find completion column
      local done_column = nil
      for _, col in ipairs(board.columns) do
        if column_helper.is_completion_column(col, board) then
          done_column = col
          break
        end
      end

      -- Should find last column as fallback (Review)
      assert.is_not_nil(done_column)
      assert.are.equals("Review", done_column.name)
    end)
  end)

  describe("Integration with board state", function()
    it("should update board state after force complete", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      -- Register dependency triggers
      board:auto_register_triggers()

      -- Create card with dependency
      local dep = Card:new("dep-1", "Dependency", {})
      local dependent = Card:new("card-1", "Dependent card", { depends_on = {"dep-1"} })
      todo:add_card(dep)
      todo:add_card(dependent)

      -- Verify initial state
      assert.are.equals(2, #todo.cards)
      assert.are.equals(0, #done.cards)

      -- Force complete
      board:move_card_with_bypass(dependent, todo, done, {"dependency"})

      -- Verify final state
      assert.are.equals(1, #todo.cards)
      assert.are.equals(1, #done.cards)
      assert.are.equals("Dependent card", done.cards[1].text)
    end)

    it("should preserve card properties after force complete", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      -- Register dependency triggers
      board:auto_register_triggers()

      -- Create card with dependency and other properties
      local dep = Card:new("dep-1", "Dependency", {})
      local dependent = Card:new("card-1", "Dependent card", {
        depends_on = {"dep-1"},
        complexity = 5,
        assignee = "test-user",
        tags = {"urgent", "bug"}
      })
      todo:add_card(dep)
      todo:add_card(dependent)

      -- Force complete
      board:move_card_with_bypass(dependent, todo, done, {"dependency"})

      -- Verify properties preserved
      local completed_card = done.cards[1]
      assert.are.equals(5, completed_card.properties.complexity)
      assert.are.equals("test-user", completed_card.properties.assignee)
      assert.are.same({"urgent", "bug"}, completed_card.properties.tags)
      assert.are.same({"dep-1"}, completed_card.properties.depends_on)
    end)
  end)

  describe("Bypass categories", function()
    it("should only bypass specified categories", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      -- Register dependency triggers
      board:auto_register_triggers()

      -- Add custom bypassable trigger with different category
      done:register_on_checking("custom_check", function(column, context)
        error("Custom check failed")
      end, { bypassable = true, category = "custom" })

      -- Create card with dependency
      local dep = Card:new("dep-1", "Dependency", {})
      local dependent = Card:new("card-1", "Dependent card", { depends_on = {"dep-1"} })
      todo:add_card(dep)
      todo:add_card(dependent)

      -- Force complete with only dependency/subtask bypass should fail on custom trigger
      local success = pcall(function()
        board:move_card_with_bypass(dependent, todo, done, {"dependency", "subtask"})
      end)

      assert.is_false(success)
    end)

    it("should bypass multiple categories when specified", function()
      local board = Board:new()
      board.title = "Test Board"

      local todo = board:add_column("col_todo", "To Do")
      local done = board:add_column("col_done", "Done")
      done.config.is_completion_state = true

      -- Register dependency and subtask triggers
      board:auto_register_triggers()

      -- Create card with both dependency and subtask issues
      local dep = Card:new("dep-1", "Dependency", {})
      local sub = Card:new("sub-1", "Subtask", {})
      local card = Card:new("card-1", "Card", {
        depends_on = {"dep-1"},
        subtasks = {"sub-1"}
      })
      todo:add_card(dep)
      todo:add_card(sub)
      todo:add_card(card)

      -- Normal move should fail
      local success = pcall(function()
        board:move_card(card, todo, done)
      end)
      assert.is_false(success)

      -- Force complete with both categories should succeed
      success = pcall(function()
        board:move_card_with_bypass(card, todo, done, {"dependency", "subtask"})
      end)
      assert.is_true(success)
      assert.are.equals(1, #done.cards)
    end)
  end)
end)
