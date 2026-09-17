-- tests/helpers/clock.lua
-- A controllable stand-in for the engine's clock.
--
-- os.time() has one-second resolution, so a test that moves a card through
-- three columns in a millisecond gets three identical timestamps: every
-- assertion about the ordering of, or the duration between, transitions then
-- passes by coincidence rather than by arithmetic. A frozen clock the test
-- advances by hand makes those deltas real and exact.
--
-- Usage:
--
--   local test_clock = require('helpers.clock')
--   local clock
--
--   before_each(function() clock = test_clock.install() end)
--   after_each(function() clock.restore() end)
--
--   it("measures a two-day lead time", function()
--     board:move_card(card, backlog, doing)
--     clock.advance(2 * test_clock.DAY)
--     board:move_card(card, doing, done)
--     assert.equals(2 * test_clock.DAY, stats.calculate_lead_time(card.properties, board).duration)
--   end)
--
-- restore() is idempotent, so calling it from after_each is safe even when the
-- test body restored it already.

local engine_clock = require('kanban-md.helpers.clock')

local M = {}

M.MINUTE = 60
M.HOUR = 60 * M.MINUTE
M.DAY = 24 * M.HOUR

-- A fixed, recognisable starting point: 2024-01-01T00:00:00Z. Nothing depends
-- on the particular value, but a constant one keeps failure messages readable
-- and stops a test accidentally depending on today's date.
M.EPOCH = 1704067200

--- Freeze the engine's clock and hand back the controls.
--- @param start number|nil Epoch seconds to start at (default M.EPOCH)
--- @return table handle with now(), set(), advance() and restore()
function M.install(start)
  local current = start or M.EPOCH
  local restored = false

  engine_clock.set(function()
    return current
  end)

  local handle = {}

  --- The time the engine currently sees.
  function handle.now()
    return current
  end

  --- Jump to an absolute time.
  --- @param timestamp number Epoch seconds
  --- @return number timestamp The new current time
  function handle.set(timestamp)
    current = timestamp
    return current
  end

  --- Move the clock forward.
  --- @param seconds number How far to advance
  --- @return number timestamp The new current time
  function handle.advance(seconds)
    current = current + seconds
    return current
  end

  --- Give the engine os.time() back.
  function handle.restore()
    if restored then
      return
    end
    restored = true
    engine_clock.reset()
  end

  return handle
end

return M
