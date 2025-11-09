-- lua/kanban-md/helpers/column.lua
-- Column helper functions

local M = {}

function M.is_completion_column(column, board)
  if not column or not column.name then
    return false
  end

  -- 1. Check explicit property
  if column.config and column.config.is_completion_state then
    return true
  end

  -- 2. Position-based fallback: last regular column
  local columns = board.columns
  local regular_columns = {}

  -- Collect all non-special columns
  for _, col in ipairs(columns) do
    if col.name and not col.name:match("^__") then
      table.insert(regular_columns, col)
    end
  end

  -- Don't use position-based fallback if there's only one column
  if #regular_columns <= 1 then
    return false
  end

  -- Consider the last regular column as completion
  return column == regular_columns[#regular_columns]
end

-- Helper function to get regular (non-special) columns
local function get_regular_columns(board)
  local regular_columns = {}
  for _, col in ipairs(board.columns) do
    if col.name and not col.name:match("^__") then
      table.insert(regular_columns, col)
    end
  end
  return regular_columns
end

function M.is_start_column(column, board)
  if not column or not column.name then
    return false
  end

  -- 1. Check explicit property on this column
  if column.config and column.config.is_start_state then
    return true
  end

  -- Check if ANY column has explicit is_start_state
  local has_explicit_start = false
  for _, col in ipairs(board.columns) do
    if col.config and col.config.is_start_state then
      has_explicit_start = true
      break
    end
  end

  -- If any column has explicit is_start_state, don't use fallbacks for this column
  if has_explicit_start then
    return false
  end

  -- 2. Check configuration default
  if board.config and board.config.default_start_column then
    local default = board.config.default_start_column
    if column.name == default or column.name:lower():find(default:lower(), 1, true) then
      return true
    end
    -- If a config default is set, don't use position-based fallback
    return false
  end

  -- 3. Position-based fallback: first regular column (only if no config default)
  local regular_columns = get_regular_columns(board)
  if #regular_columns > 0 then
    return column == regular_columns[1]
  end

  return false
end

function M.is_backlog_column(column, board)
  if not column or not column.name then
    return false
  end

  -- 1. Check explicit property on this column
  if column.config and column.config.is_backlog_state then
    return true
  end

  -- Check if ANY column has explicit is_backlog_state
  local has_explicit_backlog = false
  for _, col in ipairs(board.columns) do
    if col.config and col.config.is_backlog_state then
      has_explicit_backlog = true
      break
    end
  end

  -- If any column has explicit is_backlog_state, don't use fallbacks for this column
  if has_explicit_backlog then
    return false
  end

  -- 2. Check configuration default
  if board.config and board.config.default_backlog_column then
    local default = board.config.default_backlog_column
    if column.name == default or column.name:lower():find(default:lower(), 1, true) then
      return true
    end
  end

  -- 3. Position-based fallback: first column is backlog (only if multiple regular columns exist)
  if board.columns and #board.columns > 1 then
    if board.columns[1] == column then
      return true
    end
  end

  return false
end

function M.is_blocked_column(column, board)
  if not column or not column.name then
    return false
  end

  -- Check explicit property only (no fallback for blocked state)
  if column.config and column.config.is_blocked_state then
    return true
  end

  return false
end

function M.is_waiting_column(column, board)
  if not column or not column.name then
    return false
  end

  -- Check explicit property only (no fallback for waiting state)
  if column.config and column.config.is_waiting_state then
    return true
  end

  return false
end

return M
