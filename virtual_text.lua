-- lua/kanban-md/virtual_text.lua
-- Virtual text display for WIP warnings and cycle time statistics

local stats = require("kanban-md.stats")
local column_helpers = require("kanban-md.helpers.column")

local M = {}

-- Namespace for virtual text extmarks
local ns_id = nil

-- Initialize the virtual text namespace
function M.setup()
  if not ns_id then
    ns_id = vim.api.nvim_create_namespace("kanban_md_virtual_text")
  end
end

-- Clear all virtual text in the buffer
local function clear_virtual_text(bufnr)
  if not ns_id then
    M.setup()
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

-- Display WIP limit warnings for columns that exceed their limits
-- @param board table: Board object with columns and stats
-- @param bufnr number: Buffer number to display in
local function display_wip_warnings(board, bufnr)
  if not board.stats then
    board:calculate_stats()
  end

  -- Check board-level WIP limit
  if board.config and board.config.wip_limit then
    local total_wip = 0
    for _, count in pairs(board.stats.wip_by_column) do
      total_wip = total_wip + count
    end

    -- Display warning on board title line if WIP exceeded
    if total_wip > board.config.wip_limit then
      -- Board title is typically on line 0 (1-indexed in buffer)
      local line_num = 0
      if board.title_line then
        line_num = board.title_line - 1
      end

      vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num, 0, {
        virt_text = {{string.format(" ⚠ Board WIP limit exceeded (%d/%d)", total_wip, board.config.wip_limit), "WarningMsg"}},
        virt_text_pos = "eol"
      })
    end
  end

  -- Check column-level WIP limits
  for _, column in ipairs(board.columns) do
    if column.config and column.config.wip_limit then
      local wip = board.stats.wip_by_column[column.name] or 0

      if wip > column.config.wip_limit and column.line_number then
        -- Line numbers in parser are 1-indexed, but nvim_buf_set_extmark is 0-indexed
        local line_num = column.line_number - 1

        vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num, 0, {
          virt_text = {{string.format(" ⚠ WIP limit exceeded (%d/%d)", wip, column.config.wip_limit), "WarningMsg"}},
          virt_text_pos = "eol"
        })
      end
    end
  end
end

-- Calculate cycle time for a single card using stats module
-- @param card table: Card object with properties
-- @param board table: Board object for timestamp key lookup
-- @return number|nil: Cycle time in the configured unit, or nil
local function calculate_cycle_time(card, board)
  if not card.properties then
    return nil
  end

  -- Use the stats module's calculation (returns seconds)
  local cycle_time_seconds = stats._private and stats._private.calculate_cycle_time
    or require("kanban-md.stats")._calculate_cycle_time

  -- Direct calculation using the same logic as stats.lua
  local timestamp_keys = {"created"}

  if board and board.columns then
    for _, column in ipairs(board.columns) do
      if column.name then
        local timestamp_key = column.name:lower():gsub("[^%w_]", "_")
        table.insert(timestamp_keys, timestamp_key)
      end
    end
  end

  table.insert(timestamp_keys, "archived")

  local timestamps = {}
  for _, key in ipairs(timestamp_keys) do
    if card.properties[key] then
      table.insert(timestamps, {key = key, value = card.properties[key]})
    end
  end

  if #timestamps < 2 then
    return nil
  end

  table.sort(timestamps, function(a, b) return a.value < b.value end)
  local cycle_time_seconds = timestamps[#timestamps].value - timestamps[1].value

  -- Convert based on configured unit
  local unit = board.config.cycle_time_unit or "days"
  if unit == "days" then
    return math.floor(cycle_time_seconds / 86400)
  elseif unit == "hours" then
    return math.floor(cycle_time_seconds / 3600)
  else
    return cycle_time_seconds
  end
end

-- Display cycle time for completed cards
-- @param board table: Board object with columns and archive
-- @param bufnr number: Buffer number to display in
local function display_cycle_times(board, bufnr)
  -- Process regular columns
  for _, column in ipairs(board.columns) do
    -- Only show cycle time for completed cards
    if column_helpers.is_completion_column(column, board) then
      local tasks = column.tasks or column.cards or {}

      for _, card in ipairs(tasks) do
        if card.line_number then
          local cycle_time = calculate_cycle_time(card, board)

          if cycle_time then
            -- Line numbers in parser are 1-indexed, but nvim_buf_set_extmark is 0-indexed
            local line_num = card.line_number - 1

            local unit = board.config.cycle_time_unit or "days"
            local unit_label = unit
            if cycle_time == 1 then
              -- Singularize
              unit_label = unit:gsub("s$", "")
            end

            vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num, 0, {
              virt_text = {{string.format(" ⏱ %d %s", cycle_time, unit_label), "Comment"}},
              virt_text_pos = "eol"
            })
          end
        end
      end
    end
  end

  -- Process archive
  if board.archive then
    local archive_tasks = board.archive.tasks or board.archive.cards or {}

    for _, card in ipairs(archive_tasks) do
      if card.line_number then
        local cycle_time = calculate_cycle_time(card, board)

        if cycle_time then
          local line_num = card.line_number - 1

          local unit = board.config.cycle_time_unit or "days"
          local unit_label = unit
          if cycle_time == 1 then
            unit_label = unit:gsub("s$", "")
          end

          vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num, 0, {
            virt_text = {{string.format(" ⏱ %d %s", cycle_time, unit_label), "Comment"}},
            virt_text_pos = "eol"
          })
        end
      end
    end
  end
end

-- Update all virtual text for a board
-- @param board table: Board object to display stats for
-- @param bufnr number: Buffer number to display in
function M.update_virtual_text(board, bufnr)
  if not board or not bufnr then
    return
  end

  -- Ensure namespace is initialized
  M.setup()

  -- Check if virtual text is enabled
  if board.config.show_stats_virtual_text == false then
    return
  end

  -- Clear existing virtual text
  clear_virtual_text(bufnr)

  -- Ensure stats are calculated
  if not board.stats then
    board:calculate_stats()
  end

  -- Display WIP warnings (always shown if show_stats_virtual_text is enabled)
  display_wip_warnings(board, bufnr)

  -- Display cycle times (if enabled)
  if board.config.show_cycle_time ~= false then
    display_cycle_times(board, bufnr)
  end
end

return M
