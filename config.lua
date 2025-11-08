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
  ----------------------------
  -- BOARD DEFAULTS
  ----------------------------

  -- default_columns (table of strings)
  -- Default column names when creating a new kanban board
  -- Used by: Board creation commands
  default_columns = {"Backlog", "Ready", "In Progress", "Done"},

  -- archive_after_days (number or nil)
  -- Number of days after which completed cards should be auto-archived
  -- Used by: Archive operations (not actively implemented yet)
  archive_after_days = 30,

  ----------------------------
  -- WIP LIMITS
  ----------------------------

  -- default_wip_limit (number or nil)
  -- Default WIP (Work In Progress) limit for new boards
  -- nil = no default limit (user must configure per board/column)
  -- Currently not used - WIP limits are set per board/column explicitly
  default_wip_limit = nil,

  -- warn_on_wip_exceeded (boolean)
  -- Show warning when WIP limit is exceeded (not actively used - placeholder)
  -- Future feature: control whether warnings appear in validation results
  warn_on_wip_exceeded = true,

  -- block_on_wip_exceeded (boolean)
  -- Block card movements when WIP limit would be exceeded (not actively used - placeholder)
  -- Rejected feature: control whether WIP limits are enforced strictly - if WIP limits need to be exceeded, change the WIP limits. #wontdo
  block_on_wip_exceeded = false,

  ----------------------------
  -- DISPLAY SETTINGS
  ----------------------------

  -- show_stats_virtual_text (boolean)
  -- Display inline virtual text for WIP warnings and cycle time statistics
  -- Used by: lua/kanban-md/virtual_text.lua
  show_stats_virtual_text = true,

  -- show_lead_time (boolean)
  -- Include lead time statistics in virtual text display
  -- Lead time: Total time from backlog/creation to completion
  -- Used by: lua/kanban-md/virtual_text.lua (stats display)
  show_lead_time = true,

  -- show_cycle_time (boolean)
  -- Include cycle time statistics in virtual text display
  -- Cycle time: Time from start state to completion (active work time)
  -- Used by: lua/kanban-md/virtual_text.lua (stats display)
  show_cycle_time = true,

  -- cycle_time_unit (string: "days" | "hours" | "seconds")
  -- Unit for displaying lead time and cycle time metrics
  -- "days": Time displayed in days (e.g., "5 days")
  -- "hours": Time displayed in hours (e.g., "120 hours")
  -- "seconds": Time displayed in seconds (e.g., "432000 seconds")
  -- Used by: lua/kanban-md/stats.lua, lua/kanban-md/virtual_text.lua, lua/kanban-md/commands.lua
  cycle_time_unit = "days",

  -- default_start_column (string or nil)
  -- Default column name to use as "start state" for cycle time calculation
  -- This is used as a fallback when no column has is_start_state explicitly set
  -- Pattern matching: Partial case-insensitive match (e.g., "progress" matches "In Progress")
  -- Set to nil to rely only on explicit is_start_state or position-based fallback
  -- Used by: lua/kanban-md/helpers/column.lua (is_start_column)
  default_start_column = nil,

  -- default_backlog_column (string or nil)
  -- Default column name to use as "backlog state" for lead time calculation
  -- This is used when no column has is_backlog_state explicitly set
  -- Pattern matching: Partial case-insensitive match (e.g., "backlog" matches "Backlog")
  -- Set to nil to rely only on explicit is_backlog_state or position-based fallback
  -- Used by: lua/kanban-md/helpers/column.lua (is_backlog_column)
  default_backlog_column = nil,

  -- date_format (string: "epoch" | "iso" | "relative")
  -- Format for displaying dates in UI and commands
  -- epoch = Unix timestamp (1709567890)
  -- iso = ISO 8601 format (2024-03-04T12:34:50Z)
  -- relative = Human-readable relative time ("2 days ago")
  -- Used by: UI display functions, stat calculations
  date_format = "epoch",

  -- dependency_marking_hl (string)
  -- Neovim highlight group used for visual feedback during dependency marking
  -- Used by: commands.lua:add_dependency() for visual selection
  dependency_marking_hl = "Visual",

  ----------------------------
  -- AUTOMATION SETTINGS
  ----------------------------

  -- auto_archive (boolean)
  -- Automatically archive completed cards after archive_after_days
  -- Used by: Archive operations (not actively implemented yet)
  auto_archive = true,

  -- auto_timestamp (boolean) [CORE FEATURE]
  -- Automatically set timestamp properties when cards enter columns
  -- When enabled: Moving a card to "In Progress" sets card.properties.in_progress = os.time()
  -- Timestamps use Unix epoch format (seconds since 1970-01-01)
  -- Column names are converted to snake_case property keys ("Code Review" → code_review)
  -- Used by:
  --   - board.lua:register_basic_triggers() - trigger registration
  --   - triggers.lua:create_timestamp_trigger() - timestamp setting logic
  --   - commands.lua - manual command handling
  auto_timestamp = true,

  -- auto_id (boolean) [CORE FEATURE]
  -- Automatically generate unique IDs for boards, columns, and cards on creation
  -- When enabled: Registers on_create triggers that generate ULID-based IDs
  -- ID format:
  --   - Boards:  board_01HZXXX...
  --   - Columns: column_01HZXXX...
  --   - Cards:   card_01HZXXX...
  -- Used by:
  --   - init.lua:setup() - registers ID generation triggers
  --   - extras/id_triggers.lua - ULID generation implementation
  --   - board.lua - fallback ID generation if triggers fail
  auto_id = true,

  -- persist_card_ids (boolean)
  -- Whether to write card IDs to markdown files or keep them ephemeral
  -- false (default): IDs are generated on parse, not saved to markdown
  -- true: IDs are written to card property comments in markdown
  -- Used by: writer_mixin.lua when serializing cards
  persist_card_ids = false,

  ----------------------------
  -- COMPLEXITY TRACKING
  ----------------------------

  -- use_complexity (boolean)
  -- Enable complexity/story points tracking for cards
  -- When enabled: Automatically adds complexity property to new cards
  -- Used by: Card creation commands, statistics calculations
  use_complexity = false,

  -- default_complexity (number)
  -- Default complexity value for new cards when use_complexity = true
  -- Used by: New card creation commands
  default_complexity = 1,

  ----------------------------
  -- OPTIONAL FEATURES (Disabled by Default)
  ----------------------------

  -- dependency_validation (string | boolean) [OPTIONAL TRIGGER-BASED FEATURE]
  -- Validates that all dependencies are complete before allowing card completion
  -- This is an OPTIONAL feature implemented via the trigger system.
  --
  -- Valid values:
  --   false or "off": No dependency validation (default)
  --   true, "on", or "strict": Block moves to completion if any dependency incomplete
  --   "warn": Show warning but allow moves with incomplete dependencies
  --
  -- When enabled:
  --   1. Registers 'depends_on' as an array property type via TypeConverter
  --   2. Registers on_checking triggers on all columns
  --   3. Only validates when moving to completion columns (detected via is_completion_column())
  --   4. Can be bypassed using :KanbanForceCompleteCard command
  --
  -- Card property format:
  --   <!-- depends_on: card_abc123, card_def456 -->
  --
  -- Related commands:
  --   :KanbanAddDependency - Two-step process to add dependency between cards
  --   :KanbanForceCompleteCard - Bypass dependency validation
  --
  -- Used by:
  --   - board.lua:auto_register_triggers() - trigger registration
  --   - extras/subtasks_triggers.lua - validation implementation
  --   - commands.lua:add_dependency() - dependency creation
  --   - board.lua:validate_dependencies() - full validation with circular dependency detection
  dependency_validation = false,

  -- subtask_validation (string | boolean) [OPTIONAL TRIGGER-BASED FEATURE]
  -- Validates that all subtasks are complete before allowing parent card completion
  -- This is an OPTIONAL feature implemented via the trigger system.
  --
  -- Valid values:
  --   false or "off": No subtask validation (default)
  --   true, "on", or "strict": Block parent completion if any subtask incomplete
  --   "warn": Show warning but allow parent completion with incomplete subtasks
  --
  -- When enabled:
  --   1. Registers 'subtasks' as an array property type via TypeConverter
  --   2. Registers on_checking triggers on all columns
  --   3. Only validates when moving parent to completion columns
  --   4. Can be bypassed using :KanbanForceCompleteCard command
  --
  -- Card property format:
  --   - Parent task
  --     <!-- subtasks: subtask_id_1, subtask_id_2, subtask_id_3 -->
  --
  -- Used by:
  --   - board.lua:auto_register_triggers() - trigger registration
  --   - extras/subtasks_triggers.lua - validation implementation
  --   - commands.lua:force_complete_card() - bypass logic
  subtask_validation = false,

  ----------------------------
  -- USER EXPERIENCE
  ----------------------------

  -- enable_cursor_positioning (boolean)
  -- Automatically move cursor to newly created cards after creation
  -- Used by: Card/column creation commands
  enable_cursor_positioning = false,

  -- dependency_check_on_parse (boolean)
  -- Validate all dependencies when loading a board (check for missing/circular dependencies)
  -- When true: Shows errors/warnings for dependency issues on board load
  -- When false: Only validates dependencies during card movements
  -- Used by: commands.lua:get_current_board() - board loading
  dependency_check_on_parse = false,

  ----------------------------
  -- ACTION COMMANDS
  ----------------------------

  -- auto_archive_after_days (number)
  -- Days before auto-archiving completed cards
  -- Used by: Archive operations in actions.lua
  auto_archive_after_days = 30,

  -- use_telescope (boolean)
  -- Use Telescope picker for card selection (if available)
  -- Falls back to vim.ui.select if Telescope not installed
  -- Used by: commands.lua for card/column selection UI
  use_telescope = true,

  -- use_input (boolean)
  -- Use vim.ui.input for text input in commands
  -- Used by: commands.lua for card/column name input
  use_input = true,

  -- confirm_destructive (boolean) [CORE SAFETY FEATURE]
  -- Show confirmation dialogs before executing destructive operations
  -- Currently used for:
  --   - :KanbanForceCompleteCard - confirms before bypassing validation
  -- Future use: delete cards, delete columns, bulk operations
  -- Used by: commands.lua:force_complete_card()
  confirm_destructive = true,

  -- column_flow (table of strings)
  -- Ordered list of column names defining the standard workflow
  -- Used for "move to next/previous column" commands
  -- Special column "__ARCHIVE__" is the archive column
  -- Used by: actions.lua for column navigation commands
  column_flow = { "Backlog", "Ready", "In Progress", "Done", "__ARCHIVE__" },

  ----------------------------
  -- WRITER/FORMATTING
  ----------------------------

  -- task_indent (string)
  -- Indentation string for task items (card list items)
  -- Default: "" (no indentation)
  -- Example: "  " for 2-space indent
  -- Used by: writer_mixin.lua when writing cards
  task_indent = "",

  -- blank_lines_between_sections (boolean)
  -- Add blank lines between markdown sections (H2-H5 documentation headers)
  -- Used by: writer_mixin.lua for content block spacing
  blank_lines_between_sections = true,

  -- blank_line_after_title (boolean)
  -- Add blank line after board title (H1)
  -- Used by: writer_mixin.lua when writing title block
  blank_line_after_title = true,

  -- blank_line_after_config (boolean)
  -- Add blank line after board config comment
  -- Used by: writer_mixin.lua when writing config block
  blank_line_after_config = false,

  -- blank_line_after_column_header (boolean)
  -- Add blank line after column header (H6)
  -- Used by: writer_mixin.lua when writing column headers
  blank_line_after_column_header = true,

  -- property_separator (string)
  -- Separator between properties in HTML comments
  -- Default: ", " produces: <!-- id: 123, backlog: 1709567890 -->
  -- Used by: writer_mixin.lua when serializing card properties
  property_separator = ", ",

  -- wrap_properties_at (number)
  -- Maximum line length before wrapping property comments to multiple lines
  -- Used by: writer_mixin.lua for multiline comment formatting
  wrap_properties_at = 80,

  -- timestamp_format (string: "epoch" | "iso")
  -- Format for writing timestamps to markdown
  -- epoch: Unix timestamp (1709567890)
  -- iso: ISO 8601 format (2024-03-04T12:34:50Z)
  -- Used by: writer_mixin.lua when writing card properties
  timestamp_format = "epoch",

  -- use_multiline_comments (boolean)
  -- Use multiline HTML comment format for long property lists
  -- false: <!-- property: value, property2: value2 -->
  -- true:  <!--
  --          property: value
  --          property2: value2
  --        -->
  -- Used by: writer_mixin.lua based on wrap_properties_at threshold
  use_multiline_comments = false,

  -- multiline_threshold (number)
  -- Character count threshold for switching to multiline comments
  -- Used by: writer_mixin.lua when use_multiline_comments is enabled
  multiline_threshold = 100,

  ----------------------------
  -- COLUMN TYPE SYSTEM (Advanced/Future)
  ----------------------------

  -- column_config (table)
  -- Flexible column type system with pattern matching and property inheritance
  -- Enables user-defined column types that auto-configure properties and triggers
  --
  -- Structure:
  --   types = {
  --     [type_name] = {
  --       properties = { ... },        -- Properties inherited by columns of this type
  --       triggers = { ... },          -- Triggers auto-registered for this type
  --       patterns = { ... },          -- Lua patterns for auto-detecting this type
  --       requires_wip_limit = bool    -- Validation requirement (emits warning if missing)
  --     }
  --   }
  --   definitions = {
  --     [exact_column_name] = { type = "...", ... }  -- Explicit column→type mappings
  --   }
  --
  -- Type Resolution Priority:
  --   1. Markdown explicit: <!-- config type: completion -->
  --   2. Config named definition: definitions["Done"] = { type = "completion" }
  --   3. Config pattern match: types.completion.patterns = { "done", "complete" }
  --   4. No match: type = nil (untyped column)
  --
  -- Property Merging Priority (for conflicts):
  --   Type properties < Definition properties < Markdown properties
  --
  -- Example configuration:
  --   column_config = {
  --     types = {
  --       completion = {
  --         properties = { is_completion_state = true },
  --         patterns = { "done", "complete", "finished" }
  --       },
  --       wip = {
  --         properties = { is_active_state = true },
  --         requires_wip_limit = true,
  --         patterns = { "progress", "doing", "working" }
  --       }
  --     },
  --     definitions = {
  --       ["Done"] = { type = "completion", wip_limit = 5 }
  --     }
  --   }
  --
  -- Used by:
  --   - column_type_resolver.lua - type resolution and property merging (IMPLEMENTED)
  --   - parser.lua:164-192, 440-479 - applies types during column parsing (IMPLEMENTED)
  --   - board.lua:register_type_triggers() - auto-registers triggers (IMPLEMENTED)
  --
  -- Status: Fully implemented (structure, resolver, and integration complete)
  column_config = {
    types = {},
    definitions = {}
  },

  -- missing_property_requirement (string: "none" | "warning" | "error")
  -- Validation behavior when column type requires a property that isn't set
  -- Example: Type "wip" has requires_wip_limit=true but column has no wip_limit
  -- "none": Silent (no validation)
  -- "warning": Emit warning message during validation
  -- "error": Fail with error and halt processing
  -- Used by: column_type_resolver.lua:validate_requirements() (IMPLEMENTED)
  missing_property_requirement = "warning",

  -- write_full_config_to_markdown (boolean)
  -- Whether to write resolved column types back to markdown
  -- false (default): Keep types implicit (resolved via patterns/definitions)
  -- true: Write resolved type to markdown config comments
  -- Example when true:
  --   Column "Done" matched pattern "done" → writes <!-- config type: completion -->
  -- Used by: writer_mixin.lua (NOT IMPLEMENTED - feature not needed yet)
  write_full_config_to_markdown = false,

  ----------------------------
  -- COLUMN PROPERTIES (Metadata)
  ----------------------------

  -- These are NOT config options but column/board properties that can be set
  -- via markdown comments. Documented here for completeness:
  --
  -- is_completion_state (boolean) [CORE COLUMN PROPERTY]
  -- Marks a column as a "completion" column where cards are considered done
  -- Detection logic (priority order):
  --   1. Explicit property: <!-- column:config is_completion_state: true -->
  --   2. Position-based fallback: Last regular column (if multiple columns exist)
  --   3. No hardcoded patterns
  -- Used by:
  --   - helpers/column.lua:is_completion_column() - detection logic
  --   - board.lua - dependency validation, archiving
  --   - stats.lua - completed task counts, lead time and cycle time calculations
  --   - extras/subtasks_triggers.lua - subtask/dependency validation
  --   - commands.lua:complete_card() - finding completion column
  --
  -- is_start_state (boolean) [CORE COLUMN PROPERTY FOR CYCLE TIME]
  -- Marks a column as the "start state" where active work begins
  -- Used for cycle time calculation (start state → completion state)
  -- Detection logic (priority order):
  --   1. Explicit property: <!-- column:config is_start_state: true -->
  --   2. Configuration default: config.default_start_column matches column name
  --   3. Position-based fallback: First regular column
  -- Used by:
  --   - helpers/column.lua:is_start_column() - detection logic
  --   - stats.lua - cycle time calculations
  --   - virtual_text.lua - cycle time display with column names
  --
  -- is_backlog_state (boolean) [OPTIONAL COLUMN PROPERTY FOR LEAD TIME]
  -- Marks a column as a "backlog" state for lead time calculation
  -- Lead time calculation uses this as the start point (backlog → completion)
  -- Detection logic (priority order):
  --   1. Explicit property: <!-- column:config is_backlog_state: true -->
  --   2. Configuration default: config.default_backlog_column matches column name
  --   3. Position-based fallback: First column (only if multiple regular columns exist)
  -- Used by:
  --   - helpers/column.lua:is_backlog_column() - detection logic
  --   - stats.lua - lead time calculations
  --
  -- is_blocked_state (boolean) [OPTIONAL COLUMN PROPERTY FOR BLOCKED TIME]
  -- Marks a column as a "blocked" state (e.g., "Blocked", "On Hold")
  -- Time spent in blocked/waiting columns is tracked separately in cycle time metrics
  -- Detection logic:
  --   - Explicit property only: <!-- column:config is_blocked_state: true -->
  --   - No fallback (explicit declaration required)
  -- Used by:
  --   - helpers/column.lua:is_blocked_column() - detection logic
  --   - stats.lua - blocked time calculations
  --   - virtual_text.lua - blocked time breakdown display
  --
  -- is_waiting_state (boolean) [OPTIONAL COLUMN PROPERTY FOR BLOCKED TIME]
  -- Marks a column as a "waiting" state (e.g., "Waiting for Review", "External Dependency")
  -- Similar to is_blocked_state, tracked separately in cycle time metrics
  -- Detection logic:
  --   - Explicit property only: <!-- column:config is_waiting_state: true -->
  --   - No fallback (explicit declaration required)
  -- Used by:
  --   - helpers/column.lua:is_waiting_column() - detection logic
  --   - stats.lua - blocked time calculations
  --   - virtual_text.lua - blocked time breakdown display
  --
  -- is_active_state (boolean) [DEFINED BUT NOT ACTIVELY USED]
  -- Marks a column as an "active work" state (typically WIP columns)
  -- Status: Can be set via column types or markdown config, but no code currently checks it
  -- Future use: WIP limit enforcement, capacity management, workflow validations
  -- Currently: Metadata only - parser/writer preserve it, but no triggers/stats use it
  --
  -- wip_limit (number) [CORE COLUMN/BOARD PROPERTY]
  -- Enforces Work In Progress limits to prevent too many cards in a column/board
  -- Can be set at board level or column level
  -- Board level: <!-- kanban:config wip_limit: 10 --> (total WIP across all columns)
  -- Column level: <!-- column:config wip_limit: 3 --> (WIP for specific column)
  -- Used by:
  --   - board.lua:register_basic_triggers() - registers WIP limit validation trigger
  --   - triggers.lua:create_wip_limit_trigger() - validation logic
  --   - stats.lua:validate() - WIP limit validation during statistics
  --   - virtual_text.lua - displays WIP limit warnings inline
  --   - workflow_engine.lua - auto-registers WIP triggers
  --   - commands.lua:new_column() - prompts for WIP limit
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
