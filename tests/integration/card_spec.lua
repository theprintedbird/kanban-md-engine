require('polyfills.vim')
local Card = require('kanban-md.card')
local singletons = require('helpers.singletons')

describe("Card lifecycle", function()
  describe("card states", function()
    it("should start in Created state", function()
      local card = Card:new("test-1", "Test task")
      
      assert.are.equal("test-1", card.id)
      assert.are.equal("Test task", card.text)
      assert.is_nil(card.column) -- Not placed in any column yet
      assert.is_table(card.properties)
      assert.is_table(card.triggers)
      assert.is_table(card.triggers)
    end)
    
    it("should transition to InColumn when placed", function()
      local card = Card:new("test-2", "Test task 2")
      
      -- Simulate placing card in column
      card.column = "TODO"
      
      -- Verify card knows its column
      assert.are.equal("TODO", card.column)
      
      -- Test that we can register and execute column placement trigger
      local placement_triggered = false
      card:register_on_entry("column_placement", function(self, context)
        self.properties.placed_at = os.time()
        placement_triggered = true
        return true
      end)

      local results, errors = card:execute_triggers("on_entry", {card = card, column_name = "TODO"})
      assert.are.equals(0, #errors)
      assert.is_true(placement_triggered)
      assert.is_not_nil(card.properties.placed_at)
    end)
    
    it("should enter Moving state during transitions", function()
      local card = Card:new("test-3", "Test task 3")
      card.column = "TODO"
      
      -- Register a moving trigger that simulates state change
      local moving_state = false
      card:register_on_exit("start_move", function(self, context)
        moving_state = true
        self.properties.moving_from = context.from_column
        self.properties.moving_to = context.to_column
        self.properties.move_started = os.time()
        return true
      end)

      local results, errors = card:execute_triggers("on_exit", {card = card, from_column = "TODO", to_column = "IN_PROGRESS"})
      assert.are.equals(0, #errors)
      assert.is_true(moving_state)
      assert.are.equal("TODO", card.properties.moving_from)
      assert.are.equal("IN_PROGRESS", card.properties.moving_to)
    end)
    
    it("should enter Editing state on edit", function()
      local card = Card:new("test-4", "Original text")

      -- Register edit trigger
      local edit_count = 0
      card:register_trigger("on_edit", "track_edits", function(self, context)
        edit_count = edit_count + 1
        self.properties.edit_count = edit_count
        self.properties.last_edited = os.time()
        self.properties.previous_text = context.old_text
        return true
      end)

      -- Simulate edit
      local old_text = card.text
      card.text = "Updated text"
      local results, errors = card:execute_triggers("on_edit", {card = card, old_text = old_text, new_text = card.text})

      assert.are.equals(0, #errors)
      assert.are.equal(1, card.properties.edit_count)
      assert.are.equal("Original text", card.properties.previous_text)
      assert.is_not_nil(card.properties.last_edited)
    end)
    
    it("should transition to Archived state", function()
      local card = Card:new("test-5", "Task to archive")
      card.column = "DONE"

      -- Register archive trigger
      local archived = false
      card:register_on_entry("archive", function(self, context)
        archived = true
        self.properties.archived_at = os.time()
        self.properties.archived_from = self.column
        self.column = context.archive_column
        return true
      end)

      local results, errors = card:execute_triggers("on_entry", {card = card, archive_column = "__ARCHIVE__"})
      assert.are.equals(0, #errors)
      assert.is_true(archived)
      assert.are.equal("__ARCHIVE__", card.column)
      assert.are.equal("DONE", card.properties.archived_from)
      assert.is_not_nil(card.properties.archived_at)
    end)
    
    it("should handle Deleted state", function()
      local card = Card:new("test-6", "Task to delete")

      -- Register deletion trigger
      local deleted = false
      card:register_trigger("on_delete", "mark_deleted", function(self, context)
        deleted = true
        self.properties.deleted_at = os.time()
        self.properties.deleted = true
        return true
      end)

      local results, errors = card:execute_triggers("on_delete", {card = card})
      assert.are.equals(0, #errors)
      assert.is_true(deleted)
      assert.is_true(card.properties.deleted)
      assert.is_not_nil(card.properties.deleted_at)
    end)
  end)

  describe("state persistence", function()
    it("should maintain card state", function()
      local card = Card:new("test-7", "Test state")
      card.properties.complexity = 5
      card.column = "TODO"

      -- Verify state can be accessed
      assert.are.equal("test-7", card.id)
      assert.are.equal("Test state", card.text)
      assert.are.equal("TODO", card.column)
      assert.are.equal(5, card.properties.complexity)

      -- Verify deep copy works for properties
      local props_copy = vim.deepcopy(card.properties)
      props_copy.complexity = 10
      assert.are.equal(5, card.properties.complexity)
    end)

    it("should support property changes", function()
      local card = Card:new("test-8", "Property test")

      -- Change properties directly
      card.properties.priority = "high"
      assert.are.equal("high", card.properties.priority)

      card.properties.status = "in_progress"
      assert.are.equal("in_progress", card.properties.status)
    end)
  end)

  describe("column-agnostic behaviour", function()
		it("should get an ID on creation", function()
			-- Card is a module singleton, so this registration is visible to every
			-- spec that runs after it; snapshot the class triggers and put them
			-- back rather than leaving every later Card:new() with a time-based id.
			local restore_singletons = singletons.snapshot()

			local id_triggers = require('kanban-md.extras.id_triggers')
			local id_fn = id_triggers.time_based_id()
			Card:register_on_create("time_based_id", id_fn)

			local ok, err = pcall(function()
				local card = Card:new(nil, "ID-less card")
				assert.is_not_nil(card.id)
				assert.is_string(card.id)
			end)

			restore_singletons()
			assert.is_true(ok, tostring(err))
		end)
    it("should not have hardcoded column states", function()
      local card = Card:new("test-10", "Flexible card")

      -- Card should work with any column name
      local custom_columns = {"BACKLOG", "ANALYSIS", "DEVELOPMENT", "TESTING", "DEPLOYMENT", "LIVE"}

      for _, column_name in ipairs(custom_columns) do
        card.column = column_name
        assert.are.equal(column_name, card.column)

        -- Should be able to register triggers for any column type
        local trigger_name = "enter_" .. string.lower(column_name)
        card:register_on_entry(trigger_name, function(self, context)
          self.properties[string.lower(column_name) .. "_entered"] = os.time()
          return true
        end)

        local results, errors = card:execute_triggers("on_entry", {card = card})
        assert.are.equals(0, #errors)
        assert.is_not_nil(card.properties[string.lower(column_name) .. "_entered"])
      end
    end)
    
    it("should derive behaviour from column triggers", function()
      local card = Card:new("test-11", "Trigger-driven card")

      -- Set up different triggers for different column types
      local trigger_executions = {}

      -- Development column trigger
      local development_trigger = function(self, context)
        table.insert(trigger_executions, "development_entry")
        self.properties.assignee = "developer"
        self.properties.started_at = os.time()
        return true
      end

      -- Testing column trigger
      local testing_trigger = function(self, context)
        table.insert(trigger_executions, "testing_entry")
        self.properties.assignee = "tester"
        self.properties.needs_verification = true
        return true
      end

      -- Simulate entering development
      card.column = "DEVELOPMENT"
      local success1, result1 = pcall(development_trigger, card, {card = card})
      assert.is_true(success1)

      assert.are.equal("developer", card.properties.assignee)
      assert.is_not_nil(card.properties.started_at)

      -- Simulate entering testing
      card.column = "TESTING"
      local success2, result2 = pcall(testing_trigger, card, {card = card})
      assert.is_true(success2)

      assert.are.equal("tester", card.properties.assignee)
      assert.is_true(card.properties.needs_verification)

      -- Verify execution order
      assert.are.same({"development_entry", "testing_entry"}, trigger_executions)
    end)
    
    it("should update properties dynamically via triggers", function()
      local card = Card:new("test-12", "Dynamic properties test")

      -- Register triggers that modify properties based on context
      card:register_on_entry("dynamic_timestamp", function(self, context)
        local timestamp_key = string.lower(context.column_name) .. "_entered"
        self.properties[timestamp_key] = os.time()
        return true
      end)

      card:register_on_entry("dynamic_workflow", function(self, context)
        if context.column_name == "DONE" then
          self.properties.completed = true
          self.properties.completion_time = os.time()
        elseif context.column_name == "IN_PROGRESS" then
          self.properties.started = true
          self.properties.start_time = os.time()
        end
        return true
      end)

      -- Test dynamic property creation for IN_PROGRESS
      local results1, errors1 = card:execute_triggers("on_entry", {card = card, column_name = "IN_PROGRESS"})
      assert.are.equals(0, #errors1)

      assert.is_not_nil(card.properties.in_progress_entered)
      assert.is_true(card.properties.started)
      assert.is_not_nil(card.properties.start_time)

      -- Add a small delay to ensure different timestamps
      local function sleep(n)
        os.execute("sleep " .. tonumber(n))
      end
      sleep(0.1)

      -- Test dynamic property creation for DONE
      local results2, errors2 = card:execute_triggers("on_entry", {card = card, column_name = "DONE"})
      assert.are.equals(0, #errors2)
      
      assert.is_not_nil(card.properties.done_entered)
      assert.is_true(card.properties.completed)
      assert.is_not_nil(card.properties.completion_time)
      
      -- Verify different triggers can modify same card differently
      -- The card should have both IN_PROGRESS and DONE timestamps, showing it supports dynamic properties
      assert.is_true(card.properties.started) -- Set by IN_PROGRESS workflow
      assert.is_true(card.properties.completed) -- Set by DONE workflow
      assert.is_not_nil(card.properties.in_progress_entered) -- Set by dynamic timestamp
      assert.is_not_nil(card.properties.done_entered) -- Set by dynamic timestamp
    end)
  end)
end)
