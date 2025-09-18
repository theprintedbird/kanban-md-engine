-- lua/user/kanban-md/writer.lua
-- Writer for Markdown Kanban boards - converts data structure back to markdown

local M = {}

-- Dependencies
local config_module = require("kanban-md.config")
local helpers = require("kanban-md.helpers")
local triggers_module = require("kanban-md.actions.triggers")
local checker = require("kanban-md.actions.checker")
local add_timestamp = function(task)
	-- Normalize column name to valid property name
	local normalize_column_name = function(column_name)
		-- Special case for archive
		if column_name == "__ARCHIVE__" then
			return "archived"
		end

		-- Convert to lowercase and replace spaces/special chars with underscores
		return column_name:lower():gsub("[^%w_]", "_")
	end
	-- Add timestamp for the target column (always add, allowing multiple visits)
	local timestamp_key = normalize_column_name(task.column)
	task.properties[timestamp_key] = os.time()
	return task
end

triggers_module.register_trigger("card_moved", "add_timestamp", add_timestamp)
triggers_module.register_trigger("card_created", "add_timestamp", add_timestamp)


-- Set configuration (deprecated - use config_module.setup instead)
function M.setup(opts)
	-- For backward compatibility, pass to config module
	if opts then
		config_module.setup(opts)
	end
end

-- Format a timestamp based on config
local function format_timestamp(timestamp)
	if not timestamp then return nil end

	local config = config_module.get()
	if config.timestamp_format == "iso" then
		return os.date("!%Y-%m-%dT%H:%M:%SZ", timestamp)
	elseif config.timestamp_format == "date" then
		return os.date("%Y-%m-%d", timestamp)
	else
		-- epoch (default)
		return tostring(timestamp)
	end
end

-- Format a property value for output
local function format_property_value(value)
	if type(value) == "boolean" then
		return tostring(value)
	elseif type(value) == "number" then
		-- Check if it might be a timestamp (roughly after year 2000)
		if value > 946684800 and value < 2147483647 then
			return format_timestamp(value)
		else
			return tostring(value)
		end
	elseif type(value) == "table" then
		-- Array notation
		local items = {}
		for _, item in ipairs(value) do
			table.insert(items, tostring(item))
		end
		return "[" .. table.concat(items, ", ") .. "]"
	else
		-- String
		return tostring(value)
	end
end

-- Convert properties to comment string
local function properties_to_comment(properties, prefix)
	if not properties or vim.tbl_isempty(properties) then
		return nil
	end

	local parts = {}

	-- Add prefix if provided (e.g., "kanban:config" or "column:config")
	if prefix then
		table.insert(parts, prefix)
	end

	-- Sort properties for consistent output
	local keys = vim.tbl_keys(properties)
	table.sort(keys)

	for _, key in ipairs(keys) do
		local value = properties[key]
		local formatted = format_property_value(value)
		if formatted then
			table.insert(parts, string.format("%s: %s", key, formatted))
		end
	end

	local config = config_module.get()
	local content = table.concat(parts, config.property_separator)

	-- Decide on single-line vs multi-line comment
	if config.use_multiline_comments and #content > config.multiline_threshold then
		-- Multi-line comment
		local lines = {}
		table.insert(lines, "<!-- " .. parts[1])
		for i = 2, #parts do
			table.insert(lines, parts[i])
		end
		table.insert(lines, "-->")
		return lines
	else
		-- Single-line comment
		return "<!-- " .. content .. " -->"
	end
end

-- Write a task line
local function write_task(task, column_name)
	local config = config_module.get()
	-- Simple list item (no checkboxes)
	local line = string.format("%s- %s", config.task_indent, task.text)

	-- Add properties as inline comment if present
	local props_to_write = {}

	-- Filter out certain properties that might be internal
	local skip_properties = { "id" }  -- We might want to keep ID actually

	for key, value in pairs(task.properties or {}) do
		local should_skip = false
		for _, skip in ipairs(skip_properties) do
			if key == skip then
				should_skip = true
				break
			end
		end

		if not should_skip then
			props_to_write[key] = value
		else
			-- Actually, let's keep ID too
			props_to_write[key] = value
		end
	end

	local comment = properties_to_comment(props_to_write)
	if comment then
		if type(comment) == "table" then
			-- Multi-line comment (rare for tasks)
			return { line .. " " .. comment[1], unpack(comment, 2) }
		else
			-- Single-line comment
			return line .. " " .. comment
		end
	end

	return line
end

-- Write a column section
local function write_column(column)
	local lines = {}

	-- Column header
	table.insert(lines, "## " .. column.name)

	-- Column configuration comment if present
	if column.config and not vim.tbl_isempty(column.config) then
		local config_comment = properties_to_comment(column.config, "column:config")
		if type(config_comment) == "table" then
			for _, line in ipairs(config_comment) do
				table.insert(lines, line)
			end
		else
			table.insert(lines, config_comment)
		end
	end

	-- Tasks
	for _, task in ipairs(column.tasks or {}) do
		local task_output = write_task(task, column.name)
		if type(task_output) == "table" then
			for _, line in ipairs(task_output) do
				table.insert(lines, line)
			end
		else
			table.insert(lines, task_output)
		end
	end

	return lines
end

-- Main writer function
function M.write(board)
	local config = config_module.get()
	local lines = {}

	-- Board title
	table.insert(lines, "# " .. (board.title or "Untitled Board"))

	if config.blank_line_after_title then
		table.insert(lines, "")
	end

	-- Board configuration
	if board.config and not vim.tbl_isempty(board.config) then
		local config_comment = properties_to_comment(board.config, "kanban:config")
		if type(config_comment) == "table" then
			for _, line in ipairs(config_comment) do
				table.insert(lines, line)
			end
		else
			table.insert(lines, config_comment)
		end

		if config.blank_line_after_config then
			table.insert(lines, "")
		end
	end

	-- Add blank line before columns section if we have columns
	if board.columns and #board.columns > 0 and config.blank_lines_between_sections then
		table.insert(lines, "")
	end

	-- Regular columns
	for i, column in ipairs(board.columns or {}) do
		if i > 1 and config.blank_lines_between_sections then
			table.insert(lines, "")
		end

		local column_lines = write_column(column)
		for _, line in ipairs(column_lines) do
			table.insert(lines, line)
		end
	end

	-- Archive section
	if board.archive then
		if config.blank_lines_between_sections then
			table.insert(lines, "")
		end

		local archive_lines = write_column(board.archive)
		for _, line in ipairs(archive_lines) do
			table.insert(lines, line)
		end
	end

	-- Stats section (if needed - usually generated dynamically)
	if board.stats and board.include_stats_section then
		if config.blank_lines_between_sections then
			table.insert(lines, "")
		end

		table.insert(lines, "## __STATS__")
		table.insert(lines, string.format("<!-- generated: %s -->", os.date("%Y-%m-%d %H:%M:%S")))

		-- Write statistics as a comment block or markdown list
		if board.stats.total_tasks > 0 then
			table.insert(lines, string.format("- Total tasks: %d", board.stats.total_tasks))
			table.insert(lines, string.format("- Completed: %d", board.stats.completed_tasks))
			table.insert(lines, string.format("- In progress: %d", board.stats.in_progress_tasks))

			if board.stats.average_cycle_time then
				local unit = board.config.cycle_time_unit or "seconds"
				table.insert(lines, string.format("- Average cycle time: %.2f %s",
					board.stats.average_cycle_time, unit))
			end
		end
	end

	return lines
end

-- Write board to file
function M.write_to_file(board, filepath)
	local lines = M.write(board)
	local content = table.concat(lines, "\n")

	-- Write to file
	local file = io.open(filepath, "w")
	if not file then
		return false, "Could not open file for writing: " .. filepath
	end

	file:write(content)
	file:close()

	return true
end

-- Write board to buffer
function M.write_to_buffer(board, bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local lines = M.write(board)

	-- Save cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)

	-- Update buffer
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

	-- Try to restore cursor position intelligently
	local max_line = vim.api.nvim_buf_line_count(bufnr)
	if cursor[1] > max_line then
		cursor[1] = max_line
	end

	-- Restore cursor
	pcall(vim.api.nvim_win_set_cursor, 0, cursor)

	return true
end

-- Update a single task in place (minimal change)
function M.update_task_in_buffer(board, task_id, bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- Find the task in the board
	local parser = require("kanban-md.parser")
	local task, column = parser.find_task(board, task_id)

	if not task or not task.line_number then
		return false, "Task not found or missing line number"
	end

	-- Generate the updated task line
	local updated_line = write_task(task, column.name)

	if type(updated_line) == "table" then
		-- Multi-line (shouldn't happen often for tasks)
		vim.api.nvim_buf_set_lines(bufnr, task.line_number - 1, task.line_number, false, updated_line)
	else
		-- Single line (normal case)
		vim.api.nvim_buf_set_lines(bufnr, task.line_number - 1, task.line_number, false, { updated_line })
	end

	return true
end

-- Append a new task to a column
function M.append_task_to_column(board, column_name, task_text, properties)
	local column = nil

	-- Find the column
	for _, col in ipairs(board.columns) do
		if col.name == column_name then
			column = col
			break
		end
	end

	if not column then
		return nil, "Column not found: " .. column_name
	end

	-- Create the new task
	local new_task = {
		text = task_text,
		properties = properties or {},
		column = column_name,
	}

	-- Get configuration
	local config = config_module.get()

	-- Generate ID if enabled in config
	if config.auto_id then
		new_task = helpers.generate_id(new_task)
	end

	-- Add timestamp if enabled in config
	if config.auto_timestamp then
		triggers_module.call_trigger("card_created", "add_timestamp", new_task)
	end

	-- Add to column
	table.insert(column.tasks, new_task)

	return new_task
end


-- Move a task between columns
function M.move_task(board, task_id, target_column_name)
	local parser = require("kanban-md.parser")

	-- Find the task
	local task, source_column = parser.find_task(board, task_id)
	if not task then
		return false, "Task not found"
	end
	if not source_column then
		return false, "This task has no column, it is corrupted"
	end

	-- Find target column
	local target_column = parser.get_column(board, target_column_name)
	if not target_column then
		return false, "Target column not found"
	end

	-- Remove from source
	for i, t in ipairs(source_column.tasks) do
		if t.properties.id == task_id then
			table.remove(source_column.tasks, i)
			break
		end
	end

	-- Update task's column reference
	task.column = target_column_name

	-- TODO run all triggers
	triggers_module.call_trigger("card_moved", "add_timestamp", task)

	-- Add to target
	-- TODO make target_column an object so that triggers can be set on it
	table.insert(target_column.tasks, task)

	return true
end

-- Archive completed tasks
function M.archive_done_tasks(board, older_than_days)
	-- TODO create trigger and config setting for this
	older_than_days = older_than_days or 0
	local cutoff_time = os.time() - (older_than_days * 86400)

	-- Ensure archive exists
	if not board.archive then
		board.archive = {
			name = "__ARCHIVE__",
			tasks = {},
			config = {},
			is_archive = true,
		}
	end

	local archived_count = 0

	-- Check all columns for completed tasks
	for _, column in ipairs(board.columns) do
		local tasks_to_keep = {}

		for _, task in ipairs(column.tasks) do
			local should_archive = false

			-- Task is completed if in completion column or has done timestamp
			local is_completed = checker.is_completion_column(column, board) or task.properties.done

			if is_completed then
				if older_than_days > 0 then
					-- Check if old enough
					-- TODO generalise, using non "done" or "created"
					local done_time = task.properties.done or task.properties.created or 0
					if done_time < cutoff_time then
						should_archive = true
					end
				else
					-- Archive all completed tasks
					should_archive = true
				end
			end

			if should_archive then
				-- Add archived timestamp
				-- TODO replace with general timestamp update
				-- Update task's column reference
				task.column = "__ARCHIVE__"
				triggers_module.call_trigger("card_moved", "add_timestamp", task)
				-- TODO when columns get triggers, move trigger to there
				table.insert(board.archive.tasks, task)
				archived_count = archived_count + 1
			else
				table.insert(tasks_to_keep, task)
			end
		end

		column.tasks = tasks_to_keep
	end

	return archived_count
end
if _G._TEST then
  M._private = {
    config = config,
  }
end

return M
