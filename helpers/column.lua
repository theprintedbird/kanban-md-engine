-- lua/kanban-md/helpers/column.lua
-- Column helper functions

local M = {}

function M.is_completion_column(column, board)
  if not column or not column.name then
    return false
  end

  -- Priority order:
  -- 1. Explicit property
  if column.properties and column.properties.is_completion_state then
    return true
  end

  -- 2. Has completion triggers (Phase 2)
  if column.triggers and vim.tbl_contains(column.triggers.on_entry or {}, "mark_complete") then
    return true
  end

  -- 3. Position-based fallback (maintains backwards compatibility)
  local columns = board.columns
  local regular_columns = {}

  -- Collect all non-special columns
  for _, col in ipairs(columns) do
    if col.name and not col.name:match("^__") then
      table.insert(regular_columns, col)
    end
  end

  -- Check if column name suggests it's not a completion column
  local non_completion_patterns = {
    "progress", "doing", "working", "wip", "active", "current",
    "backlog", "todo", "ready", "waiting", "blocked", "review"
  }

  local column_name_lower = column.name:lower()
  for _, pattern in ipairs(non_completion_patterns) do
    if column_name_lower:match(pattern) then
      return false
    end
  end

  -- Check for explicit completion patterns
  local completion_patterns = {
    "done", "complete", "finished", "shipped", "deployed", "closed", "__ARCHIVE__"
  }

  for _, pattern in ipairs(completion_patterns) do
    if column_name_lower:match(pattern) then
      return true
    end
  end

  -- Don't use position-based fallback if there's only one column
  if #regular_columns <= 1 then
    return false
  end

  -- Only consider the last column as completion if there are multiple columns
  -- and the name doesn't suggest otherwise
  return column == regular_columns[#regular_columns]
end

return M
