-- tests/helpers/perf.lua
-- Timing helpers for the per-operation performance regression tests in
-- tests/integration/performance_spec.lua.
--
-- Why this is shaped the way it is:
--
--   * Bounds are PER OPERATION, never on suite wall-clock. The whole suite
--     runs in a couple of seconds, so a wall-clock bound over it would
--     measure CI runner noise rather than the engine.
--   * Timings use os.clock() (process CPU time), not os.time()/wall clock.
--     CPU time is unaffected by a runner that is descheduled while another
--     job hogs the box, which is the dominant source of flake on shared CI.
--   * Every measurement is the BEST of N runs, not the mean. Noise only ever
--     makes a run slower, so the minimum is the closest estimate of the real
--     cost and is far more stable than an average.
--   * Budgets are expressed in milliseconds measured on a reference machine
--     and then scaled by a calibration factor derived from a fixed pure-Lua
--     workload run in-process. A runner half the speed of the reference
--     machine gets twice the budget, so the bounds survive being moved
--     between laptops, containers and CI without being re-tuned.
--
-- Environment variables:
--
--   KANBAN_SKIP_PERF=1       skip the performance specs entirely
--   KANBAN_PERF_TOLERANCE=n  multiply every budget by n (e.g. 2 on a box
--                            known to be noisy). Default 1.

-- luassert is required explicitly rather than reached for as the global
-- `assert`: this module is loaded through require(), where that name
-- resolves to plain Lua's assert rather than to busted's injected one.
local luassert = require('luassert')

local M = {}

--- Milliseconds the calibration workload takes on the reference machine
--- (Apple M-series, Lua 5.3, 2026-09-17). Re-measure and update this only
--- if the workload in M.reference_workload() changes.
M.REFERENCE_MS = 7.0

--- Fixed pure-Lua workload used to measure how fast this machine is.
--- Deliberately the same shape of work as the parser's hot path: pattern
--- matching over card-like lines plus table building. It must not touch the
--- engine, so that an engine regression cannot inflate the budgets it is
--- being measured against.
function M.reference_workload()
  local acc = {}
  for i = 1, 2000 do
    local line = "- Task " .. i .. " <!-- id: ref_" .. i .. ", complexity: 3, tags: [a, b] -->"
    local text, props = line:match("^%-%s+(.-)%s*<!%-%-(.*)%-%->%s*$")
    local entry = { text = text }
    for key, value in props:gmatch("(%w+):%s*([^,]+)") do
      entry[key] = value
    end
    acc[#acc + 1] = entry
  end
  return #acc
end

--- Run fn() `iterations` times and return the fastest run, in seconds.
--- @param iterations number how many times to run fn
--- @param fn function the operation to time (called with no arguments)
--- @return number seconds the best (lowest) elapsed CPU time
function M.best_of(iterations, fn)
  local best = math.huge

  for _ = 1, iterations do
    local started = os.clock()
    fn()
    local elapsed = os.clock() - started
    if elapsed < best then
      best = elapsed
    end
  end

  return best
end

--- The smallest batch worth timing, in seconds. Below this, os.clock's
--- resolution and a single GC step are the same size as the measurement.
M.TARGET_BATCH_SECONDS = 0.005

--- Time a single call to fn(), in seconds.
---
--- The batch size is worked out rather than fixed: fn() is run in a growing
--- batch until one batch reaches TARGET_BATCH_SECONDS, and the best of
--- `samples` such batches is divided by the batch size. A fixed batch size
--- cannot work across interpreters -- 50 calls of find_task() is a healthy
--- 15ms sample under Lua 5.3 and an unmeasurable 0.2ms under LuaJIT, which
--- is how this arrived at a scaling ratio of 12x for an O(n) operation.
--- Sizing the batch to the clock instead makes every sample real, on any
--- interpreter, and the sizing runs double as JIT warm-up.
--- @param samples number how many batches to run (the fastest one wins)
--- @param fn function the operation to time
--- @return number seconds per single call
function M.per_call(samples, fn)
  local function time_batch(repeats)
    local started = os.clock()
    for _ = 1, repeats do
      fn()
    end
    return os.clock() - started
  end

  local repeats = 1
  local batch = time_batch(repeats)

  -- Grow towards the target. The step is capped so that a batch too short
  -- to measure at all cannot ask for an enormous jump in one go.
  while batch < M.TARGET_BATCH_SECONDS and repeats < 2 ^ 24 do
    local factor = 64
    if batch > 0 then
      factor = math.min(64, math.max(2, math.ceil(M.TARGET_BATCH_SECONDS / batch)))
    end

    repeats = repeats * factor
    batch = time_batch(repeats)
  end

  local best = batch
  for _ = 2, samples do
    local elapsed = time_batch(repeats)
    if elapsed < best then
      best = elapsed
    end
  end

  return best / repeats
end

--- Why the performance specs should not run, or nil if they should.
--- @return string|nil the reason, suitable for pending()
function M.skip_reason()
  if os.getenv("KANBAN_SKIP_PERF") == "1" then
    return "KANBAN_SKIP_PERF=1"
  end

  -- luacov's per-line debug hook does not slow everything down evenly: on
  -- the reference machine it costs the calibration workload about 10x and
  -- board parsing about 40x, so calibration cannot correct for it and every
  -- budget fails. It also turns a sub-second spec file into a 35-second
  -- one. Timing and coverage are measured in separate runs -- see the
  -- `test-perf` Makefile target.
  if package.loaded["luacov.runner"] or package.loaded["luacov"] then
    return "running under luacov; run `make test-perf` for timings"
  end

  return nil
end

--- True unless M.skip_reason() gives a reason not to run.
function M.enabled()
  return M.skip_reason() == nil
end

--- Extra slack applied to every budget, from KANBAN_PERF_TOLERANCE.
function M.tolerance()
  return tonumber(os.getenv("KANBAN_PERF_TOLERANCE") or "") or 1
end

local calibration

--- How much slower (>1) or faster (<1) this machine is than the reference
--- machine, measured once per process and cached.
--- @return number the calibration factor
function M.calibration()
  if not calibration then
    local measured = M.best_of(5, M.reference_workload)
    calibration = (measured * 1000) / M.REFERENCE_MS
  end

  return calibration
end

--- Scale a reference-machine budget to this machine.
--- @param reference_ms number the budget measured on the reference machine
--- @return number milliseconds allowed here
function M.budget_ms(reference_ms)
  return reference_ms * M.calibration() * M.tolerance()
end

--- Assert an operation ran within its budget, with a failure message that
--- says what was measured, what was allowed and how the budget was derived
--- -- a bare "expected true, got false" is useless for a timing failure.
--- @param label string name of the operation, for the message
--- @param reference_ms number budget in reference-machine milliseconds
--- @param measured_seconds number result of M.best_of()
function M.assert_within(label, reference_ms, measured_seconds)
  local measured_ms = measured_seconds * 1000
  local allowed_ms = M.budget_ms(reference_ms)

  luassert.is_true(measured_ms <= allowed_ms, string.format(
    "%s took %.2f ms, budget %.2f ms " ..
    "(%.2f ms reference x %.2f calibration x %.2f tolerance). " ..
    "Either this is a genuine regression, or the machine is noisier than " ..
    "calibration can account for -- rerun, then raise KANBAN_PERF_TOLERANCE " ..
    "if it is the latter.",
    label, measured_ms, allowed_ms,
    reference_ms, M.calibration(), M.tolerance()))
end

--- Assert an operation's cost grows no worse than `max_ratio` when the input
--- grows by `size_ratio`. This is the guard that catches an accidental
--- quadratic: budgets alone cannot tell "everything got 20% slower" from
--- "the algorithm changed", and a ratio is immune to machine speed entirely,
--- so it needs no calibration.
--- @param label string name of the operation
--- @param small_seconds number time at the small input size
--- @param large_seconds number time at the large input size
--- @param size_ratio number how many times bigger the large input is
--- @param max_ratio number the greatest acceptable time ratio
function M.assert_scaling(label, small_seconds, large_seconds, size_ratio, max_ratio)
  local ratio = large_seconds / small_seconds

  luassert.is_true(ratio <= max_ratio, string.format(
    "%s took %.2fx longer for %.0fx the input (%.2f ms -> %.2f ms); " ..
    "linear would be about %.0fx and the limit is %.2fx. " ..
    "A ratio near %.0fx means the operation has gone quadratic.",
    label, ratio, size_ratio, small_seconds * 1000, large_seconds * 1000,
    size_ratio, max_ratio, size_ratio * size_ratio))
end

return M
