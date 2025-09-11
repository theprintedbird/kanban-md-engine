-- lua/user/kanban-md/parser.lua
-- Parser for Markdown Kanban boards

local M = {}

-- Patterns for parsing
local patterns = {
	-- Board title (# Title)
	board_title = "^#%s+(.+)$",

	-- Column header (## Column Name)
	column_header = "^##%s+(.+)$",

	-- Task item with checkbox
	task_incomplete = "^%s*%-%s*%[%s*%]%s*(.+)$",
	task_complete = "^%s*%-%s*%[x%]%s*(.+)$",
	task_complete_upper = "^%s*%-%s*%[X%]%s*(.+)$",

	-- HTML comment blocks
	comment_block_start = "^%s*<!%-%-%s*(.-)$",
	comment_block_end = "^(.-)%-%->%s*$",
	comment_single = "<!%-%-%s*(.-)%s*%-%->",

	-- Property patterns within comments
	property = "([%w_]+):%s*([^,]*%[[^%]]*%]|[^,]+)",

	-- Special sections
	archive_section = "^##%s+__ARCHIVE__",
	stats_section = "^##%s+__STATS__",
}

-- Convert ISO timestamp to epoch (Unix timestamp)
local function iso_to_epoch(iso_string)
	-- Parse ISO format: YYYY-MM-DDTHH:MM:SSZ
	local year, month, day, hour, min, sec = iso_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z")
	if not year then
		-- Try simple date format: YYYY-MM-DD
		year, month, day = iso_string:match("(%d+)-(%d+)-(%d+)")
		if not year then
			return nil -- Not a recognized format
		end
		hour, min, sec = 0, 0, 0 -- Default to start of day
	end
	
	-- Convert to numbers
	year, month, day = tonumber(year), tonumber(month), tonumber(day)
	hour, min, sec = tonumber(hour), tonumber(min), tonumber(sec)
	
	-- Manual calculation using POSIX formula for UTC time
	-- This avoids timezone issues with os.time()
	
	-- Days since Jan 1, 1970
	local function is_leap_year(y)
		return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
	end
	
	local days = 0
	for y = 1970, year - 1 do
		days = days + (is_leap_year(y) and 366 or 365)
	end
	
	local days_in_month = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	if is_leap_year(year) then
		days_in_month[2] = 29
	end
	
	for m = 1, month - 1 do
		days = days + days_in_month[m]
	end
	
	days = days + day - 1 -- day is 1-based
	
	-- Convert to seconds
	return days * 86400 + hour * 3600 + min * 60 + sec
end

-- Parse properties from a comment string
local function parse_properties(comment_text)
	local props = {}

	-- Remove HTML comment delimiters if present to centralize comment cleanup
	comment_text = comment_text:gsub("<!%-%-", ""):gsub("%-%-%-*>", ""):gsub("^%s+", ""):gsub("%s+$", "")

	-- Remove config prefixes (kanban:config, column:config) if present
	comment_text = comment_text:gsub("^%s*kanban:config%s*,?%s*", "")
	comment_text = comment_text:gsub("^%s*column:config%s*,?%s*", "")

	-- Custom parsing to handle arrays properly
	local pos = 1
	while pos <= #comment_text do
		-- Find next property key
		local key_start, key_end, key = comment_text:find("([%w_]+):%s*", pos)
		if not key_start then break end

		-- Find the value - handle arrays specially
		local value_start = key_end + 1
		local value_end = value_start
		local bracket_count = 0

		-- Scan for the end of the value, respecting brackets
		while value_end <= #comment_text do
			local char = comment_text:sub(value_end, value_end)
			if char == '[' then
				bracket_count = bracket_count + 1
			elseif char == ']' then
				bracket_count = bracket_count - 1
			elseif char == ',' and bracket_count == 0 then
				break
			end
			value_end = value_end + 1
		end

		-- Extract and clean the value
		local value = comment_text:sub(value_start, value_end - 1):gsub("^%s+", ""):gsub("%s+$", "")

		key = key:lower()

		-- Type conversion
		if value:match("^%d+$") then
			-- Integer (timestamps, numbers)
			props[key] = tonumber(value)
		elseif value:match("^%d+%.%d+$") then
			-- Float
			props[key] = tonumber(value)
		elseif value:match("^%d%d%d%d%-%d%d%-%d%d") then
			-- ISO timestamp (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ) - convert to epoch
			local epoch = iso_to_epoch(value)
			if epoch then
				props[key] = epoch
			else
				-- Fallback to string if parsing fails
				props[key] = value
			end
		elseif value:lower() == "true" then
			props[key] = true
		elseif value:lower() == "false" then
			props[key] = false
		elseif value:match("^%[.*%]$") then
			-- Array notation [item1, item2]
			local array = {}
			-- Remove the brackets and split by comma
			local array_content = value:sub(2, -2)  -- Remove [ and ]
			for element in array_content:gmatch("([^,]+)") do
				element = element:gsub("^%s+", ""):gsub("%s+$", "")
				table.insert(array, element)
			end
			props[key] = array
		else
			-- String
			props[key] = value
		end

		-- Move to next property
		pos = value_end + 1
	end

	return props
end

-- Parse a task line and extract properties
local function parse_task(line, is_complete)
	local task = {
		complete = is_complete,
		text = "",
		properties = {},
		raw = line,
	}

	-- Extract task text
	local text
	if is_complete then
		text = line:match(patterns.task_complete) or line:match(patterns.task_complete_upper)
	else
		text = line:match(patterns.task_incomplete)
	end

	if not text then
		return nil
	end

	-- Check for inline comment with properties
	-- e.g. - [ ] Complex task <!-- created: 1735862400, started: 1735948800, complexity: 3 -->
	local task_text, comment = text:match("^(.-)%s*<!%-%-%s*(.-)%s*%-%->%s*$")

	if task_text and comment then
		task.text = task_text:gsub("^%s+", ""):gsub("%s+$", "")
		task.properties = parse_properties(comment)
	else
		task.text = text:gsub("^%s+", ""):gsub("%s+$", "")
	end

	-- Generate ID if not present
	if not task.properties.id then
		-- Simple ID generation based on text hash and timestamp
		local id_source = task.text .. os.time()
		local hash = 0
		for i = 1, #id_source do
			hash = (hash * 31 + string.byte(id_source, i)) % 0x100000000
		end
		task.properties.id = string.format("%08x", hash)
	end

	return task
end

local function split_content_to_lines(content)
	local lines
	if type(content) == "string" then
		lines = vim.split(content, "\n")
	elseif type(content) == "table" then
		lines = content
	else
		return nil, "Invalid content type"
	end
	return lines
end

-- Main parser function
function M.parse(content)
	local board = {
		title = "Untitled Board",
		config = {},
		columns = {},
		archive = nil,
		stats = {},
		raw_lines = {},
	}

	local lines = split_content_to_lines(content)

	board.raw_lines = lines

	local current_column = nil
	local in_comment_block = false
	local comment_buffer = ""
	local line_number = 0
	local pending_config = nil
	local config_type = nil  -- "board" or "column"

	if lines ~= nil then
		for _, line in ipairs(lines) do
			line_number = line_number + 1

			-- Handle multi-line comment blocks
			if in_comment_block then
				local ending = line:match(patterns.comment_block_end)
				if ending then
					comment_buffer = comment_buffer .. " " .. ending
					in_comment_block = false

					-- Process the complete comment
					if config_type == "board" and comment_buffer:match("kanban:config") then
						local config_content = comment_buffer:match("^%s*kanban:config%s*,?%s*(.*)")
						if config_content and config_content ~= "" then
								board.config = parse_properties(config_content)
						end
					-- e.g. <!-- column:config wip_limit: 3 -->"
					elseif config_type == "column" and comment_buffer:match("column:config") then
						local config_content = comment_buffer:match("^%s*column:config%s*,?%s*(.*)")
						if current_column then
							current_column.config = parse_properties(config_content)
						end
					elseif current_column and pending_config then
						-- This is task properties
						pending_config.properties = parse_properties(comment_buffer)
					end

					comment_buffer = ""
					config_type = nil
					pending_config = nil
				else
					comment_buffer = comment_buffer .. " " .. line
				end
			-- Check for comment block start
			elseif line:match(patterns.comment_block_start) then
				local comment_start = line:match(patterns.comment_block_start)

				-- Check if it's a single-line comment
				if line:match(patterns.comment_single) then
					local comment_content = line:match(patterns.comment_single)

					if comment_content:match("kanban:config") then
						local config_content = comment_content:match("^%s*kanban:config%s*,?%s*(.*)")
						if config_content and config_content ~= "" then
							board.config = parse_properties(config_content)
						end
					elseif comment_content:match("column:config") and current_column then
						local config_content = comment_content:match("^%s*column:config%s*,?%s*(.*)")
						if current_column and config_content and config_content ~= "" then
							current_column.config = parse_properties(config_content)
						end
					elseif current_column then
						-- Could be task-related, store for next task
						pending_config = { properties = parse_properties(comment_content) }
					end
				else
					-- Multi-line comment
					in_comment_block = true
					comment_buffer = comment_start

					-- Determine config type
					if comment_start:match("kanban:config") then
						config_type = "board"
					elseif comment_start:match("column:config") then
						config_type = "column"
					else
						config_type = "task"
					end
				end
			-- Parse board title
			elseif line:match(patterns.board_title) then
				board.title = line:match(patterns.board_title)
			-- Parse archive section
			elseif line:match(patterns.archive_section) then
				current_column = {
					name = "__ARCHIVE__",
					tasks = {},
					config = {},
					is_archive = true,
					line_number = line_number,
				}
				board.archive = current_column
			-- Parse stats section
			elseif line:match(patterns.stats_section) then
				current_column = {
					name = "__STATS__",
					is_stats = true,
					line_number = line_number,
				}
			-- Parse column headers
			elseif line:match(patterns.column_header) then
				local column_name = line:match(patterns.column_header)

				if not column_name:match("^__") then  -- Regular column
					current_column = {
						name = column_name,
						tasks = {},
						config = {},
						line_number = line_number,
					}
					table.insert(board.columns, current_column)
				end
			-- Parse tasks
			elseif current_column and not current_column.is_stats then
				local task = nil

				-- Check for incomplete task
				if line:match(patterns.task_incomplete) then
					task = parse_task(line, false)
				-- Check for complete task
				elseif line:match(patterns.task_complete) or line:match(patterns.task_complete_upper) then
					task = parse_task(line, true)
				end

				if task then
					task.line_number = line_number
					task.column = current_column.name

					-- Apply pending config if any
					if pending_config then
						for k, v in pairs(pending_config.properties) do
							task.properties[k] = v
						end
						pending_config = nil
					end

					table.insert(current_column.tasks, task)
				end
			end
		end
	end

	-- Post-processing
	M.calculate_stats(board)
	M.validate_board(board)

	return board
end

-- Calculate board statistics
function M.calculate_stats(board)
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
	for _, column in ipairs(board.columns) do
		local wip_count = 0

		for _, task in ipairs(column.tasks) do
			stats.total_tasks = stats.total_tasks + 1

			if not task.complete then
				wip_count = wip_count + 1
				stats.in_progress_tasks = stats.in_progress_tasks + 1
			end

			if task.complete then
				stats.completed_tasks = stats.completed_tasks + 1

				-- Calculate cycle time if timestamps exist
				if task.properties.created and task.properties.done then
					local cycle_time = task.properties.done - task.properties.created
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
	if board.archive then
		for _, task in ipairs(board.archive.tasks) do
			stats.total_tasks = stats.total_tasks + 1
			stats.completed_tasks = stats.completed_tasks + 1

			if task.properties.created and task.properties.done then
				local cycle_time = task.properties.done - task.properties.created
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
		if board.config.cycle_time_unit == "days" then
			stats.average_cycle_time = stats.average_cycle_time / 86400
		elseif board.config.cycle_time_unit == "hours" then
			stats.average_cycle_time = stats.average_cycle_time / 3600
		end
	end

	board.stats = stats
end

-- Check for duplicate task IDs in a task list
local function check_tasks_for_duplicates(tasks, location, seen_ids, validation)
	for _, task in ipairs(tasks) do
		local id = task.properties.id
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
	function M.validate_board(board)
		board.validation = {
			valid = true,
			warnings = {},
			errors = {},
		}

		-- Check board-level WIP limit
		if board.config and board.config.wip_limit then
			local total_wip = 0
			for _, count in pairs(board.stats.wip_by_column) do
				total_wip = total_wip + count
			end

			if total_wip > board.config.wip_limit then
				table.insert(board.validation.warnings,
					string.format("Board WIP limit exceeded: %d/%d", total_wip, board.config.wip_limit))
				board.validation.valid = false  -- Set to false when limits exceeded
			end
		end

		-- Check column-level WIP limits
		for _, column in ipairs(board.columns) do
			if column.config and column.config.wip_limit then
				local wip = board.stats.wip_by_column[column.name] or 0
				if wip > column.config.wip_limit then
					table.insert(board.validation.warnings,
						string.format("Column '%s' WIP limit exceeded: %d/%d",
								column.name, wip, column.config.wip_limit))
					board.validation.valid = false  -- Set to false when limits exceeded
				end
			end
		end

		-- Check for duplicate task IDs
		local seen_ids = {}

		for _, column in ipairs(board.columns) do
			check_tasks_for_duplicates(column.tasks, column.name, seen_ids, board.validation)
		end

		if board.archive then
			check_tasks_for_duplicates(board.archive.tasks, "__ARCHIVE__", seen_ids, board.validation)
		end

		return board.validation.valid
	end

-- Find a task by ID
function M.find_task(board, task_id)
	-- Search regular columns
	for _, column in ipairs(board.columns) do
		for _, task in ipairs(column.tasks) do
			if task.properties.id == task_id then
				return task, column
			end
		end
	end

	-- Search archive
	if board.archive then
		for _, task in ipairs(board.archive.tasks) do
			if task.properties.id == task_id then
				return task, board.archive
			end
		end
	end

	return nil, nil
end

-- Get column by name
function M.get_column(board, column_name)
	for _, column in ipairs(board.columns) do
		if column.name == column_name then
			return column
		end
	end

	if board.archive and column_name == "__ARCHIVE__" then
		return board.archive
	end

	return nil
end

-- For testing, conditionally export private functions
if _G._TEST then
  M._private = {
    parse_properties = parse_properties,
		split_content_to_lines = split_content_to_lines,
		check_tasks_for_duplicates = check_tasks_for_duplicates
  }
end

return M
