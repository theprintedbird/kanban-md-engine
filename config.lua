-- lua/kanban-md/config.lua
-- Centralized configuration for the kanban-md plugin
  -- - Purpose: Plugin-level global configuration
  -- - Scope: User-facing settings for the entire Neovim plugin
  -- - Content: WIP limits, display preferences, automation settings, date formats, etc.
  -- - Usage: Modified via require("kanban-md").setup(user_config)
  -- - Example settings: show_stats_virtual_text, auto_archive, default_columns

local M = {}

-- Default configuration
local default_config = {
  -- Board defaults
  default_columns = {"Backlog", "Ready", "In Progress", "Done"},
  archive_after_days = 30,

  -- WIP limits
  default_wip_limit = nil,
  warn_on_wip_exceeded = true,
  block_on_wip_exceeded = false,

  -- Display
  show_stats_virtual_text = true,
  show_cycle_time = true,
  date_format = "epoch", -- or "iso", "relative"

  -- Automation
  auto_archive = true,
  auto_timestamp = true,
  auto_id = true,
  persist_card_ids = false, -- Write card IDs to markdown (false = ephemeral IDs generated on parse)

  -- Complexity feature
  use_complexity = false,    -- Auto-add complexity to new cards
  default_complexity = 1,    -- Default complexity value for new cards

  -- Optional features (disabled by default)
  -- Dependency validation enforcement mode:
  --   false or "off": No dependency validation (default)
  --   true, "on", or "strict": Block moves to completion if dependencies incomplete
  --   "warn": Show warning but allow moves with incomplete dependencies
  dependency_validation = false,

  -- Subtask validation enforcement mode:
  --   false or "off": No subtask validation (default)
  --   true, "on", or "strict": Block moves to completion if subtasks incomplete
  --   "warn": Show warning but allow moves with incomplete subtasks
  subtask_validation = false,

  enable_cursor_positioning = false, -- Move cursor to newly created cards

  -- Dependency validation on parse
  dependency_check_on_parse = false, -- Validate dependencies when loading board

  -- Actions specific config
  auto_archive_after_days = 30,
  use_telescope = true,
  use_input = true,
  confirm_destructive = true,
  column_flow = { "Backlog", "Ready", "In Progress", "Done", "__ARCHIVE__" },

  -- Writer specific config
  task_indent = "",
  blank_lines_between_sections = true,
  blank_line_after_title = true,
  blank_line_after_config = false,
  blank_line_after_column_header = true,
  property_separator = ", ",
  wrap_properties_at = 80,
  timestamp_format = "epoch",
  use_multiline_comments = false,
  multiline_threshold = 100,

  -- Column type system
  -- Enables flexible column type definitions with pattern matching and property inheritance
  column_config = {
    -- Type definitions: users define types with properties, triggers, and patterns
    -- Example structure:
    -- types = {
    --   completion = {
    --     properties = { is_completion_state = true },
    --     triggers = {
    --       on_entry = {
    --         { module = "kanban-md.triggers", function_name = "mark_complete", name = "mark_complete" }
    --       }
    --     },
    --     patterns = { "done", "complete", "finished" }  -- Lua patterns for auto-matching
    --   },
    --   wip = {
    --     properties = { is_active_state = true },
    --     requires_wip_limit = true,  -- Validation requirement
    --     patterns = { "progress", "doing", "working" }
    --   }
    -- }
    types = {},

    -- Named column definitions: exact column name → type and properties
    -- Example:
    -- definitions = {
    --   ["Done"] = { type = "completion", wip_limit = 5 },
    --   ["In Progress"] = { type = "wip", wip_limit = 3 }
    -- }
    definitions = {}
  },

  -- Validation behavior for missing required properties
  -- Options: "none" (silent), "warning" (emit warning), "error" (fail with error)
  missing_property_requirement = "warning",

  -- Writer config: whether to write resolved types back to markdown
  -- When false (default): keep types implicit (resolved via patterns/definitions)
  -- When true: write resolved type to markdown config comments
  write_full_config_to_markdown = false,
}

-- Current configuration (starts as copy of defaults)
local current_config = vim.deepcopy(default_config)

-- Get the current configuration
function M.get()
  return current_config
end

-- Get a specific config value
function M.get_value(key)
  return current_config[key]
end

-- Update configuration (merge with existing)
function M.setup(user_config)
  if user_config then
    current_config = vim.tbl_deep_extend("force", current_config, user_config)
  end
  return current_config
end

-- Reset to defaults
function M.reset()
  current_config = vim.deepcopy(default_config)
  return current_config
end

-- Get defaults (for reference)
function M.get_defaults()
  return vim.deepcopy(default_config)
end

-- Normalize dependency enforcement mode to standard values
-- @param mode any - The mode value to normalize (boolean, string, or nil)
-- @return string|boolean - Normalized mode: "strict", "warn", "off", or false
function M.normalize_dependency_mode(mode)
  if mode == true or mode == "on" or mode == "strict" then
    return "strict"
  elseif mode == "warn" then
    return "warn"
  else
    -- false, "off", nil, or any other value
    return false
  end
end

-- Get effective dependency validation mode from current config
-- @return string|boolean - Normalized dependency mode
function M.get_dependency_mode()
  return M.normalize_dependency_mode(current_config.dependency_validation)
end

-- Get effective subtask validation mode from current config
-- @return string|boolean - Normalized subtask mode
function M.get_subtask_mode()
  return M.normalize_dependency_mode(current_config.subtask_validation)
end

return M
