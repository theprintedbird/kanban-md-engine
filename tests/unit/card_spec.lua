require('polyfills.vim')

local Card = require('kanban-md.card')
local TypeConverter = require('kanban-md.type_converter')

describe("Card:new initialization", function()
  describe("basic initialization", function()
    it("should create card with id and text", function()
      local card = Card:new("card-1", "Test task")

      assert.are.equal("card-1", card.id)
      assert.are.equal("Test task", card.text)
      assert.is_not_nil(card.properties)
      assert.is_nil(card.column)
    end)

    it("should create card with id only (text defaults to empty string)", function()
      local card = Card:new("card-2")

      assert.are.equal("card-2", card.id)
      assert.are.equal("", card.text)
      assert.is_not_nil(card.properties)
    end)

    it("should handle nil text explicitly", function()
      local card = Card:new("card-3", nil)

      assert.are.equal("card-3", card.id)
      assert.are.equal("", card.text)
    end)

    it("should handle empty string text", function()
      local card = Card:new("card-4", "")

      assert.are.equal("card-4", card.id)
      assert.are.equal("", card.text)
    end)
  end)

  describe("properties initialization", function()
    it("should create card with no properties (nil)", function()
      local card = Card:new("card-5", "Task without properties")

      assert.is_not_nil(card.properties)
      -- Properties should be a TypeConverter with no data
      assert.are.equal("table", type(card.properties))
    end)

    it("should create card with empty properties table", function()
      local card = Card:new("card-6", "Task with empty props", {})

      assert.is_not_nil(card.properties)
      assert.are.equal("table", type(card.properties))
    end)

    it("should create card with single property", function()
      local card = Card:new("card-7", "Task with complexity", {
        complexity = 5
      })

      assert.are.equal(5, card.properties.complexity)
    end)

    it("should create card with multiple numeric properties", function()
      local card = Card:new("card-8", "Task with timestamps", {
        created = 1000000,
        started = 1000100,
        complexity = 3
      })

      assert.are.equal(1000000, card.properties.created)
      assert.are.equal(1000100, card.properties.started)
      assert.are.equal(3, card.properties.complexity)
    end)

    it("should create card with boolean properties", function()
      local card = Card:new("card-9", "Task with booleans", {
        completed = true,
        blocked = false
      })

      assert.is_true(card.properties.completed)
      assert.is_false(card.properties.blocked)
    end)

    it("should create card with string properties", function()
      local card = Card:new("card-10", "Task with assignee", {
        assignee = "alice",
        status = "in_progress"
      })

      assert.are.equal("alice", card.properties.assignee)
      assert.are.equal("in_progress", card.properties.status)
    end)

    it("should create card with array properties", function()
      local card = Card:new("card-11", "Task with arrays", {
        tags = {"urgent", "backend"},
        subtasks = {"subtask-1", "subtask-2"}
      })

      assert.are.same({"urgent", "backend"}, card.properties.tags)
      assert.are.same({"subtask-1", "subtask-2"}, card.properties.subtasks)
    end)

    it("should create card with mixed property types", function()
      local card = Card:new("card-12", "Complex task", {
        complexity = 8,
        assignee = "bob",
        completed = false,
        tags = {"feature", "priority"},
        created = os.time(),
        dependencies = {"dep-1"}
      })

      assert.are.equal(8, card.properties.complexity)
      assert.are.equal("bob", card.properties.assignee)
      assert.is_false(card.properties.completed)
      assert.are.same({"feature", "priority"}, card.properties.tags)
      assert.is_number(card.properties.created)
      assert.are.same({"dep-1"}, card.properties.dependencies)
    end)
  end)

  describe("TypeConverter handling", function()
    it("should accept properties as TypeConverter object", function()
      local props = TypeConverter:new({
        complexity = 5,
        assignee = "charlie"
      })

      local card = Card:new("card-13", "Task with TypeConverter", props)

      assert.are.equal(5, card.properties.complexity)
      assert.are.equal("charlie", card.properties.assignee)
    end)

    it("should not double-wrap TypeConverter", function()
      local props = TypeConverter:new({
        test_prop = "value"
      })

      local card = Card:new("card-14", "TypeConverter test", props)

      -- Verify it's still a TypeConverter and not double-wrapped
      assert.are.equal("value", card.properties.test_prop)
      assert.is_function(card.properties.to_table)
    end)

    it("should convert plain table to TypeConverter", function()
      local card = Card:new("card-15", "Plain table test", {
        wip_limit = "5"  -- String that should convert to number
      })

      -- TypeConverter should convert wip_limit string to number
      assert.are.equal(5, card.properties.wip_limit)
    end)
  end)

  describe("edge cases", function()
    it("should handle properties with nil values", function()
      local card = Card:new("card-16", "Task with nil prop", {
        assignee = nil,
        complexity = 3
      })

      assert.is_nil(card.properties.assignee)
      assert.are.equal(3, card.properties.complexity)
    end)

    it("should handle special characters in text", function()
      local card = Card:new("card-17", "Task with special chars: @#$%^&*()")

      assert.are.equal("Task with special chars: @#$%^&*()", card.text)
    end)

    it("should handle unicode in text and properties", function()
      local card = Card:new("card-18", "Task with emoji 🚀", {
        assignee = "José"
      })

      assert.are.equal("Task with emoji 🚀", card.text)
      assert.are.equal("José", card.properties.assignee)
    end)

    it("should handle very long id", function()
      local long_id = string.rep("a", 1000)
      local card = Card:new(long_id, "Test task")

      assert.are.equal(long_id, card.id)
    end)

    it("should handle property with zero value", function()
      local card = Card:new("card-19", "Task with zero", {
        complexity = 0,
        started = 0
      })

      assert.are.equal(0, card.properties.complexity)
      assert.are.equal(0, card.properties.started)
    end)

    it("should handle negative numbers", function()
      local card = Card:new("card-20", "Task with negative", {
        position = -1
      })

      assert.are.equal(-1, card.properties.position)
    end)

    it("should handle floating point numbers", function()
      local card = Card:new("card-21", "Task with float", {
        actual_time = 3.5
      })

      assert.are.equal(3.5, card.properties.actual_time)
    end)
  end)

  describe("timestamp properties", function()
    it("should handle created timestamp", function()
      local now = os.time()
      local card = Card:new("card-22", "Task with created", {
        created = now
      })

      assert.are.equal(now, card.properties.created)
    end)

    it("should handle all timestamp properties", function()
      local t1, t2, t3, t4, t5 = 1000, 2000, 3000, 4000, 5000
      local card = Card:new("card-23", "Task with all timestamps", {
        created = t1,
        ready = t2,
        started = t3,
        done = t4,
        archived = t5
      })

      assert.are.equal(t1, card.properties.created)
      assert.are.equal(t2, card.properties.ready)
      assert.are.equal(t3, card.properties.started)
      assert.are.equal(t4, card.properties.done)
      assert.are.equal(t5, card.properties.archived)
    end)
  end)

  describe("work metrics properties", function()
    it("should handle complexity and time properties", function()
      local card = Card:new("card-24", "Task with metrics", {
        complexity = 13,
        actual_time = 120,
        blocked_time = 30
      })

      assert.are.equal(13, card.properties.complexity)
      assert.are.equal(120, card.properties.actual_time)
      assert.are.equal(30, card.properties.blocked_time)
    end)
  end)

  describe("relationship properties", function()
    it("should handle parent, dependencies, and subtasks", function()
      local card = Card:new("card-25", "Task with relationships", {
        parent = "parent-1",
        dependencies = {"dep-1", "dep-2"},
        subtasks = {"sub-1", "sub-2", "sub-3"}
      })

      assert.are.equal("parent-1", card.properties.parent)
      assert.are.same({"dep-1", "dep-2"}, card.properties.dependencies)
      assert.are.same({"sub-1", "sub-2", "sub-3"}, card.properties.subtasks)
    end)

    it("should handle blocker property", function()
      local card = Card:new("card-26", "Blocked task", {
        blocker = "Waiting for approval"
      })

      assert.are.equal("Waiting for approval", card.properties.blocker)
    end)
  end)
end)
