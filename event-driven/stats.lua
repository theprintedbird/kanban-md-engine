-- lua/kanban-md/event-driven/stats.lua
-- Statistics calculation mixin for Board class

local checker = require("kanban-md.actions.checker")
local stats_utils = require("kanban-md.stats")

-- Stats mixin that can be applied to Board instances
local StatsMixin = {}

-- Calculate comprehensive board statistics
function StatsMixin:calculate_stats()
	local stats = {
		total_tasks = 0,
		completed_tasks = 0,
		in_progress_tasks = 0,
		blocked_tasks = 0,
		total_complexity = 0,
		wip_by_column = {},
		cycle_times = {},
	}

	-- Process regular columns
	for _, column in ipairs(self.columns) do
		local wip_count = 0
		local tasks = column.tasks or column.cards or {}

		for _, task in ipairs(tasks) do
			stats.total_tasks = stats.total_tasks + 1

			-- Task is completed if in completion column
			local is_completed = checker.is_completion_column(column, self)

			if not is_completed then
				wip_count = wip_count + 1
				stats.in_progress_tasks = stats.in_progress_tasks + 1
			end

			if is_completed then
				stats.completed_tasks = stats.completed_tasks + 1

				-- Calculate cycle time if timestamps exist
				local cycle_time = stats_utils.calculate_cycle_time(task.properties)
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

			local cycle_time = stats_utils.calculate_cycle_time(task.properties)
			if cycle_time then
				table.insert(stats.cycle_times, cycle_time)
			end
		end
	end

	-- Calculate average cycle time
	if #stats.cycle_times > 0 then
		local sum = 0
		for _, time in ipairs(stats.cycle_times) do
			sum = sum + time
		end
		stats.average_cycle_time = sum / #stats.cycle_times

		-- Convert to days if needed
		if self.config.cycle_time_unit == "days" then
			stats.average_cycle_time = stats.average_cycle_time / 86400
		elseif self.config.cycle_time_unit == "hours" then
			stats.average_cycle_time = stats.average_cycle_time / 3600
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

-- For testing, conditionally export private functions
if _G._TEST then
	StatsMixin._private = {
		check_tasks_for_duplicates = check_tasks_for_duplicates
	}
end

return StatsMixin