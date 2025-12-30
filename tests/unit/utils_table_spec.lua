require('polyfills.vim')
local table_utils = require('kanban-md.utils.table')

describe("table_utils", function()
	describe("isEmpty", function()
		it("should return true for empty table", function()
			local result = table_utils.isEmpty({})
			assert.is_true(result)
		end)

		it("should return false for table with elements", function()
			local result = table_utils.isEmpty({1, 2, 3})
			assert.is_false(result)
		end)

		it("should return false for table with named keys", function()
			local result = table_utils.isEmpty({foo = "bar"})
			assert.is_false(result)
		end)

		it("should return non-table values as-is", function()
			local result = table_utils.isEmpty("string")
			assert.are.equals("string", result)
		end)

		it("should return numbers as-is", function()
			local result = table_utils.isEmpty(42)
			assert.are.equals(42, result)
		end)

		it("should return nil as-is", function()
			local result = table_utils.isEmpty(nil)
			assert.is_nil(result)
		end)
	end)

	describe("keys", function()
		it("should return keys from simple table", function()
			local tbl = {foo = "bar", baz = "qux"}
			local result = table_utils.keys(tbl)
			table.sort(result)  -- Sort for consistent comparison
			assert.are.same({"baz", "foo"}, result)
		end)

		it("should return numeric indices as keys", function()
			local tbl = {"a", "b", "c"}
			local result = table_utils.keys(tbl)
			table.sort(result)
			assert.are.same({1, 2, 3}, result)
		end)

		it("should return empty array for empty table", function()
			local result = table_utils.keys({})
			assert.are.same({}, result)
		end)

		it("should return keys from mixed table", function()
			local tbl = {[1] = "first", foo = "bar", [3] = "third"}
			local result = table_utils.keys(tbl)
			table.sort(result, function(a, b)
				if type(a) == type(b) then return a < b end
				return type(a) < type(b)
			end)
			assert.are.equals(3, #result)
		end)
	end)

	describe("deepcopy", function()
		it("should copy simple table", function()
			local original = {a = 1, b = 2, c = 3}
			local copy = table_utils.deepcopy(original)
			assert.are.same(original, copy)
			assert.are_not.equal(original, copy)  -- Different references
		end)

		it("should copy nested tables", function()
			local original = {
				a = 1,
				b = {
					c = 2,
					d = {
						e = 3
					}
				}
			}
			local copy = table_utils.deepcopy(original)
			assert.are.same(original, copy)
			assert.are_not.equal(original, copy)
			assert.are_not.equal(original.b, copy.b)
			assert.are_not.equal(original.b.d, copy.b.d)
		end)

		it("should not affect original when modifying copy", function()
			local original = {a = {b = 1}}
			local copy = table_utils.deepcopy(original)
			copy.a.b = 999
			assert.are.equals(1, original.a.b)
			assert.are.equals(999, copy.a.b)
		end)

		it("should handle arrays", function()
			local original = {1, 2, {3, 4, {5}}}
			local copy = table_utils.deepcopy(original)
			assert.are.same(original, copy)
			copy[3][3][1] = 999
			assert.are.equals(5, original[3][3][1])
		end)

		it("should handle circular references", function()
			local original = {a = 1}
			original.self = original
			local copy = table_utils.deepcopy(original)
			assert.are.equals(copy, copy.self)
			assert.are_not.equal(original, copy)
		end)

		it("should return non-tables as-is", function()
			assert.are.equals(42, table_utils.deepcopy(42))
			assert.are.equals("string", table_utils.deepcopy("string"))
			assert.is_nil(table_utils.deepcopy(nil))
			assert.is_true(table_utils.deepcopy(true))
		end)

		it("should preserve metatables", function()
			local mt = {__index = function() return "meta" end}
			local original = setmetatable({a = 1}, mt)
			local copy = table_utils.deepcopy(original)
			assert.are.equals(getmetatable(original), getmetatable(copy))
		end)
	end)

	describe("extend", function()
		it("should merge two simple tables", function()
			local t1 = {a = 1, b = 2}
			local t2 = {c = 3, d = 4}
			local result = table_utils.extend(t1, t2)
			assert.are.same({a = 1, b = 2, c = 3, d = 4}, result)
		end)

		it("should give precedence to later tables", function()
			local t1 = {a = 1, b = 2}
			local t2 = {b = 99, c = 3}
			local result = table_utils.extend(t1, t2)
			assert.are.same({a = 1, b = 99, c = 3}, result)
		end)

		it("should recursively merge nested tables", function()
			local t1 = {a = {b = 1, c = 2}}
			local t2 = {a = {c = 99, d = 3}}
			local result = table_utils.extend(t1, t2)
			assert.are.same({a = {b = 1, c = 99, d = 3}}, result)
		end)

		it("should handle multiple tables", function()
			local t1 = {a = 1}
			local t2 = {b = 2}
			local t3 = {c = 3}
			local result = table_utils.extend(t1, t2, t3)
			assert.are.same({a = 1, b = 2, c = 3}, result)
		end)

		it("should handle empty tables", function()
			local t1 = {a = 1}
			local result = table_utils.extend(t1, {})
			assert.are.same({a = 1}, result)
		end)

		it("should return empty table when no arguments", function()
			local result = table_utils.extend()
			assert.are.same({}, result)
		end)

		it("should overwrite non-table values with tables", function()
			local t1 = {a = "string"}
			local t2 = {a = {b = 1}}
			local result = table_utils.extend(t1, t2)
			assert.are.same({a = {b = 1}}, result)
		end)

		it("should overwrite table values with non-table values", function()
			local t1 = {a = {b = 1}}
			local t2 = {a = "string"}
			local result = table_utils.extend(t1, t2)
			assert.are.same({a = "string"}, result)
		end)

		it("should handle deep nesting", function()
			local t1 = {a = {b = {c = {d = 1}}}}
			local t2 = {a = {b = {c = {e = 2}}}}
			local result = table_utils.extend(t1, t2)
			assert.are.same({a = {b = {c = {d = 1, e = 2}}}}, result)
		end)

		it("should not mutate original tables", function()
			local t1 = {a = 1}
			local t2 = {b = 2}
			local result = table_utils.extend(t1, t2)
			assert.are.same({a = 1}, t1)
			assert.are.same({b = 2}, t2)
			assert.are.same({a = 1, b = 2}, result)
		end)
	end)
end)
