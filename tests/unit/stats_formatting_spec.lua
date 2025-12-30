-- tests/unit/stats_formatting_spec.lua
-- Tests for human-friendly time duration formatting
require('polyfills.vim')

_G._TEST = true

local Board = require("kanban-md.board")
local config = require("kanban-md.config")

describe("Stats - Time Duration Formatting", function()
	local board

	before_each(function()
		-- Reset config to defaults
		config.reset()

		board = Board:new()
		board.config = {}
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

	describe("format_duration helper (via stats display)", function()
		it("should format durations in precise days format by default", function()
			config.setup({ stats_time_format = "precise", cycle_time_unit = "days" })

			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local done_col = create_column("Done", { is_completion_state = true })

			-- 2.5 days = 216000 seconds
			local card = create_card({
				backlog = 1000000,
				done = 1216000  -- 2 days 12 hours later
			})

			table.insert(done_col.tasks, card)
			board.columns = { backlog_col, done_col }

			local stats_obj = board:calculate_stats()
			local stats_module = require("kanban-md.stats")
			local lines = stats_module.format_stats_display(board)

			-- Find the average lead time line
			local lead_time_line = nil
			for _, line in ipairs(lines) do
				if line:match("Average lead time:") then
					lead_time_line = line
					break
				end
			end

			assert.is_not_nil(lead_time_line)
			-- Should show "2 days 12 hours" or similar
			assert.is_true(lead_time_line:match("2 days 12 hours") ~= nil or
			               lead_time_line:match("2 days") ~= nil)
		end)

		it("should format durations in decimal format", function()
			config.setup({ stats_time_format = "decimal", cycle_time_unit = "days" })

			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local done_col = create_column("Done", { is_completion_state = true })

			-- 2.5 days = 216000 seconds
			local card = create_card({
				backlog = 1000000,
				done = 1216000
			})

			table.insert(done_col.tasks, card)
			board.columns = { backlog_col, done_col }

			board:calculate_stats()
			local stats_module = require("kanban-md.stats")
			local lines = stats_module.format_stats_display(board)

			local lead_time_line = nil
			for _, line in ipairs(lines) do
				if line:match("Average lead time:") then
					lead_time_line = line
					break
				end
			end

			assert.is_not_nil(lead_time_line)
			-- Should show "2.5 days"
			assert.is_true(lead_time_line:match("2%.5 days") ~= nil)
		end)

		it("should format durations in compact format", function()
			config.setup({ stats_time_format = "compact", cycle_time_unit = "days" })

			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local done_col = create_column("Done", { is_completion_state = true })

			-- 2.5 days = 216000 seconds
			local card = create_card({
				backlog = 1000000,
				done = 1216000
			})

			table.insert(done_col.tasks, card)
			board.columns = { backlog_col, done_col }

			board:calculate_stats()
			local stats_module = require("kanban-md.stats")
			local lines = stats_module.format_stats_display(board)

			local lead_time_line = nil
			for _, line in ipairs(lines) do
				if line:match("Average lead time:") then
					lead_time_line = line
					break
				end
			end

			assert.is_not_nil(lead_time_line)
			-- Should show "2d 12h"
			assert.is_true(lead_time_line:match("2d 12h") ~= nil or
			               lead_time_line:match("2d") ~= nil)
		end)

		it("should format short durations (< 1 day) in hours and minutes", function()
			config.setup({ stats_time_format = "precise", cycle_time_unit = "days" })

			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local done_col = create_column("Done", { is_completion_state = true })

			-- 5.5 hours = 19800 seconds
			local card = create_card({
				backlog = 1000000,
				done = 1019800
			})

			table.insert(done_col.tasks, card)
			board.columns = { backlog_col, done_col }

			board:calculate_stats()
			local stats_module = require("kanban-md.stats")
			local lines = stats_module.format_stats_display(board)

			local lead_time_line = nil
			for _, line in ipairs(lines) do
				if line:match("Average lead time:") then
					lead_time_line = line
					break
				end
			end

			assert.is_not_nil(lead_time_line)
			-- Should show hours and minutes, not fractional days
			assert.is_true(lead_time_line:match("hours") ~= nil or
			               lead_time_line:match("mins") ~= nil or
			               lead_time_line:match("h") ~= nil)
		end)

		it("should format durations in hours unit", function()
			config.setup({ stats_time_format = "precise", cycle_time_unit = "hours" })

			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local done_col = create_column("Done", { is_completion_state = true })

			-- 5.5 hours = 19800 seconds
			local card = create_card({
				backlog = 1000000,
				done = 1019800
			})

			table.insert(done_col.tasks, card)
			board.columns = { backlog_col, done_col }

			board:calculate_stats()
			local stats_module = require("kanban-md.stats")
			local lines = stats_module.format_stats_display(board)

			local lead_time_line = nil
			for _, line in ipairs(lines) do
				if line:match("Average lead time:") then
					lead_time_line = line
					break
				end
			end

			assert.is_not_nil(lead_time_line)
			-- Should show "5 hours 30 mins"
			assert.is_true(lead_time_line:match("5 hours 30 mins") ~= nil)
		end)

		it("should handle seconds unit", function()
			config.setup({ stats_time_format = "precise", cycle_time_unit = "seconds" })

			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local done_col = create_column("Done", { is_completion_state = true })

			-- 3600 seconds = 1 hour
			local card = create_card({
				backlog = 1000000,
				done = 1003600
			})

			table.insert(done_col.tasks, card)
			board.columns = { backlog_col, done_col }

			board:calculate_stats()
			local stats_module = require("kanban-md.stats")
			local lines = stats_module.format_stats_display(board)

			local lead_time_line = nil
			for _, line in ipairs(lines) do
				if line:match("Average lead time:") then
					lead_time_line = line
					break
				end
			end

			assert.is_not_nil(lead_time_line)
			-- Should show "3600 seconds"
			assert.is_true(lead_time_line:match("3600 seconds") ~= nil)
		end)
	end)

	describe("stats calculation returns seconds (not converted)", function()
		it("should keep average times in seconds in stats object", function()
			config.setup({ cycle_time_unit = "days" })

			local backlog_col = create_column("Backlog", { is_backlog_state = true })
			local done_col = create_column("Done", { is_completion_state = true })

			-- 2 days = 172800 seconds
			local card = create_card({
				backlog = 1000000,
				done = 1172800
			})

			table.insert(done_col.tasks, card)
			board.columns = { backlog_col, done_col }

			local stats_obj = board:calculate_stats()

			-- Stats should be in seconds (172800), not days (2)
			assert.equal(172800, stats_obj.average_lead_time)
		end)
	end)

	describe("blocked time formatting", function()
		it("should format active and blocked time breakdown", function()
			config.setup({ stats_time_format = "precise", cycle_time_unit = "days" })

			local progress_col = create_column("In Progress", { is_start_state = true })
			local blocked_col = create_column("Blocked", { is_blocked_state = true })
			local done_col = create_column("Done", { is_completion_state = true })

			-- 3 days total: 1 day active, 2 days blocked
			local card = create_card({
				in_progress = 1000000,  -- Day 0
				blocked = 1086400,      -- Day 1 (enter blocked)
				done = 1259200          -- Day 3 (2 days blocked)
			})

			table.insert(done_col.tasks, card)
			board.columns = { progress_col, blocked_col, done_col }

			board:calculate_stats()
			local stats_module = require("kanban-md.stats")
			local lines = stats_module.format_stats_display(board)

			local active_line = nil
			local blocked_line = nil
			for _, line in ipairs(lines) do
				if line:match("Average active time:") then
					active_line = line
				end
				if line:match("Average blocked time:") then
					blocked_line = line
				end
			end

			assert.is_not_nil(active_line)
			assert.is_not_nil(blocked_line)

			-- Should show "1 day" for active
			assert.is_true(active_line:match("1 day") ~= nil)
			-- Should show "2 days" for blocked
			assert.is_true(blocked_line:match("2 days") ~= nil)
		end)
	end)
end)
