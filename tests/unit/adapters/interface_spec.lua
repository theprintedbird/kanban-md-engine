-- tests/unit/adapters/interface_spec.lua
-- Unit tests for the abstract Adapter interface: the contract every platform
-- adapter is checked against (Adapter.validate) and the constructor concrete
-- adapters inherit from (Adapter.new).

require('polyfills.vim')

local Adapter = require("kanban-md.adapters.interface")

-- The seven methods Adapter.validate() insists on, in the order it checks them.
local REQUIRED_METHODS = {
  "notify",
  "read_buffer",
  "write_buffer",
  "get_cursor",
  "set_cursor",
  "prompt_input",
  "prompt_select",
}

--- Build a table implementing every required method, minus `omit` if given.
--- @param omit string|nil name of the one method to leave unimplemented
--- @return table implementation
local function complete_implementation(omit)
  local impl = {}
  for _, method in ipairs(REQUIRED_METHODS) do
    if method ~= omit then
      impl[method] = function() end
    end
  end
  return impl
end

describe("Adapter interface", function()
  describe("Adapter.validate()", function()
    it("accepts an adapter implementing every required method", function()
      local is_valid, err = Adapter.validate(complete_implementation())

      assert.is_true(is_valid)
      assert.is_nil(err)
    end)

    it("rejects an adapter missing any one required method, naming it", function()
      for _, missing in ipairs(REQUIRED_METHODS) do
        local is_valid, err = Adapter.validate(complete_implementation(missing))

        assert.is_false(is_valid)
        assert.equals("Adapter missing required method: " .. missing, err)
      end
    end)

    it("rejects an empty table, reporting the first missing method", function()
      local is_valid, err = Adapter.validate({})

      assert.is_false(is_valid)
      assert.equals("Adapter missing required method: notify", err)
    end)

    it("rejects a non-function value under a required method name", function()
      local impl = complete_implementation()
      impl.notify = "not a function"

      local is_valid, err = Adapter.validate(impl)

      assert.is_false(is_valid)
      assert.equals("Adapter missing required method: notify", err)
    end)

    it("does not require the optional virtual-text methods", function()
      local impl = complete_implementation()

      assert.is_nil(impl.supports_virtual_text)
      assert.is_true(Adapter.validate(impl))
    end)

    it("accepts the CLI adapter, the reference implementation", function()
      local CLIAdapter = require("kanban-md.adapters.cli")

      local is_valid, err = Adapter.validate(CLIAdapter)

      assert.is_true(is_valid)
      assert.is_nil(err)
    end)
  end)

  describe("Adapter.new()", function()
    it("returns the implementation table itself, with Adapter as metatable", function()
      local impl = complete_implementation()

      local adapter = Adapter.new(impl)

      assert.equals(impl, adapter)
      assert.equals(Adapter, getmetatable(adapter))
    end)

    it("keeps the supplied implementations rather than the abstract stubs", function()
      local impl = complete_implementation()
      local notified
      impl.notify = function(_, message, level)
        notified = { message = message, level = level }
      end

      local adapter = Adapter.new(impl)
      adapter:notify("hello", "warn")

      assert.same({ message = "hello", level = "warn" }, notified)
    end)

    it("inherits the optional virtual-text defaults from the interface", function()
      local adapter = Adapter.new(complete_implementation())

      assert.is_false(adapter:supports_virtual_text())
      assert.is_nil(adapter:create_namespace("kanban"))
      assert.is_nil(adapter:set_extmark(0, 1, 0, 0, {}))
      assert.is_nil(adapter:clear_namespace(0, 1))
    end)

    it("errors when a required method is missing, naming it", function()
      local ok, err = pcall(Adapter.new, complete_implementation("write_buffer"))

      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("Adapter missing required method: write_buffer", 1, true))
    end)

    it("errors when called with no implementation at all", function()
      local ok, err = pcall(Adapter.new)

      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("Adapter missing required method: notify", 1, true))
    end)
  end)

  describe("abstract methods", function()
    it("error when an adapter fails to override them", function()
      -- An instance that passes validate() only because the stubs exist on the
      -- prototype: calling one must still say which method is unimplemented.
      local bare = setmetatable({}, Adapter)

      for _, method in ipairs(REQUIRED_METHODS) do
        local ok, err = pcall(function() return bare[method](bare) end)

        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("Abstract method '" .. method .. "'", 1, true))
        assert.is_truthy(tostring(err):find("must be implemented by adapter", 1, true))
      end
    end)

    it("identify the adapter by name in the error message", function()
      local named = setmetatable({ name = "MyAdapter" }, Adapter)

      local ok, err = pcall(function() return named:notify("x") end)

      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("(adapter: MyAdapter)", 1, true))
    end)

    it("fall back to _type when the adapter has no name", function()
      local typed = setmetatable({ _type = "web" }, Adapter)

      local ok, err = pcall(function() return typed:get_cursor() end)

      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("(adapter type: web)", 1, true))
    end)

    it("fall back to the metatable __name when there is neither", function()
      local mt = { __index = Adapter, __name = "MetaAdapter" }
      local anonymous = setmetatable({}, mt)

      local ok, err = pcall(function() return anonymous:set_cursor(1, 0) end)

      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("(adapter: MetaAdapter)", 1, true))
    end)
  end)

  describe("non-abstract defaults", function()
    it("report no virtual text support", function()
      assert.is_false(Adapter:supports_virtual_text())
    end)

    it("return false for the buffer-identity methods", function()
      assert.is_false(Adapter:get_current_buffer())
      assert.is_false(Adapter:buf_line_count(0))
    end)
  end)
end)
