-- tests/unit/helpers/ulid_spec.lua
-- Unit tests for lua/kanban-md/helpers/ulid.lua, the vendored ULID generator
-- behind every auto-generated board/column/card id.
--
-- The module keeps its time and random functions in upvalues with no getters,
-- and extras/id_triggers.lua installs its own time function on the shared
-- instance at load. So any test that injects a function loads a private copy
-- through fresh_ulid() rather than mutating the instance the engine uses.
require('polyfills.vim')

-- Crockford's Base32: the digits, minus I, L, O and U.
local ULID_CHARS = "^[0-9A-HJKMNP-TV-Z]+$"

--- A private copy of the module, isolated from the engine's shared instance.
local function fresh_ulid()
  local key = 'kanban-md.helpers.ulid'
  local cached = package.loaded[key]

  package.loaded[key] = nil
  local module = require(key)
  package.loaded[key] = cached

  return module
end

--- A private copy with a fixed clock, in seconds with millisecond precision.
local function ulid_at(time)
  local module = fresh_ulid()
  module.set_time_func(function() return time end)
  return module
end

describe("ulid", function()
  describe("format", function()
    it("is 26 characters: 10 of time and 16 of randomness", function()
      local id = ulid_at(1789620000.123).ulid()

      assert.equals(26, #id)
      assert.equals(10, #id:sub(1, 10))
      assert.equals(16, #id:sub(11))
    end)

    it("uses only Crockford Base32 characters", function()
      local module = ulid_at(1789620000.123)

      for _ = 1, 200 do
        assert.matches(ULID_CHARS, module.ulid())
      end
    end)

    it("never emits the ambiguous I, L, O or U", function()
      local module = ulid_at(1789620000.123)
      local seen = {}

      for _ = 1, 200 do
        for char in module.ulid():gmatch(".") do
          seen[char] = true
        end
      end

      for _, excluded in ipairs({ "I", "L", "O", "U" }) do
        assert.is_nil(seen[excluded], "ULID emitted the excluded character " .. excluded)
      end
    end)

    it("is callable as a module as well as through .ulid()", function()
      local module = ulid_at(1789620000.123)

      assert.equals(26, #module(nil))
      assert.equals(module.ulid(1789620000.123):sub(1, 10), module(1789620000.123):sub(1, 10))
    end)
  end)

  describe("encode_time", function()
    it("encodes a given time deterministically", function()
      local module = fresh_ulid()

      assert.equals(module.encode_time(1789620000.123), module.encode_time(1789620000.123))
    end)

    it("honours a requested length", function()
      local module = fresh_ulid()

      assert.equals(4, #module.encode_time(1789620000.123, 4))
      assert.equals(10, #module.encode_time(1789620000.123))
    end)

    it("uses the injected time function when given no time", function()
      local module = ulid_at(1789620000.123)

      assert.equals(module.encode_time(1789620000.123), module.encode_time())
    end)

    it("distinguishes times one millisecond apart", function()
      local module = fresh_ulid()

      assert.are_not.equals(module.encode_time(1789620000.000), module.encode_time(1789620000.001))
    end)

    it("ignores sub-millisecond differences", function()
      local module = fresh_ulid()

      assert.equals(module.encode_time(1789620000.0001), module.encode_time(1789620000.0002))
    end)
  end)

  describe("monotonicity", function()
    it("sorts lexicographically in time order", function()
      local module = fresh_ulid()
      local previous = module.encode_time(1789620000)

      for i = 1, 100 do
        local current = module.encode_time(1789620000 + i)

        assert.is_true(current > previous,
          string.format("%s should sort after %s", current, previous))
        previous = current
      end
    end)

    it("sorts whole ids in time order despite the random tail", function()
      local module = fresh_ulid()
      local ids = {}

      for i = 1, 50 do
        table.insert(ids, module.ulid(1789620000 + i))
      end

      for i = 2, #ids do
        assert.is_true(ids[i] > ids[i - 1],
          string.format("%s should sort after %s", ids[i], ids[i - 1]))
      end
    end)

    it("shares a time prefix for ids generated in the same millisecond", function()
      local module = fresh_ulid()

      local first = module.ulid(1789620000.5)
      local second = module.ulid(1789620000.5)

      assert.equals(first:sub(1, 10), second:sub(1, 10))
      assert.are_not.equals(first, second)
    end)

    it("still sorts correctly across a rollover of the low digit", function()
      local module = fresh_ulid()
      -- 32 milliseconds carries the last Base32 digit over.
      local before = module.encode_time(1789620000.000)
      local after = module.encode_time(1789620000.032)

      assert.is_true(after > before)
      -- The carry lands in the second-to-last digit.
      assert.are_not.equals(before:sub(-2, -2), after:sub(-2, -2))
    end)
  end)

  describe("collisions", function()
    it("produces distinct ids within one millisecond", function()
      local module = ulid_at(1789620000.5)
      local seen = {}

      for _ = 1, 2000 do
        local id = module.ulid()

        assert.is_nil(seen[id], "duplicate ULID generated: " .. id)
        seen[id] = true
      end
    end)

    it("produces distinct random parts", function()
      local module = fresh_ulid()
      local seen = {}
      local duplicates = 0

      for _ = 1, 2000 do
        local part = module.encode_random()
        if seen[part] then
          duplicates = duplicates + 1
        end
        seen[part] = true
      end

      assert.equals(0, duplicates)
    end)
  end)

  describe("encode_random", function()
    it("defaults to 16 characters and honours a requested length", function()
      local module = fresh_ulid()

      assert.equals(16, #module.encode_random())
      assert.equals(5, #module.encode_random(5))
      assert.equals(0, #module.encode_random(0))
    end)

    it("draws from the injected random function", function()
      local module = fresh_ulid()
      -- 0 selects the first character of the encoding table.
      module.set_random_func(function() return 0 end)

      assert.equals("0000000000000000", module.encode_random())
    end)

    it("maps the top of the random range to the last character", function()
      local module = fresh_ulid()
      module.set_random_func(function() return 0.9999 end)

      assert.equals("ZZZZ", module.encode_random(4))
    end)
  end)

  describe("function injection", function()
    it("returns true from both setters", function()
      local module = fresh_ulid()

      assert.is_true(module.set_time_func(os.time))
      assert.is_true(module.set_random_func(math.random))
    end)

    it("rejects a non-function time function", function()
      local module = fresh_ulid()

      local ok, err = pcall(module.set_time_func, 12345)

      assert.is_false(ok)
      assert.matches("expected 1st argument to be a function", tostring(err))
    end)

    it("rejects a non-function random function", function()
      local module = fresh_ulid()

      local ok, err = pcall(module.set_random_func, "random")

      assert.is_false(ok)
      assert.matches("expected 1st argument to be a function", tostring(err))
    end)
  end)

  describe("the engine's shared instance", function()
    it("generates usable ids once id_triggers has installed a clock", function()
      -- extras/id_triggers.lua installs a time function on the shared module at
      -- load; without one, plain Lua has no millisecond clock and ulid() errors.
      require('kanban-md.extras.id_triggers')
      local shared = require('kanban-md.helpers.ulid')

      local id = shared()

      assert.equals(26, #id)
      assert.matches(ULID_CHARS, id)
    end)
  end)
end)
