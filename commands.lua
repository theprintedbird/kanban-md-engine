-- lua/kanban-md/commands.lua
-- Neovim user commands for kanban-md plugin

local Board = require("kanban-md.board")
local config = require("kanban-md.config")
local column_helper = require("kanban-md.helpers.column")
local virtual_text = require("kanban-md.virtual_text")
local adapter_registry = require("kanban-md.adapter_registry")

local M = {}

-- Get adapter from central registry
local function get_adapter()
  return adapter_registry.get_adapter()
end

-- State for two-step dependency creation
local dependency_state = {
  first_card = nil,        -- The card that will depend on another
  first_column = nil,      -- Column containing the first card
  first_line = nil,        -- Line number for visual feedback
  extmark_id = nil,        -- ID of the highlight extmark
}

-- Namespace for dependency marking highlights (initialized lazily on first use)
local ns_dependency = nil
local function get_ns_dependency()
  if not ns_dependency then
    ns_dependency = get_adapter():create_namespace('kanban_dependency_mark')
  end
  return ns_dependency
end

-- Helper function to clear dependency state
local function clear_dependency_state()
  -- Clear highlight if exists
  if dependency_state.extmark_id and dependency_state.first_line then
    local bufnr = vim.api.nvim_get_current_buf()
    pcall(vim.api.nvim_buf_del_extmark, bufnr, get_ns_dependency(), dependency_state.extmark_id)
  end

  -- Reset state
  dependency_state.first_card = nil
  dependency_state.first_column = nil
  dependency_state.first_line = nil
  dependency_state.extmark_id = nil
end

-- Helper function to extract user-friendly error message from Lua error strings
-- Strips technical context and file paths, preserving the core error message
local function extract_error_message(err)
  if type(err) ~= "string" then
    return "An unknown error occurred"
  end

  -- Pattern 1: Extract message after validation failed pattern
  -- "Card entry validation failed [trigger_name]: User Message"
  local msg = err:match("Card %w+ validation failed %[%w+%]: (.+)")
  if msg then
    -- Clean up file path references if present
    msg = msg:gsub("%.%.%.%w+Bird/[^:]+:%d+: ", "")
    return msg
  end

  -- Pattern 2: Extract message after trigger failed pattern
  -- "Entry trigger failed: trigger_name: User Message"
  msg = err:match("Entry trigger failed: [%w_]+: (.+)")
  if msg then
    msg = msg:gsub("%.%.%.%w+Bird/[^:]+:%d+: ", "")
    return msg
  end

  -- Pattern 3: Extract message after exit trigger failed pattern
  msg = err:match("Exit trigger '[%w_]+' failed: (.+)")
  if msg then
    msg = msg:gsub("%.%.%.%w+Bird/[^:]+:%d+: ", "")
    return msg
  end

  -- Pattern 4: Clean up file paths from any remaining error
  -- Remove patterns like "...edBird/nvim-plugins/kanban-md/lua/kanban-md/file.lua:123: "
  msg = err:gsub("%.%.%.%w+Bird/[^:]+:%d+: ", "")

  -- If the message still has a stack trace reference at the start, extract just the message
  local clean_msg = msg:match("^[^:]+:%d+: (.+)") or msg

  return clean_msg
end

-- Helper function to notify user with Kanban plugin context
local function notify(message, level)
  get_adapter():notify(message, level, { title = "Kanban" })
end

-- Helper function to get current buffer lines
local function get_buffer_lines(bufnr)
  bufnr = bufnr or 0
  return get_adapter():read_buffer(bufnr )
end

-- Helper function to set buffer lines
local function set_buffer_lines(lines, bufnr)
  bufnr = bufnr or 0
  get_adapter():write_buffer(lines,{ bufnr = bufnr})
end

-- Helper function to get current buffer's board
local function get_current_board()
  local lines = get_buffer_lines()
  local board = Board:new()
  board:parse(lines)

  -- Validate dependencies on parse if enabled
  if config.get_value("dependency_check_on_parse") then
    local result = board:validate_dependencies()
    if not result:is_success() then
      -- Show errors
      if #result.errors > 0 then
        local error_msg = "Dependency errors:\n" .. table.concat(result.errors, "\n")
        notify(error_msg, "error")
      end
      -- Show warnings
      if #result.warnings > 0 then
        local warning_msg = "Dependency warnings:\n" .. table.concat(result.warnings, "\n")
        notify(warning_msg, "warn")
      end
    end
  end

  return board
end

-- Helper function to update current buffer with board content
local function update_buffer_with_board(board, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = board:write()
  set_buffer_lines(lines, bufnr)

  -- Re-parse board to get fresh line numbers after writing
  local fresh_board = Board:new()
  fresh_board:parse(lines)

  -- Update virtual text with fresh line numbers
  virtual_text.update_virtual_text(fresh_board, bufnr)
end

-- Helper function to get user input
local function get_input(prompt, default, callback)
  get_adapter():prompt_input(prompt, default or "", function(result)
    if result and result ~= "" then
      callback(result)
    end
  end)
end

-- Helper function to show selection menu
local function select_from_list(items, prompt, callback)
  if not items or #items == 0 then
    get_adapter():notify("No items to select from", "warn")
    return
  end

  get_adapter():prompt_select(items, {
    prompt = prompt,
    format_item = function(item)
      return tostring(item)
    end,
  }, callback)
end

-- Helper function to find cursor position card
local function get_card_at_cursor()
  local board = get_current_board()
  local cursor = get_adapter():get_cursor(0)
  local line_num = cursor[1]

  -- Look through all columns and cards to find one at this line
  for _, column in ipairs(board.columns) do
    for _, card in ipairs(column.cards) do
      if card.line_number == line_num then
        return card, column, board
      end
    end
  end

  -- Check archive
  if board.archive then
    for _, card in ipairs(board.archive.cards) do
      if card.line_number == line_num then
        return card, board.archive, board
      end
    end
  end

  return nil, nil, board
end

-- Helper function to move cursor to a card marked with _cursor_target
-- @param board_with_flag The board instance that has cards with _cursor_target flags
local function move_cursor_to_target_card(board_with_flag)
  -- We need to re-parse to get line numbers, but keep track of which card to find
  local target_card_text = nil
  local target_column_name = nil

  -- First, find the card with the flag in the passed board
  if board_with_flag then
    for _, column in ipairs(board_with_flag.columns) do
      for _, card in ipairs(column.cards) do
        if card.properties and card.properties._cursor_target then
          target_card_text = card.text
          target_column_name = column.name
          break
        end
      end
      if target_card_text then break end
    end
  end

  -- If no target found in passed board, return
  if not target_card_text then
    return false
  end

  -- Re-parse the current buffer to get updated line numbers
  local board = get_current_board()

  -- Search for the card by text and column name in the re-parsed board
  local target_line = nil

  for _, column in ipairs(board.columns) do
    if column.name == target_column_name then
      -- Search for card with matching text in this column
      for _, card in ipairs(column.cards) do
        if card.text == target_card_text then
          target_line = card.line_number
          break
        end
      end
      break
    end
  end

  -- If found, move cursor
  if target_line then
    get_adapter():set_cursor(0, {line = target_line, col = 0})
    return true
  end

  return false
end

-- Command: Create new kanban board
function M.new_board()
  get_input("Board title: ", "New Kanban Board", function(title)
    local board = Board:new()
    board.title = title

    -- Add default columns from config
    local default_columns = config.get_value("default_columns")
    for _, col_name in ipairs(default_columns) do
      board:add_column("col_" .. col_name:lower():gsub("%s+", "_"), col_name)
    end

    -- Clear current buffer and set new board content
    update_buffer_with_board(board)
    get_adapter():notify("Created new kanban board: " .. title, "info")
  end)
end

-- Command: Add new card
function M.new_card()
  local board = get_current_board()

  if #board.columns == 0 then
    get_adapter():notify("No columns found. Create a board first.", "error")
    return
  end

  get_input("Card text: ", "", function(card_text)
    -- Get column names for selection
    local column_names = {}
    for _, col in ipairs(board.columns) do
      table.insert(column_names, col.name)
    end

    select_from_list(column_names, "Select column:", function(choice)
      if not choice then return end

      -- Re-parse board to get current state
      local current_board = get_current_board()

      -- Find the selected column
      local selected_column = nil
      for _, col in ipairs(current_board.columns) do
        if col.name == choice then
          selected_column = col
          break
        end
      end

      if selected_column then
        -- Create new card
        local card = require("kanban-md.card"):new(nil, card_text, {})

        -- Wrap in pcall to catch validation errors (e.g., WIP limits)
        local success, err = pcall(function()
          selected_column:add_card(card)
        end)

        if not success then
          notify(extract_error_message(err), "error")
          return
        end

        -- Update buffer
        update_buffer_with_board(current_board)

        -- Move cursor to new card if enabled
        if config.get_value('enable_cursor_positioning') then
          move_cursor_to_target_card(current_board)
        end

        notify("Added card '" .. card_text .. "' to " .. choice, "info")
      end
    end)
  end)
end

-- Command: Move card to different column
function M.move_card()
  local card, current_column, board = get_card_at_cursor()

  if not card then
    get_adapter():notify("No card found at cursor position", "warn")
    return
  end
	if not current_column then
		get_adapter():notify("The current column could not be ascertained or found.", "error")
		return
	end

  -- Get column names for selection (excluding current column)
  local column_names = {}
  for _, col in ipairs(board.columns) do
    if col.name ~= current_column.name then
      table.insert(column_names, col.name)
    end
  end

  -- Add archive option
  table.insert(column_names, "__ARCHIVE__")

  select_from_list(column_names, "Move card to:", function(choice)
    if not choice then return end

    -- Re-parse board to get current state
    local current_board = get_current_board()

    -- Find current card and column in refreshed board
    -- Use line_number for matching since IDs may not exist on parsed cards
    local current_card, source_column = nil, nil
    for _, col in ipairs(current_board.columns) do
      for _, c in ipairs(col.cards) do
        if c.line_number == card.line_number then
          current_card = c
          source_column = col
          break
        end
      end
      if current_card then break end
    end

    -- Also check archive if not found in columns
    if not current_card and current_board.archive then
      for _, c in ipairs(current_board.archive.cards) do
        if c.line_number == card.line_number then
          current_card = c
          source_column = current_board.archive
          break
        end
      end
    end

    if not current_card or not source_column then
      get_adapter():notify("Card not found after refresh", "error")
      return
    end

    -- Find target column or archive
    local target_column = nil
    if choice == "__ARCHIVE__" then
      if not current_board.archive then
        current_board.archive = require("kanban-md.column"):new("__ARCHIVE__", "__ARCHIVE__")
        current_board.archive.is_archive = true
      end
      target_column = current_board.archive
      -- Add archived timestamp
      current_card.properties.archived = os.time()
    else
      for _, col in ipairs(current_board.columns) do
        if col.name == choice then
          target_column = col
          break
        end
      end

      if target_column and config.get_value("auto_timestamp") then
        local col_key = choice:lower():gsub("%s+", "_")
        current_card.properties[col_key] = os.time()
      end
    end

    if not target_column then
      get_adapter():notify("Target column not found", "error")
      return
    end

    -- Wrap move operation in pcall to catch validation errors
    local success, err = pcall(function()
      current_board:move_card(current_card, source_column, target_column)
    end)

    if not success then
      notify(extract_error_message(err), "error")
      return
    end

    update_buffer_with_board(current_board)
    notify("Moved card '" .. current_card.text .. "' to " .. choice, "info")
  end)
end

-- Command: Mark card as complete and move to Done column
function M.complete_card()
  local card, current_column, board = get_card_at_cursor()

  if not card then
    get_adapter():notify("No card found at cursor position", "warn")
    return
  end

  -- Find completion column
  local done_column = nil
  for _, col in ipairs(board.columns) do
    if column_helper.is_completion_column(col, board) then
      done_column = col
      break
    end
  end

  if not done_column then
    get_adapter():notify("No completion column found", "error")
    return
  end

  -- Add completion timestamp and move using new API
  if config.get_value("auto_timestamp") then
    local col_key = done_column.name:lower():gsub("%s+", "_")
    card.properties[col_key] = os.time()
  end

  -- Wrap move operation in pcall to catch validation errors
  local success, err = pcall(function()
    board:move_card(card, current_column, done_column)
  end)

  if not success then
    notify(extract_error_message(err), "error")
    return
  end

  update_buffer_with_board(board)
  notify("Completed card '" .. card.text .. "'", "info")
end

-- Helper function to execute force complete
local function execute_force_complete(card, current_column, done_column, board)
  -- Add completion timestamp if enabled
  if config.get_value("auto_timestamp") then
    local col_key = done_column.name:lower():gsub("%s+", "_")
    card.properties[col_key] = os.time()
  end

  -- Attempt move with dependency/subtask bypass
  local success, err = pcall(function()
    board:move_card_with_bypass(
      card,
      current_column,
      done_column,
      {"dependency", "subtask"}  -- Only bypass these categories
    )
  end)

  if not success then
    notify(extract_error_message(err), "error")
    return
  end

  update_buffer_with_board(board)
  notify(
    string.format("Force completed '%s' (bypassed dependency/subtask checks)", card.text),
    "info"
  )
end

-- Command: Force complete card (bypass dependency/subtask validation)
function M.force_complete_card()
  local card, current_column, board = get_card_at_cursor()

  if not card then
    get_adapter():notify("No card found at cursor position", "warn")
    return
  end

  -- Find completion column
  local done_column = nil
  for _, col in ipairs(board.columns) do
    if column_helper.is_completion_column(col, board) then
      done_column = col
      break
    end
  end

  if not done_column then
    get_adapter():notify("No completion column found", "error")
    return
  end

  -- Check if card already in completion column
  if column_helper.is_completion_column(current_column, board) then
    get_adapter():notify("Card is already in a completion column", "warn")
    return
  end

  -- Show confirmation if configured
  if config.get_value("confirm_destructive") then
    get_adapter():prompt_select(
      {"Yes, force complete", "Cancel"},
      {
        prompt = string.format(
          "Force complete '%s' (bypasses dependency/subtask checks)?\n" ..
          "⚠️  WIP limits and workflow rules will still apply.",
          card.text
        ),
      },
      function(choice)
        if choice == "Yes, force complete" then
          execute_force_complete(card, current_column, done_column, board)
        end
      end
    )
  else
    execute_force_complete(card, current_column, done_column, board)
  end
end

-- Command: Set complexity on card at cursor
function M.set_complexity()
  local card, current_column, board = get_card_at_cursor()

  if not card then
    get_adapter():notify("No card found at cursor position", "warn")
    return
  end

  -- Get current complexity if it exists
  local current = card.properties.complexity or ""

  get_input("Set complexity: ", tostring(current), function(input)
    -- Validate input is a positive number
    local complexity = tonumber(input)

    if not complexity then
      get_adapter():notify("Invalid complexity value. Must be a number.", "error")
      return
    end

    if complexity < 0 then
      get_adapter():notify("Complexity must be a positive number", "error")
      return
    end

    -- Re-parse board to get current state
    local current_board = get_current_board()

    -- Find the card again in the refreshed board
    local current_card = nil
    for _, col in ipairs(current_board.columns) do
      for _, c in ipairs(col.cards) do
        if c.line_number == card.line_number then
          current_card = c
          break
        end
      end
      if current_card then break end
    end

    -- Also check archive if not found in columns
    if not current_card and current_board.archive then
      for _, c in ipairs(current_board.archive.cards) do
        if c.line_number == card.line_number then
          current_card = c
          break
        end
      end
    end

    if not current_card then
      get_adapter():notify("Card not found after refresh", "error")
      return
    end

    -- Set the complexity
    current_card.properties.complexity = complexity

    -- Update buffer
    update_buffer_with_board(current_board)
    get_adapter():notify("Set complexity to " .. complexity .. " for card '" .. current_card.text .. "'", "info")
  end)
end

-- Command: Archive done cards based on age
function M.archive_done_cards()
  local board = get_current_board()
  local archive_days = config.get_value("archive_after_days") or 30

  -- Use board method to perform archival
  local archived_count = board:archive_done_cards(archive_days)

  if archived_count > 0 then
    update_buffer_with_board(board)
    get_adapter():notify("Archived " .. archived_count .. " cards older than " .. archive_days .. " days", "info")
  else
    get_adapter():notify("No cards to archive", "info")
  end
end

-- Command: Add new column to board
function M.new_column()
  local board = get_current_board()

  get_input("Column name: ", "", function(column_name)
    if not column_name or column_name == "" then
      get_adapter():notify("Column name cannot be empty", "error")
      return
    end

    -- Check if column already exists
    if board:get_column_by_name(column_name) then
      get_adapter():notify("Column '" .. column_name .. "' already exists", "error")
      return
    end

    -- Optionally prompt for WIP limit (use get_adapter():prompt_input directly to handle empty input)
    get_adapter():prompt_input("WIP limit (optional, press Enter to skip): ", "", function(wip_input)
				-- Re-parse board to get current state
				local current_board = get_current_board()

				-- Prepare config
				local col_config = nil
				if wip_input and wip_input ~= "" then
					local wip_limit = tonumber(wip_input)
					if wip_limit and wip_limit > 0 then
						col_config = { wip_limit = wip_limit }
					else
						get_adapter():notify("Invalid WIP limit. Column created without WIP limit.", "warn")
					end
				end

				-- Wrap column creation in pcall to catch any errors
				local success, err = pcall(function()
					current_board:add_new_column(column_name, col_config)
				end)

				if not success then
					notify(extract_error_message(err), "error")
					return
				end

				-- Update buffer
				update_buffer_with_board(current_board)

				local msg = "Added column '" .. column_name .. "'"
				if col_config and col_config.wip_limit then
					msg = msg .. " with WIP limit " .. col_config.wip_limit
				end
				notify(msg, "info")
    end)
  end)
end

-- Command: Show board statistics
function M.show_stats()
  local board = get_current_board()
  board:calculate_stats()

  -- Get formatted stats from stats module
  local stats_module = require("kanban-md.stats")
  local lines = stats_module.format_stats_display(board)
  -- Show in a new buffer or floating window
  -- Check if a stats buffer already exists
  local stats_buf_name = "Kanban Statistics"
  local existing_buf = nil

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match(stats_buf_name .. "$") then
        existing_buf = buf
        break
      end
    end
  end

  local buf
  if existing_buf then
    -- Reuse existing buffer
    buf = existing_buf
		vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    get_adapter():write_buffer(lines, {bufnr = buf})
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  else
    -- Create new buffer
    buf = vim.api.nvim_create_buf(false, true)
    get_adapter():write_buffer(lines, { bufnr = buf})
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
		vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    vim.api.nvim_buf_set_name(buf, stats_buf_name)
  end

  -- Find existing window with this buffer or open in split
  local stats_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      stats_win = win
      break
    end
  end

  if not stats_win then
    vim.cmd("split")
    stats_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(stats_win, buf)
  else
    vim.api.nvim_set_current_win(stats_win)
  end
end

-- Command: Add dependency between two cards (two-step process)
function M.add_dependency()
  local card, column, board = get_card_at_cursor()

  if not card then
    get_adapter():notify("No card found at cursor position", "warn")
    clear_dependency_state()
    return
  end

  -- First invocation: Mark the dependant card (the one that will depend on another)
  if not dependency_state.first_card then
    -- Validate card has ID
    if not card.properties.id or card.properties.id == "" then
      get_adapter():notify("Card must have an ID property. Run :KanbanPersistIds to enable persistent IDs.", "error")
      return
    end

    -- Store first card
    dependency_state.first_card = card
    dependency_state.first_column = column
    dependency_state.first_line = card.line_number

    -- Add visual feedback (highlight the line)
    local bufnr = vim.api.nvim_get_current_buf()
    dependency_state.extmark_id = get_adapter():set_extmark(bufnr, get_ns_dependency(), card.line_number - 1, 0, {
      line_hl_group = config.get_value("dependency_marking_hl"),
      priority = 100,
    })

    notify("First card marked. Select the dependency card and run command again.", "info")
    return
  end

  -- Second invocation: Mark the dependency card
  -- Validate second card has ID
  if not card.properties.id or card.properties.id == "" then
    get_adapter():notify("Dependency card must have an ID property. Run :KanbanPersistIds to enable persistent IDs, or move the card to generate a temporary ID.", "error")
    clear_dependency_state()
    return
  end

  -- Validate not adding self-dependency
  if card.properties.id == dependency_state.first_card.properties.id then
    get_adapter():notify("Cannot add a card as its own dependency", "error")
    clear_dependency_state()
    return
  end

  -- Re-parse board to get current state
  local current_board = get_current_board()

  -- Find the first card in the refreshed board
  local first_card_refreshed = nil
  local first_column_refreshed = nil
  for _, col in ipairs(current_board.columns) do
    for _, c in ipairs(col.cards) do
      if c.properties.id == dependency_state.first_card.properties.id then
        first_card_refreshed = c
        first_column_refreshed = col
        break
      end
    end
    if first_card_refreshed then break end
  end

  -- Check archive if not found in columns
  if not first_card_refreshed and current_board.archive then
    for _, c in ipairs(current_board.archive.cards) do
      if c.properties.id == dependency_state.first_card.properties.id then
        first_card_refreshed = c
        first_column_refreshed = current_board.archive
        break
      end
    end
  end

  if not first_card_refreshed then
    get_adapter():notify("First card not found after refresh", "error")
    clear_dependency_state()
    return
  end

  -- Initialize depends_on array if needed
  if not first_card_refreshed.properties.depends_on then
    first_card_refreshed.properties.depends_on = {}
  end

  -- Ensure depends_on is an array
  if type(first_card_refreshed.properties.depends_on) ~= "table" then
    first_card_refreshed.properties.depends_on = { first_card_refreshed.properties.depends_on }
  end

  -- Check for duplicate dependency
  for _, dep_id in ipairs(first_card_refreshed.properties.depends_on) do
    if dep_id == card.properties.id then
      get_adapter():notify("Dependency already exists", "warn")
      clear_dependency_state()
      return
    end
  end

  -- Optional: Check for circular dependencies
  local function has_circular_dependency(start_id, target_id, board_ref)
    local visited = {}
    local function check_deps(current_id)
      if current_id == target_id then
        return true
      end
      if visited[current_id] then
        return false
      end
      visited[current_id] = true

      local task = board_ref:find_task(current_id)
      if not task or not task.properties.depends_on then
        return false
      end

      for _, dep_id in ipairs(task.properties.depends_on) do
        if check_deps(dep_id) then
          return true
        end
      end
      return false
    end
    return check_deps(start_id)
  end

  if has_circular_dependency(card.properties.id, dependency_state.first_card.properties.id, current_board) then
    get_adapter():notify("Cannot add dependency: would create a circular dependency", "error")
    clear_dependency_state()
    return
  end

  -- Add the dependency
  table.insert(first_card_refreshed.properties.depends_on, card.properties.id)

  -- Update buffer
  update_buffer_with_board(current_board)

  -- Clear state and visual feedback
  clear_dependency_state()

  notify("Added dependency: '" .. first_card_refreshed.text .. "' depends on '" .. card.text .. "'", "info")
end

-- Command: Enable persistent IDs for cards
function M.persist_card_ids()
  local board = get_current_board()

  -- Check if persist_card_ids is already enabled in board config
  local already_enabled = board.config and board.config.persist_card_ids == true

  -- Check global config as well
  local global_enabled = config.get_value("persist_card_ids")

  if already_enabled and global_enabled then
    get_adapter():notify("Persistent card IDs are already enabled for this board", "info")
    return
  end

  -- Enable persist_card_ids in board config
  if not board.config then
    board.config = {}
  end
  board.config.persist_card_ids = true

  -- Also update global config for this session
  config.setup({ persist_card_ids = true })

  -- Count cards that will get IDs persisted
  local card_count = 0
  local cards_needing_ids = 0

  -- Ensure all cards have IDs
  for _, column in ipairs(board.columns) do
    for _, card in ipairs(column.cards) do
      card_count = card_count + 1
      if not card.id or card.id == "" then
        -- Generate ID using ULID if available, otherwise use simple hash
        local id_triggers = require('kanban-md.extras.id_triggers')
        local trigger_fn = id_triggers.ulid_id()
        local context = { card = card, timestamp = os.time() }
        trigger_fn(card, context)
        cards_needing_ids = cards_needing_ids + 1
      end
    end
  end

  -- Check archive as well
  if board.archive then
    for _, card in ipairs(board.archive.cards) do
      card_count = card_count + 1
      if not card.id or card.id == "" then
        local id_triggers = require('kanban-md.extras.id_triggers')
        local trigger_fn = id_triggers.ulid_id()
        local context = { card = card, timestamp = os.time() }
        trigger_fn(card, context)
        cards_needing_ids = cards_needing_ids + 1
      end
    end
  end

  -- Update buffer with IDs now persisted
  update_buffer_with_board(board)

  local msg = string.format(
    "Enabled persistent card IDs. %d card%s will now have ID%s persisted to markdown.",
    card_count,
    card_count == 1 and "" or "s",
    card_count == 1 and "" or "s"
  )

  if cards_needing_ids > 0 then
    msg = msg .. string.format(" (%d new ID%s generated)", cards_needing_ids, cards_needing_ids == 1 and "" or "s")
  end

  notify(msg, "info")
end

-- Command: Show plugin version
function M.show_version()
  local version = require('kanban-md.version')
  vim.notify('kanban-md version ' .. version, vim.log.levels.INFO)
end

-- Setup function to register all commands
function M.setup()
  local commands = {
    KanbanNewBoard = M.new_board,
    KanbanNewCard = M.new_card,
    KanbanNewColumn = M.new_column,
    KanbanMoveCard = M.move_card,
    KanbanCompleteCard = M.complete_card,
    KanbanForceCompleteCard = M.force_complete_card,
    KanbanSetComplexity = M.set_complexity,
    KanbanArchive = M.archive_done_cards,
    KanbanStats = M.show_stats,
    KanbanAddDependency = M.add_dependency,
    KanbanPersistIds = M.persist_card_ids,
    KanbanVersion = M.show_version,
  }

  for name, func in pairs(commands) do
    vim.api.nvim_create_user_command(name, func, {
      desc = "Kanban: " .. name:gsub("Kanban", ""):gsub("(%l)(%u)", "%1 %2")
    })
  end

  -- Setup autocmd to refresh virtual text when entering kanban buffers
  vim.api.nvim_create_autocmd({"BufEnter", "BufWritePost"}, {
    pattern = "*.md",
    callback = function(args)
      local bufnr = args.buf
      local lines = get_adapter():read_buffer(bufnr)

      -- Quick check: does this look like a kanban board?
      local is_kanban = false
      local strategy = config.get_value("detection_strategy")

      -- Handle legacy config option for backwards compatibility
      if not strategy or strategy == "" then
        local require_marker = config.get_value("require_kanban_marker")
        if require_marker == true then
          strategy = "marker"
        elseif require_marker == false then
          strategy = "auto"
        else
          strategy = "marker" -- default
        end
      end

      -- Get buffer name for extension checking
      local bufname = get_adapter():get_buffer_name(bufnr)
      local has_kanban_extension = bufname and bufname:match("%.kanban%.md$") ~= nil

      if strategy == "marker" then
        -- Look for explicit <!-- kanban-board --> marker in first 10 lines
        for i = 1, math.min(10, #lines) do
          if lines[i]:match("<!%-%-%s*kanban%-board%s*%-%->") then
            is_kanban = true
            break
          end
        end
      elseif strategy == "extension" then
        -- Only parse files with .kanban.md extension
        is_kanban = has_kanban_extension
      elseif strategy == "both" then
        -- Accept either marker OR .kanban.md extension
        if has_kanban_extension then
          is_kanban = true
        else
          -- Check for marker
          for i = 1, math.min(10, #lines) do
            if lines[i]:match("<!%-%-%s*kanban%-board%s*%-%->") then
              is_kanban = true
              break
            end
          end
        end
      elseif strategy == "auto" then
        -- Legacy behaviour: Look for H6 headers (######) which are used for columns
        for _, line in ipairs(lines) do
          if line:match("^######%s+") then
            is_kanban = true
            break
          end
        end
      end

      if is_kanban then
        -- Parse and update virtual text
        local board = Board:new()
        local ok, err = pcall(function()
          board:parse(lines)
          virtual_text.update_virtual_text(board, bufnr)
        end)

        if not ok then
          -- Silently fail - don't want to spam users with errors
          -- on non-kanban markdown files
        end
      end
    end,
    desc = "Update kanban virtual text on buffer enter"
  })
end

return M
