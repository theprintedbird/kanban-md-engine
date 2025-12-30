require('polyfills.vim')
local string_utils = require('kanban-md.utils.string')

describe("string_utils", function()
	describe("split", function()
		it("should split string by default separator (whitespace)", function()
			local result = string_utils.split("hello world test")
			assert.are.same({"hello", "world", "test"}, result)
		end)

		it("should split string by custom separator", function()
			local result = string_utils.split("apple,banana,orange", ",")
			assert.are.same({"apple", "banana", "orange"}, result)
		end)

		it("should handle multiple consecutive separators", function()
			local result = string_utils.split("one,,three", ",")
			-- gmatch with pattern [^,]+ skips empty strings
			assert.are.same({"one", "three"}, result)
		end)

		it("should handle empty string", function()
			local result = string_utils.split("", ",")
			assert.are.same({}, result)
		end)

		it("should split by pipe character", function()
			local result = string_utils.split("a|b|c", "|")
			assert.are.same({"a", "b", "c"}, result)
		end)

		it("should split by hyphen", function()
			local result = string_utils.split("foo-bar-baz", "-")
			assert.are.same({"foo", "bar", "baz"}, result)
		end)

		it("should handle string with no separators", function()
			local result = string_utils.split("single", ",")
			assert.are.same({"single"}, result)
		end)

		it("should handle whitespace with custom separator", function()
			local result = string_utils.split("  hello   world  ")
			assert.are.same({"hello", "world"}, result)
		end)

		it("should split by dot (escaped pattern character)", function()
			-- Note: This might fail as dot is a Lua pattern character
			-- Current implementation may not handle pattern escaping
			local result = string_utils.split("a.b.c", ".")
			-- With current implementation using [^.]+, this should work
			assert.are.same({"a", "b", "c"}, result)
		end)
	end)
end)
