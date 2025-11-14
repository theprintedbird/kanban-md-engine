-- lua/kanban-md/parser.lua
-- Parser mixin for Board class - converts Markdown to Board instances

local Column = require("kanban-md.column")
local Card = require("kanban-md.card")
local TypeConverter = require("kanban-md.type_converter")
local StringUtils = require("kanban-md.utils.string")
local TblUtils = require("kanban-md.utils.table")

-- Parser mixin that can be applied to Board instances
local ParserMixin = {}

-- Patterns for parsing
local patterns = {
	-- Board title (# Title)
	board_title = "^#%s+(.+)$",

	-- Column header (###### Column Name) - H6 for columns
	column_header = "^######%s+(.+)$",

	-- Task item (simple list)
	task_item = "^%s*%-%s*(.+)$",

	-- HTML comment blocks
	comment_block_start = "^%s*<!%-%-%s*(.-)$",
	comment_block_end = "^(.-)%-%->%s*$",
	comment_single = "<!%-%-%s*(.-)%s*%-%->",

	-- Property patterns within comments
	property = "([%w_]+):%s*([^,]*%[[^%]]*%]|[^,]+)",

	-- Non-kanban sections (H2-H5 headers) - these are preserved as markdown
	section_header = "^##[^#]",

	-- Special sections (also use H6)
	archive_section = "^######%s+__ARCHIVE__",
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
			elseif bracket_count == 0 then
				-- Check if we're at the start of the next property (word followed by colon)
				-- Look ahead to detect pattern: whitespace + word + colon
				local ahead = comment_text:sub(value_end)
				if ahead:match("^%s+[%w_]+:%s*") then
					break  -- Stop here, next property detected
				end
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

-- Apply column configuration with type resolution and property merging
-- Handles both "column:config" and simplified "config" syntax
local function apply_column_config(column, config_content)
	if not column or not config_content or config_content == "" then
		return
	end

	-- Parse markdown properties
	local markdown_props = parse_properties(config_content)

	-- Get global config and resolver
	local global_config = require("kanban-md.config").get()
	local resolver = require("kanban-md.column_type_resolver")

	-- Resolve column type (markdown > definition > pattern)
	local column_type = resolver.resolve_type(column.name, markdown_props, global_config)

	-- Merge properties (type defaults < definition < markdown)
	local final_config = resolver.merge_properties(
		column.name,
		markdown_props,
		column_type,
		global_config
	)

	-- Set column type and config
	column.type = column_type
	column.config = TypeConverter:new(final_config)
end

-- Parse a task line and extract properties
local function parse_task(line)
	local task = {
		text = "",
		properties = TypeConverter:new({}),
		raw = line,
	}

	-- Extract task text
	local text = line:match(patterns.task_item)

	if not text then
		return nil
	end

	-- Check for inline comment with properties
	-- e.g. - Complex task <!-- backlog: 1735862400, in_progress: 1735948800, complexity: 3 -->
	local task_text, comment = text:match("^(.-)%s*<!%-%-%s*(.-)%s*%-%->%s*$")

	if task_text and comment then
		task.text = task_text:gsub("^%s+", ""):gsub("%s+$", "")
		task.properties = TypeConverter:new(parse_properties(comment))
	else
		task.text = text:gsub("^%s+", ""):gsub("%s+$", "")
	end

	return task
end

local function split_content_to_lines(content)
	local lines
	if type(content) == "string" then
		lines = StringUtils.split(content, "\n")
	elseif type(content) == "table" then
		lines = content
	else
		return nil, "Invalid content type"
	end
	return lines
end

-- Helper: Flush accumulated markdown lines into a content block
local function flush_markdown_buffer(board, buffer)
	if #buffer > 0 then
		-- Always create markdown blocks, even for whitespace-only content
		-- Blank lines are semantically meaningful in board structure
		local ContentBlock = require("kanban-md.content_block")
		table.insert(board.content_blocks, ContentBlock.markdown(TblUtils.deepcopy(buffer)))
	end
end

-- Helper: Add a structured block reference
local function add_structured_block(board, block)
	local ContentBlock = require("kanban-md.content_block")
	table.insert(board.content_blocks, block)
end

-- Parse markdown content and populate this Board instance
function ParserMixin:parse(content)
	-- Initialize board properties if not already set
	self.title = self.title or "Untitled Board"
	self.config = self.config or TypeConverter:new({})
	self.columns = {} -- Reset columns for fresh parse
	self.archive = nil
	self.stats = {}
	self.content_blocks = {} -- Initialize content blocks array

	local lines = split_content_to_lines(content)
	self.raw_lines = lines

	local current_column = nil
	local in_comment_block = false
	local comment_buffer = ""
	local line_number = 0
	local pending_config = nil
	local config_type = nil  -- "board" or "column"

	-- Content block tracking
	local markdown_buffer = {}
	local seen_title = false
	local ContentBlock = require("kanban-md.content_block")

	if lines ~= nil then
		for _, line in ipairs(lines) do
			line_number = line_number + 1

			-- Track whether this line should be added to markdown buffer
			local add_to_markdown = true

			-- Handle multi-line comment blocks
			if in_comment_block then
				add_to_markdown = false
				local ending = line:match(patterns.comment_block_end)
				if ending then
					comment_buffer = comment_buffer .. " " .. ending
					in_comment_block = false

					-- Process the complete comment
					if config_type == "board" and comment_buffer:match("kanban:config") then
						local config_content = comment_buffer:match("^%s*kanban:config%s*,?%s*(.*)")
						if config_content and config_content ~= "" then
							self.config = TypeConverter:new(parse_properties(config_content))
						end
					-- e.g. <!-- column:config wip_limit: 3 --> or <!-- config type: wip -->
					elseif config_type == "column" then
						-- Handle both "column:config" and simplified "config" syntax
						local config_content = comment_buffer:match("^%s*column:config%s*,?%s*(.*)")
							or comment_buffer:match("^%s*config%s*,?%s*(.*)")
						apply_column_config(current_column, config_content)
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
				add_to_markdown = false
				local comment_start = line:match(patterns.comment_block_start)

				-- Check if it's a single-line comment
				if line:match(patterns.comment_single) then
					local comment_content = line:match(patterns.comment_single)

					if comment_content:match("kanban:config") then
						local config_content = comment_content:match("^%s*kanban:config%s*,?%s*(.*)")
						if config_content and config_content ~= "" then
							self.config = TypeConverter:new(parse_properties(config_content))
						end
					elseif current_column and (comment_content:match("column:config") or comment_content:match("^%s*config%s")) then
						-- Handle both "column:config" and simplified "config" syntax
						local config_content = comment_content:match("^%s*column:config%s*,?%s*(.*)")
							or comment_content:match("^%s*config%s*,?%s*(.*)")
						apply_column_config(current_column, config_content)
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
					elseif comment_start:match("column:config") or (current_column and comment_start:match("^%s*config%s")) then
						config_type = "column"
					else
						config_type = "task"
					end
				end
			-- Parse board title
			elseif line:match(patterns.board_title) then
				add_to_markdown = false
				-- Flush markdown buffer before title
				flush_markdown_buffer(self, markdown_buffer)
				markdown_buffer = {}

				self.title = line:match(patterns.board_title)

				-- Add title block
				add_structured_block(self, ContentBlock.title())
				seen_title = true
			-- Parse archive section
			elseif line:match(patterns.archive_section) then
				add_to_markdown = false
				-- Flush markdown buffer before column
				flush_markdown_buffer(self, markdown_buffer)
				markdown_buffer = {}

				current_column = Column:new("__ARCHIVE__", "__ARCHIVE__")
				current_column.is_archive = true
				current_column.line_number = line_number
				current_column.command_log = self.command_log -- Share command log
				self.archive = current_column

				-- Add column block
				add_structured_block(self, ContentBlock.column(current_column))
				-- Note: Archive is stored separately in self.archive, not in self.columns
			-- Parse column headers
			elseif line:match(patterns.column_header) then
				add_to_markdown = false
				local column_name = line:match(patterns.column_header)

				if not column_name:match("^__") then  -- Regular column
					-- Flush markdown buffer before column
					flush_markdown_buffer(self, markdown_buffer)
					markdown_buffer = {}

					current_column = Column:new("column_" .. #self.columns + 1, column_name)
					current_column.line_number = line_number
					current_column.command_log = self.command_log -- Share command log
					table.insert(self.columns, current_column)

					-- Add column block
					add_structured_block(self, ContentBlock.column(current_column))
				end
			-- Parse tasks
			elseif current_column then
				local task_data = nil

				-- Check for task item
				if line:match(patterns.task_item) then
					task_data = parse_task(line)
				end

				if task_data then
					add_to_markdown = false
					task_data.line_number = line_number
					task_data.column = current_column.name

					-- Apply pending config if any
					if pending_config then
						for k, v in pairs(pending_config.properties) do
							task_data.properties[k] = v
						end
						pending_config = nil
					end

					-- Create Card object and add to column
					local card = Card:new(task_data.properties.id, task_data.text, task_data.properties)
					card.line_number = task_data.line_number
					card.column = task_data.column
					card.raw = task_data.raw

					-- Use column's add_card method to properly integrate with event system
					current_column:add_card(card)
				end
			end

			-- Add line to markdown buffer if it's not a structured element
			if add_to_markdown then
				table.insert(markdown_buffer, line)
			end
		end

		-- Flush remaining markdown buffer at the end
		flush_markdown_buffer(self, markdown_buffer)
	end

	-- Post-processing - resolve types for columns without explicit config
	local global_config = require("kanban-md.config").get()
	local resolver = require("kanban-md.column_type_resolver")

	for _, column in ipairs(self.columns) do
		-- Only resolve type if not already set (i.e., no config comment was found)
		if not column.type then
			-- Try to resolve type via patterns or definitions
			local column_type = resolver.resolve_type(column.name, {}, global_config)

			if column_type then
				-- Merge properties from type and definition
				local final_config = resolver.merge_properties(
					column.name,
					{}, -- No markdown properties
					column_type,
					global_config
				)

				-- Set column type and merge config
				column.type = column_type
				-- Merge with existing config (which might be empty)
				for key, value in pairs(final_config) do
					column.config[key] = value
				end
			end
		end
	end

	-- Handle archive and stats sections similarly
	if self.archive and not self.archive.type then
		local column_type = resolver.resolve_type(self.archive.name, {}, global_config)
		if column_type then
			local final_config = resolver.merge_properties(self.archive.name, {}, column_type, global_config)
			self.archive.type = column_type
			for key, value in pairs(final_config) do
				self.archive.config[key] = value
			end
		end
	end

	-- Delegate to stats mixin if available
	if self.calculate_stats then
		self:calculate_stats()
	end
	if self.validate then
		self:validate()
	end

	-- Auto-register triggers based on configuration
	if self.auto_register_triggers then
		self:auto_register_triggers()
	end

	return self
end

-- Find a task/card by ID
function ParserMixin:find_task(task_id)
	-- TODO guards
	-- Search regular columns
	for _, column in ipairs(self.columns) do
		for _, card in ipairs(column.cards) do
			if card.properties and card.properties.id == task_id then
				return card, column
			end
		end
	end

	-- Search archive
	if self.archive then
		for _, card in ipairs(self.archive.cards) do
			if card.properties and card.properties.id == task_id then
				return card, self.archive
			end
		end
	end

	return nil, nil
end

-- Get column by name (different from existing get_column which uses ID)
function ParserMixin:get_column_by_name(column_name)
	for _, column in ipairs(self.columns) do
		if column.name == column_name then
			return column
		end
	end

	if self.archive and column_name == "__ARCHIVE__" then
		return self.archive
	end

	return nil
end

-- For testing, conditionally export private functions
if _G._TEST then
  ParserMixin._private = {
    parse_properties = parse_properties,
	split_content_to_lines = split_content_to_lines
  }
end

return ParserMixin
