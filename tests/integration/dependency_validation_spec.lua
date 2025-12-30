-- Integration tests for dependency validation through board:move_card()
-- These tests verify the dependency trigger behavior in realistic scenarios
require('polyfills.vim')
_G._TEST = true
local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')
local WorkflowEngine = require('kanban-md.workflow_engine')

-- Helper to get a fresh board with basic structure for tests
local function create_simple_test_board()
  local board = Board:new()
  board.title = "Test Board"

  -- Enable dependencies feature for testing
  board.config.dependency_validation = true

  -- Create columns using board's add_column method
  local todo_column = board:add_column("todo", "To Do")
  local done_column = board:add_column("done", "Done")

  -- Explicitly mark done column as completion column to avoid position-based detection issues
  done_column.properties = {is_completion_state = true}

  return board, todo_column, done_column
end

describe("Dependency validation integration", function()
  local board, card, todo_column, done_column

  before_each(function()
    board, todo_column, done_column = create_simple_test_board()

    -- Create a test card
    card = Card:new("test_task_1", "Test task", {id = "test_task_1"})
    todo_column:add_card(card)

    -- Register triggers (including dependencies)
    board:auto_register_triggers()
  end)

  after_each(function()
    board = nil
    card = nil
    todo_column = nil
    done_column = nil
    collectgarbage("collect")
  end)

  describe("basic dependency validation", function()
    it("should block moves with incomplete dependencies", function()
      -- Create a dependency task with proper ID setup
      board.config.auto_id = false
      local dep_card = Card:new("dep_1", "Dependency task", {id = "dep_1"})
      todo_column:add_card(dep_card)

      -- Set up card with dependency
      card.properties.depends_on = {"dep_1"}

      -- Try to move to completion column - should fail
      local success, err = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success)
      assert.matches("not complete", err)
    end)

    it("should check task dependencies for completion moves", function()
      -- Create a fresh board with three columns to test non-completion moves
      local test_board = Board:new()
      test_board.title = "Test Board"
      test_board.config.dependency_validation = true

      local test_todo = test_board:add_column("todo", "To Do")
      local test_in_progress = test_board:add_column("in_progress", "In Progress")
      local test_done = test_board:add_column("done", "Done")

      -- Explicitly mark done as completion column
      test_done.properties = {is_completion_state = true}

      -- Register triggers after all columns are created
      test_board:auto_register_triggers()

      -- Create dependency task
      local dep_card = Card:new("dep_1", "Dependency task", {id = "dep_1"})
      dep_card.id = "dep_1"
      test_todo:add_card(dep_card)

      -- Create main card with dependency
      local test_card = Card:new("test_task_1", "Test task", {id = "test_task_1", depends_on = {"dep_1"}})
      test_card.id = "test_task_1"
      test_card.properties.id = "test_task_1"
      test_card.properties.depends_on = {"dep_1"}
      test_todo:add_card(test_card)

      -- Try to move to completion column (should fail)
      local success, err = pcall(function()
        test_board:move_card(test_card, test_todo, test_done)
      end)
      assert.is_false(success)
      assert.matches("not complete", err)

      -- Try moving to non-completion column (should succeed)
      local success2, err2 = pcall(function()
        test_board:move_card(test_card, test_todo, test_in_progress)
      end)
      assert.is_true(success2, "Move should succeed: " .. tostring(err2))
    end)

    it("should allow moves when dependencies satisfied", function()
      -- Create dependency task and move it to completion
      local dep_card = Card:new("dep_1", "Dependency task", {id = "dep_1"})
      dep_card.id = "dep_1"
      done_column:add_card(dep_card) -- Place in Done column

      -- Set up card with satisfied dependency
      card.properties.depends_on = {"dep_1"}

      -- Should allow move to completion column
      local success = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_true(success)
    end)

    it("should block moves with unsatisfied dependencies", function()
      -- Create multiple dependency tasks, some complete, some not
      local dep1 = Card:new("dep_1", "Dependency 1", {id = "dep_1"})
      dep1.id = "dep_1"
      done_column:add_card(dep1) -- Complete

      local dep2 = Card:new("dep_2", "Dependency 2", {id = "dep_2"})
      dep2.id = "dep_2"
      todo_column:add_card(dep2) -- Not complete

      -- Set up card with mixed dependencies
      card.properties.depends_on = {"dep_1", "dep_2"}

      -- Should block move due to incomplete dependency
      local success, err = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success)
      assert.matches("not complete", err)
    end)

    it("should handle missing dependencies as errors", function()
      -- Set up card with non-existent dependency
      card.properties.depends_on = {"nonexistent_task"}

      -- Should return error for missing dependency
      local success, err = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success)
      assert.matches("not found", err)
    end)
  end)

  describe("complex dependency scenarios", function()
    it("should handle multiple dependencies all complete", function()
      -- Create multiple dependencies all complete
      local dep1 = Card:new("dep_1", "Dependency 1", {id = "dep_1"})
      dep1.id = "dep_1"
      done_column:add_card(dep1)

      local dep2 = Card:new("dep_2", "Dependency 2", {id = "dep_2"})
      dep2.id = "dep_2"
      done_column:add_card(dep2)

      local dep3 = Card:new("dep_3", "Dependency 3", {id = "dep_3"})
      dep3.id = "dep_3"
      done_column:add_card(dep3)

      -- Set up card with multiple satisfied dependencies
      card.properties.depends_on = {"dep_1", "dep_2", "dep_3"}

      -- Should allow move since all dependencies are complete
      local success = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_true(success)
    end)

    it("should handle dependency chains", function()
      -- Create a chain: card -> dep1 -> dep2
      local dep2 = Card:new("dep_2", "Dependency 2", {id = "dep_2"})
      dep2.id = "dep_2"
      todo_column:add_card(dep2) -- Not complete yet

      local dep1 = Card:new("dep_1", "Dependency 1", {
        id = "dep_1",
        depends_on = {"dep_2"}
      })
      dep1.id = "dep_1"
      dep1.properties.depends_on = {"dep_2"}
      todo_column:add_card(dep1)

      card.properties.depends_on = {"dep_1"}

      -- Try to move card - should fail because dep1 can't complete (dep2 incomplete)
      local success1, err1 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success1)
      assert.matches("dep_1", err1) -- dep1 is incomplete

      -- Try to move dep1 - should fail because dep2 incomplete
      local success2, err2 = pcall(function()
        board:move_card(dep1, todo_column, done_column)
      end)
      assert.is_false(success2)
      assert.matches("dep_2", err2) -- dep2 is incomplete

      -- Complete dep2, then dep1 should be moveable
      board:move_card(dep2, todo_column, done_column)
      board:move_card(dep1, todo_column, done_column)

      -- Now card should also be moveable
      local success4 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_true(success4)
    end)

    it("should allow parallel dependencies completion", function()
      -- Create multiple independent dependencies
      local dep1 = Card:new("parallel_dep_1", "Parallel dep 1", {id = "parallel_dep_1"})
      dep1.id = "parallel_dep_1"
      local dep2 = Card:new("parallel_dep_2", "Parallel dep 2", {id = "parallel_dep_2"})
      dep2.id = "parallel_dep_2"
      local dep3 = Card:new("parallel_dep_3", "Parallel dep 3", {id = "parallel_dep_3"})
      dep3.id = "parallel_dep_3"

      -- All start incomplete
      todo_column:add_card(dep1)
      todo_column:add_card(dep2)
      todo_column:add_card(dep3)

      card.properties.depends_on = {"parallel_dep_1", "parallel_dep_2", "parallel_dep_3"}

      -- Card should be blocked
      local success1 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success1)

      -- Complete them one by one - card still blocked until all complete
      board:move_card(dep1, todo_column, done_column)
      local success2 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success2) -- Still 2 incomplete

      board:move_card(dep2, todo_column, done_column)
      local success3 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success3) -- Still 1 incomplete

      board:move_card(dep3, todo_column, done_column)
      local success4 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_true(success4) -- All complete now
    end)
  end)

  describe("dependency and subtask interaction", function()
    it("should handle cards with both dependencies and subtasks", function()
      -- Enable both features
      board.config.subtask_validation = true
      board:auto_register_triggers()

      -- Create a dependency
      local dep = Card:new("dep_1", "Dependency", {id = "dep_1"})
      dep.id = "dep_1"
      done_column:add_card(dep) -- Complete

      -- Create a subtask
      local subtask = Card:new("subtask_1", "Subtask", {id = "subtask_1"})
      subtask.id = "subtask_1"
      todo_column:add_card(subtask) -- Not complete

      -- Set up card with both dependency and subtask
      card.properties.depends_on = {"dep_1"}
      card.properties.subtasks = {"subtask_1"}

      -- Should block because subtask incomplete (even though dependency is complete)
      local success1, err1 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success1)
      assert.matches("subtask_1", err1)

      -- Complete the subtask
      board:move_card(subtask, todo_column, done_column)

      -- Now should succeed (both dependency and subtask complete)
      local success2 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_true(success2)
    end)
  end)

  describe("non-completion column moves", function()
    it("should allow moves to non-completion columns regardless of dependencies", function()
      -- Create a fresh board with three columns
      local test_board = Board:new()
      test_board.title = "Test Board"
      test_board.config.dependency_validation = true

      local test_todo = test_board:add_column("todo", "To Do")
      local test_in_progress = test_board:add_column("in_progress", "In Progress")
      local test_done = test_board:add_column("done", "Done")

      -- Explicitly mark done as completion column
      test_done.properties = {is_completion_state = true}

      -- Register triggers after all columns are created
      test_board:auto_register_triggers()

      -- Create incomplete dependency
      local dep_card = Card:new("dep_1", "Dependency task", {id = "dep_1"})
      dep_card.id = "dep_1"
      test_todo:add_card(dep_card)

      -- Create card with dependency
      local test_card = Card:new("test_task_1", "Test task", {id = "test_task_1", depends_on = {"dep_1"}})
      test_card.id = "test_task_1"
      test_card.properties.id = "test_task_1"
      test_card.properties.depends_on = {"dep_1"}
      test_todo:add_card(test_card)

      -- Moving to in-progress should succeed (it's not a completion column)
      local success = pcall(function()
        test_board:move_card(test_card, test_todo, test_in_progress)
      end)
      assert.is_true(success)
    end)
  end)

  describe("enforcement mode", function()
    it("should block moves in strict mode (default)", function()
      -- Create incomplete dependency
      local dep_card = Card:new("dep_1", "Dependency task", {id = "dep_1"})
      dep_card.id = "dep_1"
      todo_column:add_card(dep_card)

      -- Set up card with dependency
      card.properties.depends_on = {"dep_1"}

      -- Strict mode (default) should block
      local success, err = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success)
      assert.matches("not done", err)
    end)

    it("should block moves when dependency_validation = true", function()
      -- Reset and configure as "true" (should normalize to "strict")
      board.config.dependency_validation = true
      board:auto_register_triggers()

      -- Create incomplete dependency
      local dep_card = Card:new("dep_1", "Dependency task", {id = "dep_1"})
      dep_card.id = "dep_1"
      todo_column:add_card(dep_card)

      card.properties.depends_on = {"dep_1"}

      -- Should block
      local success, err = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success)
      assert.matches("not done", err)
    end)

    it("should block moves when dependency_validation = 'strict'", function()
      -- Reset and configure as "strict"
      board.config.dependency_validation = "strict"
      board:auto_register_triggers()

      -- Create incomplete dependency
      local dep_card = Card:new("dep_1", "Dependency task", {id = "dep_1"})
      dep_card.id = "dep_1"
      todo_column:add_card(dep_card)

      card.properties.depends_on = {"dep_1"}

      -- Should block
      local success, err = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success)
      assert.matches("not done", err)
    end)

    it("should allow moves with warnings in warn mode", function()
      -- Configure warn mode and re-register triggers
      board.config.dependency_validation = "warn"
      -- Clear existing triggers first
      for _, column in ipairs(board.columns) do
        column:clear_triggers("on_checking", "dependencies")
      end
      board:auto_register_triggers()

      -- Create incomplete dependency
      local dep_card = Card:new("dep_1", "Dependency task", {id = "dep_1"})
      dep_card.id = "dep_1"
      todo_column:add_card(dep_card)

      card.properties.depends_on = {"dep_1"}

      -- Should allow move (no error thrown)
      local success = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_true(success)

      -- Card should be in done column
      local found = false
      for _, c in ipairs(done_column.cards) do
        if c.id == card.id then
          found = true
          break
        end
      end
      assert.is_true(found, "Card should be in done column")
    end)

    it("should not register triggers when dependency_validation = false", function()
      -- Reset board with dependencies disabled
      local new_board = Board:new()
      new_board.title = "Test Board"
      new_board.config.dependency_validation = false

      local col1 = new_board:add_column("todo", "To Do")
      local col2 = new_board:add_column("done", "Done")
      new_board:auto_register_triggers()

      -- Create cards with dependency
      local dep = Card:new("dep_1", "Dependency", {id = "dep_1"})
      dep.id = "dep_1"
      col1:add_card(dep)

      local main_card = Card:new("main", "Main task", {id = "main", depends_on = {"dep_1"}})
      main_card.id = "main"
      main_card.properties.depends_on = {"dep_1"}
      col1:add_card(main_card)

      -- Should allow move without checking dependencies
      local success = pcall(function()
        new_board:move_card(main_card, col1, col2)
      end)
      assert.is_true(success)
    end)
  end)
end)
