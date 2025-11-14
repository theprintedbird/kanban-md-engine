-- lua/kanban-md/writer_mixin.lua
-- Writer mixin for Board class - converts data structure back to markdown

-- Dependencies
local config_module = require("kanban-md.config")
local triggers_module = require("kanban-md.triggers")
local column_helpers = require("kanban-md.helpers.column")
local TblUtils = require("kanban-md.utils.table")
local adapter_registry = require("kanban-md.adapter_registry")

-- Writer mixin that can be applied to Board instances
local WriterMixin = {}

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

-- Convert TypeConverter objects to plain tables, pass through regular tables
local function to_plain_table(obj)
	if type(obj) == "table" and type(obj.to_table) == "function" then
		return obj:to_table()
	end
	return obj
end

-- Convert properties to comment string
local function properties_to_comment(properties, prefix)
	-- Ensure properties is a plain table, not a TypeConverter
	properties = to_plain_table(properties)

	if not properties or TblUtils.isEmpty(properties) then
		return nil
	end

	local parts = {}

	-- Add prefix if provided (e.g., "kanban:config" or "column:config")
	if prefix then
		table.insert(parts, prefix)
	end

	-- Sort properties for consistent output
	local keys = TblUtils.keys(properties)
	table.sort(keys)

	for _, key in ipairs(keys) do
		-- Skip underscore-prefixed properties (ephemeral/internal)
		if not key:match("^_") then
			local value = properties[key]
			local formatted = format_property_value(value)
			if formatted then
				table.insert(parts, string.format("%s: %s", key, formatted))
			end
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
	local lines = {}

	-- Get properties to write
	local props_to_write = to_plain_table(task.properties or {})
	if config_module.get_value('persist_card_ids') and task.id then
		props_to_write.id = task.id
	end

	-- Build property comment
	local comment = properties_to_comment(props_to_write)

	-- Handle multi-line cards
	if task.content_lines then
		-- First line with properties
		local first_line = task.content_lines[1]
		if comment then
			if type(comment) == "table" then
				table.insert(lines, first_line .. " " .. comment[1])
				for i = 2, #comment do
					table.insert(lines, comment[i])
				end
			else
				table.insert(lines, first_line .. " " .. comment)
			end
		else
			table.insert(lines, first_line)
		end

		-- Continuation lines (preserve original indentation)
		for i = 2, #task.content_lines do
			table.insert(lines, task.content_lines[i])
		end

		return lines
	end

	-- Single-line card (existing behaviour)
	local line = string.format("%s- %s", config.task_indent, task.text)
	if comment then
		if type(comment) == "table" then
			return { line .. " " .. comment[1], unpack(comment, 2) }
		else
			return line .. " " .. comment
		end
	end

	return line
end

-- Write a column section
local function write_column(column)
	local lines = {}
	local config = config_module.get()

	-- Column header
	table.insert(lines, "###### " .. column.name)

	-- Column configuration comment if present
	local plain_config = to_plain_table(column.config)
	if plain_config and not TblUtils.isEmpty(plain_config) then
		local config_comment = properties_to_comment(plain_config, "column:config")
		if type(config_comment) == "table" then
			for _, line in ipairs(config_comment) do
				table.insert(lines, line)
			end
		else
			table.insert(lines, config_comment)
		end
	end

	-- Add blank line after header/config if configured and there are cards
	if config.blank_line_after_column_header and column.cards and #column.cards > 0 then
		table.insert(lines, "")
	end

	-- cards
	for _, task in ipairs(column.cards or {}) do
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

-- Main writer function - dispatches to appropriate implementation
function WriterMixin:write()
	-- Use content blocks if available (new behavior)
	if self.content_blocks and #self.content_blocks > 0 then
		return self:write_from_blocks()
	else
		-- Fallback: Generate structure without blocks (for programmatically created boards)
		return self:write_legacy()
	end
end

-- Write from content blocks (preserves markdown)
function WriterMixin:write_from_blocks()
	local config = config_module.get()
	local lines = {}
	local ContentBlock = require("kanban-md.content_block")
	local skip_next_single_blank = false

	for i, block in ipairs(self.content_blocks) do
		if block.type == ContentBlock.TYPES.MARKDOWN then
			-- If we just added a config-driven blank line after a column header,
			-- skip the first blank line of this markdown block if it starts with one
			-- (prevents duplicate blank lines on round-trip)
			if skip_next_single_blank and #block.lines > 0 and block.lines[1] == "" then
				-- Skip the first blank line, but output the rest
				for j = 2, #block.lines do
					table.insert(lines, block.lines[j])
				end
				skip_next_single_blank = false
			else
				-- Preserve markdown verbatim
				for _, line in ipairs(block.lines) do
					table.insert(lines, line)
				end
				skip_next_single_blank = false
			end

		elseif block.type == ContentBlock.TYPES.TITLE then
			skip_next_single_blank = false
			-- Generate from current board title
			table.insert(lines, "# " .. (self.title or "Untitled Board"))

			-- Add board config if present (immediately after title)
			local plain_board_config = to_plain_table(self.config)
			if plain_board_config and not TblUtils.isEmpty(plain_board_config) then
				local config_comment = properties_to_comment(plain_board_config, "kanban:config")
				if type(config_comment) == "table" then
					for _, line in ipairs(config_comment) do
						table.insert(lines, line)
					end
				else
					table.insert(lines, config_comment)
				end
			end

		elseif block.type == ContentBlock.TYPES.COLUMN then
			skip_next_single_blank = false
			-- Generate from current column data
			local column = block.ref

			-- Column header (H6)
			table.insert(lines, "###### " .. column.name)

			-- Column configuration comment if present
			local plain_config = to_plain_table(column.config)
			if plain_config and not TblUtils.isEmpty(plain_config) then
				local config_comment = properties_to_comment(plain_config, "column:config")
				if type(config_comment) == "table" then
					for _, line in ipairs(config_comment) do
						table.insert(lines, line)
					end
				else
					table.insert(lines, config_comment)
				end
			end

			-- Add blank line after header/config if configured and there are cards
			if config.blank_line_after_column_header and column.cards and #column.cards > 0 then
				table.insert(lines, "")
				-- Mark that we added a config-driven blank line, so we should skip
				-- the next single-blank markdown block (it's a duplicate from a previous write)
				skip_next_single_blank = true
			end

			-- Cards
			for _, task in ipairs(column.cards or {}) do
				local task_output = write_task(task, column.name)
				if type(task_output) == "table" then
					for _, line in ipairs(task_output) do
						table.insert(lines, line)
					end
				else
					table.insert(lines, task_output)
				end
			end
		end
	end

	return lines
end

-- Legacy write (for backwards compatibility, programmatically created boards without content blocks)
function WriterMixin:write_legacy()
	local config = config_module.get()
	local lines = {}

	-- Board title
	table.insert(lines, "# " .. (self.title or "Untitled Board"))

	if config.blank_line_after_title then
		table.insert(lines, "")
	end

	-- Board configuration
	local plain_board_config = to_plain_table(self.config)
	if plain_board_config and not TblUtils.isEmpty(plain_board_config) then
		local config_comment = properties_to_comment(plain_board_config, "kanban:config")
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
	if self.columns and #self.columns > 0 and config.blank_lines_between_sections then
		table.insert(lines, "")
	end

	-- Regular columns
	for i, column in ipairs(self.columns or {}) do
		if i > 1 and config.blank_lines_between_sections then
			table.insert(lines, "")
		end

		local column_lines = write_column(column)
		for _, line in ipairs(column_lines) do
			table.insert(lines, line)
		end
	end

	-- Archive section
	if self.archive then
		if config.blank_lines_between_sections then
			table.insert(lines, "")
		end

		local archive_lines = write_column(self.archive)
		for _, line in ipairs(archive_lines) do
			table.insert(lines, line)
		end
	end

	return lines
end

-- Write board to file
function WriterMixin:write_to_file(filepath)
	local lines = self:write()
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
function WriterMixin:write_to_buffer(bufnr)
	bufnr = bufnr or adapter_registry.get_adapter():get_current_buffer()
	local lines = self:write()

	-- Save cursor position
	local cursor = adapter_registry.get_adapter():get_cursor(0)

	-- Update buffer
	adapter_registry.get_adapter():write_buffer(lines,{ bufnr = bufnr, start = 0, _end = -1})

	-- Try to restore cursor position intelligently
	local max_line = adapter_registry.get_adapter():buf_line_count(bufnr)
	if cursor[1] > max_line then
		cursor[1] = max_line
	end

	-- Restore cursor
	adapter_registry.get_adapter():set_cursor(cursor)

	return true
end

-- Update a single task in place (minimal change)
function WriterMixin:update_task_in_buffer(task_id, bufnr)
	bufnr = bufnr or adapter_registry.get_adapter():get_current_buffer()

	-- Find the task in the board
	local parser = require("kanban-md.parser")
	local task, column = parser.find_task(self, task_id)

	if not task or not task.line_number then
		return false, "Task not found or missing line number"
	end

	-- Generate the updated task line
	local updated_line = write_task(task, column.name)

	if type(updated_line) == "table" then
		-- Multi-line (shouldn't happen often for cards)
		adapter_registry.get_adapter():write_buffer(updated_line, {bufnr = bufnr, start = task.line_number - 1, _end = task.line_number })
	else
		-- Single line (normal case)
		adapter_registry.get_adapter():write_buffer(updated_line,{bufnr = bufnr, start = task.line_number - 1, _end = task.line_number })
	end

	return true
end

-- For testing, conditionally export private functions
if _G._TEST then
  WriterMixin._private = {
    format_timestamp = format_timestamp,
    format_property_value = format_property_value,
    properties_to_comment = properties_to_comment,
    write_task = write_task,
    write_column = write_column
  }
end

return WriterMixin
