require('polyfills.vim')
local triggers = require('kanban-md.triggers')
local Card = require('kanban-md.card')
local fixtures = require('tests.fixtures.boards')

describe("Trigger implementations", function()
  describe("timestamp trigger", function()
    local trigger_fn
    local test_card
    local test_column

    before_each(function()
      trigger_fn = triggers.timestamp()
      test_card = Card:new("test-1", "Test task", {})
      test_column = { name = "In Progress", id = "in_progress" }
    end)

    it("should set timestamp property when execute function is called", function()
      local old_time = os.time()

      local context = { card = test_card }
      local result = trigger_fn(test_column, context)

      assert.is_number(test_card.properties.in_progress)
      assert.is_true(test_card.properties.in_progress >= old_time)
      assert.is_true(result) -- Returns true on success
    end)

    it("should use normalised column names", function()
      local column_with_spaces = { name = "In Progress & Review", id = "in_progress_review" }

      local context = { card = test_card }
      trigger_fn(column_with_spaces, context)

      assert.is_number(test_card.properties.in_progress___review)
    end)

    it("should handle special columns (__ARCHIVE__)", function()
      local archive_column = { name = "__ARCHIVE__", id = "__ARCHIVE__" }

      local context = { card = test_card }
      trigger_fn(archive_column, context)

      assert.is_number(test_card.properties.archived)
    end)

    it("should update timestamp if already exists", function()
      test_card.properties.in_progress = 1234567890

      local context = { card = test_card }
      local result = trigger_fn(test_column, context)
      local new_timestamp = test_card.properties.in_progress

      assert.is_number(new_timestamp)
      assert.is_true(new_timestamp > 1234567890)
      assert.is_true(result)
    end)
  end)

  describe("WIP limit trigger", function()
    local trigger_fn
    local test_card
    local test_column

    before_each(function()
      trigger_fn = triggers.wip_limit(3)
      test_card = Card:new("test-1", "Test task", {})
      test_column = {
        name = "In Progress",
        cards = {},
        config = { wip_limit = 3 }
      }
    end)

    it("should validate against limit", function()
      -- Add cards up to one less than limit (so adding test_card would reach limit)
      for i = 1, 2 do
        table.insert(test_column.cards, Card:new("card-" .. i, "Task " .. i))
      end

      -- WIP trigger checks target_column in context
      local context = { card = test_card, target_column = test_column }
      local result = trigger_fn(test_column, context)

      -- New trigger returns Triggerable result format
      assert.is_table(result)
      assert.is_true(result.success)
    end)

    it("should count cards correctly", function()
      -- Add 2 cards (under limit)
      for i = 1, 2 do
        table.insert(test_column.cards, Card:new("card-" .. i, "Task " .. i))
      end

      -- WIP trigger checks target_column in context
      local context = { card = test_card, target_column = test_column }
      local result = trigger_fn(test_column, context)

      -- New trigger returns Triggerable result format
      assert.is_table(result)
      assert.is_true(result.success)
      assert.are.equal(0, #result.errors)
    end)

    it("should error on violation", function()
      -- Add cards to exactly the limit
      for i = 1, 3 do
        table.insert(test_column.cards, Card:new("card-" .. i, "Task " .. i))
      end

      -- WIP trigger checks target_column in context
      local context = { card = test_card, target_column = test_column }
      local result = trigger_fn(test_column, context)

      -- New trigger returns Triggerable error result
      assert.is_table(result)
      assert.is_false(result.success)
      assert.is_true(#result.errors > 0)
      assert.matches("WIP limit reached for 'In Progress' %(3/3%)%. Remove or complete a card before adding more%.", result.errors[1])
    end)
  end)

  describe("assignment trigger", function()
    local trigger_fn
    local test_card
    local test_column

    before_each(function()
      trigger_fn = triggers.assignment()
      test_card = Card:new("test-1", "Test task", {})
      test_column = {
        name = "In Progress",
        config = { assignees = {"alice", "bob", "charlie"} },
        last_assigned_index = 0
      }
    end)

    it("should implement round-robin assignment", function()
      -- First assignment
      trigger_fn(test_column, { card = test_card })
      assert.are.equal("alice", test_card.properties.assignee)
      assert.are.equal(1, test_column.last_assigned_index)

      -- Second assignment
      local card2 = Card:new("test-2", "Test task 2", {})
      trigger_fn(test_column, { card = card2 })
      assert.are.equal("bob", card2.properties.assignee)
      assert.are.equal(2, test_column.last_assigned_index)

      -- Third assignment
      local card3 = Card:new("test-3", "Test task 3", {})
      trigger_fn(test_column, { card = card3 })
      assert.are.equal("charlie", card3.properties.assignee)
      assert.are.equal(3, test_column.last_assigned_index)

      -- Should wrap around
      local card4 = Card:new("test-4", "Test task 4", {})
      trigger_fn(test_column, { card = card4 })
      assert.are.equal("alice", card4.properties.assignee)
      assert.are.equal(1, test_column.last_assigned_index)
    end)

    it("should track assignment index", function()
      assert.are.equal(0, test_column.last_assigned_index)

      trigger_fn(test_column, { card = test_card })

      assert.are.equal(1, test_column.last_assigned_index)
    end)

    it("should override existing assignee", function()
      test_card.properties.assignee = "existing_user"
      local original_index = test_column.last_assigned_index

      trigger_fn(test_column, { card = test_card })

      -- Assignment trigger always assigns, overriding existing value
      assert.are.equal("alice", test_card.properties.assignee)
      assert.are.equal(1, test_column.last_assigned_index)
    end)
  end)

  describe("custom validation triggers", function()
    it("should allow registering custom property validators via on_checking", function()
      local Board = require('kanban-md.board')
      local Column = require('kanban-md.column')
      local Triggerable = require('kanban-md.triggerable')

      -- Create a board with columns
      local board = Board:new()
      board.title = "Test Board"
      local backlog = Column:new("Backlog")
      local done = Column:new("Done")
      done.config.is_completion_state = true
      table.insert(board.columns, backlog)
      table.insert(board.columns, done)

      -- Create a custom validation trigger that requires a "priority" property
      local priority_validator = function(column, context)
        if not context.card.properties.priority then
          return Triggerable:error("Card must have a 'priority' property before completion")
        end
        local valid_priorities = {high = true, medium = true, low = true}
        if not valid_priorities[context.card.properties.priority] then
          return Triggerable:error("Priority must be 'high', 'medium', or 'low'")
        end
        return Triggerable:success()
      end

      -- Register the validator on the completion column
      done:register_on_checking("priority_validation", priority_validator)

      -- Create a test card without priority
      local test_card = Card:new("test-1", "Test task", {})
      table.insert(backlog.cards, test_card)

      -- Try to move to Done without priority - should fail
      local success, err = pcall(function()
        board:move_card(test_card, backlog, done)
      end)
      assert.is_false(success)
      assert.matches("priority", err:lower())

      -- Note: After failed move, card has been removed from backlog but not added to done
      -- This is expected - see board.lua line 202: "Board object may be inconsistent"
      assert.are.equal(0, #backlog.cards)
      assert.are.equal(0, #done.cards)

      -- Create a new card with valid priority for the success case
      local test_card2 = Card:new("test-2", "Test task 2", {priority = "high"})
      table.insert(backlog.cards, test_card2)

      -- Move with valid priority - should succeed
      success, err = pcall(function()
        board:move_card(test_card2, backlog, done)
      end)
      assert.is_true(success)

      -- Verify card is now in done
      assert.are.equal(0, #backlog.cards)
      assert.are.equal(1, #done.cards)
    end)

    it("should support warning mode for validation triggers", function()
      local Board = require('kanban-md.board')
      local Column = require('kanban-md.column')
      local Triggerable = require('kanban-md.triggerable')

      -- Create a board with columns
      local board = Board:new()
      board.title = "Test Board"
      local backlog = Column:new("Backlog")
      local done = Column:new("Done")
      done.config.is_completion_state = true
      table.insert(board.columns, backlog)
      table.insert(board.columns, done)

      -- Track warnings via callback
      local warnings_received = {}
      local estimate_validator = function(column, context)
        if not context.card.properties.estimated_time then
          table.insert(warnings_received, "Card has no estimated_time - consider adding one")
          return Triggerable:warning("Card has no estimated_time - consider adding one")
        end
        return Triggerable:success()
      end

      -- Register the validator
      done:register_on_checking("estimate_check", estimate_validator)

      -- Create a test card without estimate
      local test_card = Card:new("test-1", "Test task", {})
      table.insert(backlog.cards, test_card)

      -- Move should succeed despite warning (warnings don't block moves)
      local success = pcall(function()
        board:move_card(test_card, backlog, done)
      end)
      assert.is_true(success)
      -- Verify the warning was triggered
      assert.is_true(#warnings_received > 0)
      assert.matches("estimated_time", warnings_received[1])
    end)
  end)
end)
