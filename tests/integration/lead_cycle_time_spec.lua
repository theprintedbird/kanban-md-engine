-- tests/integration/lead_cycle_time_spec.lua
-- Lead time, cycle time and blocked time measured across real card moves.
--
-- tests/unit/stats_metrics_spec.lua covers the arithmetic against hand-written
-- property tables. This file covers the path that produces those properties:
-- the engine's auto-timestamp triggers. Under os.time() every move in a test
-- lands in the same second, so the durations are all zero and any assertion
-- about them holds whatever the maths does. With the clock frozen and advanced
-- by hand, the deltas are exact and the arithmetic is genuinely under test.
require('polyfills.vim')

local Board = require('kanban-md.board')
local Card = require('kanban-md.card')
local config = require('kanban-md.config')
local stats = require('kanban-md.stats')
local test_clock = require('helpers.clock')

describe("Lead and cycle time across real moves", function()
  local clock

  before_each(function()
    config.reset()
    clock = test_clock.install()
  end)

  after_each(function()
    clock.restore()
    config.reset()
  end)

  -- Backlog -> Ready -> In Progress -> Blocked -> In Progress -> Done, with
  -- every state named explicitly so none of this depends on the position-based
  -- fallbacks in helpers/column.lua.
  local function workflow_board()
    local board = Board:new()

    local backlog = board:add_column("backlog", "Backlog")
    backlog.config.is_backlog_state = true

    local ready = board:add_column("ready", "Ready")

    local doing = board:add_column("in_progress", "In Progress")
    doing.config.is_start_state = true

    local blocked = board:add_column("blocked", "Blocked")
    blocked.config.is_blocked_state = true

    local done = board:add_column("done", "Done")
    done.config.is_completion_state = true

    board:auto_register_triggers()

    return board, backlog, ready, doing, blocked, done
  end

  it("records a distinct timestamp for every transition", function()
    local board, backlog, ready, doing, _, done = workflow_board()

    local card = Card:new("c1", "Ship it")
    backlog:add_card(card)

    clock.advance(test_clock.DAY)
    board:move_card(card, backlog, ready)

    clock.advance(2 * test_clock.DAY)
    board:move_card(card, ready, doing)

    clock.advance(3 * test_clock.DAY)
    board:move_card(card, doing, done)

    assert.equals(test_clock.EPOCH, card.properties.backlog)
    assert.equals(test_clock.EPOCH + 1 * test_clock.DAY, card.properties.ready)
    assert.equals(test_clock.EPOCH + 3 * test_clock.DAY, card.properties.in_progress)
    assert.equals(test_clock.EPOCH + 6 * test_clock.DAY, card.properties.done)
  end)

  it("measures lead time from the backlog to completion", function()
    local board, backlog, ready, doing, _, done = workflow_board()

    local card = Card:new("c2", "Ship it")
    backlog:add_card(card)

    clock.advance(test_clock.DAY)
    board:move_card(card, backlog, ready)

    clock.advance(2 * test_clock.DAY)
    board:move_card(card, ready, doing)

    clock.advance(3 * test_clock.DAY)
    board:move_card(card, doing, done)

    local lead_time = stats._private.calculate_lead_time(card.properties, board)

    assert.is_not_nil(lead_time)
    assert.equals(6 * test_clock.DAY, lead_time.duration)
    assert.equals("Backlog", lead_time.start_column)
    assert.equals("Done", lead_time.end_column)
  end)

  it("measures cycle time from the start state only, so queue time is excluded", function()
    local board, backlog, ready, doing, _, done = workflow_board()

    local card = Card:new("c3", "Ship it")
    backlog:add_card(card)

    -- A week sitting in the backlog and in Ready: lead time counts it, cycle
    -- time does not.
    clock.advance(7 * test_clock.DAY)
    board:move_card(card, backlog, ready)

    clock.advance(test_clock.DAY)
    board:move_card(card, ready, doing)

    clock.advance(4 * test_clock.HOUR)
    board:move_card(card, doing, done)

    local lead_time = stats._private.calculate_lead_time(card.properties, board)
    local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

    assert.equals(8 * test_clock.DAY + 4 * test_clock.HOUR, lead_time.duration)
    assert.equals(4 * test_clock.HOUR, cycle_time.duration)
    assert.equals("In Progress", cycle_time.start_column)
    assert.equals("Done", cycle_time.end_column)
  end)

  it("splits cycle time into blocked and active time", function()
    local board, backlog, ready, doing, blocked, done = workflow_board()

    local card = Card:new("c4", "Ship it")
    backlog:add_card(card)
    board:move_card(card, backlog, ready)
    board:move_card(card, ready, doing)

    -- Two hours of work, eight hours blocked, one more hour of work.
    clock.advance(2 * test_clock.HOUR)
    board:move_card(card, doing, blocked)

    clock.advance(8 * test_clock.HOUR)
    board:move_card(card, blocked, doing)

    clock.advance(test_clock.HOUR)
    board:move_card(card, doing, done)

    local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

    -- The second entry into In Progress overwrites the first timestamp, so the
    -- start of the cycle is the *return* from Blocked. This is what the
    -- one-timestamp-per-column data model can express; it is asserted here so
    -- that a change to it is a deliberate one.
    assert.equals(test_clock.EPOCH + 10 * test_clock.HOUR, card.properties.in_progress)
    assert.equals(test_clock.HOUR, cycle_time.duration)
    assert.equals(0, cycle_time.blocked_time)
    assert.equals(test_clock.HOUR, cycle_time.active_time)
  end)

  it("never reports more blocked time than the cycle it is taken from", function()
    -- Regression: blocked time used to be summed over the card's whole
    -- history, so a block that happened before the cycle started was
    -- subtracted from it and active_time came out negative.
    local board, backlog, ready, doing, blocked, done = workflow_board()

    local card = Card:new("c9", "Ship it")
    backlog:add_card(card)
    board:move_card(card, backlog, ready)
    board:move_card(card, ready, doing)

    clock.advance(6 * test_clock.HOUR)
    board:move_card(card, doing, blocked)

    clock.advance(12 * test_clock.HOUR)
    board:move_card(card, blocked, doing) -- restarts the cycle

    clock.advance(test_clock.MINUTE)
    board:move_card(card, doing, done)

    local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

    assert.equals(test_clock.MINUTE, cycle_time.duration)
    assert.is_true(cycle_time.blocked_time <= cycle_time.duration)
    assert.is_true(cycle_time.active_time >= 0)
  end)

  it("counts the time between entering a blocked column and leaving it", function()
    local board, backlog, ready, doing, blocked, done = workflow_board()

    local card = Card:new("c5", "Ship it")
    backlog:add_card(card)
    board:move_card(card, backlog, ready)
    board:move_card(card, ready, doing)

    clock.advance(2 * test_clock.HOUR)
    board:move_card(card, doing, blocked)

    clock.advance(8 * test_clock.HOUR)
    board:move_card(card, blocked, done)

    local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

    assert.equals(10 * test_clock.HOUR, cycle_time.duration)
    assert.equals(8 * test_clock.HOUR, cycle_time.blocked_time)
    assert.equals(2 * test_clock.HOUR, cycle_time.active_time)
  end)

  it("reports no blocked time for a card that was never blocked", function()
    local board, backlog, ready, doing, _, done = workflow_board()

    local card = Card:new("c6", "Ship it")
    backlog:add_card(card)
    board:move_card(card, backlog, ready)
    board:move_card(card, ready, doing)

    clock.advance(3 * test_clock.HOUR)
    board:move_card(card, doing, done)

    local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

    assert.equals(0, cycle_time.blocked_time)
    assert.equals(3 * test_clock.HOUR, cycle_time.active_time)
  end)

  it("aggregates the durations of several cards into the board stats", function()
    local board, backlog, ready, doing, _, done = workflow_board()

    local quick = Card:new("c7", "Quick one")
    local slow = Card:new("c8", "Slow one")

    backlog:add_card(quick)
    backlog:add_card(slow)

    board:move_card(quick, backlog, ready)
    board:move_card(quick, ready, doing)
    clock.advance(test_clock.DAY)
    board:move_card(quick, doing, done)

    board:move_card(slow, backlog, ready)
    board:move_card(slow, ready, doing)
    clock.advance(4 * test_clock.DAY)
    board:move_card(slow, doing, done)

    board:calculate_stats()

    -- One day and five days from the backlog, so an average of three.
    assert.equals(2, #board.stats.lead_times)
    assert.equals(3 * test_clock.DAY, board.stats.average_lead_time)
  end)
end)
