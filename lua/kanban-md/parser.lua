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

		-- Preserve authored case of keys; they are used as-is
		-- (Config keys like wip_limit, is_completion_state and timestamp keys
		-- are authored in lowercase by convention; custom keys preserve whatever
		-- case the user writes -- see PLAN-config-fixes.md Task 5)

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

-- Detect if a line is a continuation line (indented by 2+ spaces or 1+ tabs)
local function is_continuation_line(line)
	return line:match("^  +") or line:match("^\t+")  -- 2+ spaces or 1+ tabs at start
end

-- Detect a bullet marker with nothing after it (an empty list item), e.g.
-- "-", "- " or "-   ". CommonMark allows this and would treat any following
-- indented lines as that item's continuation; kanban-md declines to (an
-- empty first line gives a card no usable text), and instead reports it
-- through the adapter and leaves the line as column documentation -- see
-- features/multiline-lists.md, "Empty Cards".
local function is_empty_list_item(line)
	return line:match("^%s*%-%s*$") ~= nil
end

-- Report a warning through the registered adapter, if any. Silent when no
-- adapter is registered, following the same pattern as column_type_resolver.lua
-- and type_converter.lua -- the parser must never reach for io.*/vim.* itself
-- (SPEC.md section 8/9).
local function notify(message)
	local adapter_registry = require("kanban-md.adapter_registry")
	if adapter_registry.has_adapter() then
		adapter_registry.get_adapter():notify(message, "warn")
	end
end

-- Opening delimiter of a fenced code block (three or more backticks or
-- tildes), or nil. Everything between an opening fence and its matching close
-- is literal markdown, not kanban syntax.
local function match_fence(line)
	return line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
end

-- A fence closes only on a line of the same character, at least as long as
-- the opening delimiter, with nothing after it but whitespace. So a `~~~`
-- inside a ``` fence is just code, as is a ``` with an info string.
local function fence_closes(open_marker, line)
	local marker, rest = line:match("^%s*([`~]+)(.*)$")
	if not marker then
		return false
	end
	return marker:sub(1, 1) == open_marker:sub(1, 1)
		and #marker >= #open_marker
		and rest:match("^%s*$") ~= nil
end

-- Apply column configuration with type resolution and property merging
-- Handles both "column:config" and simplified "config" syntax
-- Config keys the engine later compares as numbers. A board file is written by
-- hand, so `wip_limit: "7"` is entirely possible; a numeric-looking value is
-- coerced here so the comparison in calculate_stats() sees a number. A value
-- that is not a number at all is left exactly as authored -- dropping it would
-- lose it on the next write -- and validate() reports it instead.
local NUMERIC_CONFIG_KEYS = { "wip_limit" }

local function coerce_numeric_config(props)
	for _, key in ipairs(NUMERIC_CONFIG_KEYS) do
		local value = props[key]

		if type(value) == "string" then
			-- Accept a quoted number as a number.
			local number = tonumber((value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")))

			if number then
				props[key] = number
			end
		end
	end

	return props
end

local function apply_column_config(column, config_content)
	if not column or not config_content or config_content == "" then
		return
	end

	-- Parse markdown properties
	local markdown_props = coerce_numeric_config(parse_properties(config_content))

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

	-- Set column type and config.
	--
	-- Two layers are kept on the column (see PLAN-config-fixes.md Task 3):
	--   * column.markdown_config -- exactly the properties the user authored in
	--     the markdown comment. This is the layer the writer serialises back by
	--     default, so implicit/type-resolved properties are never injected into
	--     the user's file.
	--   * column.config -- the merged/resolved config (type defaults < definition
	--     < markdown) that triggers, helpers, stats and validation consult.
	column.type = column_type
	column.markdown_config = TypeConverter:new(markdown_props)
	column.config = TypeConverter:new(final_config)
end

-- Split a task line into its text and its trailing property comment.
-- The property block is the *last* HTML comment on the line, so a card whose
-- text contains a literal HTML comment of its own is no longer truncated at it.
local function split_property_comment(text)
	return text:match("^(.*)%s*<!%-%-%s*(.-)%s*%-%->%s*$")
end

-- Parse a task line and extract properties
local function parse_task(line)
	local task = {
		text = "",
		content_lines = {line},  -- Start with first line
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
	local task_text, comment = split_property_comment(text)

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
	table.insert(board.content_blocks, block)
end

-- Helper: Finalize a card and add it to the column
local function finalize_card(column, card_data)
	-- Extract text from first line
	local first_line = card_data.content_lines[1]
	local text = first_line:match(patterns.task_item)

	-- Check for inline properties on first line
	-- Note: parse_task has already extracted inline properties, but we need to
	-- clean the text and update content_lines. We merge (not replace) so that
	-- pending_config and inline properties can coexist -- see PLAN-config-fixes.md Task 6
	local task_text, comment = split_property_comment(text)
	if task_text and comment then
		card_data.text = task_text:gsub("^%s+", ""):gsub("%s+$", "")
		-- Merge inline comment properties into existing properties (don't replace)
		card_data.properties:merge(parse_properties(comment))

		-- Update first line in content_lines to remove properties
		card_data.content_lines[1] = "- " .. card_data.text
	else
		card_data.text = text:gsub("^%s+", ""):gsub("%s+$", "")
	end

	-- Create Card object
	local card = Card:new(
		card_data.properties.id,
		card_data.text,
		card_data.properties
	)

	card.line_number = card_data.line_number
	card.column = card_data.column
	card.raw = card_data.raw

	-- Store content lines if multi-line
	if #card_data.content_lines > 1 then
		card.content_lines = card_data.content_lines
	end

	column:add_card(card)
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

	-- Multiline card tracking
	local current_card = nil          -- Card being accumulated
	local blank_line_seen = false     -- Track blank lines
	local column_has_cards = false    -- Track if current column has any cards yet

	-- Fenced code block tracking
	local fence_marker = nil          -- Open fence's delimiter, nil when outside a fence
	local fence_card = nil            -- Card the open fence belongs to, if any

	if lines ~= nil then
		for _, line in ipairs(lines) do
			line_number = line_number + 1

			-- Track whether this line should be added to markdown buffer
			local add_to_markdown = true

			-- A fence can only be opened by a line the branches below do not
			-- consume as kanban syntax, so remember the comment state now:
			-- the branches may clear it before the fence check at the bottom
			-- of the loop.
			local was_in_comment_block = in_comment_block

			-- Whether the fence branch below consumed this line, so that a
			-- closing delimiter is not mistaken for a new opening one.
			local in_fence = false

			-- Handle fenced code blocks. Nothing between the fences is kanban
			-- syntax, however much it looks like a column, a card or a
			-- property comment, so route the line straight to wherever the
			-- surrounding content is going and skip the parsing branches.
			if fence_marker then
				add_to_markdown = false
				in_fence = true

				if fence_closes(fence_marker, line) then
					fence_marker = nil
				end

				if fence_card then
					-- A fence opened inside a card's continuation lines; the
					-- whole block, blank lines included, stays with the card.
					table.insert(fence_card.content_lines, line)
				else
					table.insert(markdown_buffer, line)
				end

				if not fence_marker then
					fence_card = nil
				end
			-- Handle multi-line comment blocks
			elseif in_comment_block then
				add_to_markdown = false
				local ending = line:match(patterns.comment_block_end)
				if ending then
					comment_buffer = comment_buffer .. " " .. ending
					in_comment_block = false

					-- Process the complete comment
					if config_type == "board" and comment_buffer:match("kanban:config") then
						local config_content = comment_buffer:match("^%s*kanban:config%s*,?%s*(.*)")
						if config_content and config_content ~= "" then
							-- Merge into existing config (later comments override earlier keys)
							self.config:merge(coerce_numeric_config(parse_properties(config_content)))
						end
						pending_config = nil
					-- e.g. <!-- column:config wip_limit: 3 --> or <!-- config type: wip -->
					elseif config_type == "column" then
						-- Handle both "column:config" and simplified "config" syntax
						local config_content = comment_buffer:match("^%s*column:config%s*,?%s*(.*)")
							or comment_buffer:match("^%s*config%s*,?%s*(.*)")
						apply_column_config(current_column, config_content)
						pending_config = nil
					elseif config_type == "task" and current_column then
						-- Task properties (multi-line comment following a card).
						-- Mirror the single-line path (see the comment_single
						-- branch below): stash as pending_config so the
						-- existing flush logic (task/column/archive/EOF
						-- branches) applies it to current_card. See
						-- PLAN-config-fixes.md Task 4.
						pending_config = { properties = parse_properties(comment_buffer) }
					end

					comment_buffer = ""
					config_type = nil
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
							-- Merge into existing config (later comments override earlier keys)
							self.config:merge(coerce_numeric_config(parse_properties(config_content)))
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

				-- Flush current card if any
				if current_card then
					-- Apply pending config if any
					if pending_config then
						for k, v in pairs(pending_config.properties) do
							current_card.properties[k] = v
						end
						pending_config = nil
					end
					finalize_card(current_column, current_card)
					current_card = nil
					blank_line_seen = false
				end

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

				-- Reset card tracking for archive column
				column_has_cards = false
			-- Parse column headers
			elseif line:match(patterns.column_header) then
				local column_name = line:match(patterns.column_header)

				if not column_name:match("^__") then  -- Regular column
					add_to_markdown = false

					-- Flush current card if any
					if current_card then
						-- Apply pending config if any
						if pending_config then
							for k, v in pairs(pending_config.properties) do
								current_card.properties[k] = v
							end
							pending_config = nil
						end
						finalize_card(current_column, current_card)
						current_card = nil
						blank_line_seen = false
					else
						-- No open current_card: if there's pending_config, it
						-- belonged to nothing (orphaned property comment between
						-- columns) and should be dropped per PLAN-config-fixes.md Task 10
						pending_config = nil
					end

					-- Flush markdown buffer before column
					flush_markdown_buffer(self, markdown_buffer)
					markdown_buffer = {}

					current_column = Column:new("column_" .. #self.columns + 1, column_name)
					current_column.line_number = line_number
					current_column.command_log = self.command_log -- Share command log
					table.insert(self.columns, current_column)

					-- Add column block
					add_structured_block(self, ContentBlock.column(current_column))

					-- Reset card tracking for new column
					column_has_cards = false
				else
					-- Unknown "__X__" special section (anything other than
					-- __ARCHIVE__, which is handled above). There is no
					-- recognised structure for it, so preserve it verbatim as
					-- markdown rather than destroying it, and stop routing
					-- subsequent content to the *previous* column (see
					-- PLAN-config-fixes.md Task 5).

					-- Flush current card if any, mirroring the regular
					-- column-header branch above, so the previous column's
					-- last card isn't left dangling.
					if current_card then
						-- Apply pending config if any
						if pending_config then
							for k, v in pairs(pending_config.properties) do
								current_card.properties[k] = v
							end
							pending_config = nil
						end
						finalize_card(current_column, current_card)
						current_card = nil
						blank_line_seen = false
					else
						-- No open current_card: if there's pending_config, it
						-- belonged to nothing (orphaned property comment between
						-- columns) and should be dropped per PLAN-config-fixes.md Task 10
						pending_config = nil
					end

					-- Stop attributing following list items/content to the
					-- previous column. With current_column nil, the
					-- task/blank/continuation handling below is skipped
					-- entirely, so this header line and everything that
					-- follows falls through to the generic markdown-buffer
					-- path (add_to_markdown stays true) until the next
					-- H6/H1/archive header flushes it as one markdown block.
					current_column = nil
					column_has_cards = false
				end
			-- Parse tasks with multi-line support
			elseif current_column then
				local is_blank = line:match("^%s*$")
				local is_task = line:match(patterns.task_item)
				local is_continuation = is_continuation_line(line)

				-- An empty list item ("-" with nothing after it, or only
				-- trailing whitespace) gives a card no usable text. Report it
				-- and let the line fall through to whichever branch it would
				-- otherwise take (see features/multiline-lists.md, "Empty
				-- Cards", and SPEC.md section 7.4).
				if not is_blank and is_empty_list_item(line) then
					notify("List items may not start with a blank line")
				end

				-- Handle blank lines
				if is_blank then
					if current_card then
						blank_line_seen = true
					end
					table.insert(markdown_buffer, line)
					add_to_markdown = false

				-- Handle list items
				elseif is_task then
					-- Flush current card if any
					if current_card then
						-- Flush markdown buffer before finalizing card
						flush_markdown_buffer(self, markdown_buffer)
						markdown_buffer = {}

						-- Apply pending config if any
						if pending_config then
							for k, v in pairs(pending_config.properties) do
								current_card.properties[k] = v
							end
							pending_config = nil
						end

						finalize_card(current_column, current_card)
						current_card = nil
					else
						-- This is the first card in the column
						if not column_has_cards and #markdown_buffer > 0 then
							-- Store accumulated markdown verbatim as column header markdown.
							-- Trailing blank lines are part of the authored layout: the blank
							-- line separating prose from the first card has to survive the
							-- round trip, so nothing is trimmed here.
							current_column.header_markdown = TblUtils.deepcopy(markdown_buffer)
							markdown_buffer = {}
						else
							-- Flush markdown buffer before starting new card
							flush_markdown_buffer(self, markdown_buffer)
							markdown_buffer = {}
						end
					end

					-- Start new card
					current_card = parse_task(line)
					current_card.line_number = line_number
					current_card.column = current_column.name
					blank_line_seen = false
					add_to_markdown = false
					column_has_cards = true  -- Mark that we've seen at least one card

				-- Handle continuation lines
				elseif current_card and is_continuation and not blank_line_seen then
					table.insert(current_card.content_lines, line)
					add_to_markdown = false

				-- Handle column documentation
				else
					-- Flush current card if transitioning to markdown
					if current_card then
						-- Apply pending config if any
						if pending_config then
							for k, v in pairs(pending_config.properties) do
								current_card.properties[k] = v
							end
							pending_config = nil
						end

						finalize_card(current_column, current_card)
						current_card = nil
					end

					table.insert(markdown_buffer, line)
					add_to_markdown = false
					blank_line_seen = false
				end
			end

			-- Add line to markdown buffer if it's not a structured element
			if add_to_markdown then
				table.insert(markdown_buffer, line)
			end

			-- Open a fence, now that the line above has been routed normally.
			-- If it went into a card's continuation lines, the rest of the
			-- block belongs to that card too.
			if not fence_marker and not in_fence and not was_in_comment_block then
				local opening = match_fence(line)
				if opening then
					fence_marker = opening
					if current_card and is_continuation_line(line) then
						fence_card = current_card
					end
				end
			end
		end

		-- Flush current card if any at end of file
		if current_card then
			-- Apply pending config if any
			if pending_config then
				for k, v in pairs(pending_config.properties) do
					current_card.properties[k] = v
				end
				pending_config = nil
			end
			finalize_card(current_column, current_card)
			current_card = nil
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
