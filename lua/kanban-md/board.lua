-- lua/kanban-md/board.lua
-- Board class with stats calculation and parsing capabilities

local Triggerable = require('kanban-md.triggerable')
local Column = require('kanban-md.column')
local StatsMixin = require('kanban-md.stats')
local ParserMixin = require('kanban-md.parser')
local WriterMixin = require('kanban-md.writer_mixin')
local TblUtils = require("kanban-md.utils.table")

-- Board class with stats calculation and parsing capabilities
local Board = {}
Board.__index = Board
setmetatable(Board, { __index = Triggerable })

-- Initialize class-level triggers
Board.triggers = {}
Board.trigger_order = {}

-- Apply mixins to Board
for k, v in pairs(StatsMixin) do
  if k ~= "_private" then  -- Don't copy private test functions
    Board[k] = v
  end
end

for k, v in pairs(ParserMixin) do
  if k ~= "_private" then  -- Don't copy private test functions
    Board[k] = v
  end
end

for k, v in pairs(WriterMixin) do
  if k ~= "_private" then  -- Don't copy private test functions
    Board[k] = v
  end
end

function Board:new()
  local obj = {
    id = nil,  -- Will be set by on_create trigger if auto_id is enabled
    columns = {},
		-- Note: Archive is stored separately in self.archive, not in self.columns
    config = {},
    triggers = {},
    trigger_order = {},
    -- Content blocks for preserving markdown when parsing/writing
    content_blocks = {}
  }
  setmetatable(obj, Board)

  -- Fire on_create triggers (both class-level and instance-level)
  local context = {
    board = obj,
    timestamp = os.time()
  }

  -- Execute class-level triggers first (if any)
  if Board.triggers and Board.triggers["on_create"] then
    for name, trigger_fn in pairs(Board.triggers["on_create"]) do
      local success, result = pcall(trigger_fn, obj, context)
      if not success then
        error(string.format("Error in on_create trigger '%s': %s", name, result))
      end
    end
  end

  -- Then execute instance-level triggers
  obj:execute_triggers("on_create", context)

  -- Fallback: if ID is still nil after triggers, generate a simple one
  if not obj.id then
    obj.id = "board_" .. os.time()
  end

  return obj
end

function Board:add_column(id, name)
  -- Support three signatures:
  -- 1. add_column(column) - Column instance
  -- 2. add_column(name) - name only, ID will be auto-generated
  -- 3. add_column(id, name) - explicit ID and name

  local column

  -- Check if first argument is a Column instance
  if type(id) == "table" and getmetatable(id) == Column then
    -- Signature 1: Column instance
    column = id
  elseif name == nil then
    -- Signature 2: Single parameter - treat as name, ID will be auto-generated
    if type(id) ~= "string" then
      error(string.format("Board:add_column() expects string name as parameter, got %s. Usage: board:add_column(column) or board:add_column(name) or board:add_column(id, name)", type(id)))
    end
    column = Column:new(nil, id)
  else
    -- Signature 3: Two parameters - id and name
    if type(id) ~= "string" then
      error(string.format("Board:add_column() expects string id as first parameter, got %s. Usage: board:add_column(id, name)", type(id)))
    end
    if type(name) ~= "string" then
      error(string.format("Board:add_column() expects string name as second parameter, got %s. Usage: board:add_column(id, name)", type(name)))
    end
    column = Column:new(id, name)
  end

  table.insert(self.columns, column)
	column.board = self

  return column
end

-- Validate a card move without executing it
-- Checks workflow rules to determine if the move is allowed
-- @param card Card - the card to move
-- @param from_column Column|nil - the source column object (nil for new cards)
-- @param to_column string|Column - the target column name or Column instance
-- @return ValidationResult - result indicating if move is valid
function Board:validate_move(card, from_column, to_column)
  local ValidationResult = require('kanban-md.validation_result')
  local WorkflowEngine = require('kanban-md.workflow_engine')

  if type(card) ~= "table" or not card.id then
    error("Board:validate_move() expects Card object as first parameter")
  end
  if from_column ~= nil and (type(from_column) ~= "table" or not from_column.id) then
    error("Board:validate_move() expects Column object or nil as second parameter")
  end

  -- Handle both Column instance and string column name
  local to_column_name
  if type(to_column) == "table" and getmetatable(to_column) == Column then
    -- Column instance - extract the name
    to_column_name = to_column.name
  elseif type(to_column) == "string" then
    -- String column name
    to_column_name = to_column
  else
    error("Board:validate_move() expects Column object or string column name as third parameter")
  end

  -- Find the target column
  local target_column = self:get_column_by_name(to_column_name)

  if not target_column then
    return ValidationResult.error(string.format("Target column '%s' not found", to_column_name))
  end

  -- If no source column, skip workflow validation (new card being added)
  if not from_column then
    return ValidationResult.success()
  end

  -- Check if transition is allowed by workflow rules
  local valid_transitions = WorkflowEngine.get_valid_transitions_static(self, card, from_column)

  local is_valid = false
  for _, valid_target in ipairs(valid_transitions) do
    if valid_target == to_column_name then
      is_valid = true
      break
    end
  end

  if not is_valid then
    return ValidationResult.error(string.format(
      "Invalid transition from '%s' to '%s'",
      from_column.name,
      to_column_name
    ))
  end

  -- Transition is valid
  return ValidationResult.success()
end

-- Move a card between columns
-- Accepts card and column objects
-- If either remove or add fails, error propagates up
-- Caller handles error by not writing to buffer
function Board:move_card(card, from_column, to_column)
  if type(card) ~= "table" or not card.id then
    error("Board:move_card() expects Card object as first parameter")
  end
  if type(from_column) ~= "table" or not from_column.id then
    error("Board:move_card() expects Column object as second parameter")
  end
  if type(to_column) ~= "table" or not to_column.id then
    error("Board:move_card() expects Column object as third parameter")
  end

  -- Build context for triggers
  local context = {
    card = card,
    source_column = from_column,
    target_column = to_column,
    board = self
  }

  -- Just call remove + add
  -- If either fails, error propagates up
  -- Board object may be inconsistent, but we never write it to buffer
  from_column:remove_card(card, context)
  to_column:add_card(card, context)

  return true
end

-- Move a card with selective validation bypass
-- @param card Card - The card to move
-- @param from_column Column - Source column
-- @param to_column Column - Target column
-- @param bypass_categories table - Array of trigger categories to bypass (e.g., {"dependency", "subtask"})
-- @return boolean - Success status
function Board:move_card_with_bypass(card, from_column, to_column, bypass_categories)
  if type(card) ~= "table" or not card.id then
    error("Board:move_card_with_bypass() expects Card object as first parameter")
  end
  if type(from_column) ~= "table" or not from_column.id then
    error("Board:move_card_with_bypass() expects Column object as second parameter")
  end
  if type(to_column) ~= "table" or not to_column.id then
    error("Board:move_card_with_bypass() expects Column object as third parameter")
  end
  if type(bypass_categories) ~= "table" then
    error("Board:move_card_with_bypass() expects array of categories as fourth parameter")
  end

  -- Build context with bypass flag
  local context = {
    card = card,
    source_column = from_column,
    target_column = to_column,
    board = self,
    _bypass_categories = bypass_categories
  }

  -- Execute move with bypass context
  from_column:remove_card(card, context)
  to_column:add_card(card, context)

  return true
end

function Board:get_column(id)
  for _, column in ipairs(self.columns) do
    if column.id == id then
      return column
    end
  end
  return nil
end

function Board:get_column_by_name(name)
  for _, column in ipairs(self.columns) do
    if column.name == name then
      return column
    end
  end
  return nil
end

-- Resolve a single configuration value using the precedence:
--   board file config (self.config, parsed from `<!-- kanban:config ... -->`)
--   > plugin config (require('kanban-md.config').get_value(key))
--
-- Presence in the board file is determined by whether the key is *stored*, not
-- by whether the stored value is truthy. This means an explicit `false` in the
-- board file correctly overrides a `true` plugin default.
--
-- self.config may be a plain table (freshly created via Board:new) or a
-- TypeConverter (installed by the parser). Both are handled.
-- @param key string - The configuration key to resolve
-- @return any - The resolved configuration value
function Board:get_config_value(key)
  local TypeConverter = require('kanban-md.type_converter')
  local plugin_config = require('kanban-md.config')
  local board_config = self.config

  if getmetatable(board_config) == TypeConverter then
    -- TypeConverter: use :has() so an explicit `false` counts as present
    if board_config:has(key) then
      return board_config[key]
    end
  elseif type(board_config) == "table" then
    -- Plain table: presence is a non-nil raw value (so `false` still wins)
    if rawget(board_config, key) ~= nil then
      return board_config[key]
    end
  end

  return plugin_config.get_value(key)
end

-- Build a plain-table snapshot of the effective configuration: the global
-- plugin config overlaid with any keys authored in the board file. Used to
-- thread board-file-overridable options (timestamp_format, task_indent,
-- property_separator, blank_line_*, persist_card_ids, ...) into the writer.
-- @return table - Plain table of resolved config values
function Board:get_effective_config()
  local TypeConverter = require('kanban-md.type_converter')
  local plugin_config = require('kanban-md.config')
  local snapshot = TblUtils.deepcopy(plugin_config.get())
  local board_config = self.config

  if getmetatable(board_config) == TypeConverter then
    for _, key in ipairs(board_config:keys()) do
      snapshot[key] = board_config[key]
    end
  elseif type(board_config) == "table" then
    for key, _ in pairs(board_config) do
      snapshot[key] = board_config[key]
    end
  end

  return snapshot
end

-- Validate all dependencies in the board
-- Checks for missing dependencies, circular dependencies, and consistency issues
-- @return ValidationResult - Result with errors and warnings
function Board:validate_dependencies()
  local ValidationResult = require('kanban-md.validation_result')
  local column_helper = require('kanban-md.helpers.column')
  local result = ValidationResult.success()

  -- Helper function to detect circular dependencies
  local function has_circular_dependency(start_id, target_id, visited)
    visited = visited or {}
    if visited[start_id] then
      return false  -- Already visited, no cycle here
    end
    if start_id == target_id then
      return true  -- Found cycle
    end
    visited[start_id] = true

    local card = self:find_task(start_id)
    if not card or not card.properties.depends_on then
      return false
    end

    for _, dep_id in ipairs(card.properties.depends_on) do
      if has_circular_dependency(dep_id, target_id, visited) then
        return true
      end
    end
    return false
  end

  -- Iterate through all cards and check dependencies
  local all_columns = TblUtils.deepcopy(self.columns)
  if self.archive then
    table.insert(all_columns, self.archive)
  end

  for _, column in ipairs(all_columns) do
    for _, card in ipairs(column.cards) do
      if card.properties.depends_on and #card.properties.depends_on > 0 then
        -- Check each dependency
        for _, dep_id in ipairs(card.properties.depends_on) do
          -- Check if dependency exists
          local dep_card, dep_column = self:find_task(dep_id)
          if not dep_card then
            result:add_error(string.format(
              "Card '%s' (ID: %s) has missing dependency: %s",
              card.text or "Unknown",
              card.properties.id or "no-id",
              dep_id
            ))
          else
            -- Check for circular dependency
            if has_circular_dependency(dep_id, card.properties.id, {}) then
              result:add_error(string.format(
                "Circular dependency detected: '%s' <-> '%s'",
                card.text or card.properties.id,
                dep_card.text or dep_id
              ))
            end

            -- Check consistency: warn if complete card depends on incomplete card
            local card_is_complete = column_helper.is_completion_column(column, self)
            local dep_is_complete = dep_column and column_helper.is_completion_column(dep_column, self)

            if card_is_complete and not dep_is_complete then
              result:add_warning(string.format(
                "Complete card '%s' depends on incomplete card '%s' (in '%s')",
                card.text or card.properties.id,
                dep_card.text or dep_id,
                dep_column and dep_column.name or "Unknown"
              ))
            end
          end
        end
      end
    end
  end

  return result
end

-- Add a new column to the board
-- Inserts column block before archive if present, otherwise at end
-- @param name string - Name of the column to create
-- @param config table|nil - Optional configuration for the column
-- @return Column - The created column object
function Board:add_new_column(name, config)
  local TypeConverter = require('kanban-md.type_converter')
  local column = Column:new(nil, name)

  if config then
    -- Programmatic config counts as authored: set both the resolved layer
    -- (column.config, consulted by triggers/helpers/stats) and the authored
    -- layer (column.markdown_config, serialised by the writer) so a
    -- programmatically added column round-trips through write() as well as
    -- write_legacy(). See PLAN-config-fixes.md Task 3.
    column.config = TypeConverter:new(config)
    column.markdown_config = TypeConverter:new(config)
  end

  table.insert(self.columns, column)
  column.board = self

  -- If we have content blocks, insert column block at appropriate position
  if self.content_blocks and #self.content_blocks > 0 then
    local ContentBlock = require('kanban-md.content_block')
    local insert_pos = #self.content_blocks + 1

    -- Find position before archive
    for i, block in ipairs(self.content_blocks) do
      if block.type == ContentBlock.TYPES.COLUMN then
        if block.ref and block.ref.is_archive then
          insert_pos = i
          break
        end
      end
    end

    table.insert(self.content_blocks, insert_pos, ContentBlock.column(column))
  end

  return column
end

-- Configuration-driven trigger registration
function Board:auto_register_triggers()
  -- Register workflow triggers if configuration exists
  if self.config.workflow then
    local WorkflowEngine = require('kanban-md.workflow_engine')
    WorkflowEngine:new(self) -- This will auto-setup triggers during initialization
  end

  -- Register optional subtasks/dependencies triggers if enabled
  local plugin_config = require('kanban-md.config')

  -- Get dependency/subtask modes (board file config overrides plugin config,
  -- resolved via get_config_value then normalised to the canonical mode string)
  local dependency_mode = plugin_config.normalize_dependency_mode(self:get_config_value('dependency_validation'))
  local subtask_mode = plugin_config.normalize_dependency_mode(self:get_config_value('subtask_validation'))

  if dependency_mode or subtask_mode then
    local subtasks_module = require('kanban-md.extras.subtasks_triggers')

    -- Register property types with TypeConverter
    subtasks_module.register_property_types()

    -- Register triggers on all columns
    for _, column in ipairs(self.columns) do
      -- Register dependency triggers with bypass metadata
      if dependency_mode then
        local dep_fn = subtasks_module.create_dependency_trigger(dependency_mode)
        column:register_on_checking("dependencies", dep_fn, {
          bypassable = true,
          category = "dependency"
        })
      end

      -- Register subtask triggers with bypass metadata
      if subtask_mode then
        local subtask_fn = subtasks_module.create_subtask_trigger(subtask_mode)
        column:register_on_checking("subtasks", subtask_fn, {
          bypassable = true,
          category = "subtask"
        })
      end
    end
  end

  -- Register board-level configured triggers
  if self.config.triggers then
    self:register_configured_triggers(self.config.triggers, self)
  end

  -- Register column-level triggers
  for _, column in ipairs(self.columns) do
    -- Register basic validation triggers on all columns
    self:register_basic_triggers(column)

    -- Register type-based triggers
    if column.type then
      self:register_type_triggers(column)
    end

    -- Validate column requirements
    local global_config = require('kanban-md.config').get()
    local resolver = require('kanban-md.column_type_resolver')
    resolver.validate_requirements(column, global_config)

    -- Register column-specific configured triggers
    if column.config and column.config.triggers then
      self:register_configured_triggers(column.config.triggers, column)
    end
  end
end

function Board:register_type_triggers(column)
  -- Get global config and type definition
  local global_config = require('kanban-md.config').get()
  local resolver = require('kanban-md.column_type_resolver')
  local type_def = resolver.get_type_definition(column.type, global_config)

  if not type_def then
    return -- Type not found in config, skip (already validated)
  end

  -- Get trigger configuration from type
  local type_triggers = resolver.get_type_triggers(type_def)

  -- Register triggers for each event type
  for event_type, trigger_list in pairs(type_triggers) do
    if type(trigger_list) == "table" then
      for _, trigger_config in ipairs(trigger_list) do
        -- Use existing method to register trigger
        local success, err = pcall(function()
          self:register_trigger_from_config(event_type, trigger_config, column)
        end)

        if not success then
          -- Emit clear error message about missing trigger
          error(string.format(
            "Column type '%s' requires trigger '%s' but it could not be registered: %s. " ..
            "Check that the trigger module '%s' is loaded.",
            column.type,
            trigger_config.name or "unknown",
            err,
            trigger_config.module or "unknown"
          ))
        end
      end
    end
  end
end

function Board:register_basic_triggers(column)
  -- Load basic trigger functions
  local triggers = require('kanban-md.triggers')
  local capacity_triggers = require('kanban-md.extras.capacity_triggers')

  -- Register timestamp trigger if auto_timestamp is enabled (default: true)
  -- Board file config wins over the plugin default (explicit false disables it)
  local auto_timestamp = self:get_config_value('auto_timestamp')

  if auto_timestamp ~= false then
    local timestamp_fn = triggers.timestamp()
    column:register_on_entry("add_timestamp", timestamp_fn)
  end

  -- Register default complexity trigger if use_complexity is enabled
  local use_complexity = self:get_config_value('use_complexity')

  if use_complexity then
    local default_complexity = self:get_config_value('default_complexity')

    local complexity_fn = triggers.default_complexity(default_complexity)
    column:register_on_entry("add_default_complexity", complexity_fn)
  end

  -- Register cursor positioning trigger if enabled
  local enable_cursor_positioning = self:get_config_value('enable_cursor_positioning')

  if enable_cursor_positioning then
    local cursor_triggers = require('kanban-md.extras.cursor_triggers')
    local cursor_fn = cursor_triggers.create_cursor_target_trigger()
    column:register_on_entry("mark_for_cursor", cursor_fn)
  end

  -- Register WIP limit trigger if configured (using existing triggers.lua)
  if column.config and column.config.wip_limit then
    local wip_fn = triggers.wip_limit(column.config.wip_limit)
    column:register_on_checking("wip_limit", wip_fn)
  end

  -- Register capacity points trigger if configured (using extras)
  if column.config and column.config.capacity and column.config.capacity.max_points then
    local points_fn = capacity_triggers.create_capacity_points_trigger(column.config.capacity.max_points)
    column:register_on_checking("capacity_points", points_fn)
  end
end

function Board:register_configured_triggers(triggers_config, target_object)
  -- Register each trigger type from configuration
  for trigger_type, trigger_list in pairs(triggers_config) do
    if type(trigger_list) == "table" then
      for _, trigger_config in ipairs(trigger_list) do
        self:register_trigger_from_config(trigger_type, trigger_config, target_object)
      end
    end
  end
end

function Board:register_trigger_from_config(trigger_type, trigger_config, target_object)
  -- Load the specified module and function
  local module_name = trigger_config.module
  local function_name = trigger_config.function_name or trigger_config["function"]
  local trigger_name = trigger_config.name

  if not module_name or not function_name or not trigger_name then
    error(string.format("Invalid trigger configuration: module=%s, function=%s, name=%s",
          tostring(module_name), tostring(function_name), tostring(trigger_name)))
  end

  local success, module = pcall(require, module_name)
  if not success then
    error(string.format("Failed to load trigger module '%s': %s", module_name, module))
  end

  local trigger_fn = module[function_name]
  if not trigger_fn or type(trigger_fn) ~= "function" then
    error(string.format("Trigger function '%s' not found in module '%s'", function_name, module_name))
  end

  -- Create the trigger function with any provided arguments
  local args = trigger_config.args or {}
  local execute_fn = trigger_fn(unpack(args))

  -- Register the trigger on the target object
  if trigger_type == "on_checking" then
    target_object:register_on_checking(trigger_name, execute_fn)
  elseif trigger_type == "on_entry" then
    target_object:register_on_entry(trigger_name, execute_fn)
  elseif trigger_type == "on_exit" then
    target_object:register_on_exit(trigger_name, execute_fn)
  elseif trigger_type == "on_stay" then
    target_object:register_on_stay(trigger_name, execute_fn)
  else
    error(string.format("Unknown trigger type: %s", trigger_type))
  end
end

-- Archive completed cards using triggers module for timestamp handling
-- @param older_than_days number|nil - Only archive cards older than this many days (0 = all)
-- @return number - Count of archived cards
function Board:archive_done_cards(older_than_days)
  older_than_days = older_than_days or 0
  local cutoff_time = os.time() - (older_than_days * 86400)
  local column_helpers = require('kanban-md.helpers.column')
  local triggers_module = require('kanban-md.triggers')

  -- Ensure archive exists
  if not self.archive then
    self.archive = Column:new("__ARCHIVE__", "__ARCHIVE__")
    self.archive.is_archive = true
  end

  local archived_count = 0

  -- Check all columns for completed cards
  for _, column in ipairs(self.columns) do
    local cards_to_keep = {}

    for _, task in ipairs(column.cards) do
      local should_archive = false

      -- Task is completed if in completion column
      local is_completed = column_helpers.is_completion_column(column, self)

      if is_completed then
        if older_than_days > 0 then
          -- Check if old enough
          local completion_column_name
          for _, col in ipairs(self.columns) do
            if column_helpers.is_completion_column(col, self) then
              completion_column_name = col.name:lower()
              break
            end
          end
          local done_time = task.properties[completion_column_name] or 0
          if done_time < cutoff_time then
            should_archive = true
          end
        else
          -- Archive all completed cards
          should_archive = true
        end
      end

      if should_archive then
        -- Update task's column reference (for timestamp trigger)
        task.column = "__ARCHIVE__"

        -- Use triggers module for timestamp handling
        local timestamp_execute_fn = triggers_module.timestamp()
        local archive_column_context = { name = "__ARCHIVE__" }
        timestamp_execute_fn(archive_column_context, { card = task })

        table.insert(self.archive.cards, task)
        archived_count = archived_count + 1
      else
        table.insert(cards_to_keep, task)
      end
    end

    column.cards = cards_to_keep
  end

  return archived_count
end

return Board
