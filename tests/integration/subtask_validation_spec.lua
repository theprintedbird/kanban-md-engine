-- Integration tests for subtask validation through board:move_card()
-- These tests verify the subtask trigger behavior in realistic scenarios
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

  -- Enable subtasks feature for testing
  board.config.subtask_validation = true

  -- Create columns using board's add_column method
  local todo_column = board:add_column("todo", "To Do")
  local done_column = board:add_column("done", "Done")

  -- Explicitly mark done column as completion column to avoid position-based detection issues
  done_column.properties = {is_completion_state = true}

  return board, todo_column, done_column
end

describe("Subtask validation integration", function()
  local board, card, todo_column, done_column

  before_each(function()
    board, todo_column, done_column = create_simple_test_board()

    -- Create a test card
    card = Card:new("test_task_1", "Test task", {id = "test_task_1"})
    todo_column:add_card(card)

    -- Register triggers (including subtasks)
    board:auto_register_triggers()
  end)

  after_each(function()
    board = nil
    card = nil
    todo_column = nil
    done_column = nil
    collectgarbage("collect")
  end)

  describe("basic subtask validation", function()
    it("should check subtasks for parent completion", function()
      -- Create a fresh board with three columns
      local test_board = Board:new()
      test_board.title = "Test Board"
      test_board.config.subtask_validation = true

      local test_todo = test_board:add_column("todo", "To Do")
      local test_in_progress = test_board:add_column("in_progress", "In Progress")
      local test_done = test_board:add_column("done", "Done")

      -- Explicitly mark done as completion column
      test_done.properties = {is_completion_state = true}

      -- Register triggers after all columns are created
      test_board:auto_register_triggers()

      -- Create subtask
      local subtask = Card:new("subtask_1", "Subtask", {id = "subtask_1"})
      subtask.id = "subtask_1"
      test_todo:add_card(subtask)

      -- Create parent card with subtask
      local parent_card = Card:new("parent_1", "Parent task", {id = "parent_1", subtasks = {"subtask_1"}})
      parent_card.id = "parent_1"
      parent_card.properties.id = "parent_1"
      parent_card.properties.subtasks = {"subtask_1"}
      test_todo:add_card(parent_card)

      -- Try to move parent to completion column (should fail)
      local success, err = pcall(function()
        test_board:move_card(parent_card, test_todo, test_done)
      end)
      assert.is_false(success)
      assert.matches("incomplete", err)

      -- Try moving to non-completion column (should succeed)
      local success2, err2 = pcall(function()
        test_board:move_card(parent_card, test_todo, test_in_progress)
      end)
      assert.is_true(success2, "Move should succeed: " .. tostring(err2))
    end)

    it("should allow parent move when subtasks complete", function()
      -- Create subtask and move it to completion
      local subtask = Card:new("subtask_1", "Subtask", {id = "subtask_1"})
      subtask.id = "subtask_1"
      done_column:add_card(subtask) -- Place in Done column

      -- Set up parent card with completed subtask
      card.properties.subtasks = {"subtask_1"}

      -- Should allow move to completion column
      local success = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_true(success)
    end)

    it("should block parent with incomplete subtasks", function()
      -- Create multiple subtasks, some complete, some not
      local subtask1 = Card:new("subtask_1", "Subtask 1", {id = "subtask_1"})
      subtask1.id = "subtask_1"
      done_column:add_card(subtask1) -- Complete

      local subtask2 = Card:new("subtask_2", "Subtask 2", {id = "subtask_2"})
      subtask2.id = "subtask_2"
      todo_column:add_card(subtask2) -- Not complete

      local subtask3 = Card:new("subtask_3", "Subtask 3", {id = "subtask_3"})
      subtask3.id = "subtask_3"
      todo_column:add_card(subtask3) -- Not complete

      -- Set up parent with mixed subtasks
      card.properties.subtasks = {"subtask_1", "subtask_2", "subtask_3"}

      -- Should block move due to incomplete subtasks
      local success, err = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success)
      assert.matches(".*Card exit validation failed %[subtasks%]: Cannot complete: 2 subtasks still incomplete %(subtask_2, subtask_3%)%. Complete them first%.", err)
    end)

    it("should handle missing subtask references", function()
      -- Set up parent with reference to non-existent subtask
      card.properties.subtasks = {"nonexistent_subtask", "another_missing"}

      -- Should block move and report missing subtasks
      local success, err = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success)
      assert.matches("not found", err)
    end)
  end)

  describe("nested subtask hierarchies", function()
    it("should handle three-level hierarchies", function()
      -- Create a three-level hierarchy: parent -> child -> grandchild
      local grandchild = Card:new("grandchild_1", "Grandchild task", {id = "grandchild_1"})
      grandchild.id = "grandchild_1"
      todo_column:add_card(grandchild) -- Not complete yet

      local child = Card:new("child_1", "Child task", {
        id = "child_1",
        subtasks = {"grandchild_1"}
      })
      child.id = "child_1"
      child.properties.subtasks = {"grandchild_1"}
      todo_column:add_card(child)

      local parent = Card:new("parent_1", "Parent task", {
        id = "parent_1",
        subtasks = {"child_1"}
      })
      parent.id = "parent_1"
      parent.properties.subtasks = {"child_1"}
      todo_column:add_card(parent)

      -- Try to move parent - should fail because grandchild incomplete
      local success1, err1 = pcall(function()
        board:move_card(parent, todo_column, done_column)
      end)
      assert.is_false(success1)
      assert.matches("child_1", err1) -- Child is incomplete

      -- Try to move child - should fail because grandchild incomplete
      local success2, err2 = pcall(function()
        board:move_card(child, todo_column, done_column)
      end)
      assert.is_false(success2)
      assert.matches("grandchild_1", err2) -- Grandchild is incomplete

      -- Complete grandchild, then child should be moveable
      board:move_card(grandchild, todo_column, done_column)
      board:move_card(child, todo_column, done_column)

      -- Now parent should also be moveable
      local success4 = pcall(function()
        board:move_card(parent, todo_column, done_column)
      end)
      assert.is_true(success4)
    end)

    it("should allow parallel subtask completion", function()
      -- Create multiple independent subtasks
      local subtask1 = Card:new("parallel_1", "Parallel task 1", {id = "parallel_1"})
      subtask1.id = "parallel_1"
      local subtask2 = Card:new("parallel_2", "Parallel task 2", {id = "parallel_2"})
      subtask2.id = "parallel_2"
      local subtask3 = Card:new("parallel_3", "Parallel task 3", {id = "parallel_3"})
      subtask3.id = "parallel_3"

      -- All start incomplete
      todo_column:add_card(subtask1)
      todo_column:add_card(subtask2)
      todo_column:add_card(subtask3)

      card.properties.subtasks = {"parallel_1", "parallel_2", "parallel_3"}

      -- Parent should be blocked
      local success1 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success1)

      -- Complete them one by one - parent still blocked until all complete
      board:move_card(subtask1, todo_column, done_column)
      local success2 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success2) -- Still 2 incomplete

      board:move_card(subtask2, todo_column, done_column)
      local success3 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_false(success3) -- Still 1 incomplete

      board:move_card(subtask3, todo_column, done_column)
      local success4 = pcall(function()
        board:move_card(card, todo_column, done_column)
      end)
      assert.is_true(success4) -- All complete now
    end)
  end)

  describe("complex parent-child relationships", function()
    it("should handle shared subtasks across multiple parents", function()
      -- Create a complex scenario with multiple parents sharing children
      local shared_subtask = Card:new("shared_1", "Shared subtask", {id = "shared_1"})
      shared_subtask.id = "shared_1"
      todo_column:add_card(shared_subtask)

      local parent1 = Card:new("parent_1", "Parent 1", {
        id = "parent_1",
        subtasks = {"shared_1"}
      })
      parent1.id = "parent_1"
      parent1.properties.subtasks = {"shared_1"}
      todo_column:add_card(parent1)

      local parent2 = Card:new("parent_2", "Parent 2", {
        id = "parent_2",
        subtasks = {"shared_1"}
      })
      parent2.id = "parent_2"
      parent2.properties.subtasks = {"shared_1"}
      todo_column:add_card(parent2)

      -- Both parents should be blocked by incomplete shared subtask
      local success1, err1 = pcall(function()
        board:move_card(parent1, todo_column, done_column)
      end)
      assert.is_false(success1)
      assert.matches("shared_1", err1)

      local success2, err2 = pcall(function()
        board:move_card(parent2, todo_column, done_column)
      end)
      assert.is_false(success2)
      assert.matches("shared_1", err2)

      -- Complete shared subtask
      board:move_card(shared_subtask, todo_column, done_column)

      -- Both parents should now be moveable
      local success3 = pcall(function()
        board:move_card(parent1, todo_column, done_column)
      end)
      assert.is_true(success3)

      local success4 = pcall(function()
        board:move_card(parent2, todo_column, done_column)
      end)
      assert.is_true(success4)
    end)
  end)
end)
