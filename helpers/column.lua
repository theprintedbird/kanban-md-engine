-- lua/kanban-md/helpers/column.lua
-- Column helper functions

local M = {}

function M.is_completion_column(column, board)
  if not column or not column.name then
    return false
  end

  -- 1. Check explicit property
  if column.properties and column.properties.is_completion_state then
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

return M
