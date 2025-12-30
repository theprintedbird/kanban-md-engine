require('polyfills.vim')
local Board = require('kanban-md.board')
local Column = require('kanban-md.column')
local Card = require('kanban-md.card')
local WorkflowEngine = require('kanban-md.workflow_engine')
local fixtures = require('tests.fixtures.boards')
local mocks = require('tests.helpers.mocks')

describe("Full state machine integration", function()
  describe("card movement flow", function()
    it("should handle complete move workflow", function()
      -- Setup a board with workflow validation
      local board = Board:new()
      board.id = "test-board"
      local todo_column = board:add_column("todo", "Todo")
      local progress_column = board:add_column("progress", "In Progress")
      local done_column = board:add_column("done", "Done")
      
      -- Add a card to Todo
      local card = Card:new("card-1", "Test task")
      todo_column:add_card(card)
      
      assert.are.equal(1, #todo_column.cards)
      assert.are.equal("todo", card.column)
			assert.are.equal("card-1", todo_column.cards[1].id)
      
      -- Move card through workflow: Todo -> Progress -> Done
      -- Move to Progress
      local result = board:validate_move(card, todo_column, progress_column)
      assert.are.equal("approved", result.state)
      assert.is_nil(result:get_error())
      
      -- Execute the move
      board:move_card(card, todo_column, progress_column)
      -- todo_column:remove_card(card.id)
      -- progress_column:add_card(card)
      
      assert.are.equal(0, #todo_column.cards)
      assert.are.equal(1, #progress_column.cards)
      assert.are.equal("progress", card.column)

      -- Move to Done
      local validate_move_to_done = board:validate_move(card, progress_column, done_column)
      assert.are.equal("approved", validate_move_to_done .state)
      
      board:move_card(card, progress_column, done_column)
      -- progress_column:remove_card(card.id)
      -- done_column:add_card(card)
      -- 
      assert.are.equal(0, #progress_column.cards)
      assert.are.equal(1, #done_column.cards)
      assert.are.equal("done", card.column)
    end)
    
    it("should execute all triggers in sequence", function()
      local board = Board:new()
      local column = board:add_column("progress", "In Progress")
      
      -- Setup triggers that track execution order
      local execution_order = {}
      
      local trigger1 = mocks.create_mock_trigger("timestamp", function(context)
        table.insert(execution_order, "timestamp")
        context.card.properties.started = os.time()
        return { success = true }
      end)
      
      local trigger2 = mocks.create_mock_trigger("assignment", function(context)
        table.insert(execution_order, "assignment")
        context.card.properties.assignee = "developer"
        return { success = true }
      end)
      
      local trigger3 = mocks.create_mock_trigger("validation", function(context)
        table.insert(execution_order, "validation")
        return { success = true }
      end)
      
      -- Register triggers in specific order
      column:register_trigger("on_entry", "timestamp", trigger1)
      column:register_trigger("on_entry", "assignment", trigger2)
      column:register_trigger("on_entry", "validation", trigger3)
      
      -- Add card and verify all triggers execute in order
      local card = Card:new("card-1", "Test task")
      column:add_card(card)
      
      assert.are.same({"timestamp", "assignment", "validation"}, execution_order)
      assert.is_not_nil(card.properties.started)
      assert.are.equal("developer", card.properties.assignee)
    end)
    
    it("should update statistics after moves", function()
      local board = Board:new()
      local todo_column = Column:new("todo", "Todo")
      local done_column = Column:new("done", "Done")

      board:add_column(todo_column)
      board:add_column(done_column)

      -- Register auto-timestamp triggers
      board:auto_register_triggers()

      -- Add cards and track statistics
      local card1 = Card:new("card-1", "Task 1", { complexity = 3 })
      local card2 = Card:new("card-2", "Task 2", { complexity = 5 })

      todo_column:add_card(card1)
      todo_column:add_card(card2)

      -- Initial stats
      assert.are.equal(2, #todo_column.cards)
      assert.are.equal(0, #done_column.cards)

      -- Move one card to done (timestamp set automatically by trigger)
			board:move_card(card1,todo_column,done_column)

      -- Verify statistics updated
      assert.are.equal(1, #todo_column.cards)
      assert.are.equal(1, #done_column.cards)
      assert.is_not_nil(card1.properties.done, "Completion timestamp should be set automatically by trigger")
    end)
    
    it("should maintain consistency through transitions", function()
      local board = Board:new()
      local column = board:add_column("progress", "In Progress")
      column.config.wip_limit = 2

      -- Register WIP limit checking trigger
      local triggers = require('kanban-md.triggers')
      local wip_fn, wip_rollback = triggers.wip_limit(column.config.wip_limit)
      column:register_on_checking("wip_limit", wip_fn, wip_rollback)

      -- Add cards up to WIP limit
      local card1 = Card:new("card-1", "Task 1")
      local card2 = Card:new("card-2", "Task 2")

      column:add_card(card1)
      column:add_card(card2)

      assert.are.equal(2, #column.cards)

      -- Trying to add third card should trigger WIP limit validation
      local card3 = Card:new("card-3", "Task 3")

      -- This should fail due to WIP limit
      local success, err = pcall(function()
        column:add_card(card3)
      end)

      -- Should fail with WIP limit error
      assert.is_false(success)
      assert.matches("WIP limit", err)

      -- Board state should remain consistent
      assert.are.equal(2, #column.cards)
      assert.is_nil(card3.column)
    end)

    it("should allow removing cards from column at WIP limit", function()
      local board = Board:new()
      local source_column = board:add_column("source", "Source")
      local target_column = board:add_column("target", "Target")

      -- Set WIP limit on source column
      source_column.config.wip_limit = 1

      -- Register WIP limit checking trigger on source
      local triggers = require('kanban-md.triggers')
      local wip_fn, wip_rollback = triggers.wip_limit(source_column.config.wip_limit)
      source_column:register_on_checking("wip_limit", wip_fn, wip_rollback)

      -- Add card up to WIP limit
      local card1 = Card:new("card-1", "Task 1")
      source_column:add_card(card1)

      assert.are.equal(1, #source_column.cards)

      -- Moving card OUT of column at WIP limit should succeed
      -- This was the bug: exit validation was incorrectly checking source column's WIP
      local success, err = pcall(function()
        board:move_card(card1, source_column, target_column)
      end)

      -- Should succeed - cards can always leave a column
      assert.is_true(success, "Should be able to move card out of column at WIP limit: " .. tostring(err))

      -- Verify the move completed
      assert.are.equal(0, #source_column.cards)
      assert.are.equal(1, #target_column.cards)
      assert.are.equal("target", card1.column)
    end)
  end)

  describe("trigger chains", function()
    it("should execute cascading triggers", function()
      local board = Board:new()
      local column1 = board:add_column("review", "Review")
      local column2 = board:add_column("done", "Done")
      
      local cascade_log = {}
      
      -- Setup cascading triggers that trigger subsequent actions
      local review_trigger = mocks.create_mock_trigger("mark_reviewed", function(context)
        table.insert(cascade_log, "marked_as_reviewed")
        context.card.properties.reviewed = true
        context.card.properties.reviewed_at = os.time()
        
        -- Cascade: Auto-move to done if review passes
        if context.card.properties.review_status == "pass" then
          table.insert(cascade_log, "auto_move_triggered")
          -- This would trigger the move to done column
          return { success = true, cascade = { target_column = "done" } }
        end
        
        return { success = true }
      end)
      
      local done_trigger = mocks.create_mock_trigger("mark_complete", function(context)
        table.insert(cascade_log, "marked_complete")
        context.card.properties.completed = true
        context.card.properties.completed_at = os.time()
        return { success = true }
      end)
      
      column1:register_trigger("on_entry", "mark_reviewed", review_trigger)
      column2:register_trigger("on_entry", "mark_complete", done_trigger)
      
      -- Add card with passing review
      local card = Card:new("card-1", "Test task", { review_status = "pass" })
      column1:add_card(card)
      
      -- Verify first trigger executed
      assert.is_true(card.properties.reviewed)
      assert.is_not_nil(card.properties.reviewed_at)
      assert.are.same({"marked_as_reviewed", "auto_move_triggered"}, cascade_log)
      
      -- Simulate the cascaded move to done
      column1:remove_card(card)
      column2:add_card(card)
      
      -- Verify cascade completed
      assert.is_true(card.properties.completed)
      assert.is_not_nil(card.properties.completed_at)
      assert.are.same({"marked_as_reviewed", "auto_move_triggered", "marked_complete"}, cascade_log)
    end)
    
    it("should handle trigger failures in chain", function()
      local board = Board:new()
      local column = board:add_column("test", "Test Column")

      local execution_log = {}

      -- First trigger succeeds
      local trigger1 = mocks.create_mock_trigger("success", function(context)
        table.insert(execution_log, "trigger1_success")
        context.card.properties.step1 = true
        return { success = true }
      end)

      -- Second trigger fails
      local trigger2 = mocks.create_failing_trigger("failure", "Validation failed")

      -- Third trigger should not execute due to failure
      local trigger3 = mocks.create_mock_trigger("skipped", function(context)
        table.insert(execution_log, "trigger3_executed")
        return { success = true }
      end)

      column:register_trigger("on_entry", "success", trigger1)
      column:register_trigger("on_entry", "failure", trigger2)
      column:register_trigger("on_entry", "skipped", trigger3)

      local card = Card:new("card-1", "Test task")

      -- Adding card should fail due to trigger2
      local success, error_msg = pcall(function()
        column:add_card(card)
      end)

      assert.is_false(success)
      assert.matches("Validation failed", error_msg)

      -- Only first trigger should have executed
      assert.are.same({"trigger1_success"}, execution_log)

      -- With copy-and-commit: original card is never modified (changes were on discarded copy)
      assert.is_nil(card.properties.step1, "Original card should be unchanged")

      -- Card should not be in column due to failure
      assert.are.equal(0, #column.cards)
    end)
    
    it("should maintain order of execution", function()
      local board = Board:new()
      local column = board:add_column("test", "Test Column")
      
      local execution_order = {}
      
      -- Register triggers in specific order with dependencies
      for i = 1, 5 do
        local trigger_name = "trigger_" .. i
        local trigger = mocks.create_mock_trigger(trigger_name, function(context)
          table.insert(execution_order, trigger_name)
          context.card.properties["step_" .. i] = i
          return { success = true }
        end)
        column:register_trigger("on_entry", trigger_name, trigger)
      end
      
      local card = Card:new("card-1", "Test task")
      column:add_card(card)
      
      -- Verify strict execution order
      assert.are.same({
        "trigger_1", "trigger_2", "trigger_3", "trigger_4", "trigger_5"
      }, execution_order)
      
      -- Verify all steps completed in order
      for i = 1, 5 do
        assert.are.equal(i, card.properties["step_" .. i])
      end
    end)
    
    it("should share context between triggers", function()
      local board = Board:new()
      local column = board:add_column("test", "Test Column")
      
      -- Triggers that build on each other's context
      local trigger1 = mocks.create_mock_trigger("init", function(context)
        context.shared_data = { count = 0, processed_by = {} }
        context.card.properties.initialized = true
        return { success = true }
      end)
      
      local trigger2 = mocks.create_mock_trigger("process", function(context)
        context.shared_data.count = context.shared_data.count + 1
        table.insert(context.shared_data.processed_by, "processor")
        context.card.properties.processed = context.shared_data.count
        return { success = true }
      end)
      
      local trigger3 = mocks.create_mock_trigger("finalize", function(context)
        context.shared_data.count = context.shared_data.count + 1
        table.insert(context.shared_data.processed_by, "finalizer")
        context.card.properties.final_count = context.shared_data.count
        context.card.properties.processors = table.concat(context.shared_data.processed_by, ",")
        return { success = true }
      end)
      
      column:register_trigger("on_entry", "init", trigger1)
      column:register_trigger("on_entry", "process", trigger2)
      column:register_trigger("on_entry", "finalize", trigger3)
      
      local card = Card:new("card-1", "Test task")
      column:add_card(card)
      
      -- Verify shared context was used correctly
      assert.is_true(card.properties.initialized)
      assert.are.equal(1, card.properties.processed)
      assert.are.equal(2, card.properties.final_count)
      assert.are.equal("processor,finalizer", card.properties.processors)
    end)
  end)

  describe("error recovery", function()
    it("should rollback on validation failure", function()
      local board = Board:new()
      local column = board:add_column("test", "Test Column")

      -- Create a trigger that modifies state then fails
      -- With copy-and-commit, the modifications happen on a copy which is then discarded
      local failing_trigger = function(column, context)
        -- Modify card state (this modifies the COPY, not the original)
        context.card.properties.modified = true
        context.card.properties.temp_value = "should_be_rolled_back"

        -- Then fail
        error("Validation failed after modification")
      end

      column:register_trigger("on_entry", "failing", failing_trigger)

      local card = Card:new("card-1", "Test task", { original = true })

      -- Attempt to add card should fail
      -- With copy-and-commit: original card remains unchanged (modifications were on the discarded copy)
      local success, error_msg = pcall(function()
        column:add_card(card)
      end)

      assert.is_false(success)
      assert.matches("Validation failed", error_msg)

      -- Card state should be unchanged (copy-and-commit means original was never modified)
      assert.is_true(card.properties.original, "Original property should still be true")
      assert.is_nil(card.properties.modified, "Modified property should be nil (never set on original)")
      assert.is_nil(card.properties.temp_value, "Temp value should be nil (never set on original)")

      -- Card should not be in column
      assert.are.equal(0, #column.cards, "Card should not be in column after failed add")
    end)
  --   
  --   it("should recover from partial failures", function()
  --     local board = Board:new()
  --     local column = board:add_column("test", "Test Column")
  --     
  --     local execution_log = {}
  --     local rollback_log = {}
  --     
  --     -- Three triggers: success, success, fail
  --     local trigger1 = {
  --       name = "success1",
  --       execute = function(context)
  --         table.insert(execution_log, "trigger1_execute")
  --         context.card.properties.step1 = true
  --         return { success = true }
  --       end,
  --       rollback = function(context, previous_state)
  --         table.insert(rollback_log, "trigger1_rollback")
  --         context.card.properties.step1 = nil
  --         return true
  --       end
  --     }
  --     
  --     local trigger2 = {
  --       name = "success2", 
  --       execute = function(context)
  --         table.insert(execution_log, "trigger2_execute")
  --         context.card.properties.step2 = true
  --         return { success = true }
  --       end,
  --       rollback = function(context, previous_state)
  --         table.insert(rollback_log, "trigger2_rollback")
  --         context.card.properties.step2 = nil
  --         return true
  --       end
  --     }
  --     
  --     local trigger3 = {
  --       name = "failure",
  --       execute = function(context)
  --         table.insert(execution_log, "trigger3_execute")
  --         context.card.properties.step3 = true
  --         error("Third trigger failed")
  --       end,
  --       rollback = function(context, previous_state)
  --         table.insert(rollback_log, "trigger3_rollback")
  --         context.card.properties.step3 = nil
  --         return true
  --       end
  --     }
  --     
  --     column:register_trigger("on_entry", "success1", trigger1)
  --     column:register_trigger("on_entry", "success2", trigger2)
  --     column:register_trigger("on_entry", "failure", trigger3)
  --     
  --     local card = Card:new("card-1", "Test task")
  --     
  --     -- Should execute all triggers, then rollback in reverse order
  --     local success, error_msg = pcall(function()
  --       column:add_card(card)
  --     end)
  --     
  --     assert.is_false(success)
  --     assert.matches("Third trigger failed", error_msg)
  --     
  --     -- All triggers should have executed
  --     assert.are.same({"trigger1_execute", "trigger2_execute", "trigger3_execute"}, execution_log)
  --     
  --     -- Rollback should happen in reverse order
  --     assert.are.same({"trigger3_rollback", "trigger2_rollback", "trigger1_rollback"}, rollback_log)
  --     
  --     -- All changes should be rolled back
  --     assert.is_nil(card.properties.step1)
  --     assert.is_nil(card.properties.step2)
  --     assert.is_nil(card.properties.step3)
  --   end)
  --   
  --   it("should maintain board consistency", function()
  --     local board = Board:new()
  --     local source_column = Column:new("source", "Source")
  --     local target_column = Column:new("target", "Target")
  --     
  --     board:add_column(source_column)
  --     board:add_column(target_column)
  --     
  --     -- Add cards to source
  --     local card1 = Card:new("card-1", "Task 1")
  --     local card2 = Card:new("card-2", "Task 2")
  --     
  --     source_column:add_card(card1)
  --     source_column:add_card(card2)
  --     
  --     assert.are.equal(2, #source_column.cards)
  --     assert.are.equal(0, #target_column.cards)
  --     
  --     -- Setup a trigger that fails on target column
  --     local failing_trigger = mocks.create_failing_trigger("validation", "Target validation failed")
  --     target_column:register_trigger("on_entry", "validation", failing_trigger)
  --     
  --     -- Attempt to move card1 to target
  --     local initial_source_count = #source_column.cards
  --     local initial_target_count = #target_column.cards
  --     
  --     local success, error_msg = pcall(function()
  --       -- Simulate move operation
  --       source_column:remove_card(card1.id)
  --       target_column:add_card(card1)  -- This should fail
  --     end)
  --     
  --     assert.is_false(success)
  --     
  --     -- Board should maintain consistency - card1 should still be in source
  --     -- (In real implementation, the move would be wrapped in a transaction)
  --     assert.are.equal("source", card1.column)
  --     
  --     -- Other cards should be unaffected
  --     assert.are.equal("source", card2.column)
  --     assert.are.equal(1, #source_column.cards)  -- card1 was removed but move failed
  --     assert.are.equal(0, #target_column.cards)   -- card1 not added due to failure
  --   end)
  --   
  --   it("should log all error states", function()
  --     local board = Board:new() 
  --     local column = Column:new("test", "Test Column")
  --     board:add_column(column)
  --     
  --     local error_log = {}
  --     
  --     -- Mock the command log to capture errors
  --     board.command_log = {
  --       add_command = function(self, command)
  --         -- Capture error information
  --         if not command.success then
  --           table.insert(error_log, {
  --             command_name = command.name,
  --             error = command.error,
  --             timestamp = command.timestamp,
  --             context = command.context
  --           })
  --         end
  --       end,
  --       rollback_last = function(self, count)
  --         table.insert(error_log, { action = "rollback", count = count })
  --       end
  --     }
  --     
  --     -- Setup failing trigger
  --     local failing_trigger = {
  --       name = "failing_trigger",
  --       execute = function(context)
  --         error("Test error for logging")
  --       end,
  --       rollback = function(context, previous_state)
  --         return true
  --       end
  --     }
  --     
  --     column:register_trigger("on_entry", "failing_trigger", failing_trigger)
  --     
  --     local card = Card:new("card-1", "Test task")
  --     
  --     -- Trigger the error
  --     local success, error_msg = pcall(function()
  --       column:add_card(card)
  --     end)
  --     
  --     assert.is_false(success)
  --     
  --     -- Verify error logging (implementation-dependent)
  --     -- This would depend on the actual command logging implementation
  --     assert.is_not_nil(error_log)
  --     -- In a real implementation, we'd verify specific error details were logged
  --   end)
  end)

  -- describe("concurrent operations", function()
  --   it("should handle multiple cards moving", function()
  --     local board = Board:new()
  --     local source_column = Column:new("source", "Source")
  --     local target_column = Column:new("target", "Target")
  --     
  --     board:add_column(source_column)
  --     board:add_column(target_column)
  --     
  --     -- Add multiple cards to source
  --     local cards = {}
  --     for i = 1, 5 do
  --       local card = Card:new("card-" .. i, "Task " .. i)
  --       table.insert(cards, card)
  --       source_column:add_card(card)
  --     end
  --     
  --     assert.are.equal(5, #source_column.cards)
  --     assert.are.equal(0, #target_column.cards)
  --     
  --     -- Simulate concurrent moves by tracking execution order
  --     local move_log = {}
  --     
  --     -- Add trigger to track moves
  --     local move_trigger = mocks.create_mock_trigger("track_move", function(context)
  --       table.insert(move_log, {
  --         card_id = context.card.id,
  --         timestamp = os.time(),
  --         target_column = context.column.name
  --       })
  --       return { success = true }
  --     end)
  --     
  --     target_column:register_trigger("on_entry", "track_move", move_trigger)
  --     
  --     -- Move all cards simultaneously (simulating concurrent operations)
  --     local successful_moves = 0
  --     for _, card in ipairs(cards) do
  --       local success, error_msg = pcall(function()
  --         source_column:remove_card(card.id)
  --         target_column:add_card(card)
  --         successful_moves = successful_moves + 1
  --       end)
  --       
  --       if not success then
  --         print("Move failed for " .. card.id .. ": " .. error_msg)
  --       end
  --     end
  --     
  --     -- Verify all moves completed
  --     assert.are.equal(5, successful_moves)
  --     assert.are.equal(0, #source_column.cards)
  --     assert.are.equal(5, #target_column.cards)
  --     assert.are.equal(5, #move_log)
  --     
  --     -- Verify all cards are in target column
  --     for _, card in ipairs(cards) do
  --       assert.are.equal("target", card.column)
  --     end
  --   end)
  --   
  --   it("should prevent race conditions", function()
  --     local board = Board:new()
  --     local column = board:add_column("limited", "Limited Column")
  --     column.config.wip_limit = 3
  --     
  --     -- Track WIP limit checks to detect race conditions
  --     local wip_checks = {}
  --     local cards_added = 0
  --     
  --     -- Override WIP validation to track concurrent access
  --     local original_add_card = column.add_card
  --     column.add_card = function(self, card)
  --       -- Simulate checking WIP limit
  --       local current_count = #self.cards
  --       table.insert(wip_checks, {
  --         card_id = card.id,
  --         count_before = current_count,
  --         timestamp = os.time()
  --       })
  --       
  --       -- Small delay to increase chance of race condition
  --       -- (In real concurrent environment)
  --       
  --       if current_count >= self.config.wip_limit then
  --         error("WIP limit exceeded: " .. current_count .. " >= " .. self.config.wip_limit)
  --       end
  --       
  --       -- Call original method
  --       original_add_card(self, card)
  --       cards_added = cards_added + 1
  --     end
  --     
  --     -- Try to add 5 cards to a 3-card limit column
  --     local cards = {}
  --     local successful_adds = 0
  --     local failed_adds = 0
  --     
  --     for i = 1, 5 do
  --       local card = Card:new("card-" .. i, "Task " .. i)
  --       table.insert(cards, card)
  --       
  --       local success, error_msg = pcall(function()
  --         column:add_card(card)
  --         successful_adds = successful_adds + 1
  --       end)
  --       
  --       if not success then
  --         failed_adds = failed_adds + 1
  --       end
  --     end
  --     
  --     -- Should respect WIP limit
  --     assert.are.equal(3, successful_adds)
  --     assert.are.equal(2, failed_adds)
  --     assert.are.equal(3, #column.cards)
  --     assert.are.equal(5, #wip_checks)  -- All cards attempted WIP check
  --   end)
  --   
  --   it("should maintain WIP limits under load", function()
  --     local board = Board:new()
  --     local progress_column = Column:new("progress", "In Progress")
  --     local done_column = Column:new("done", "Done")
  --     
  --     progress_column.config.wip_limit = 2
  --     board:add_column(progress_column)
  --     board:add_column(done_column)
  --     
  --     -- Fill progress column to limit
  --     local card1 = Card:new("card-1", "Task 1")
  --     local card2 = Card:new("card-2", "Task 2")
  --     
  --     progress_column:add_card(card1)
  --     progress_column:add_card(card2)
  --     
  --     assert.are.equal(2, #progress_column.cards)
  --     
  --     -- Create multiple cards trying to enter simultaneously
  --     local waiting_cards = {}
  --     for i = 3, 7 do
  --       local card = Card:new("card-" .. i, "Task " .. i)
  --       table.insert(waiting_cards, card)
  --     end
  --     
  --     -- Track WIP violations
  --     local violations = {}
  --     local successful_entries = 0
  --     
  --     -- Try to add all waiting cards
  --     for _, card in ipairs(waiting_cards) do
  --       local success, error_msg = pcall(function()
  --         progress_column:add_card(card)
  --         successful_entries = successful_entries + 1
  --       end)
  --       
  --       if not success then
  --         table.insert(violations, {
  --           card_id = card.id,
  --           error = error_msg,
  --           column_count = #progress_column.cards
  --         })
  --       end
  --     end
  --     
  --     -- Should maintain WIP limit strictly
  --     assert.are.equal(0, successful_entries)  -- No new cards should be added
  --     assert.are.equal(2, #progress_column.cards)  -- Still at limit
  --     assert.are.equal(5, #violations)  -- All 5 cards rejected
  --     
  --     -- Now move one card out to make space
  --     progress_column:remove_card(card1.id)
  --     done_column:add_card(card1)
  --     
  --     assert.are.equal(1, #progress_column.cards)
  --     
  --     -- Try adding one more card - should succeed now
  --     local new_card = Card:new("card-new", "New Task")
  --     local success, error_msg = pcall(function()
  --       progress_column:add_card(new_card)
  --     end)
  --     
  --     assert.is_true(success)
  --     assert.are.equal(2, #progress_column.cards)  -- Back to limit
  --     assert.are.equal("progress", new_card.column)
  --   end)
  -- end)
end)
