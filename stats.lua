-- lua/kanban-md/stats.lua
-- Statistics calculation mixin for Board class

local column_helpers = require("kanban-md.helpers.column")

-- Stats mixin that can be applied to Board instances
local StatsMixin = {}

-- Helper: normalize column name to timestamp key format
local function normalize_column_name(column_name)
	return column_name:lower():gsub("[^%w_]", "_")
end

-- Helper: find column by name
local function find_column_by_name(board, column_name)
	for _, column in ipairs(board.columns) do
		if column.name == column_name then
			return column
		end
	end
	return nil
end

-- Helper: find earliest timestamp from columns matching a predicate
-- @param task_properties table: Task properties containing timestamp fields
-- @param board table: Board object
-- @param predicate function: Function(column, board) that returns true for matching columns
-- @return number|nil, string|nil: Earliest timestamp value and column name, or nil
local function find_earliest_timestamp_for_columns(task_properties, board, predicate)
	local earliest_timestamp = nil
	local earliest_column = nil

	for _, column in ipairs(board.columns) do
		if predicate(column, board) then
			local timestamp_key = normalize_column_name(column.name)
			local timestamp = task_properties[timestamp_key]

			if timestamp and (not earliest_timestamp or timestamp < earliest_timestamp) then
				earliest_timestamp = timestamp
				earliest_column = column.name
			end
		end
	end

	return earliest_timestamp, earliest_column
end

-- Helper: find completion timestamp
-- @param task_properties table: Task properties containing timestamp fields
-- @param board table: Board object
-- @return number|nil, string|nil: Completion timestamp and column name, or nil
local function find_completion_timestamp(task_properties, board)
	-- First check archive
	if task_properties.archived then
		return task_properties.archived, "__ARCHIVE__"
	end

	-- Find latest timestamp from completion columns
	return find_earliest_timestamp_for_columns(task_properties, board, column_helpers.is_completion_column)
end

-- Helper: find backlog timestamp (earliest backlog state)
-- @param task_properties table: Task properties containing timestamp fields
-- @param board table: Board object
-- @return number|nil, string|nil: Backlog timestamp and column name, or nil
local function find_backlog_timestamp(task_properties, board)
	local backlog_timestamp, backlog_column = find_earliest_timestamp_for_columns(
		task_properties, board, column_helpers.is_backlog_column
	)

	return backlog_timestamp, backlog_column
end

-- Helper: find start state timestamp
-- @param task_properties table: Task properties containing timestamp fields
-- @param board table: Board object
-- @return number|nil, string|nil: Start timestamp and column name, or nil
local function find_start_state_timestamp(task_properties, board)
	return find_earliest_timestamp_for_columns(task_properties, board, column_helpers.is_start_column)
end

-- Helper: calculate total blocked/waiting time
-- @param task_properties table: Task properties containing timestamp fields
-- @param board table: Board object
-- @return number: Total blocked/waiting time in seconds
local function calculate_blocked_time(task_properties, board)
	local total_blocked = 0

	-- Collect all timestamps chronologically with their column info
	local timeline = {}

	for _, column in ipairs(board.columns) do
		local timestamp_key = normalize_column_name(column.name)
		local timestamp = task_properties[timestamp_key]

		if timestamp then
			table.insert(timeline, {
				timestamp = timestamp,
				column = column,
				is_blocked = column_helpers.is_blocked_column(column, board),
				is_waiting = column_helpers.is_waiting_column(column, board)
			})
		end
	end

	-- Sort chronologically
	table.sort(timeline, function(a, b) return a.timestamp < b.timestamp end)

	-- Calculate time spent in blocked/waiting states
	for i = 1, #timeline - 1 do
		local current = timeline[i]
		local next = timeline[i + 1]

		if current.is_blocked or current.is_waiting then
			total_blocked = total_blocked + (next.timestamp - current.timestamp)
		end
	end

	return total_blocked
end

-- Calculate lead time (from backlog or creation to completion)
-- @param task_properties table: Task properties containing timestamp fields
-- @param board table: Board object
-- @return table|nil: Lead time data {duration, start_time, start_column, end_time, end_column}, or nil
local function calculate_lead_time(task_properties, board)
	local start_time, start_column = find_backlog_timestamp(task_properties, board)
	local end_time, end_column = find_completion_timestamp(task_properties, board)

	if not start_time or not end_time then
		return nil
	end

	return {
		duration = end_time - start_time,
		start_time = start_time,
		start_column = start_column,
		end_time = end_time,
		end_column = end_column
	}
end

-- Calculate cycle time (from start state to completion)
-- @param task_properties table: Task properties containing timestamp fields
-- @param board table: Board object
-- @return table|nil: Cycle time data {duration, start_time, start_column, end_time, end_column, blocked_time, active_time}, or nil
local function calculate_cycle_time(task_properties, board)
	local start_time, start_column = find_start_state_timestamp(task_properties, board)
	local end_time, end_column = find_completion_timestamp(task_properties, board)

	if not start_time or not end_time then
		return nil
	end

	local total_duration = end_time - start_time
	local blocked_time = calculate_blocked_time(task_properties, board)
	local active_time = total_duration - blocked_time

	return {
		duration = total_duration,
		start_time = start_time,
		start_column = start_column,
		end_time = end_time,
		end_column = end_column,
		blocked_time = blocked_time,
		active_time = active_time
	}
end

-- Calculate comprehensive board statistics
function StatsMixin:calculate_stats()
	local stats = {
		total_tasks = 0,
		completed_tasks = 0,
		in_progress_tasks = 0,
		blocked_tasks = 0,
		total_complexity = 0,
		wip_by_column = {},
		lead_times = {},
		cycle_times = {},
	}

	-- Process regular columns
	for _, column in ipairs(self.columns) do
		local wip_count = 0
		local tasks = column.tasks or column.cards or {}

		for _, task in ipairs(tasks) do
			stats.total_tasks = stats.total_tasks + 1

			-- Task is completed if in completion column
			local is_completed = column_helpers.is_completion_column(column, self)

			if not is_completed then
				wip_count = wip_count + 1
				stats.in_progress_tasks = stats.in_progress_tasks + 1
			end

			if is_completed then
				stats.completed_tasks = stats.completed_tasks + 1

				-- Calculate lead time and cycle time for completed tasks
				local lead_time = calculate_lead_time(task.properties, self)
				if lead_time then
					table.insert(stats.lead_times, lead_time)
				end

				local cycle_time = calculate_cycle_time(task.properties, self)
				if cycle_time then
					table.insert(stats.cycle_times, cycle_time)
				end
			end

			if task.properties.blocked then
				stats.blocked_tasks = stats.blocked_tasks + 1
			end

			if task.properties.complexity then
				stats.total_complexity = stats.total_complexity + task.properties.complexity
			end
		end

		stats.wip_by_column[column.name] = wip_count
	end

	-- Process archive
	if self.archive then
		local archive_tasks = self.archive.tasks or self.archive.cards or {}
		for _, task in ipairs(archive_tasks) do
			stats.total_tasks = stats.total_tasks + 1
			stats.completed_tasks = stats.completed_tasks + 1

			local lead_time = calculate_lead_time(task.properties, self)
			if lead_time then
				table.insert(stats.lead_times, lead_time)
			end

			local cycle_time = calculate_cycle_time(task.properties, self)
			if cycle_time then
				table.insert(stats.cycle_times, cycle_time)
			end
		end
	end

	-- Calculate average lead time
	if #stats.lead_times > 0 then
		local sum = 0
		for _, time_data in ipairs(stats.lead_times) do
			sum = sum + time_data.duration
		end
		stats.average_lead_time = sum / #stats.lead_times

		-- Convert to days if needed
		if self.config.cycle_time_unit == "days" then
			stats.average_lead_time = stats.average_lead_time / 86400
		elseif self.config.cycle_time_unit == "hours" then
			stats.average_lead_time = stats.average_lead_time / 3600
		end
	end

	-- Calculate average cycle time
	if #stats.cycle_times > 0 then
		local sum = 0
		local blocked_sum = 0
		local active_sum = 0
		for _, time_data in ipairs(stats.cycle_times) do
			sum = sum + time_data.duration
			blocked_sum = blocked_sum + time_data.blocked_time
			active_sum = active_sum + time_data.active_time
		end
		stats.average_cycle_time = sum / #stats.cycle_times
		stats.average_blocked_time = blocked_sum / #stats.cycle_times
		stats.average_active_time = active_sum / #stats.cycle_times

		-- Convert to days if needed
		if self.config.cycle_time_unit == "days" then
			stats.average_cycle_time = stats.average_cycle_time / 86400
			stats.average_blocked_time = stats.average_blocked_time / 86400
			stats.average_active_time = stats.average_active_time / 86400
		elseif self.config.cycle_time_unit == "hours" then
			stats.average_cycle_time = stats.average_cycle_time / 3600
			stats.average_blocked_time = stats.average_blocked_time / 3600
			stats.average_active_time = stats.average_active_time / 3600
		end
	end

	-- Store stats on the board instance
	self.stats = stats
	return stats
end

-- Check for duplicate task IDs in a task list (helper function)
local function check_tasks_for_duplicates(tasks, location, seen_ids, validation)
	for _, task in ipairs(tasks) do
		local id = task.properties and task.properties.id
		if id then
			if seen_ids[id] then
				table.insert(validation.errors,
					string.format("Duplicate task ID '%s' in %s", id, location))
				validation.valid = false
			end
			seen_ids[id] = true
		end
	end
end

-- Validate board structure and WIP limits
function StatsMixin:validate()
	self.validation = {
		valid = true,
		warnings = {},
		errors = {},
	}

	-- Ensure stats are calculated
	if not self.stats then
		self:calculate_stats()
	end

	-- Check board-level WIP limit
	if self.config and self.config.wip_limit then
		local total_wip = 0
		for _, count in pairs(self.stats.wip_by_column) do
			total_wip = total_wip + count
		end

		if total_wip > self.config.wip_limit then
			table.insert(self.validation.warnings,
				string.format("Board WIP limit exceeded: %d/%d", total_wip, self.config.wip_limit))
			self.validation.valid = false  -- Set to false when limits exceeded
		end
	end

	-- Check column-level WIP limits
	for _, column in ipairs(self.columns) do
		if column.config and column.config.wip_limit then
			local wip = self.stats.wip_by_column[column.name] or 0
			if wip > column.config.wip_limit then
				table.insert(self.validation.warnings,
					string.format("Column '%s' WIP limit exceeded: %d/%d",
							column.name, wip, column.config.wip_limit))
				self.validation.valid = false  -- Set to false when limits exceeded
			end
		end
	end

	-- Check for duplicate task IDs
	local seen_ids = {}

	for _, column in ipairs(self.columns) do
		local tasks = column.tasks or column.cards or {}
		check_tasks_for_duplicates(tasks, column.name, seen_ids, self.validation)
	end

	if self.archive then
		local archive_tasks = self.archive.tasks or self.archive.cards or {}
		check_tasks_for_duplicates(archive_tasks, "__ARCHIVE__", seen_ids, self.validation)
	end

	return self.validation.valid
end

-- Format stats into human-readable text output
-- @param board table: Board object with calculated stats
-- @return table: Array of formatted text lines
local function format_stats_display(board)
	local stats = board.stats
	if not stats then
		return {"No statistics available"}
	end

	local lines = {
		"=== Kanban Board Statistics ===",
		"",
		"Total tasks: " .. stats.total_tasks,
		"Completed tasks: " .. stats.completed_tasks,
		"In progress tasks: " .. stats.in_progress_tasks,
		"Blocked tasks: " .. stats.blocked_tasks,
		"Total complexity: " .. stats.total_complexity,
		""
	}

	-- WIP by column
	table.insert(lines, "WIP by column:")
	for col_name, wip_count in pairs(stats.wip_by_column) do
		table.insert(lines, "  " .. col_name .. ": " .. wip_count)
	end

	-- Lead time info
	if stats.average_lead_time then
		table.insert(lines, "")
		local unit = board.config.cycle_time_unit or "days"
		table.insert(lines, "Average lead time: " .. string.format("%.1f", stats.average_lead_time) .. " " .. unit)
		table.insert(lines, "Completed tasks with lead time: " .. #stats.lead_times)
	else
		-- Show why lead time isn't available
		if stats.completed_tasks > 0 and #stats.lead_times == 0 then
			table.insert(lines, "")
			table.insert(lines, "Lead time: N/A (completed cards missing backlog timestamps)")
		end
	end

	-- Cycle time info
	if stats.average_cycle_time then
		table.insert(lines, "")
		local unit = board.config.cycle_time_unit or "days"
		table.insert(lines, "Average cycle time: " .. string.format("%.1f", stats.average_cycle_time) .. " " .. unit)

		-- Show blocked/active time breakdown if available
		if stats.average_blocked_time and stats.average_blocked_time > 0 then
			table.insert(lines, "  - Average active time: " .. string.format("%.1f", stats.average_active_time) .. " " .. unit)
			table.insert(lines, "  - Average blocked time: " .. string.format("%.1f", stats.average_blocked_time) .. " " .. unit)
		end

		table.insert(lines, "Completed tasks with cycle time: " .. #stats.cycle_times)
	end

	return lines
end

-- Export calculation and formatting functions for use by virtual_text and other modules
StatsMixin.calculate_lead_time = calculate_lead_time
StatsMixin.calculate_cycle_time = calculate_cycle_time
StatsMixin.calculate_blocked_time = calculate_blocked_time
StatsMixin.format_stats_display = format_stats_display

-- For testing, conditionally export additional private functions
if _G._TEST then
	StatsMixin._private = {
		check_tasks_for_duplicates = check_tasks_for_duplicates,
		calculate_lead_time = calculate_lead_time,
		calculate_cycle_time = calculate_cycle_time,
		calculate_blocked_time = calculate_blocked_time,
		find_backlog_timestamp = find_backlog_timestamp,
		find_start_state_timestamp = find_start_state_timestamp,
		find_completion_timestamp = find_completion_timestamp,
		normalize_column_name = normalize_column_name
	}
end

return StatsMixin