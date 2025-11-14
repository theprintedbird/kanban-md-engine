local Adapter = require("kanban-md.adapters.interface")

local NeovimAdapter = Adapter.new({
  name = "NeovimAdapter",

  notify = function(self, message, level)
    -- level should be a string like "info", "warn", "error"
    -- Convert to vim.log.levels constant
    local level_str = string.upper(level or "info")
    local log_level = vim.log.levels[level_str] or vim.log.levels.INFO
    vim.notify(message, log_level)
  end,

	get_current_buffer = function()
		return vim.api.nvim_get_current_buf()
	end,

	get_buffer_name = function(self, bufnr)
		return vim.api.nvim_buf_get_name(bufnr)
	end,

	buf_line_count = function(self, bufnr)
		return vim.api.nvim_buf_line_count(bufnr)
	end,


	read_buffer = function(self, bufnr, opts)
		-- {buffer}, {start}, {end}, {strict_indexing}
		opts = opts or {}
		local start = opts.start or 0
		local _end = opts._end or -1
		return vim.api.nvim_buf_get_lines(bufnr, start, _end, false)
	end,

	-- Write array of strings to buffer/file
	write_buffer = function(self, lines, opts)
		opts = opts or {}
		local bufnr = opts.bufnr or get_current_buffer()
		local start = opts.start or 0
		local _end = opts._end or -1
		local strict_indexing = false
	-- {buffer} (integer) Buffer id, or 0 for current buffer
	-- {start} (integer) First line index
	-- {end} (integer) Last line index, exclusive
	-- {strict_indexing} (boolean) Whether out-of-bounds should be an error.
	-- {replacement} (string[]) Array of lines to use as replacement
		vim.api.nvim_buf_set_lines(bufnr, start, _end, strict_indexing, lines)
	end,

  -- Required: Cursor management
  get_cursor = function(self)
		return vim.api.nvim_win_get_cursor(0)
  end,

  set_cursor = function(self, line, col)
    -- Set cursor position
		pcall(vim.api.nvim_win_set_cursor, 0, {line, col})
  end,

  -- Required: UI prompts
  prompt_input = function(self, prompt, default, callback)
    -- Prompt user for input, call callback(input)
    vim.ui.input({
			prompt = prompt,
			default = default,
		}, callback)
  end,

	---@class vim.ui.SelectOpts
	---@field prompt? string Text of the prompt. Defaults to "Select one of:"
	---@field format_item? fun(item: any): string Function to format an individual item. Defaults to tostring
	---@field kind? string Arbitrary hint string indicating the item shape

	---@param items any[] Arbitrary items to select from
	---@param opts vim.ui.SelectOpts Additional options
	---@param on_choice fun(item: any?, idx: integer?) Called once the user made a choice. `item` is the selected item or nil if aborted. `idx` is the 1-based index or nil if aborted
  prompt_select = function(self, items, opts, callback)
		opts = opts or {}

    -- Prompt user to select from items, call callback(item, idx)
		vim.ui.select(items, opts, callback)
  end,

  -- Optional: Virtual text support
  supports_virtual_text = function(self)
    return true  -- Override if you support virtual text
  end,

  create_namespace = function(self, name)
    -- Return namespace ID if supported, nil otherwise
		return vim.api.nvim_create_namespace(name)
  end,

  clear_namespace = function(self, bufnr, ns, opts)
		opts = opts or {}
		local line_start = opts.line_start or 0
		local line_end = opts.line_end or -1
    -- Clear virtual text if supported
		return vim.api.nvim_buf_clear_namespace(bufnr, ns, line_start, line_end)
  end,

  set_extmark = function(self, bufnr, ns, line, col, opts)
    -- Set extmark for virtual text
    return vim.api.nvim_buf_set_extmark(bufnr, ns, line, col, opts)
  end,
})
return NeovimAdapter
