-- tests/unit/helpers/clock_spec.lua
-- The engine's injectable time source, and the test helper that drives it.
require('polyfills.vim')

local engine_clock = require('kanban-md.helpers.clock')
local test_clock = require('helpers.clock')

describe("kanban-md.helpers.clock", function()
  -- Every test in here replaces a module-level singleton; reset unconditionally
  -- so a failed assertion cannot leave a frozen clock behind for the rest of
  -- the run.
  after_each(function()
    engine_clock.reset()
  end)

  describe("default source", function()
    it("returns os.time()", function()
      local before = os.time()
      local now = engine_clock.now()
      local after = os.time()

      assert.is_true(now >= before and now <= after,
        string.format("%d is not between %d and %d", now, before, after))
    end)

    it("returns a number", function()
      assert.is_number(engine_clock.now())
    end)
  end)

  describe("set", function()
    it("makes now() return the injected source's value", function()
      engine_clock.set(function() return 12345 end)

      assert.equals(12345, engine_clock.now())
    end)

    it("calls the source on every now(), rather than caching it", function()
      local calls = 0
      engine_clock.set(function()
        calls = calls + 1
        return calls
      end)

      assert.equals(1, engine_clock.now())
      assert.equals(2, engine_clock.now())
      assert.equals(2, calls)
    end)

    it("returns the source it replaced, so a caller can restore it by hand", function()
      local first = function() return 1 end
      engine_clock.set(first)

      local previous = engine_clock.set(function() return 2 end)

      assert.equals(first, previous)
      assert.equals(2, engine_clock.now())

      engine_clock.set(previous)
      assert.equals(1, engine_clock.now())
    end)

    it("rejects anything that is not a function", function()
      assert.has_error(function() engine_clock.set(12345) end,
        "clock.set expects a function returning epoch seconds")
    end)
  end)

  describe("reset", function()
    it("puts os.time back", function()
      engine_clock.set(function() return 12345 end)
      engine_clock.reset()

      assert.is_true(math.abs(os.time() - engine_clock.now()) <= 1)
    end)

    it("is safe to call when nothing was injected", function()
      engine_clock.reset()
      engine_clock.reset()

      assert.is_number(engine_clock.now())
    end)
  end)
end)

describe("helpers.clock (test helper)", function()
  after_each(function()
    engine_clock.reset()
  end)

  it("freezes the engine's clock at a recognisable epoch", function()
    local clock = test_clock.install()

    assert.equals(test_clock.EPOCH, engine_clock.now())
    assert.equals(test_clock.EPOCH, engine_clock.now())
    assert.equals("2024-01-01T00:00:00Z", os.date("!%Y-%m-%dT%H:%M:%SZ", engine_clock.now()))

    clock.restore()
  end)

  it("starts wherever it is told to", function()
    local clock = test_clock.install(500)

    assert.equals(500, engine_clock.now())

    clock.restore()
  end)

  it("advances by the given number of seconds", function()
    local clock = test_clock.install()

    clock.advance(test_clock.DAY)

    assert.equals(test_clock.EPOCH + 86400, engine_clock.now())
    assert.equals(test_clock.EPOCH + 86400, clock.now())
  end)

  it("accumulates successive advances", function()
    local clock = test_clock.install()

    clock.advance(test_clock.MINUTE)
    clock.advance(test_clock.HOUR)
    clock.advance(test_clock.DAY)

    assert.equals(test_clock.EPOCH + 60 + 3600 + 86400, engine_clock.now())
  end)

  it("returns the new time from advance and set", function()
    local clock = test_clock.install()

    assert.equals(test_clock.EPOCH + 5, clock.advance(5))
    assert.equals(99, clock.set(99))
    assert.equals(99, engine_clock.now())
  end)

  it("exposes the units the durations are written in", function()
    assert.equals(60, test_clock.MINUTE)
    assert.equals(3600, test_clock.HOUR)
    assert.equals(86400, test_clock.DAY)
  end)

  it("gives os.time back on restore", function()
    local clock = test_clock.install()
    clock.restore()

    assert.is_true(math.abs(os.time() - engine_clock.now()) <= 1)
  end)

  it("has an idempotent restore, so after_each can repeat the test body's", function()
    local clock = test_clock.install()
    clock.restore()

    local other = test_clock.install(777)
    clock.restore() -- the stale handle must not disturb the live clock

    assert.equals(777, engine_clock.now())

    other.restore()
  end)
end)
