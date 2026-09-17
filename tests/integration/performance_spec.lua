-- tests/integration/performance_spec.lua
-- Per-operation performance regression tests.
--
-- These are bounds on individual engine operations -- parse, write, stats,
-- validation, lookup, move -- over generated boards. They are NOT a bound on
-- how long the suite takes: the whole suite runs in a few seconds, so a
-- wall-clock bound over it would be measuring the CI runner rather than the
-- engine.
--
-- Two kinds of assertion, because they catch different things:
--
--   * A BUDGET says an operation cost no more than N milliseconds. It
--     catches "this got several times more expensive".
--   * A SCALING ratio says six times the cards cost no more than nine times
--     the time. It catches a change of algorithmic shape, which a budget
--     loose enough not to flake will happily absorb at these sizes.
--
-- Every operation is therefore measured once in setup(), at both sizes
-- where it makes a scaling claim and at the large size otherwise. The
-- describe blocks below assert against those measurements rather than
-- re-timing anything, so nothing is paid for twice.
--
-- tests/helpers/perf.lua explains the measurement technique (CPU time,
-- best-of-N, calibration against a fixed workload). The short version: a
-- budget is a millisecond figure measured on a reference machine, scaled to
-- whatever machine is running now, with roughly three times the headroom.
--
-- These specs skip themselves under luacov, whose per-line hook makes every
-- timing meaningless -- so `make coverage` and CI's coverage run do not
-- measure them, and `make test-perf` is the target that does. Set
-- KANBAN_SKIP_PERF=1 to skip them anyway; KANBAN_PERF_TOLERANCE=2 doubles
-- every budget on a box known to be noisy.
require('polyfills.vim')

local Board = require('kanban-md.board')
local large_board = require('fixtures.large_board')
local perf = require('helpers.perf')

local COLUMNS = 12

-- 240 cards and 1440 cards. The large board is far bigger than anything
-- anyone hand-maintains, so per-card costs dominate the fixed ones, and the
-- six-fold spread is what gives the scaling ratios enough leverage to see a
-- quadratic term before it dominates the linear one.
local SMALL_CARDS_PER_COLUMN = 20
local LARGE_CARDS_PER_COLUMN = 120
local LARGE_CARDS = COLUMNS * LARGE_CARDS_PER_COLUMN

local SIZE_RATIO = LARGE_CARDS_PER_COLUMN / SMALL_CARDS_PER_COLUMN

-- Linear would be 6x. Parse, write and stats measure between 5.7x and 6.9x
-- on the reference machine, and a quadratic would be heading for 36x, so 9x
-- leaves room for noise while still failing well before the curve bends.
local MAX_SCALING_RATIO = 9

-- validate(), find_task() and move_card() get a budget but deliberately no
-- scaling assertion. They cost tenths of a millisecond even on the large
-- board, where memory latency rather than the work itself sets the price:
-- the 240-card board stays in cache and the 1440-card one does not. Under
-- Lua 5.3 that shows up as 6.1x-7.7x for 6x the cards, and under LuaJIT --
-- which makes the per-card work cheap enough for the memory traffic to
-- dominate completely -- as 12.8x-15.2x, with honestly sized batches and no
-- change to the engine. A ratio that a change of interpreter moves by more
-- than a quadratic would is not evidence about the algorithm, so these three
-- are left to their budgets.

--- it(), but marked pending when timings cannot be trusted -- under luacov,
--- or when KANBAN_SKIP_PERF=1 asks for them to be skipped.
local function perf_it(description, fn)
  it(description, function()
    local skip_reason = perf.skip_reason()
    if skip_reason then
      return pending(skip_reason)
    end

    fn()
  end)
end

describe("performance", function()
  -- measured.<operation> = { small = seconds, large = seconds }
  local measured = {}
  local small_board, big_board

  setup(function()
    -- Building and timing the fixtures is the expensive part, so it is
    -- gated on the same condition as the assertions: under luacov this
    -- setup alone would take tens of seconds.
    if not perf.enabled() then
      return
    end

    local small_markdown = large_board.markdown(COLUMNS, SMALL_CARDS_PER_COLUMN)
    local large_markdown = large_board.markdown(COLUMNS, LARGE_CARDS_PER_COLUMN)

    small_board = Board:new()
    small_board:parse(small_markdown)

    big_board = Board:new()
    big_board:parse(large_markdown)

    -- perf.per_call() sizes its own batch, so an operation costing
    -- microseconds and one costing a fifth of a second are both measured
    -- honestly here, and both are recorded per single call.
    local function measure_large(name, samples, large_fn)
      measured[name] = { large = perf.per_call(samples, large_fn) }
    end

    -- Both sizes, for the operations that make a scaling claim. The small
    -- board is not timed for the others: an unused measurement is just time
    -- added to the suite.
    local function measure_both(name, samples, small_fn, large_fn)
      measure_large(name, samples, large_fn)
      measured[name].small = perf.per_call(samples, small_fn)
    end

    local function parse(markdown)
      return function()
        local fresh = Board:new()
        fresh:parse(markdown)
      end
    end

    measure_both("parse", 2, parse(small_markdown), parse(large_markdown))

    measure_both("write", 3,
      function() small_board:write() end,
      function() big_board:write() end)

    measure_both("calculate_stats", 3,
      function() small_board:calculate_stats() end,
      function() big_board:calculate_stats() end)

    measure_large("validate", 3, function() big_board:validate() end)

    -- The last card of the last column: the worst case for a lookup that
    -- walks the columns in order.
    measure_large("find_task", 3, function()
      big_board:find_task(large_board.last_card_id(COLUMNS, LARGE_CARDS_PER_COLUMN))
    end)

    -- Moved there and back, so the board ends in the state it started in
    -- however many iterations run.
    local function move_there_and_back(board)
      local first_column = board.columns[1]
      local second_column = board.columns[2]
      local card = first_column.cards[1]

      return function()
        board:move_card(card, first_column, second_column)
        board:move_card(card, second_column, first_column)
      end
    end

    measure_large("move_card", 3, move_there_and_back(big_board))
  end)

  describe("fixtures", function()
    perf_it("builds the boards the bounds are measured against", function()
      local function count_cards(board)
        local total = 0
        for _, column in ipairs(board.columns) do
          total = total + #column.cards
        end
        return total
      end

      -- If this ever fails, every budget below is meaningless: they would
      -- be measuring a different amount of work.
      assert.are.equal(COLUMNS, #big_board.columns)
      assert.are.equal(LARGE_CARDS, count_cards(big_board))
      assert.are.equal(COLUMNS * SMALL_CARDS_PER_COLUMN, count_cards(small_board))

      -- The lookups above have to actually find something, or find_task is
      -- being timed on a miss.
      assert.is_not_nil(big_board:find_task(
        large_board.last_card_id(COLUMNS, LARGE_CARDS_PER_COLUMN)))
    end)
  end)

  describe("budgets", function()
    perf_it("parses a 1440-card board within budget", function()
      perf.assert_within("parse", 520, measured.parse.large)
    end)

    perf_it("writes a 1440-card board within budget", function()
      perf.assert_within("write", 70, measured.write.large)
    end)

    perf_it("calculates stats for a 1440-card board within budget", function()
      perf.assert_within("calculate_stats", 90, measured.calculate_stats.large)
    end)

    perf_it("validates a 1440-card board within budget", function()
      perf.assert_within("validate", 1.5, measured.validate.large)
    end)

    perf_it("finds the last card of a 1440-card board within budget", function()
      perf.assert_within("find_task (worst case)", 0.9, measured.find_task.large)
    end)

    perf_it("moves a card on a 1440-card board within budget", function()
      perf.assert_within("move_card (there and back)", 0.15, measured.move_card.large)
    end)
  end)

  describe("scaling", function()
    -- These need no calibration: a ratio of two timings taken in the same
    -- process is immune to how fast the machine is.
    local function assert_scales(operation)
      perf.assert_scaling(operation,
        measured[operation].small, measured[operation].large,
        SIZE_RATIO, MAX_SCALING_RATIO)
    end

    perf_it("parse stays linear in the number of cards", function()
      assert_scales("parse")
    end)

    perf_it("write stays linear in the number of cards", function()
      assert_scales("write")
    end)

    perf_it("calculate_stats stays linear in the number of cards", function()
      assert_scales("calculate_stats")
    end)
  end)
end)
