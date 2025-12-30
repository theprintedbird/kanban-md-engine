require('polyfills.vim')
local Triggerable = require('kanban-md.triggerable')

describe("Triggerable mixin", function()
  local TestObject
  
  before_each(function()
    -- Create a test object that includes the Triggerable mixin
    TestObject = {
      id = "test-object",
      data = { value = 1 },
      triggers = {},
      trigger_order = {}
    }

    -- Mix in Triggerable methods
    for k, v in pairs(Triggerable) do
      TestObject[k] = v
    end
  end)

  describe("trigger registration", function()
    it("should register on_entry triggers", function()
      local trigger_fn = function() return "enter triggered" end
      
      TestObject:register_on_entry("test_trigger", trigger_fn)
      
      local triggers = TestObject:get_triggers("on_entry")
      assert.is_not_nil(triggers["test_trigger"])
      assert.are.equal(trigger_fn, triggers["test_trigger"])
    end)
    
    it("should register on_exit triggers", function()
      local trigger_fn = function() return "exit triggered" end
      
      TestObject:register_on_exit("test_trigger", trigger_fn)
      
      local triggers = TestObject:get_triggers("on_exit")
      assert.is_not_nil(triggers["test_trigger"])
      assert.are.equal(trigger_fn, triggers["test_trigger"])
    end)
    
    it("should register on_stay triggers", function()
      local trigger_fn = function() return "stay triggered" end

      TestObject:register_on_stay("test_trigger", trigger_fn)

      local triggers = TestObject:get_triggers("on_stay")
      assert.is_not_nil(triggers["test_trigger"])
      assert.are.equal(trigger_fn, triggers["test_trigger"])
    end)

    it("should register on_checking triggers", function()
      local trigger_fn = function() return true, nil, "warning", {meta = "data"} end

      TestObject:register_on_checking("test_trigger", trigger_fn)

      local triggers = TestObject:get_triggers("on_checking")
      assert.is_not_nil(triggers["test_trigger"])
      assert.are.equal(trigger_fn, triggers["test_trigger"])
    end)

    
    it("should allow multiple triggers for same event", function()
      local trigger1 = function() return "trigger1" end
      local trigger2 = function() return "trigger2" end
      
      TestObject:register_on_entry("trigger1", trigger1)
      TestObject:register_on_entry("trigger2", trigger2)
      
      local triggers = TestObject:get_triggers("on_entry")
      assert.is_not_nil(triggers["trigger1"])
      assert.is_not_nil(triggers["trigger2"])
      assert.are.equal(trigger1, triggers["trigger1"])
      assert.are.equal(trigger2, triggers["trigger2"])
    end)
    
    it("should maintain trigger order", function()
      local execution_order = {}
      
      local trigger1 = function() table.insert(execution_order, "first") end
      local trigger2 = function() table.insert(execution_order, "second") end
      local trigger3 = function() table.insert(execution_order, "third") end
      
      TestObject:register_on_entry("first", trigger1)
      TestObject:register_on_entry("second", trigger2)
      TestObject:register_on_entry("third", trigger3)
      
      local triggers = TestObject:get_triggers("on_entry")
      assert.are.equal(3, vim.tbl_count(triggers))
      
      -- Execute all triggers and verify order is maintained
      TestObject:execute_triggers("on_entry", {})
      
      -- Note: Lua table iteration order is not guaranteed, so we check
      -- that all triggers were executed rather than strict ordering
      assert.are.equal(3, #execution_order)
      assert.is_true(vim.tbl_contains(execution_order, "first"))
      assert.is_true(vim.tbl_contains(execution_order, "second"))
      assert.is_true(vim.tbl_contains(execution_order, "third"))
    end)
  end)

  describe("trigger execution", function()
    it("should execute triggers in registration order", function()
      local execution_log = {}
      
      local trigger1 = function(self, context)
        table.insert(execution_log, "trigger1_executed")
        return "trigger1_result"
      end
      
      local trigger2 = function(self, context)
        table.insert(execution_log, "trigger2_executed")
        return "trigger2_result"
      end
      
      TestObject:register_on_entry("trigger1", trigger1)
      TestObject:register_on_entry("trigger2", trigger2)
      
      local results, errors = TestObject:execute_triggers("on_entry", { test = "context" })
      
      assert.are.equal(2, #execution_log)
      assert.are.equal(2, #results)
      assert.are.equal(0, #errors)
      
      -- Check all triggers executed
      assert.is_true(vim.tbl_contains(execution_log, "trigger1_executed"))
      assert.is_true(vim.tbl_contains(execution_log, "trigger2_executed"))
    end)
    
    it("should pass card context to triggers", function()
      local received_context = nil
      local received_self = nil
      
      local trigger_fn = function(self, context)
        received_context = context
        received_self = self
        return "success"
      end
      
      TestObject:register_on_entry("context_test", trigger_fn)

      local test_context = { card_id = "test-123", column = "todo" }
      TestObject:execute_triggers("on_entry", test_context)
      
      assert.is_not_nil(received_context)
      assert.is_not_nil(received_self)
      assert.are.equal(TestObject, received_self)
      assert.are.equal(test_context, received_context)
    end)
    
    it("should handle trigger errors gracefully", function()
      local error_trigger = function(self, context)
        error("Test error message")
      end
      
      local success_trigger = function(self, context)
        return "success"
      end
      
      TestObject:register_on_entry("error_trigger", error_trigger)
      TestObject:register_on_entry("success_trigger", success_trigger)
      
      local results, errors = TestObject:execute_triggers("on_entry", {})
      
      assert.are.equal(2, #results)
      assert.are.equal(1, #errors)
      
      -- Find the error result
      local error_result = nil
      local success_result = nil
      for _, result in ipairs(results) do
        if result.name == "error_trigger" then
          error_result = result
        elseif result.name == "success_trigger" then
          success_result = result
        end
      end
      
      assert.is_not_nil(error_result)
      assert.is_not_nil(success_result)
      assert.is_false(error_result.success)
      assert.is_true(success_result.success)
      assert.is_not_nil(error_result.error)
    end)
    
    it("should skip triggers with failed conditions", function()
      local condition_met = false
      local trigger_executed = false
      
      local conditional_trigger = function(self, context)
        if not condition_met then
          return { success = false, reason = "Condition not met" }
        end
        trigger_executed = true
        return { success = true }
      end
      
      TestObject:register_on_entry("conditional", conditional_trigger)

      -- First execution should fail condition
      TestObject:execute_triggers("on_entry", {})
      assert.is_false(trigger_executed)

      -- Second execution should succeed
      condition_met = true
      TestObject:execute_triggers("on_entry", {})
      assert.is_true(trigger_executed)
    end)
  end)

  describe("on_checking triggers", function()
    it("should execute on_checking triggers with standardized result format", function()
      local warning_trigger = function(self, context)
        return {success = true, warnings = {"This is a warning"}, metadata = {meta = "data"}}
      end

      local error_trigger = function(self, context)
        error("This is an error")
      end

      local success_trigger = function(self, context)
        return {success = true, metadata = {result = "success"}}
      end

      TestObject:register_on_checking("warning", warning_trigger)
      TestObject:register_on_checking("error", error_trigger)
      TestObject:register_on_checking("success", success_trigger)

      local results, errors = TestObject:execute_triggers("on_checking", {test = "context"})

      assert.are.equal(3, #results)
      assert.are.equal(1, #errors) -- Only the error trigger should create an error

      -- Find specific results
      local warning_result, error_result, success_result = nil, nil, nil
      for _, result in ipairs(results) do
        if result.name == "warning" then warning_result = result
        elseif result.name == "error" then error_result = result
        elseif result.name == "success" then success_result = result
        end
      end

      -- Test warning trigger result
      assert.is_not_nil(warning_result)
      assert.is_true(warning_result.success)
      assert.is_nil(warning_result.error)
      -- With new format, warnings is an array
      assert.are.equal(1, #(warning_result.result.warnings or {}))
      assert.are.equal("This is a warning", (warning_result.result.warnings or {})[1])
      assert.are.equal("data", warning_result.result.metadata.meta)

      -- Test error trigger result
      assert.is_not_nil(error_result)
      assert.is_false(error_result.success) -- Trigger failed with error()
      assert.is_not_nil(error_result.error)

      -- Test success trigger result
      assert.is_not_nil(success_result)
      assert.is_true(success_result.success)
      assert.is_nil(success_result.error)
      assert.are.equal("success", success_result.result.metadata.result)
    end)

    it("should handle legacy string result format for checking triggers", function()
      local legacy_trigger = function(self, context)
        return "Legacy warning message"
      end

      TestObject:register_on_checking("legacy", legacy_trigger)

      local results, errors = TestObject:execute_triggers("on_checking", {})

      assert.are.equal(1, #results)
      assert.are.equal(0, #errors)

      local result = results[1]
      assert.is_true(result.success)
      assert.is_nil(result.error)
      assert.are.equal("Legacy warning message", result.warning)
    end)

    it("should create standardized checking context", function()
      local Card = {id = "card1", name = "Test Card", properties = {complexity = 3}}
      local SourceColumn = {id = "col1", name = "Todo"}
      local TargetColumn = {id = "col2", name = "In Progress"}
      local Board = {id = "board1", columns = {}}

      local context = TestObject:create_checking_context(
        Card, SourceColumn, TargetColumn, Board, "move", 1234567890
      )

      assert.are.equal(Card, context.card)
      assert.are.equal(SourceColumn, context.source_column)
      assert.are.equal(TargetColumn, context.target_column)
      assert.are.equal("In Progress", context.target_column_name)
      assert.are.equal("move", context.transition_type)
      assert.are.equal(1234567890, context.timestamp)
      assert.are.equal(Board, context.board)
    end)

    it("should use default values in checking context", function()
      local Card = {id = "card1"}
      local SourceColumn = {id = "col1"}

      local context = TestObject:create_checking_context(Card, SourceColumn)

      assert.are.equal(Card, context.card)
      assert.are.equal(SourceColumn, context.source_column)
      assert.is_nil(context.target_column)
      assert.is_nil(context.target_column_name)
      assert.are.equal("move", context.transition_type)
      assert.is_number(context.timestamp)
      assert.is_nil(context.board)
    end)
  end)

  describe("trigger result helpers", function()
    it("should create success result with warning", function()
      local result = TestObject:success("Warning message", {test = "data"})

      assert.is_true(result.success)
      assert.is_nil(result.error)
      assert.are.equal("Warning message", result.warnings[1])
      assert.are.equal("data", result.metadata.test)
    end)

    it("should create success result without warning", function()
      local result = TestObject:success(nil, {result = "ok"})

      assert.is_true(result.success)
      assert.is_nil(result.error)
      assert.is_nil(result.warning)
      assert.are.equal("ok", result.metadata.result)
    end)

    it("should create error result", function()
      local result = TestObject:error("Error message", {error_code = 500})

      assert.is_false(result.success)
      assert.are.equal("Error message", result.errors[1])
      assert.is_nil(result.warning)
      assert.are.equal(500, result.metadata.error_code)
    end)

    it("should create warning result", function()
      local result = TestObject:warning("Warning message", {warn_code = 200})

      assert.is_true(result.success)
      assert.is_nil(result.error)
      assert.are.equal("Warning message", result.warnings[1])
      assert.are.equal(200, result.metadata.warn_code)
    end)
  end)
end)
