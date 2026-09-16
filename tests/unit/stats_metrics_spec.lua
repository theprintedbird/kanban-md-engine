-- tests/unit/stats_metrics_spec.lua
-- Tests for lead time and cycle time calculations
require('polyfills.vim')

_G._TEST = true

local Board = require("kanban-md.board")

describe("Stats - Lead Time and Cycle Time Calculations", function()
	local board

	before_each(function()
		board = Board:new()
		board.config = {
			cycle_time_unit = "days"
		}
	end)

	local function create_column(name, config)
		return {
			name = name,
			config = config or {},
			tasks = {},
			cards = {}
		}
	end

	local function create_card(properties)
		return {
			text = "Test task",
			properties = properties or {}
		}
	end

	describe("calculate_lead_time", function()
		it("should calculate lead time from backlog to completion", function()
			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local progress_col = create_column("In Progress")
			local done_col = create_column("Done", { is_completion_state = true })
			board.columns = { backlog_col, progress_col, done_col }

			local card = create_card({
				backlog = 1000000,      -- Start in backlog
				in_progress = 1086400,  -- 1 day later
				done = 1259200          -- 3 days later (total: 3 days from backlog)
			})

			local stats = require("kanban-md.stats")
			local lead_time = stats._private.calculate_lead_time(card.properties, board)

			assert.is_not_nil(lead_time)
			assert.equal(1000000, lead_time.start_time)
			assert.equal("Backlog", lead_time.start_column)
			assert.equal(1259200, lead_time.end_time)
			assert.equal("Done", lead_time.end_column)
			assert.equal(259200, lead_time.duration) -- 3 days in seconds
		end)

		it("should use position-based fallback (first column) when no explicit backlog", function()
			local progress_col = create_column("In Progress")
			local done_col = create_column("Done", { is_completion_state = true })
			board.columns = { progress_col, done_col }

			local card = create_card({
				in_progress = 1086400,
				done = 1259200
			})

			local stats = require("kanban-md.stats")
			local lead_time = stats._private.calculate_lead_time(card.properties, board)

			assert.is_not_nil(lead_time)
			-- Should use first column (In Progress) as backlog due to position-based fallback
			assert.equal(1086400, lead_time.start_time)
			assert.equal("In Progress", lead_time.start_column)
			assert.equal(1259200, lead_time.end_time)
			assert.equal(172800, lead_time.duration)
		end)

		it("should return nil if only one column exists (no backlog timestamp)", function()
			local done_col = create_column("Done", { is_completion_state = true })
			board.columns = { done_col }

			local card = create_card({
				done = 1259200
			})

			local stats = require("kanban-md.stats")
			local lead_time = stats._private.calculate_lead_time(card.properties, board)

			-- Should return nil since no backlog column and only 1 column (no position-based fallback)
			assert.is_nil(lead_time)
		end)

		it("should return nil if no start timestamp", function()
			local done_col = create_column("Done", { is_completion_state = true })
			board.columns = { done_col }

			local card = create_card({
				done = 1259200
			})

			local stats = require("kanban-md.stats")
			local lead_time = stats._private.calculate_lead_time(card.properties, board)

			assert.is_nil(lead_time)
		end)

		it("should return nil if no completion timestamp", function()
			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			board.columns = { backlog_col }

			local card = create_card({
				backlog = 1000000
			})

			local stats = require("kanban-md.stats")
			local lead_time = stats._private.calculate_lead_time(card.properties, board)

			assert.is_nil(lead_time)
		end)

		it("should prefer archived timestamp for completion", function()
			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local done_col = create_column("Done", { is_completion_state = true })
			board.columns = { backlog_col, done_col }

			local card = create_card({
				backlog = 1000000,
				done = 1259200,
				archived = 1345600  -- 4 days from backlog
			})

			local stats = require("kanban-md.stats")
			local lead_time = stats._private.calculate_lead_time(card.properties, board)

			assert.equal(1345600, lead_time.end_time)
			assert.equal("__ARCHIVE__", lead_time.end_column)
			assert.equal(345600, lead_time.duration) -- 4 days
		end)
	end)

	describe("calculate_cycle_time", function()
		it("should calculate cycle time from start state to completion", function()
			local backlog_col = create_column("Backlog")
			local progress_col = create_column("In Progress", { is_start_state = true })
			local done_col = create_column("Done", { is_completion_state = true })
			board.columns = { backlog_col, progress_col, done_col }

			local card = create_card({
				backlog = 1000000,
				in_progress = 1086400,  -- Cycle time starts here
				done = 1259200          -- 2 days from in_progress
			})

			local stats = require("kanban-md.stats")
			local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

			assert.is_not_nil(cycle_time)
			assert.equal(1086400, cycle_time.start_time)
			assert.equal("In Progress", cycle_time.start_column)
			assert.equal(1259200, cycle_time.end_time)
			assert.equal("Done", cycle_time.end_column)
			assert.equal(172800, cycle_time.duration) -- 2 days in seconds
		end)

		it("should calculate blocked time separately", function()
			local progress_col = create_column("In Progress", { is_start_state = true })
			local blocked_col = create_column("Blocked", { is_blocked_state = true })
			local done_col = create_column("Done", { is_completion_state = true })
			board.columns = { progress_col, blocked_col, done_col }

			local card = create_card({
				in_progress = 1000000,  -- Day 0
				blocked = 1086400,      -- Day 1 (enter blocked)
				done = 1259200          -- Day 3 (1 day blocked, 2 days total)
			})

			local stats = require("kanban-md.stats")
			local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

			assert.is_not_nil(cycle_time)
			assert.equal(259200, cycle_time.duration)      -- 3 days total
			assert.equal(172800, cycle_time.blocked_time)  -- 2 days blocked (day 1-3)
			assert.equal(86400, cycle_time.active_time)    -- 1 day active (day 0-1)
		end)

		it("should calculate waiting time as blocked time", function()
			local progress_col = create_column("In Progress", { is_start_state = true })
			local waiting_col = create_column("Waiting", { is_waiting_state = true })
			local done_col = create_column("Done", { is_completion_state = true })
			board.columns = { progress_col, waiting_col, done_col }

			local card = create_card({
				in_progress = 1000000,  -- Day 0
				waiting = 1086400,      -- Day 1
				done = 1172800          -- Day 2
			})

			local stats = require("kanban-md.stats")
			local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

			assert.equal(172800, cycle_time.duration)     -- 2 days total
			assert.equal(86400, cycle_time.blocked_time)  -- 1 day waiting
			assert.equal(86400, cycle_time.active_time)   -- 1 day active
		end)

		it("should handle multiple blocked/waiting periods", function()
			local progress1_col = create_column("In Progress", { is_start_state = true })
			local blocked_col = create_column("Blocked", { is_blocked_state = true })
			local progress2_col = create_column("Review")
			local waiting_col = create_column("Waiting", { is_waiting_state = true })
			local done_col = create_column("Done", { is_completion_state = true })
			board.columns = { progress1_col, blocked_col, progress2_col, waiting_col, done_col }

			local card = create_card({
				in_progress = 1000000,  -- Day 0
				blocked = 1086400,      -- Day 1 (blocked for 1 day)
				review = 1172800,       -- Day 2 (active for 1 day)
				waiting = 1259200,      -- Day 3 (waiting for 1 day)
				done = 1345600          -- Day 4
			})

			local stats = require("kanban-md.stats")
			local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

			assert.equal(345600, cycle_time.duration)     -- 4 days total
			assert.equal(172800, cycle_time.blocked_time) -- 2 days (1 blocked + 1 waiting)
			assert.equal(172800, cycle_time.active_time)  -- 2 days active
		end)

		it("should return nil if no start state timestamp", function()
			-- Create two columns so Done is not also the start column by position
			local backlog_col = create_column("Backlog")
			local done_col = create_column("Done", { is_completion_state = true })
			board.columns = { backlog_col, done_col }

			-- Card only has done timestamp, not backlog (start state by position)
			local card = create_card({
				done = 1259200
			})

			local stats = require("kanban-md.stats")
			local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

			-- Should be nil because card never entered the start state column (Backlog)
			assert.is_nil(cycle_time)
		end)

		it("should return nil if no completion timestamp", function()
			local progress_col = create_column("In Progress", { is_start_state = true })
			board.columns = { progress_col }

			local card = create_card({
				in_progress = 1000000
			})

			local stats = require("kanban-md.stats")
			local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

			assert.is_nil(cycle_time)
		end)

		it("should use position-based fallback for start state", function()
			local backlog_col = create_column("Backlog")
			local progress_col = create_column("In Progress")
			local done_col = create_column("Done", { is_completion_state = true })
			board.columns = { backlog_col, progress_col, done_col }

			local card = create_card({
				backlog = 1000000,      -- First column (start state by position)
				in_progress = 1086400,
				done = 1259200
			})

			local stats = require("kanban-md.stats")
			local cycle_time = stats._private.calculate_cycle_time(card.properties, board)

			assert.is_not_nil(cycle_time)
			assert.equal("Backlog", cycle_time.start_column)
			assert.equal(1000000, cycle_time.start_time)
		end)
	end)

	describe("calculate_stats integration", function()
		it("should calculate both lead time and cycle time for completed cards", function()
			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local progress_col = create_column("In Progress", { is_start_state = true })
			local done_col = create_column("Done", { is_completion_state = true })

			local card1 = create_card({
				backlog = 1000000,
				in_progress = 1086400,  -- 1 day later
				done = 1259200          -- 2 days from start, 3 from backlog
			})

			table.insert(done_col.tasks, card1)
			board.columns = { backlog_col, progress_col, done_col }

			local stats = board:calculate_stats()

			assert.equal(1, #stats.lead_times)
			assert.equal(1, #stats.cycle_times)

			-- Lead time: 3 days (backlog → done)
			assert.equal(259200, stats.lead_times[1].duration)

			-- Cycle time: 2 days (in_progress → done)
			assert.equal(172800, stats.cycle_times[1].duration)
		end)

		it("should calculate average lead time and cycle time in seconds", function()
			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local progress_col = create_column("In Progress", { is_start_state = true })
			local done_col = create_column("Done", { is_completion_state = true })

			local card1 = create_card({
				backlog = 1000000,
				in_progress = 1086400,
				done = 1172800  -- 2 days lead, 1 day cycle
			})

			local card2 = create_card({
				backlog = 1000000,
				in_progress = 1172800,
				done = 1345600  -- 4 days lead, 2 days cycle
			})

			table.insert(done_col.tasks, card1)
			table.insert(done_col.tasks, card2)
			board.columns = { backlog_col, progress_col, done_col }

			local stats = board:calculate_stats()

			-- Average lead time: (172800 + 345600) / 2 = 259200 seconds (3 days)
			assert.equal(259200, stats.average_lead_time)

			-- Average cycle time: (86400 + 172800) / 2 = 129600 seconds (1.5 days)
			assert.equal(129600, stats.average_cycle_time)
		end)

		it("should calculate average blocked time in seconds", function()
			local progress_col = create_column("In Progress", { is_start_state = true })
			local blocked_col = create_column("Blocked", { is_blocked_state = true })
			local done_col = create_column("Done", { is_completion_state = true })

			local card1 = create_card({
				in_progress = 1000000,
				blocked = 1086400,  -- 1 day active
				done = 1172800      -- 1 day blocked, total 2 days
			})

			local card2 = create_card({
				in_progress = 1000000,
				done = 1172800      -- 2 days active, 0 blocked
			})

			table.insert(done_col.tasks, card1)
			table.insert(done_col.tasks, card2)
			board.columns = { progress_col, blocked_col, done_col }

			local stats = board:calculate_stats()

			-- Average blocked time: (86400 + 0) / 2 = 43200 seconds (0.5 days)
			assert.equal(43200, stats.average_blocked_time)

			-- Average active time: (86400 + 172800) / 2 = 129600 seconds (1.5 days)
			assert.equal(129600, stats.average_active_time)
		end)
	end)

	describe("normalize_column_name", function()
		it("should normalize column names to snake_case timestamp keys", function()
			local stats = require("kanban-md.stats")

			assert.equal("in_progress", stats._private.normalize_column_name("In Progress"))
			assert.equal("waiting_for_review", stats._private.normalize_column_name("Waiting for Review"))
			assert.equal("done", stats._private.normalize_column_name("Done"))
			assert.equal("code_review", stats._private.normalize_column_name("Code Review"))
		end)
	end)
end)

describe("Stats - non-numeric complexity", function()
  it("counts a complexity that is not a number as zero", function()
    local board = Board:new()
    board:parse(table.concat({
      "# Odd Board",
      "",
      "###### To Do",
      "- Numeric <!-- complexity: 3 -->",
      "- Nonsense <!-- complexity: not a number -->",
      "",
    }, "\n"))

    assert.are.equal(3, board.stats.total_complexity)
    assert.are.equal(2, board.stats.total_tasks)
  end)
end)
