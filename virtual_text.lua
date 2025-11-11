-- lua/kanban-md/virtual_text.lua
-- Virtual text display for WIP warnings and cycle time statistics

local stats = require("kanban-md.stats")
local column_helpers = require("kanban-md.helpers.column")
local adapter_registry = require("kanban-md.adapter_registry")

local M = {}

-- Namespace for virtual text extmarks
local ns_id = nil

-- Get adapter from registry
local function get_adapter()
  return adapter_registry.get_adapter()
end

-- Initialize the virtual text namespace
function M.setup()
  if not ns_id then
    ns_id = get_adapter():create_namespace("kanban_md_virtual_text")
  end
end

-- Clear all virtual text in the buffer
local function clear_virtual_text(bufnr)
  if not ns_id then
    M.setup()
  end
  get_adapter():clear_namespace(bufnr, ns_id)
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

      get_adapter():set_extmark(bufnr, ns_id, line_num, 0, {
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

        get_adapter():set_extmark(bufnr, ns_id, line_num, 0, {
          virt_text = {{string.format(" ⚠ WIP limit exceeded (%d/%d)", wip, column.config.wip_limit), "WarningMsg"}},
          virt_text_pos = "eol"
        })
      end
    end
  end
end

-- Helper: format time duration to configured unit
-- @param seconds number: Time in seconds
-- @param board table: Board object with config
-- @return number, string: Formatted value and unit label
local function format_time(seconds, board)
  local unit = board.config.cycle_time_unit or "days"
  local value

  if unit == "days" then
    value = math.floor(seconds / 86400)
  elseif unit == "hours" then
    value = math.floor(seconds / 3600)
  else
    value = seconds
  end

  local unit_label = unit
  if value == 1 then
    -- Singularize
    unit_label = unit:gsub("s$", "")
  end

  return value, unit_label
end

-- Helper: format decimal time to 1 decimal place
-- @param seconds number: Time in seconds
-- @param board table: Board object with config
-- @return string: Formatted time with unit
local function format_time_decimal(seconds, board)
  local unit = board.config.cycle_time_unit or "days"
  local value

  if unit == "days" then
    value = seconds / 86400
  elseif unit == "hours" then
    value = seconds / 3600
  else
    value = seconds
  end

  local unit_label = unit
  if value >= 0.95 and value < 1.05 then
    -- Close to 1, singularize
    unit_label = unit:gsub("s$", "")
  end

  return string.format("%.1f %s", value, unit_label)
end

-- Display lead time and cycle time for completed cards
-- @param board table: Board object with columns and archive
-- @param bufnr number: Buffer number to display in
local function display_metrics(board, bufnr)
  local show_lead = board.config.show_lead_time ~= false
  local show_cycle = board.config.show_cycle_time ~= false

  -- Helper function to display metrics for a single card
  local function display_card_metrics(card, line_num)
    if not card.properties then
      return
    end

    -- Get metrics from stats module
    local lead_time_data = stats.calculate_lead_time(card.properties, board)
    local cycle_time_data = stats.calculate_cycle_time(card.properties, board)

    -- Build virtual text segments
    local virt_text = {}

    -- Lead time section
    if show_lead and lead_time_data then
      local value, unit = format_time(lead_time_data.duration, board)
      local text = string.format("⏱ Lead (%s → %s): %d %s",
        lead_time_data.start_column or "?",
        lead_time_data.end_column or "?",
        value,
        unit
      )
      table.insert(virt_text, {" " .. text, "Comment"})
    end

    -- Cycle time section
    if show_cycle and cycle_time_data then
      -- Add separator if we showed lead time
      if #virt_text > 0 then
        table.insert(virt_text, {" | ", "Comment"})
      end

      local value, unit = format_time(cycle_time_data.duration, board)
      local text = string.format("⚡ Cycle (%s → %s): %d %s",
        cycle_time_data.start_column or "?",
        cycle_time_data.end_column or "?",
        value,
        unit
      )
      table.insert(virt_text, {text, "Comment"})

      -- Show blocked time breakdown if present
      if cycle_time_data.blocked_time and cycle_time_data.blocked_time > 0 then
        local blocked_str = format_time_decimal(cycle_time_data.blocked_time, board)
        local active_str = format_time_decimal(cycle_time_data.active_time, board)
        table.insert(virt_text, {string.format(" [active: %s, blocked: %s]", active_str, blocked_str), "Comment"})
      end
    elseif show_cycle and not cycle_time_data and lead_time_data then
      -- Show N/A if cycle time is unavailable but lead time exists
      if #virt_text > 0 then
        table.insert(virt_text, {" | ", "Comment"})
      end
      table.insert(virt_text, {"⚡ Cycle: N/A", "Comment"})
    end

    -- Display if we have any virtual text
    if #virt_text > 0 then
      get_adapter():set_extmark(bufnr, ns_id, line_num, 0, {
        virt_text = virt_text,
        virt_text_pos = "eol"
      })
    end
  end

  -- Process regular columns
  for _, column in ipairs(board.columns) do
    -- Only show metrics for completed cards
    if column_helpers.is_completion_column(column, board) then
      local tasks = column.tasks or column.cards or {}

      for _, card in ipairs(tasks) do
        if card.line_number then
          -- Line numbers in parser are 1-indexed, but nvim_buf_set_extmark is 0-indexed
          local line_num = card.line_number - 1
          display_card_metrics(card, line_num)
        end
      end
    end
  end

  -- Process archive
  if board.archive then
    local archive_tasks = board.archive.tasks or board.archive.cards or {}

    for _, card in ipairs(archive_tasks) do
      if card.line_number then
        local line_num = card.line_number - 1
        display_card_metrics(card, line_num)
      end
    end
  end
end

-- Update all virtual text for a board
-- @param board table: Board object to display stats for
-- @param bufnr number: Buffer number to display in
function M.update_virtual_text(board, bufnr)
	if not get_adapter():supports_virtual_text() then
		return
	end
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

  -- Display lead time and cycle time metrics (if enabled)
  if board.config.show_lead_time ~= false or board.config.show_cycle_time ~= false then
    display_metrics(board, bufnr)
  end
end

return M
