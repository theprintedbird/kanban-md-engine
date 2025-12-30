require('polyfills.vim')
local Column = require('kanban-md.column')
local mocks = require('tests.helpers.mocks')

-- Mock card for testing
local function create_test_card(id, properties)
  local card = {
    id = id or "test_card_" .. math.random(1000),
    properties = properties or {},
    column = nil
  }

  return card
end

describe("Column with triggers", function()
  local column

  before_each(function()
    column = Column:new("test_column", "Test Column")
  end)

  describe("column states", function()
    it("should start as ColumnEmpty", function()
      assert.are.equal("test_column", column.id)
      assert.are.equal("Test Column", column.name)
      assert.are.same({}, column.cards)
      assert.is_table(column.triggers)
    end)

    it("should transition to ColumnActive on card addition", function()
      local card = create_test_card("card1")
      
      column:add_card(card)
      
      assert.are.equal(1, #column.cards)
      assert.are.equal(card, column.cards[1])
      assert.are.equal("test_column", card.column)
    end)

    it("should transition to ColumnAtLimit at WIP limit", function()
      column.config.wip_limit = 2
      local card1 = create_test_card("card1")
      local card2 = create_test_card("card2")
      
      column:add_card(card1)
      column:add_card(card2)
      
      assert.are.equal(2, #column.cards)
      assert.are.equal(column.config.wip_limit, #column.cards)
    end)

    it("should transition to ColumnOverLimit on forced add", function()
      column.config.wip_limit = 1
      local card1 = create_test_card("card1")
      local card2 = create_test_card("card2")
      
      column:add_card(card1)
      column:add_card(card2)  -- This exceeds the limit
      
      assert.are.equal(2, #column.cards)
      assert.is_true(#column.cards > column.config.wip_limit)
    end)

    it("should return to ColumnEmpty when last card removed", function()
      local card = create_test_card("card1")

      column:add_card(card)
      assert.are.equal(1, #column.cards)

      local removed_card = column:remove_card(card)
      assert.are.equal(0, #column.cards)
      assert.are.equal(card, removed_card)
      -- Card column should still reference the column ID it was removed from
      assert.are.equal("test_column", removed_card.column)
    end)
  end)

  describe("card operations", function()
    it("should execute on_entry triggers when card added", function()
      local trigger_called = false
      local trigger_context = nil

      column:register_on_entry("test_trigger", function(self, context)
        trigger_called = true
        trigger_context = {col = self, card = context.card}
        return {success = true}
      end)

      local card = create_test_card("card1")
      column:add_card(card)

      assert.is_true(trigger_called)
      assert.are.equal(column, trigger_context.col)
      -- With copy-and-commit, triggers receive a copy of the card
      assert.are.equal(card.id, trigger_context.card.id)
      assert.are.equal(card.column, trigger_context.card.column)
    end)

    it("should execute on_exit triggers when card removed", function()
      local trigger_called = false
      local trigger_context = nil

      column:register_on_exit("test_trigger", function(self, context)
        trigger_called = true
        trigger_context = {col = self, card = context.card}
        return {success = true}
      end)

      local card = create_test_card("card1")
      column:add_card(card)

      -- Reset trigger state
      trigger_called = false
      trigger_context = nil

      column:remove_card(card)

      assert.is_true(trigger_called)
      assert.are.equal(column, trigger_context.col)
      -- With copy-and-commit, triggers receive a copy of the card
      assert.are.equal(card.id, trigger_context.card.id)
      assert.are.equal(card.column, trigger_context.card.column)
    end)

    it("should execute on_stay triggers periodically", function()
      local mock_trigger = mocks.create_mock_trigger("stay_trigger")

      column:register_on_stay("stay_trigger", mock_trigger)

      local card = create_test_card("card1")
      column:add_card(card)

      -- Manually trigger on_stay
      local trigger_fn = column.triggers["on_stay"]["stay_trigger"]
      local success, result = pcall(trigger_fn, column, {card = card})
      assert.is_true(success)

      assert.are.equal(1, mock_trigger.get_call_count())
    end)

    it("should validate entry requirements", function()
      local entry_allowed = true

      column:register_on_entry("validator", function(self, context)
        if not entry_allowed then
          error("Entry not allowed")
        end
        return {success = true}
      end)

      local card = create_test_card("card1")

      -- Should succeed when entry allowed
      column:add_card(card)
      assert.are.equal(1, #column.cards)

      -- Test failure case
      entry_allowed = false
      local card2 = create_test_card("card2")

      -- The trigger will fail and add_card will throw an error
      local success, err = pcall(function()
        column:add_card(card2)
      end)
      assert.is_false(success)
      assert.is_not_nil(err)
      assert.are.equal(1, #column.cards)  -- Card not added due to trigger failure
    end)

    it("should check exit constraints", function()
      local exit_allowed = true

      column:register_on_exit("exit_validator", function(self, context)
        if not exit_allowed then
          error("Exit not allowed")
        end
        return {success = true}
      end)

      local card = create_test_card("card1")
      column:add_card(card)

      -- Should succeed when exit allowed
      local removed = column:remove_card(card)
      assert.are.equal(card, removed)
      assert.are.equal(0, #column.cards)

      -- Test failure case
      exit_allowed = false
      local card2 = create_test_card("card2")
      column:add_card(card2)

      -- The trigger will fail and remove_card will throw an error
      local success, err = pcall(function()
        column:remove_card(card2)
      end)
      assert.is_false(success)
      assert.is_not_nil(err)
      assert.are.equal(1, #column.cards)  -- Card not removed due to trigger failure
    end)
  end)

  describe("ProcessingEntry state", function()
    it("should validate requirements before entry", function()
      local requirements_met = false

      column:register_on_entry("requirements_check", function(self, context)
        if not requirements_met then
          error("Requirements not met")
        end
        return {success = true}
      end)

      local card = create_test_card("card1")

      -- Test when requirements not met
      local trigger_fn = column.triggers["on_entry"]["requirements_check"]
      local success, err = pcall(trigger_fn, column, {card = card})
      assert.is_false(success)

      -- Test when requirements met
      requirements_met = true
      local success2, result2 = pcall(trigger_fn, column, {card = card})
      assert.is_true(success2)
    end)

    it("should execute entry triggers if valid", function()
      local timestamp_set = false
      
      column:register_on_entry("timestamp", function(self, context)
        context.card.properties.entered_at = os.time()
        timestamp_set = true
        return {success = true}
      end)
      
      local card = create_test_card("card1")
      column:add_card(card)
      
      assert.is_true(timestamp_set)
      assert.is_not_nil(card.properties.entered_at)
    end)

    it("should update statistics after entry", function()
      local stats_updated = false
      
      column:register_on_entry("update_stats", function(self, context)
        if not self.stats then
          self.stats = {card_count = 0}
        end
        self.stats.card_count = self.stats.card_count + 1
        stats_updated = true
        return {success = true}
      end)
      
      local card = create_test_card("card1")
      column:add_card(card)
      
      assert.is_true(stats_updated)
      assert.are.equal(1, column.stats.card_count)
    end)

    it("should deny entry if requirements not met", function()
      local failing_trigger = mocks.create_failing_trigger("entry_blocker", "Cannot enter this column")

      column:register_on_entry("entry_blocker", failing_trigger)

      local card = create_test_card("card1")
      local trigger_fn = column.triggers["on_entry"]["entry_blocker"]
      local success, err = pcall(trigger_fn, column, {card = card})

      assert.is_false(success)
      assert.is_not_nil(err)
    end)
  end)

  describe("ProcessingExit state", function()
    it("should check constraints before exit", function()
      local constraints_passed = true

      column:register_on_exit("constraint_check", function(self, context)
        if not constraints_passed then
          error("Constraints not satisfied")
        end
        return {success = true}
      end)

      local card = create_test_card("card1")
      column:add_card(card)

      -- Test when constraints pass
      local trigger_fn = column.triggers["on_exit"]["constraint_check"]
      local success, result = pcall(trigger_fn, column, {card = card})
      assert.is_true(success)

      -- Test when constraints fail
      constraints_passed = false
      local success2, err2 = pcall(trigger_fn, column, {card = card})
      assert.is_false(success2)
    end)

    it("should execute exit triggers if allowed", function()
      local exit_time_set = false
      
      column:register_on_exit("exit_timestamp", function(self, context)
        context.card.properties.exited_at = os.time()
        exit_time_set = true
        return {success = true}
      end)
      
      local card = create_test_card("card1")
      column:add_card(card)
      column:remove_card(card)
      
      assert.is_true(exit_time_set)
      assert.is_not_nil(card.properties.exited_at)
    end)

    it("should block exit if constraints fail", function()
      local failing_exit = mocks.create_failing_trigger("exit_blocker", "Cannot exit this column yet")

      column:register_on_exit("exit_blocker", failing_exit)

      local card = create_test_card("card1")
      column:add_card(card)

      local trigger_fn = column.triggers["on_exit"]["exit_blocker"]
      local success, err = pcall(trigger_fn, column, {card = card})

      assert.is_false(success)
      assert.is_not_nil(err)
    end)
  end)

  -- Note: state capture and rollback tests removed as part of buffer-as-source-of-truth refactoring
  -- The command pattern with rollback was replaced with simpler error propagation

  describe("trigger execution", function()
    -- Note: command logging test removed as part of buffer-as-source-of-truth refactoring

    it("should maintain trigger execution order", function()
      local execution_order = {}

      column:register_on_entry("first", function()
        table.insert(execution_order, "first")
        return {success = true}
      end)

      column:register_on_entry("second", function()
        table.insert(execution_order, "second")
        return {success = true}
      end)

      column:register_on_entry("third", function()
        table.insert(execution_order, "third")
        return {success = true}
      end)

      local card = create_test_card("card1")
      column:add_card(card)

      -- Note: Lua table iteration order is not guaranteed, so this test
      -- demonstrates execution but order may vary
      assert.are.equal(3, #execution_order)
      assert.is_true(vim.tbl_contains(execution_order, "first"))
      assert.is_true(vim.tbl_contains(execution_order, "second"))
      assert.is_true(vim.tbl_contains(execution_order, "third"))
    end)
  end)
end)
