-- lua/kanban-md/writer_mixin.lua
-- Writer mixin for Board class - converts data structure back to markdown

-- Dependencies
local config_module = require("kanban-md.config")
local column_helpers = require("kanban-md.helpers.column")
local TblUtils = require("kanban-md.utils.table")
local adapter_registry = require("kanban-md.adapter_registry")

-- Writer mixin that can be applied to Board instances
local WriterMixin = {}

-- Format a timestamp based on config
-- @param timestamp number|nil
-- @param config table|nil - effective config; falls back to global plugin config
local function format_timestamp(timestamp, config)
	if not timestamp then return nil end

	config = config or config_module.get()
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
-- @param value any
-- @param key string - the property key (for determining if it's a timestamp)
-- @param timestamp_keys table|nil - set of property keys that are timestamps
-- @param config table|nil - effective config; falls back to global plugin config
local function format_property_value(value, key, timestamp_keys, config)
	if type(value) == "boolean" then
		return tostring(value)
	elseif type(value) == "number" then
		-- Only treat as timestamp if the key is in the explicit timestamp_keys set
		-- (which includes "archived" plus all column timestamp keys)
		if timestamp_keys and timestamp_keys[key] then
			return format_timestamp(value, config)
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

-- Build a set of property keys that should be formatted as timestamps
-- Includes "archived" plus normalised names of all columns
-- @param board table
-- @return table - set where timestamp keys are keys with true values
local function build_timestamp_keys(board)
	local keys = {
		archived = true  -- Special key for archived timestamp
	}

	-- Add normalised column names (they are used as timestamp property keys)
	if board.columns then
		for _, column in ipairs(board.columns) do
			if column.name then
				local normalised = column_helpers.normalize_column_name(column.name)
				keys[normalised] = true
			end
		end
	end

	-- Also add the archive column if it exists
	if board.archive and board.archive.name then
		local normalised = column_helpers.normalize_column_name(board.archive.name)
		keys[normalised] = true
	end

	return keys
end

-- Convert properties to comment string
-- @param properties table
-- @param prefix string|nil - e.g. "kanban:config" or "column:config"
-- @param config table|nil - effective config; falls back to global plugin config
-- @param timestamp_keys table|nil - set of property keys that are timestamps
local function properties_to_comment(properties, prefix, config, timestamp_keys)
	config = config or config_module.get()

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
			local formatted = format_property_value(value, key, timestamp_keys, config)
			if formatted then
				table.insert(parts, string.format("%s: %s", key, formatted))
			end
		end
	end

	-- Join prefix with a space, then join remaining parts with property_separator
	local content
	if prefix then
		-- parts[1] is the prefix, parts[2..n] are the property key:value pairs
		local property_parts = {}
		for i = 2, #parts do
			table.insert(property_parts, parts[i])
		end
		if #property_parts > 0 then
			content = prefix .. " " .. table.concat(property_parts, config.property_separator)
		else
			content = prefix
		end
	else
		content = table.concat(parts, config.property_separator)
	end

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
-- @param task table
-- @param column_name string
-- @param config table|nil - effective config; falls back to global plugin config
-- @param timestamp_keys table|nil - set of property keys that are timestamps
local function write_task(task, column_name, config, timestamp_keys)
	config = config or config_module.get()
	local lines = {}

	-- Get properties to write
	local props_to_write = to_plain_table(task.properties or {})
	if config.persist_card_ids then
		-- write_task is the single source of truth for persisted card ids
		-- (PLAN-config-fixes.md Task 2): an id the user authored in the
		-- markdown (task.properties.id) is the canonical persisted identity
		-- and always wins over the in-memory task.id, so a trigger-synced or
		-- freshly generated task.id can never clobber an authored id.
		local authored_id = task.properties and task.properties.id
		props_to_write.id = authored_id or task.id
	end
	-- When persist_card_ids is false, props_to_write already carries whatever
	-- the user authored in task.properties.id (if anything) verbatim, via
	-- to_plain_table(task.properties) above -- no extra handling needed.

	-- Build property comment
	local comment = properties_to_comment(props_to_write, nil, config, timestamp_keys)

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

-- Select which column config layer to serialise back to markdown.
--
-- By default only the *authored* layer (column.markdown_config) is written, so
-- implicit/type-resolved properties (from column_config types, definitions or
-- patterns) are never injected into the user's file -- honouring the
-- "Markdown always wins" contract and write_full_config_to_markdown = false
-- (see PLAN-config-fixes.md Task 3, features/CONFIG_PLAN.md).
--
-- When the effective write_full_config_to_markdown is true, the fully resolved
-- column.config is written instead.
--
-- Programmatically built columns (via Board:add_column / direct column.config
-- assignment) never go through the parser's type resolution, so column.type is
-- nil and there is no authored markdown_config; those fall back to
-- column.config so write_legacy keeps serialising them as before.
-- @param column table
-- @param config table - effective config
-- @return table|nil - the config layer to serialise, or nil to write nothing
local function select_column_config(column, config)
	if config.write_full_config_to_markdown then
		return column.config
	end
	if column.markdown_config ~= nil then
		return column.markdown_config
	end
	if column.type == nil then
		-- No parser type resolution occurred: treat direct config as authored.
		return column.config
	end
	-- Type-resolved column with no authored config: write nothing.
	return nil
end

-- Write a column section
-- @param column table
-- @param config table|nil - effective config; falls back to global plugin config
-- @param timestamp_keys table|nil - set of property keys that are timestamps
local function write_column(column, config, timestamp_keys)
	config = config or config_module.get()
	local lines = {}

	-- Column header
	table.insert(lines, "###### " .. column.name)

	-- Column configuration comment if present (authored layer by default)
	local plain_config = to_plain_table(select_column_config(column, config))
	if plain_config and not TblUtils.isEmpty(plain_config) then
		local config_comment = properties_to_comment(plain_config, "column:config", config, timestamp_keys)
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

	-- Header markdown (content between column header and first card)
	if column.header_markdown and #column.header_markdown > 0 then
		for _, line in ipairs(column.header_markdown) do
			table.insert(lines, line)
		end
	end

	-- cards
	for _, task in ipairs(column.cards or {}) do
		local task_output = write_task(task, column.name, config, timestamp_keys)
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
	local config = self:get_effective_config()
	local timestamp_keys = build_timestamp_keys(self)
	local lines = {}
	local ContentBlock = require("kanban-md.content_block")

	-- Check if there's a TITLE block in content_blocks
	local has_title_block = false
	for _, block in ipairs(self.content_blocks) do
		if block.type == ContentBlock.TYPES.TITLE then
			has_title_block = true
			break
		end
	end

	-- If there's no title block but we have board config, emit it at the top
	if not has_title_block then
		local plain_board_config = to_plain_table(self.config)
		if plain_board_config and not TblUtils.isEmpty(plain_board_config) then
			local config_comment = properties_to_comment(plain_board_config, "kanban:config", config, timestamp_keys)
			if type(config_comment) == "table" then
				for _, line in ipairs(config_comment) do
					table.insert(lines, line)
				end
			else
				table.insert(lines, config_comment)
			end
		end
	end

	for i, block in ipairs(self.content_blocks) do
		if block.type == ContentBlock.TYPES.MARKDOWN then
			-- Preserve markdown verbatim
			for _, line in ipairs(block.lines) do
				table.insert(lines, line)
			end

		elseif block.type == ContentBlock.TYPES.TITLE then
			-- Generate from current board title
			table.insert(lines, "# " .. (self.title or "Untitled Board"))

			-- Add board config if present (immediately after title)
			local plain_board_config = to_plain_table(self.config)
			if plain_board_config and not TblUtils.isEmpty(plain_board_config) then
				local config_comment = properties_to_comment(plain_board_config, "kanban:config", config, timestamp_keys)
				if type(config_comment) == "table" then
					for _, line in ipairs(config_comment) do
						table.insert(lines, line)
					end
				else
					table.insert(lines, config_comment)
				end
			end

		elseif block.type == ContentBlock.TYPES.COLUMN then
			-- Generate from current column data
			local column = block.ref

			-- Column header (H6)
			table.insert(lines, "###### " .. column.name)

			-- Column configuration comment if present (authored layer by default)
			local plain_config = to_plain_table(select_column_config(column, config))
			if plain_config and not TblUtils.isEmpty(plain_config) then
				local config_comment = properties_to_comment(plain_config, "column:config", config, timestamp_keys)
				if type(config_comment) == "table" then
					for _, line in ipairs(config_comment) do
						table.insert(lines, line)
					end
				else
					table.insert(lines, config_comment)
				end
			end

			-- Add blank line after header/config if configured and there are cards
			-- BUT only if header_markdown doesn't already start with a blank line
			local should_add_blank = config.blank_line_after_column_header
				and column.cards and #column.cards > 0
			if should_add_blank then
				-- Check if header_markdown already provides a blank line
				local header_has_leading_blank = column.header_markdown
					and #column.header_markdown > 0
					and column.header_markdown[1] == ""
				if not header_has_leading_blank then
					table.insert(lines, "")
				end
			end

			-- Header markdown (content between column header and first card)
			if column.header_markdown and #column.header_markdown > 0 then
				for _, line in ipairs(column.header_markdown) do
					table.insert(lines, line)
				end
			end

			-- Cards
			for _, task in ipairs(column.cards or {}) do
				local task_output = write_task(task, column.name, config, timestamp_keys)
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
	local config = self:get_effective_config()
	local timestamp_keys = build_timestamp_keys(self)
	local lines = {}

	-- Board title
	table.insert(lines, "# " .. (self.title or "Untitled Board"))

	if config.blank_line_after_title then
		table.insert(lines, "")
	end

	-- Board configuration
	local plain_board_config = to_plain_table(self.config)
	if plain_board_config and not TblUtils.isEmpty(plain_board_config) then
		local config_comment = properties_to_comment(plain_board_config, "kanban:config", config, timestamp_keys)
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

		local column_lines = write_column(column, config, timestamp_keys)
		for _, line in ipairs(column_lines) do
			table.insert(lines, line)
		end
	end

	-- Archive section
	if self.archive then
		if config.blank_lines_between_sections then
			table.insert(lines, "")
		end

		local archive_lines = write_column(self.archive, config, timestamp_keys)
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
	local updated_line = write_task(task, column.name, self:get_effective_config())

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
