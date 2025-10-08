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

return M
