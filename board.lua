-- lua/kanban-md/board.lua
-- Board class with stats calculation and parsing capabilities

local Triggerable = require('kanban-md.triggerable')
local Column = require('kanban-md.column')
local StatsMixin = require('kanban-md.stats')
local ParserMixin = require('kanban-md.parser')
local WriterMixin = require('kanban-md.writer_mixin')

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

-- Add a new column to the board
-- Inserts column block before archive if present, otherwise at end
-- @param name string - Name of the column to create
-- @param config table|nil - Optional configuration for the column
-- @return Column - The created column object
function Board:add_new_column(name, config)
  local TypeConverter = require('kanban-md.type_converter')
  local column = Column:new(nil, name)

  if config then
    column.config = TypeConverter:new(config)
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
  local enable_subtasks = self.config.enable_subtasks
  if enable_subtasks == nil then
    enable_subtasks = plugin_config.get_value('enable_subtasks')
  end
  local enable_dependencies = self.config.enable_dependencies
  if enable_dependencies == nil then
    enable_dependencies = plugin_config.get_value('enable_dependencies')
  end

  if enable_subtasks or enable_dependencies then
    local subtasks_module = require('kanban-md.extras.subtasks_triggers')

    -- Register property types with TypeConverter
    subtasks_module.register_property_types()

    -- Register triggers on all columns
    for _, column in ipairs(self.columns) do
      if enable_dependencies then
        local dep_fn, dep_rollback = subtasks_module.create_dependency_trigger()
        column:register_on_checking("dependencies", dep_fn, dep_rollback)
      end

      if enable_subtasks then
        local subtask_fn, subtask_rollback = subtasks_module.create_subtask_trigger()
        column:register_on_checking("subtasks", subtask_fn, subtask_rollback)
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
  local plugin_config = require('kanban-md.config')

  -- Register timestamp trigger if auto_timestamp is enabled (default: true)
  local auto_timestamp = self.config.auto_timestamp
  if auto_timestamp == nil then
    auto_timestamp = plugin_config.get_value('auto_timestamp')
  end

  if auto_timestamp ~= false then
    local timestamp_fn, timestamp_rollback = triggers.timestamp()
    column:register_on_entry("add_timestamp", timestamp_fn, timestamp_rollback)
  end

  -- Register default complexity trigger if use_complexity is enabled
  local use_complexity = self.config.use_complexity
  if use_complexity == nil then
    use_complexity = plugin_config.get_value('use_complexity')
  end

  if use_complexity then
    local default_complexity = self.config.default_complexity
    if default_complexity == nil then
      default_complexity = plugin_config.get_value('default_complexity')
    end

    local complexity_fn, complexity_rollback = triggers.default_complexity(default_complexity)
    column:register_on_entry("add_default_complexity", complexity_fn, complexity_rollback)
  end

  -- Register cursor positioning trigger if enabled
  local enable_cursor_positioning = self.config.enable_cursor_positioning
  if enable_cursor_positioning == nil then
    enable_cursor_positioning = plugin_config.get_value('enable_cursor_positioning')
  end

  if enable_cursor_positioning then
    local cursor_triggers = require('kanban-md.extras.cursor_triggers')
    local cursor_fn = cursor_triggers.create_cursor_target_trigger()
    column:register_on_entry("mark_for_cursor", cursor_fn)
  end

  -- Register WIP limit trigger if configured (using existing triggers.lua)
  if column.config and column.config.wip_limit then
    local wip_fn, wip_rollback = triggers.wip_limit(column.config.wip_limit)
    column:register_on_checking("wip_limit", wip_fn, wip_rollback)
  end

  -- Register capacity points trigger if configured (using extras)
  if column.config and column.config.capacity and column.config.capacity.max_points then
    local points_fn, points_rollback = capacity_triggers.create_capacity_points_trigger(column.config.capacity.max_points)
    column:register_on_checking("capacity_points", points_fn, points_rollback)
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
  local execute_fn, rollback_fn = trigger_fn(unpack(args))

  -- Register the trigger on the target object
  if trigger_type == "on_checking" then
    target_object:register_on_checking(trigger_name, execute_fn, rollback_fn)
  elseif trigger_type == "on_entry" then
    target_object:register_on_entry(trigger_name, execute_fn, rollback_fn)
  elseif trigger_type == "on_exit" then
    target_object:register_on_exit(trigger_name, execute_fn, rollback_fn)
  elseif trigger_type == "on_stay" then
    target_object:register_on_stay(trigger_name, execute_fn, rollback_fn)
  else
    error(string.format("Unknown trigger type: %s", trigger_type))
  end
end

return Board
