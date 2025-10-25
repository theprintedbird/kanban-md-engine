-- lua/kanban-md/commands.lua
-- Neovim user commands for kanban-md plugin

local Board = require("kanban-md.board")
local config = require("kanban-md.config")
local column_helper = require("kanban-md.helpers.column")

local M = {}

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
  vim.notify(message, level, { title = "Kanban" })
end

-- Helper function to get current buffer lines
local function get_buffer_lines(bufnr)
  bufnr = bufnr or 0
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

-- Helper function to set buffer lines
local function set_buffer_lines(lines, bufnr)
  bufnr = bufnr or 0
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

-- Helper function to get current buffer's board
local function get_current_board()
  local lines = get_buffer_lines()
  local board = Board:new()
  board:parse(lines)
  return board
end

-- Helper function to update current buffer with board content
local function update_buffer_with_board(board)
  local lines = board:write()
  set_buffer_lines(lines)
end

-- Helper function to get user input
local function get_input(prompt, default, callback)
  vim.ui.input({
    prompt = prompt,
    default = default or "",
  }, function(result)
    if result and result ~= "" then
      callback(result)
    end
  end)
end

-- Helper function to show selection menu
local function select_from_list(items, prompt, callback)
  if not items or #items == 0 then
    vim.notify("No items to select from", vim.log.levels.WARN)
    return
  end
  
  vim.ui.select(items, {
    prompt = prompt,
    format_item = function(item)
      return tostring(item)
    end,
  }, callback)
end

-- Helper function to find cursor position card
local function get_card_at_cursor()
  local board = get_current_board()
  local cursor = vim.api.nvim_win_get_cursor(0)
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
    vim.api.nvim_win_set_cursor(0, {target_line, 0})
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
    vim.notify("Created new kanban board: " .. title, vim.log.levels.INFO)
  end)
end

-- Command: Add new card
function M.new_card()
  local board = get_current_board()

  if #board.columns == 0 then
    vim.notify("No columns found. Create a board first.", vim.log.levels.ERROR)
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
          notify(extract_error_message(err), vim.log.levels.ERROR)
          return
        end

        -- Update buffer
        update_buffer_with_board(current_board)

        -- Move cursor to new card if enabled
        if config.get_value('enable_cursor_positioning') then
          move_cursor_to_target_card(current_board)
        end

        notify("Added card '" .. card_text .. "' to " .. choice, vim.log.levels.INFO)
      end
    end)
  end)
end

-- Command: Move card to different column
function M.move_card()
  local card, current_column, board = get_card_at_cursor()
  
  if not card then
    vim.notify("No card found at cursor position", vim.log.levels.WARN)
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
      vim.notify("Card not found after refresh", vim.log.levels.ERROR)
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
      vim.notify("Target column not found", vim.log.levels.ERROR)
      return
    end

    -- Wrap move operation in pcall to catch validation errors
    local success, err = pcall(function()
      current_board:move_card(current_card, source_column, target_column)
    end)

    if not success then
      notify(extract_error_message(err), vim.log.levels.ERROR)
      return
    end

    update_buffer_with_board(current_board)
    notify("Moved card '" .. current_card.text .. "' to " .. choice, vim.log.levels.INFO)
  end)
end

-- Command: Mark card as complete and move to Done column
function M.complete_card()
  local card, current_column, board = get_card_at_cursor()

  if not card then
    vim.notify("No card found at cursor position", vim.log.levels.WARN)
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
    vim.notify("No completion column found", vim.log.levels.ERROR)
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
    notify(extract_error_message(err), vim.log.levels.ERROR)
    return
  end

  update_buffer_with_board(board)
  notify("Completed card '" .. card.text .. "'", vim.log.levels.INFO)
end

-- Command: Set complexity on card at cursor
function M.set_complexity()
  local card, current_column, board = get_card_at_cursor()

  if not card then
    vim.notify("No card found at cursor position", vim.log.levels.WARN)
    return
  end

  -- Get current complexity if it exists
  local current = card.properties.complexity or ""

  get_input("Set complexity: ", tostring(current), function(input)
    -- Validate input is a positive number
    local complexity = tonumber(input)

    if not complexity then
      vim.notify("Invalid complexity value. Must be a number.", vim.log.levels.ERROR)
      return
    end

    if complexity < 0 then
      vim.notify("Complexity must be a positive number", vim.log.levels.ERROR)
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
      vim.notify("Card not found after refresh", vim.log.levels.ERROR)
      return
    end

    -- Set the complexity
    current_card.properties.complexity = complexity

    -- Update buffer
    update_buffer_with_board(current_board)
    vim.notify("Set complexity to " .. complexity .. " for card '" .. current_card.text .. "'", vim.log.levels.INFO)
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
    vim.notify("Archived " .. archived_count .. " cards older than " .. archive_days .. " days", vim.log.levels.INFO)
  else
    vim.notify("No cards to archive", vim.log.levels.INFO)
  end
end

-- Command: Add new column to board
function M.new_column()
  local board = get_current_board()

  get_input("Column name: ", "", function(column_name)
    if not column_name or column_name == "" then
      vim.notify("Column name cannot be empty", vim.log.levels.ERROR)
      return
    end

    -- Check if column already exists
    if board:get_column_by_name(column_name) then
      vim.notify("Column '" .. column_name .. "' already exists", vim.log.levels.ERROR)
      return
    end

    -- Optionally prompt for WIP limit (use vim.ui.input directly to handle empty input)
    vim.ui.input({
      prompt = "WIP limit (optional, press Enter to skip): ",
      default = "",
    }, function(wip_input)
      -- Re-parse board to get current state
      local current_board = get_current_board()

      -- Prepare config
      local col_config = nil
      if wip_input and wip_input ~= "" then
        local wip_limit = tonumber(wip_input)
        if wip_limit and wip_limit > 0 then
          col_config = { wip_limit = wip_limit }
        else
          vim.notify("Invalid WIP limit. Column created without WIP limit.", vim.log.levels.WARN)
        end
      end

      -- Wrap column creation in pcall to catch any errors
      local success, err = pcall(function()
        current_board:add_new_column(column_name, col_config)
      end)

      if not success then
        notify(extract_error_message(err), vim.log.levels.ERROR)
        return
      end

      -- Update buffer
      update_buffer_with_board(current_board)

      local msg = "Added column '" .. column_name .. "'"
      if col_config and col_config.wip_limit then
        msg = msg .. " with WIP limit " .. col_config.wip_limit
      end
      notify(msg, vim.log.levels.INFO)
    end)
  end)
end

-- Command: Show board statistics
function M.show_stats()
  local board = get_current_board()
  board:calculate_stats()

  local stats = board.stats
  if not stats then
    vim.notify("No statistics available", vim.log.levels.WARN)
    return
  end

  -- Format statistics message
  local lines = {
    "=== Kanban Board Statistics ===",
    "",
    "Total tasks: " .. stats.total_tasks,
    "Completed tasks: " .. stats.completed_tasks,
    "In progress tasks: " .. stats.in_progress_tasks,
    "Blocked tasks: " .. stats.blocked_tasks,
    "Total complexity: " .. stats.total_complexity,
    ""
  }

  -- WIP by column
  table.insert(lines, "WIP by column:")
  for col_name, wip_count in pairs(stats.wip_by_column) do
    table.insert(lines, "  " .. col_name .. ": " .. wip_count)
  end

  -- Cycle time info
  if stats.average_cycle_time then
    table.insert(lines, "")
    local unit = board.config.cycle_time_unit or "seconds"
    table.insert(lines, "Average cycle time: " .. string.format("%.1f", stats.average_cycle_time) .. " " .. unit)
    table.insert(lines, "Completed tasks with cycle time: " .. #stats.cycle_times)
  end

  -- Show in a new buffer or floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

  -- Open in split
  vim.cmd("split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_buf_set_name(buf, "Kanban Statistics")
end

-- Setup function to register all commands
function M.setup()
  local commands = {
    KanbanNewBoard = M.new_board,
    KanbanNewCard = M.new_card,
    KanbanNewColumn = M.new_column,
    KanbanMoveCard = M.move_card,
    KanbanCompleteCard = M.complete_card,
    KanbanSetComplexity = M.set_complexity,
    KanbanArchive = M.archive_done_cards,
    KanbanStats = M.show_stats,
  }

  for name, func in pairs(commands) do
    vim.api.nvim_create_user_command(name, func, {
      desc = "Kanban: " .. name:gsub("Kanban", ""):gsub("(%l)(%u)", "%1 %2")
    })
  end
end

return M