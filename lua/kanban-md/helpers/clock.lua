--- The engine's source of wall-clock time.
---
--- Every timestamp the engine writes - column transitions, creation times, the
--- archive cutoff - comes from `clock.now()` rather than `os.time()` directly.
--- That is the only reason this module exists: `os.time()` has one-second
--- resolution, so a test that moves a card through three columns gets three
--- identical timestamps and any assertion about ordering or duration between
--- them passes by coincidence. A test that sets its own clock can move a card
--- through a week of column transitions in a millisecond and assert the real
--- deltas.
---
--- Production code never calls `set()`; `now()` returns `os.time()` unless a
--- test has said otherwise.
local clock = {}

local DEFAULT_SOURCE = os.time

local source = DEFAULT_SOURCE

--- The current time, in epoch seconds.
--- @return number
function clock.now()
	return source()
end

--- Replace the time source. Tests only.
--- @param fn function A function returning epoch seconds
--- @return function previous The source that was in place, for restoring by hand
function clock.set(fn)
	assert(type(fn) == "function", "clock.set expects a function returning epoch seconds")

	local previous = source
	source = fn

	return previous
end

--- Restore the default time source, `os.time`.
--- @return nil
function clock.reset()
	source = DEFAULT_SOURCE
end

return clock
