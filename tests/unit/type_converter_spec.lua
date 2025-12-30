require('polyfills.vim')
local TypeConverter = require('kanban-md.type_converter')

describe("TypeConverter", function()
  describe("creation", function()
    it("should create empty converter with no arguments", function()
      local tc = TypeConverter:new()
      assert.is_not_nil(tc)
      assert.are.equal(0, #tc:keys())
    end)

    it("should create converter with initial data", function()
      local tc = TypeConverter:new({ name = "test", value = 42 })
      assert.are.equal("test", tc.name)
      assert.are.equal(42, tc.value)
    end)

    it("should have separate _raw and _converted tables", function()
      local tc = TypeConverter:new({ foo = "bar" })
      assert.is_not_nil(tc._raw)
      assert.is_not_nil(tc._converted)
      assert.are.equal("bar", tc._raw.foo)
    end)
  end)

  describe("numeric property conversion", function()
    it("should convert string to number for wip_limit", function()
      local tc = TypeConverter:new({ wip_limit = "5" })
      assert.are.equal(5, tc.wip_limit)
      assert.are.equal("number", type(tc.wip_limit))
    end)

    it("should convert string to number for complexity", function()
      local tc = TypeConverter:new({ complexity = "3" })
      assert.are.equal(3, tc.complexity)
    end)

    it("should convert string to number for timestamp properties", function()
      local tc = TypeConverter:new({
        created = "1234567890",
        started = "1234567891",
        done = "1234567892",
        archived = "1234567893"
      })
      assert.are.equal(1234567890, tc.created)
      assert.are.equal(1234567891, tc.started)
      assert.are.equal(1234567892, tc.done)
      assert.are.equal(1234567893, tc.archived)
    end)

    it("should keep number as number for numeric properties", function()
      local tc = TypeConverter:new({ wip_limit = 10 })
      assert.are.equal(10, tc.wip_limit)
    end)

    it("should handle conversion failure gracefully", function()
      local tc = TypeConverter:new({ wip_limit = "not_a_number" })
      -- Should return original value and log warning
      assert.are.equal("not_a_number", tc.wip_limit)
    end)

    it("should convert position to number", function()
      local tc = TypeConverter:new({ position = "2" })
      assert.are.equal(2, tc.position)
    end)

    it("should convert actual_time and blocked_time", function()
      local tc = TypeConverter:new({
        actual_time = "120",
        blocked_time = "30"
      })
      assert.are.equal(120, tc.actual_time)
      assert.are.equal(30, tc.blocked_time)
    end)
  end)

  describe("boolean property conversion", function()
    it("should convert string 'true' to boolean true", function()
      local tc = TypeConverter:new({ blocked = "true" })
      assert.is_true(tc.blocked)
      assert.are.equal("boolean", type(tc.blocked))
    end)

    it("should convert string 'false' to boolean false", function()
      local tc = TypeConverter:new({ urgent = "false" })
      assert.is_false(tc.urgent)
    end)

    it("should be case-insensitive for boolean conversion", function()
      local tc = TypeConverter:new({
        blocked = "TRUE",
        urgent = "False",
        reviewed = "TrUe"
      })
      assert.is_true(tc.blocked)
      assert.is_false(tc.urgent)
      assert.is_true(tc.reviewed)
    end)

    it("should keep boolean as boolean", function()
      local tc = TypeConverter:new({ blocked = true, urgent = false })
      assert.is_true(tc.blocked)
      assert.is_false(tc.urgent)
    end)

    it("should convert all boolean properties", function()
      local tc = TypeConverter:new({
        blocked = "true",
        urgent = "false",
        reviewed = "true",
        auto = "false",
        revalidated = "true",
        changes_requested = "false"
      })
      assert.is_true(tc.blocked)
      assert.is_false(tc.urgent)
      assert.is_true(tc.reviewed)
      assert.is_false(tc.auto)
      assert.is_true(tc.revalidated)
      assert.is_false(tc.changes_requested)
    end)

    it("should return original value for non-boolean strings", function()
      local tc = TypeConverter:new({ blocked = "maybe" })
      assert.are.equal("maybe", tc.blocked)
    end)
  end)

  describe("array property conversion", function()
    it("should parse comma-separated string to array for tags", function()
      local tc = TypeConverter:new({ tags = "bug,urgent,backend" })
      assert.are.same({"bug", "urgent", "backend"}, tc.tags)
    end)

    it("should trim whitespace from array elements", function()
      local tc = TypeConverter:new({ tags = "bug, urgent  , backend" })
      assert.are.same({"bug", "urgent", "backend"}, tc.tags)
    end)

    it("should keep existing arrays as arrays", function()
      local tc = TypeConverter:new({ tags = {"already", "an", "array"} })
      assert.are.same({"already", "an", "array"}, tc.tags)
    end)

    it("should convert all array properties", function()
      -- Register optional array properties for testing
      TypeConverter.register_array_property("depends_on")
      TypeConverter.register_array_property("subtasks")

      local tc = TypeConverter:new({
        tags = "tag1,tag2",
        depends_on = "card-1, card-2",
        subtasks = "sub-1,sub-2,sub-3",
        authorized_approvers = "alice,bob"
      })
      assert.are.same({"tag1", "tag2"}, tc.tags)
      assert.are.same({"card-1", "card-2"}, tc.depends_on)
      assert.are.same({"sub-1", "sub-2", "sub-3"}, tc.subtasks)
      assert.are.same({"alice", "bob"}, tc.authorized_approvers)
    end)

    it("should handle single element arrays", function()
      local tc = TypeConverter:new({ tags = "single" })
      assert.are.same({"single"}, tc.tags)
    end)

    it("should handle empty string for arrays", function()
      local tc = TypeConverter:new({ tags = "" })
      -- Empty string should result in empty array
      assert.are.same({},  tc.tags)
    end)
  end)

  describe("non-special properties", function()
    it("should pass through string properties unchanged", function()
      local tc = TypeConverter:new({
        name = "Task name",
        assignee = "john",
        status = "in_progress"
      })
      assert.are.equal("Task name", tc.name)
      assert.are.equal("john", tc.assignee)
      assert.are.equal("in_progress", tc.status)
    end)

    it("should pass through number properties for non-numeric keys", function()
      local tc = TypeConverter:new({ custom_number = 42 })
      assert.are.equal(42, tc.custom_number)
    end)

    it("should pass through table properties for non-array keys", function()
      local tc = TypeConverter:new({ custom_table = { a = 1, b = 2 } })
      assert.are.same({ a = 1, b = 2 }, tc.custom_table)
    end)
  end)

  describe("__newindex (setter)", function()
    it("should allow setting new values", function()
      local tc = TypeConverter:new()
      tc.wip_limit = "7"
      assert.are.equal(7, tc.wip_limit)
    end)

    it("should store raw value and clear cache", function()
      local tc = TypeConverter:new({ wip_limit = "5" })
      -- Access to populate cache
      local _ = tc.wip_limit
      assert.are.equal(5, tc._converted.wip_limit)

      -- Set new value
      tc.wip_limit = "10"
      assert.are.equal("10", tc._raw.wip_limit)
      assert.is_nil(tc._converted.wip_limit)

      -- Access again to convert
      assert.are.equal(10, tc.wip_limit)
    end)

    it("should allow updating existing values", function()
      local tc = TypeConverter:new({ name = "old" })
      tc.name = "new"
      assert.are.equal("new", tc.name)
    end)
  end)

  describe("caching behavior", function()
    it("should cache converted values", function()
      local tc = TypeConverter:new({ wip_limit = "5" })

      -- First access - converts and caches
      local val1 = tc.wip_limit
      assert.are.equal(5, tc._converted.wip_limit)

      -- Second access - uses cache
      local val2 = tc.wip_limit
      assert.are.equal(val1, val2)
    end)

    it("should clear cache on value update", function()
      local tc = TypeConverter:new({ wip_limit = "5" })
      local _ = tc.wip_limit -- Populate cache

      tc.wip_limit = "10" -- Should clear cache
      assert.is_nil(tc._converted.wip_limit)
    end)
  end)

  describe("to_table()", function()
    it("should convert all properties to plain table", function()
      local tc = TypeConverter:new({
        wip_limit = "5",
        blocked = "true",
        tags = "bug,urgent",
        name = "test"
      })

      local result = tc:to_table()
      assert.are.equal(5, result.wip_limit)
      assert.is_true(result.blocked)
      assert.are.same({"bug", "urgent"}, result.tags)
      assert.are.equal("test", result.name)
    end)

    it("should return empty table for empty converter", function()
      local tc = TypeConverter:new()
      local result = tc:to_table()
      assert.are.same({}, result)
    end)

    it("should not include internal tables", function()
      local tc = TypeConverter:new({ foo = "bar" })
      local result = tc:to_table()
      assert.is_nil(result._raw)
      assert.is_nil(result._converted)
    end)

    it("should create a new table (not reference)", function()
      local tc = TypeConverter:new({ name = "test" })
      local result1 = tc:to_table()
      local result2 = tc:to_table()
      assert.are_not.equal(result1, result2) -- Different table instances
      assert.are.same(result1, result2) -- But same content
    end)
  end)

  describe("has()", function()
    it("should return true for existing keys", function()
      local tc = TypeConverter:new({ name = "test" })
      assert.is_true(tc:has("name"))
    end)

    it("should return false for non-existing keys", function()
      local tc = TypeConverter:new({ name = "test" })
      assert.is_false(tc:has("other"))
    end)

    it("should return true even if value is nil", function()
      local tc = TypeConverter:new({ name = nil })
      -- This should return false because nil values aren't stored
      assert.is_false(tc:has("name"))
    end)

    it("should return true for false boolean values", function()
      local tc = TypeConverter:new({ blocked = false })
      assert.is_true(tc:has("blocked"))
    end)
  end)

  describe("get_raw()", function()
    it("should return raw value without conversion", function()
      local tc = TypeConverter:new({ wip_limit = "5" })
      assert.are.equal("5", tc:get_raw("wip_limit"))
      assert.are.equal("string", type(tc:get_raw("wip_limit")))
    end)

    it("should return nil for non-existing keys", function()
      local tc = TypeConverter:new()
      assert.is_nil(tc:get_raw("nonexistent"))
    end)
  end)

  describe("keys()", function()
    it("should return all keys", function()
      local tc = TypeConverter:new({ a = 1, b = 2, c = 3 })
      local keys = tc:keys()
      table.sort(keys) -- Sort for consistent comparison
      assert.are.same({"a", "b", "c"}, keys)
    end)

    it("should return empty table for empty converter", function()
      local tc = TypeConverter:new()
      assert.are.same({}, tc:keys())
    end)

    it("should not include internal keys", function()
      local tc = TypeConverter:new({ foo = "bar" })
      local keys = tc:keys()
      assert.is_false(vim.tbl_contains(keys, "_raw"))
      assert.is_false(vim.tbl_contains(keys, "_converted"))
    end)
  end)

  describe("merge()", function()
    it("should merge plain table into converter", function()
      local tc = TypeConverter:new({ a = 1 })
      tc:merge({ b = 2, c = 3 })
      assert.are.equal(1, tc.a)
      assert.are.equal(2, tc.b)
      assert.are.equal(3, tc.c)
    end)

    it("should override existing values", function()
      local tc = TypeConverter:new({ a = 1, b = 2 })
      tc:merge({ b = 99, c = 3 })
      assert.are.equal(1, tc.a)
      assert.are.equal(99, tc.b)
      assert.are.equal(3, tc.c)
    end)

    it("should handle merging with type conversion", function()
      local tc = TypeConverter:new()
      tc:merge({ wip_limit = "5", blocked = "true" })
      assert.are.equal(5, tc.wip_limit)
      assert.is_true(tc.blocked)
    end)

    it("should handle nil argument gracefully", function()
      local tc = TypeConverter:new({ a = 1 })
      tc:merge(nil)
      assert.are.equal(1, tc.a)
    end)

    it("should handle merging with another TypeConverter", function()
      local tc1 = TypeConverter:new({ a = 1 })
      local tc2 = TypeConverter:new({ b = 2 })
      -- This should iterate over tc2 and set values via __newindex
      tc1:merge(tc2._raw)
      assert.are.equal(1, tc1.a)
      assert.are.equal(2, tc1.b)
    end)
  end)

  describe("nil value handling", function()
    it("should return nil for non-existing properties", function()
      local tc = TypeConverter:new()
      assert.is_nil(tc.nonexistent)
    end)

    it("should handle setting nil values", function()
      local tc = TypeConverter:new({ a = 1 })
      tc.a = nil
      assert.is_nil(tc:get_raw("a"))
    end)

    it("should not cache nil values", function()
      local tc = TypeConverter:new()
      local val = tc.nonexistent
      assert.is_nil(val)
      -- Check that nil is cached
      assert.is_nil(tc._converted.nonexistent)
    end)
  end)

  describe("edge cases", function()
    it("should handle empty strings", function()
      local tc = TypeConverter:new({ name = "" })
      assert.are.equal("", tc.name)
    end)

    it("should handle zero values", function()
      local tc = TypeConverter:new({ wip_limit = 0, blocked = false })
      assert.are.equal(0, tc.wip_limit)
      assert.is_false(tc.blocked)
    end)

    it("should handle special characters in string values", function()
      local tc = TypeConverter:new({ name = "test@#$%^&*()" })
      assert.are.equal("test@#$%^&*()", tc.name)
    end)

    it("should handle unicode characters", function()
      local tc = TypeConverter:new({ name = "テスト" })
      assert.are.equal("テスト", tc.name)
    end)

    it("should handle very long strings", function()
      local long_string = string.rep("a", 10000)
      local tc = TypeConverter:new({ name = long_string })
      assert.are.equal(long_string, tc.name)
    end)

    it("should handle negative numbers", function()
      local tc = TypeConverter:new({ wip_limit = "-5" })
      assert.are.equal(-5, tc.wip_limit)
    end)

    it("should handle floating point numbers", function()
      local tc = TypeConverter:new({ wip_limit = "3.14" })
      assert.are.equal(3.14, tc.wip_limit)
    end)
  end)

  describe("method access", function()
    it("should access methods correctly without infinite recursion", function()
      local tc = TypeConverter:new({ name = "test" })
      -- These should not cause stack overflow
      assert.is_function(tc.to_table)
      assert.is_function(tc.has)
      assert.is_function(tc.keys)
      assert.is_function(tc.merge)
      assert.is_function(tc.get_raw)
    end)

    it("should prioritize methods over properties", function()
      local tc = TypeConverter:new({ to_table = "not_a_function" })
      -- Accessing to_table should return the method, not the raw value
      assert.is_function(tc.to_table)
    end)
  end)

  describe("complex scenarios", function()
    it("should handle mixed property types", function()
      local tc = TypeConverter:new({
        wip_limit = "10",
        blocked = "true",
        tags = "bug,urgent",
        name = "Complex Task",
        complexity = "5",
        custom_field = "custom_value"
      })

      assert.are.equal(10, tc.wip_limit)
      assert.is_true(tc.blocked)
      assert.are.same({"bug", "urgent"}, tc.tags)
      assert.are.equal("Complex Task", tc.name)
      assert.are.equal(5, tc.complexity)
      assert.are.equal("custom_value", tc.custom_field)
    end)

    it("should handle conversion after multiple updates", function()
      local tc = TypeConverter:new()

      tc.wip_limit = "5"
      assert.are.equal(5, tc.wip_limit)

      tc.wip_limit = "10"
      assert.are.equal(10, tc.wip_limit)

      tc.wip_limit = 15
      assert.are.equal(15, tc.wip_limit)
    end)

    it("should work correctly with vim.deepcopy", function()
      local tc = TypeConverter:new({ wip_limit = "5", tags = "a,b" })
      local copy = vim.deepcopy(tc)

      -- Verify the copy has the same RAW data (not converted)
      -- Note: deepcopy doesn't preserve metatables, so copy is just a plain table
      assert.are.equal("5", copy._raw.wip_limit)
      assert.are.equal("a,b", copy._raw.tags) -- Raw value, not converted
    end)

    it("should handle creating TypeConverter from to_table() output", function()
      local tc1 = TypeConverter:new({ wip_limit = "5", blocked = "true" })
      local plain_table = tc1:to_table()
      local tc2 = TypeConverter:new(plain_table)

      -- tc2 should have converted values as raw input
      assert.are.equal(5, tc2.wip_limit)
      assert.is_true(tc2.blocked)
    end)
  end)
end)
