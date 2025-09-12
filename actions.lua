
-- Additional Triggers:

-- Reorder within column
-- function card_prioritised()
-- end

-- Add/update complexity
-- function card_estimated()
-- end

-- Add tags for filtering
-- function card_tagged()
-- end

-- lua/kanban-md/actions.lua
-- User actions for Kanban board manipulation

local M = {}

-- Dependencies
local parser = require("kanban-md.parser")
local writer = require("kanban-md.writer")
local checker = require("kanban-md.actions.checker")
local config_module = require("kanban-md.config")

-- Local state
local last_board = nil
local undo_stack = {}
local undo_limit = 50

-- Helper to get config
local function get_config()
	return config_module.get()
end

-- Setup function (deprecated - use config_module.setup instead)
function M.setup(opts)
	-- For backward compatibility, pass to config module
	if opts then
		config_module.setup(opts)
	end
end

-- Helper function to derive column flow from board structure
local function get_column_flow(board)
	local flow = {}

	-- Add all regular columns in order
	for _, column in ipairs(board.columns) do
		table.insert(flow, column.name)
	end

	-- Archive is always last if it exists
	if board.archive then
		table.insert(flow, "__ARCHIVE__")
	end

	return flow
end

-- Helper: Get current board from buffer
local function get_current_board(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	return parser.parse(lines)
end

-- Helper: Save board state for undo
local function save_undo_state(board)
	table.insert(undo_stack, vim.deepcopy(board))
	if #undo_stack > undo_limit then
		table.remove(undo_stack, 1)
	end
end


-- Helper: Get task under cursor
local function get_task_under_cursor(board)
	local line_num = vim.api.nvim_win_get_cursor(0)[1]

	-- Find task at current line
	for _, column in ipairs(board.columns) do
		for _, task in ipairs(column.tasks) do
			if task.line_number == line_num then
				return task, column
			end
		end
	end

	-- Check archive
	if board.archive then
		for _, task in ipairs(board.archive.tasks) do
			if task.line_number == line_num then
				return task, board.archive
			end
		end
	end

	return nil, nil
end

-- Helper: Select from list
local function select_from_list(items, prompt, format_fn)
	local config = get_config()
	if config.use_telescope and pcall(require, "telescope") then
		-- Use telescope if available
		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")

		pickers.new({}, {
			prompt_title = prompt,
			finder = finders.new_table {
				results = items,
				entry_maker = function(entry)
					return {
						value = entry,
						display = format_fn and format_fn(entry) or tostring(entry),
						ordinal = format_fn and format_fn(entry) or tostring(entry),
					}
				end,
			},
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						coroutine.resume(M._select_coroutine, selection.value)
					end
				end)
				return true
			end,
		}):find()

		-- Wait for selection
		M._select_coroutine = coroutine.running()
		return coroutine.yield()
	else
		-- Fallback to vim.ui.select
		local formatted_items = {}
		for _, item in ipairs(items) do
			table.insert(formatted_items, format_fn and format_fn(item) or tostring(item))
		end

		local choice = nil
		vim.ui.select(formatted_items, {
			prompt = prompt,
		}, function(selected, idx)
			if idx then
				choice = items[idx]
			end
		end)

		-- Wait for vim.ui.select to complete
		vim.wait(1000, function() return choice ~= nil end, 10)
		return choice
	end
end

-- Action: Create new board
function M.create_board()
	-- Get board name
	local board_name = vim.fn.input("Board name: ", "New Board")
	if board_name == "" then return end

	-- Create board structure
	local lines = { "# " .. board_name, "" }

	-- Add default configuration
	table.insert(lines, "<!-- kanban:config")
	table.insert(lines, "wip_limit: 10")
	table.insert(lines, "cycle_time_unit: days")
	table.insert(lines, "-->")
	table.insert(lines, "")

	-- Add default columns
	local config = get_config()
	for _, column_name in ipairs(config.default_columns) do
		table.insert(lines, "## " .. column_name)

		-- Add WIP limit for certain columns
		if column_name == "In Progress" or column_name == "Ready" then
			table.insert(lines, "<!-- column:config wip_limit: 3 -->")
		end

		table.insert(lines, "")
	end

	-- Add archive section
	table.insert(lines, "## __ARCHIVE__")
	table.insert(lines, "<!-- Completed tasks older than 30 days -->")

	-- Create new buffer or use current
	local bufnr = vim.api.nvim_get_current_buf()
	local buf_name = vim.api.nvim_buf_get_name(bufnr)

	if buf_name ~= "" then
		-- Current buffer has a file, create new buffer
		vim.cmd("enew")
		bufnr = vim.api.nvim_get_current_buf()
	end

	-- Set content
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

	-- Set filetype
	vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")

	vim.notify("Created board: " .. board_name, vim.log.levels.INFO)
end

-- Action: Create new task
-- TODO use config setting for starting column, or use first column
function M.create_task(column_name)
	local board = get_current_board()
	save_undo_state(board)

	-- If no column specified, show selector
	if not column_name then
		local columns = {}
		for _, col in ipairs(board.columns) do
			-- Skip Done column for new tasks
			-- TODO remove hardcoded Done column
			if col.name ~= "Done" then
				table.insert(columns, col.name)
			end
		end

		column_name = select_from_list(columns, "Select column for new task")
		if not column_name then return end
	end

	-- Check WIP limit
	-- TODO move to trigger
	local config = get_config()
	local can_add, msg = checker.check_wip_limit{board=board, column=column_name, config=config}
	if not can_add then
		vim.notify(msg, vim.log.levels.ERROR)
		return
	end

	-- Get task description
	local task_text = vim.fn.input("Task description: ")
	if task_text == "" then return end

	-- Get optional complexity
	local complexity = vim.fn.input("Complexity (1-5, or Enter to skip): ")
	local properties = {}
	if complexity ~= "" then
		properties.complexity = tonumber(complexity) or 1
	end


	-- Create the task
	local new_task = writer.append_task_to_column(board, column_name, task_text, properties)

	if new_task then
		-- Write to buffer
		writer.write_to_buffer(board)

		-- Find and jump to the new task
		local new_board = get_current_board()
		for _, col in ipairs(new_board.columns) do
			if col.name == column_name then
				for _, task in ipairs(col.tasks) do
					if task.properties.id == new_task.properties.id then
						if task.line_number then
							vim.api.nvim_win_set_cursor(0, { task.line_number, 0 })
						end
						break
					end
				end
			end
		end

		vim.notify("Created task in " .. column_name, vim.log.levels.INFO)
	end
end


-- stub
-- TODO replace this
function M.decide_task(something, yes_no)
end

-- Enhanced movement function
local function move_task_advanced(options)
	local board = options.board or get_current_board()
	save_undo_state(board)
	local task_id = options.task_id
	local target_column = options.target_column

	local task, source_column = parser.find_task(board, task_id)

	-- Check if move is allowed
	local allowed, errors, warnings = checker.check_transition_rules(
		board, task, source_column, target_column
	)

	if not allowed then
		local error_msg = type(errors) == "table" and table.concat(errors, "; ") or errors
		vim.notify("Cannot move task: " .. error_msg, vim.log.levels.ERROR)
		return false, errors
	end

	-- Show warnings if any
	if warnings then
		if type(warnings) == "table" then
			for _, warning in ipairs(warnings) do
				vim.notify("Warning: " .. warning, vim.log.levels.WARN)
			end
		else
			vim.notify("Warning: " .. warnings, vim.log.levels.WARN)
		end
	end

	-- Proceed with move
	return writer.move_task(board, task_id, target_column)
end

-- Action: Move task
function M.move_task(options)
	local board = options.board or get_current_board()
	save_undo_state(board)
	local task_id = options.task_id
	local target_column = options.target_column

	-- If no task specified, use task under cursor
	if not task_id then
		local task, column = get_task_under_cursor(board)
		if not task then
			vim.notify("No task under cursor", vim.log.levels.ERROR)
			return
		end
		task_id = task.properties.id
	end

	-- Find the task
	local task, source_column = parser.find_task(board, task_id)
	if not task then
		vim.notify("Task not found", vim.log.levels.ERROR)
		return
	end
	if not source_column then
		vim.notify("Source column for task " .. task_id .. " not found.")
		return
	end

	-- If no target specified, show selector
	if not target_column then
		local columns = {}
		for _, col in ipairs(board.columns) do
			if col.name ~= source_column.name then
				table.insert(columns, col.name)
			end
		end

		-- Add archive option
		if not source_column.is_archive then
			table.insert(columns, "__ARCHIVE__")
		end

		target_column = select_from_list(columns,
			string.format("Move '%s' to:", task.text:sub(1, 30)))
		if not target_column then return end
	end

	-- Check WIP limit
	local config = get_config()
	local can_move, msg = checker.check_wip_limit{board=board, column=target_column, config=config}
	if not can_move then
		vim.notify(msg, vim.log.levels.ERROR)
		return
	end

	-- Perform the move
	local success, err = move_task_advanced{board=board,task_id=task_id, target_column=target_column}

	if success then
		writer.write_to_buffer(board)
		vim.notify(string.format("Moved task to %s", target_column), vim.log.levels.INFO)
	else
		vim.notify("Failed to move task: " .. err, vim.log.levels.ERROR)
	end
end


-- Action: Move task forward in workflow
-- TODO think about replacing this with move_task_advanced
function M.move_task_forward(options)
	local board = options and options.board or get_current_board()
	local task_id = options and options.task_id
	local target_column = options and options.target_column
	local task, source_column

	if task_id then
		task, source_column = parser.find_task(board, task_id)
	else
		task, source_column = get_task_under_cursor(board)
	end

	if not task then
		vim.notify("No task under cursor", vim.log.levels.ERROR)
		return
	end

	-- Use board structure for flow instead of hardcoded config

	-- Find next column in flow
	if not target_column then
		local flow = get_column_flow(board)
		local current_idx = nil
		for i, col_name in ipairs(flow) do
			if col_name == source_column.name then
				current_idx = i
				break
			end
		end
		if not current_idx or current_idx >= #flow then
			vim.notify("Task is already in final column", vim.log.levels.WARN)
			return
		end

		target_column = flow[current_idx + 1]
	end

	M.move_task({task_id = task.properties.id, target_column = target_column})
end

-- Action: Move task backward in workflow
-- TODO think about replacing this with move_task_advanced
function M.move_task_backward(options)
	local board = options and options.board or get_current_board()
	local task_id = options and options.task_id
	local target_column = options and options.target_column
	local task, source_column

	if task_id then
		task, source_column = parser.find_task(board, task_id)
	else
		task, source_column = get_task_under_cursor(board)
	end

	if not task then
		vim.notify("No task under cursor", vim.log.levels.ERROR)
		return
	end

	-- Use board structure for flow instead of hardcoded config
	if not target_column then
		local flow = get_column_flow(board)
	
		-- Find previous column in flow
		local current_idx = nil
		for i, col_name in ipairs(flow) do
			if col_name == source_column.name then
				current_idx = i
				break
			end
		end

		if not current_idx or current_idx <= 1 then
			vim.notify("Task is already in first column", vim.log.levels.WARN)
			return
		end

		target_column = flow[current_idx - 1]
	end
	M.move_task({task_id = task.properties.id, target_column = target_column})
end


-- Action: Delete task
function M.delete_task(task_id)
	local board = get_current_board()

	-- If no task specified, use task under cursor
	if not task_id then
		local task, column = get_task_under_cursor(board)
		if not task then
			vim.notify("No task under cursor", vim.log.levels.ERROR)
			return
		end
		task_id = task.properties.id

		-- Confirm deletion
		local config = get_config()
		if config.confirm_destructive then
			local confirm = vim.fn.input(
				string.format("Delete '%s'? (y/n): ", task.text:sub(1, 50))
			)
			if confirm:lower() ~= "y" then
				return
			end
		end
	end

	save_undo_state(board)

	-- Find and remove the task
	local found = false
	for _, column in ipairs(board.columns) do
		for i, task in ipairs(column.tasks) do
			if task.properties.id == task_id then
				table.remove(column.tasks, i)
				found = true
				break
			end
		end
		if found then break end
	end

	-- Check archive
	if not found and board.archive then
		for i, task in ipairs(board.archive.tasks) do
			if task.properties.id == task_id then
				table.remove(board.archive.tasks, i)
				found = true
				break
			end
		end
	end

	if found then
		writer.write_to_buffer(board)
		vim.notify("Task deleted", vim.log.levels.INFO)
	else
		vim.notify("Task not found", vim.log.levels.ERROR)
	end
end

-- Action: Archive done tasks
function M.archive_done_tasks(older_than_days)
	local board = get_current_board()
	save_undo_state(board)

	local config = get_config()
	older_than_days = older_than_days or config.auto_archive_after_days or 0

	local count = writer.archive_done_tasks(board, older_than_days)

	if count > 0 then
		writer.write_to_buffer(board)
		vim.notify(string.format("Archived %d task(s)", count), vim.log.levels.INFO)
	else
		vim.notify("No tasks to archive", vim.log.levels.INFO)
	end
end

-- Action: Edit task
function M.edit_task()
	local board = get_current_board()
	local task, column = get_task_under_cursor(board)

	if not task then
		vim.notify("No task under cursor", vim.log.levels.ERROR)
		return
	end

	save_undo_state(board)

	-- Edit task text
	local new_text = vim.fn.input("Edit task: ", task.text)
	if new_text ~= "" and new_text ~= task.text then
		task.text = new_text
		writer.update_task_in_buffer(board, task.properties.id)
		vim.notify("Task updated", vim.log.levels.INFO)
	end
end

-- Action: Add/edit task property
function M.edit_task_property()
	local board = get_current_board()
	local task, column = get_task_under_cursor(board)

	if not task then
		vim.notify("No task under cursor", vim.log.levels.ERROR)
		return
	end

	save_undo_state(board)

	-- Select property to edit
	local properties = { "complexity", "assignee", "tags", "blocker", "custom..." }
	local prop = select_from_list(properties, "Select property to edit")

	if not prop then return end

	if prop == "custom..." then
		prop = vim.fn.input("Property name: ")
		if prop == "" then return end
	end

	-- Get current value
	local current = task.properties[prop] or ""
	if type(current) == "table" then
		current = table.concat(current, ", ")
	end

	-- Get new value
	local new_value = vim.fn.input(string.format("Set %s: ", prop), tostring(current))

	if new_value ~= "" then
		-- Parse value type
		if prop == "tags" and new_value:match(",") then
			-- Convert comma-separated to array
			local tags = {}
			for tag in new_value:gmatch("([^,]+)") do
				table.insert(tags, vim.trim(tag))
			end
			task.properties[prop] = tags
		elseif tonumber(new_value) then
			task.properties[prop] = tonumber(new_value)
		elseif new_value:lower() == "true" then
			task.properties[prop] = true
		elseif new_value:lower() == "false" then
			task.properties[prop] = false
		else
			task.properties[prop] = new_value
		end
	elseif new_value == "" and current ~= "" then
		-- Remove property
		task.properties[prop] = nil
	end

	writer.update_task_in_buffer(board, task.properties.id)
	vim.notify("Property updated", vim.log.levels.INFO)
end

-- Action: Show task details
function M.show_task_details()
	local board = get_current_board()
	local task, column = get_task_under_cursor(board)

	if not task then
		vim.notify("No task under cursor", vim.log.levels.ERROR)
		return
	end

	local details = {
		"Task: " .. task.text,
		"Column: " .. column.name,
		"ID: " .. (task.properties.id or "none"),
		"",
		"Properties:",
	}

	-- Add properties
	for key, value in pairs(task.properties) do
		local formatted_value = value
		if type(value) == "table" then
			formatted_value = table.concat(value, ", ")
		elseif type(value) == "number" and value > 946684800 and value < 2147483647 then
			-- Likely a timestamp
			formatted_value = os.date("%Y-%m-%d %H:%M", value)
		end
		table.insert(details, string.format("  %s: %s", key, formatted_value))
	end

	-- Calculate cycle time if applicable
	if task.properties.created and task.properties.done then
		local cycle_time = (task.properties.done - task.properties.created) / 86400
		table.insert(details, "")
		table.insert(details, string.format("Cycle time: %.1f days", cycle_time))
	end

	-- Show in floating window
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, details)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	local width = 50
	local height = #details

	local opts = {
		relative = "cursor",
		width = width,
		height = height,
		row = 1,
		col = 0,
		style = "minimal",
		border = "rounded",
		title = " Task Details ",
		title_pos = "center",
	}

	local win = vim.api.nvim_open_win(buf, false, opts)

	-- Close on any key press
	vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", 
		":close<CR>", { noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(buf, "n", "q", 
		":close<CR>", { noremap = true, silent = true })
end

-- Action: Filter tasks
function M.filter_tasks(filter)
	local board = get_current_board()

	if not filter then
		filter = vim.fn.input("Filter (tag:backend, assignee:john, etc.): ")
		if filter == "" then return end
	end

	-- Parse filter
	local key, value = filter:match("(%w+):(.+)")
	if not key then
		-- Simple text search
		key = "text"
		value = filter
	end

	-- Find matching tasks
	local matches = {}

	local check_column = function(column)
		for _, task in ipairs(column.tasks) do
			local match = false

			if key == "text" then
				match = task.text:lower():match(value:lower())
			elseif key == "tag" or key == "tags" then
				if type(task.properties.tags) == "table" then
					for _, tag in ipairs(task.properties.tags) do
						if tag:lower() == value:lower() then
							match = true
							break
						end
					end
				end
			else
				-- Generic property match
				local prop = task.properties[key]
				if prop then
					if type(prop) == "string" then
						match = prop:lower():match(value:lower())
					else
						match = tostring(prop) == value
					end
				end
			end

			if match then
				table.insert(matches, {
					task = task,
					column = column.name,
					line = task.line_number,
				})
			end
		end
	end

	-- Check all columns
	for _, column in ipairs(board.columns) do
		check_column(column)
	end
	if board.archive then
		check_column(board.archive)
	end

	-- Show results
	if #matches == 0 then
		vim.notify("No tasks match filter", vim.log.levels.INFO)
		return
	end

	-- Use quickfix list
	local qf_items = {}
	for _, match in ipairs(matches) do
		table.insert(qf_items, {
			bufnr = vim.api.nvim_get_current_buf(),
			lnum = match.line,
			col = 1,
			text = string.format("[%s] %s", match.column, match.task.text),
		})
	end

	vim.fn.setqflist(qf_items, "r")
	vim.cmd("copen")
	vim.notify(string.format("Found %d matching task(s)", #matches), vim.log.levels.INFO)
end

-- Action: Undo last action
function M.undo()
	if #undo_stack == 0 then
		vim.notify("Nothing to undo", vim.log.levels.INFO)
		return
	end

	local previous_state = table.remove(undo_stack)
	writer.write_to_buffer(previous_state)
	vim.notify("Undone last action", vim.log.levels.INFO)
end

-- Action: Jump to column
function M.jump_to_column()
	local board = get_current_board()

	local columns = {}
	for _, col in ipairs(board.columns) do
		table.insert(columns, col.name)
	end
	if board.archive then
		table.insert(columns, "__ARCHIVE__")
	end

	local column_name = select_from_list(columns, "Jump to column")
	if not column_name then return end

	-- Find column line number
	for _, col in ipairs(board.columns) do
		if col.name == column_name and col.line_number then
			vim.api.nvim_win_set_cursor(0, { col.line_number, 0 })
			return
		end
	end

	if board.archive and column_name == "__ARCHIVE__" and board.archive.line_number then
		vim.api.nvim_win_set_cursor(0, { board.archive.line_number, 0 })
	end
end


if _G._TEST then
  M._private = {
		get_current_board = get_current_board,
    get_task_under_cursor = get_task_under_cursor,
		move_task_advanced = move_task_advanced,
		get_column_flow = get_column_flow,
  }
end

return M
