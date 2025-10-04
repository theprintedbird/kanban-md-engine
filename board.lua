-- lua/kanban-md/board-with-commands.lua
-- Enhanced board with command pattern, logging, and rollback capabilities
-- A command pattern system with rollback capabilities for use with triggers.
-- This will make the board truly migratable and provide robust undo/transaction support.## Key Design Features
--
-- ### 1. **Command Pattern Implementation**
-- - Each trigger action is wrapped in a `Command` object with `execute` and `rollback` functions
-- - Commands are uniquely identified and timestamped for tracking
-- - Fallback behaviour for triggers without rollback capability (returns error message)
--
-- ### 2. **Command Log System**
-- - Maintains a comprehensive history of all executed commands
-- - Configurable maximum size with automatic trimming
-- - Preserves context and state before/after each command execution
-- - Enables undo operations and audit trails
--
-- ### 3. **Transaction Support**
-- - Begin/commit/rollback transaction semantics
-- - Nested transaction support via stack
-- - Automatic rollback on errors during complex operations
-- - Example: `move_card_with_rollback` uses transactions to ensure atomicity
--
-- ### 4. **State Capture**
-- - Each class (`Card`, `Column`, `Board`) implements `capture_state()` 
-- - Deep copies preserve exact state at command execution time
-- - Enables accurate rollback to previous states
--
-- ### 5. **Rollback Strategies**
--
-- **Three types of rollback behaviour:**
--
-- 1. **Full Rollback**: Restores previous state completely (e.g., timestamp trigger)
-- 2. **No-op Rollback**: Validation triggers that don't change state
-- 3. **Null Rollback**: For non-reversible operations (logs warning)
--
-- ### 6. **Migration Support**
-- - `export_command_log()` creates serialisable log representation
-- - Could be stored in board metadata comments for persistence
-- - Enables replay of commands for migration between versions
--
-- ### 7. **Backwards Compatibility**
-- - Original `execute_trigger` still works
-- - New `execute_trigger_with_logging` adds command pattern features
-- - Gradual migration path for existing code
--
-- ## Example Rollback Implementations
--
-- **Timestamp Trigger**: Stores and restores previous timestamp value
-- **WIP Limit**: Validation only, no state change to rollback  
-- **Assignment**: Restores previous assignee and round-robin index
--
-- ## Benefits
--
-- 1. **Robust Undo**: Any series of operations can be undone
-- 2. **Error Recovery**: Transactions ensure consistency on failure
-- 3. **Audit Trail**: Complete history of all board modifications
-- 4. **Migration Path**: Command log can be replayed to migrate boards
-- 5. **Debugging**: Clear trace of what happened and when
-- 6. **Testability**: Commands can be tested in isolation
--
-- The system gracefully handles both reversible and non-reversible operations, providing warnings when rollback isn't possible whilst maintaining board integrity through the transaction system.

local Triggerable = require('kanban-md.triggerable')
local Column = require('kanban-md.column')
local StatsMixin = require('kanban-md.stats')
local ParserMixin = require('kanban-md.parser')
local WriterMixin = require('kanban-md.writer_mixin')

-- Board class with transaction support, stats calculation, and parsing capabilities
local Board = {}
Board.__index = Board
setmetatable(Board, { __index = Triggerable })

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
    config = {}
  }
  setmetatable(obj, Board)
  obj:init_commands() -- Initialize both commands and triggers

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

function Board:capture_state()
  local column_states = {}
  for _, column in ipairs(self.columns) do
    table.insert(column_states, column:capture_state())
  end
  return {
    id = self.id,
    columns = column_states,
    config = vim.deepcopy(self.config)
  }
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

  -- Share the command log with child objects for unified history
  column.command_log = self.command_log

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

-- Move a card between columns with context and validation
-- Accepts card and column objects
-- Returns: success (boolean), error_message (string or nil)
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

  return self:move_card_with_rollback(card, from_column, to_column)
end

function Board:move_card_with_rollback(card, from_column, to_column)
  if type(card) ~= "table" or not card.id then
    error("Board:move_card_with_rollback() expects Card object as first parameter")
  end
  if type(from_column) ~= "table" or not from_column.id then
    error("Board:move_card_with_rollback() expects Column object as second parameter")
  end
  if type(to_column) ~= "table" or not to_column.id then
    error("Board:move_card_with_rollback() expects Column object as third parameter")
  end

  -- Begin transaction for complex operation
  self.command_log:begin_transaction()

  -- Build context for triggers
  local context = {
    card = card,
    source_column = from_column,
    target_column = to_column,
    board = self
  }

  -- Try to remove from source column with context
  local removed_card = from_column:remove_card(card, context)
  if not removed_card then
    self.command_log:rollback_transaction()
    return false, "Failed to remove card from source column"
  end

  -- Try to add to target column with context
  local success, err = pcall(function()
    to_column:add_card(removed_card, context)
  end)

  if not success then
    -- Rollback the transaction on error
    self.command_log:rollback_transaction()
    return false, err
  end

  -- Commit the transaction
  self.command_log:commit_transaction()
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

-- Configuration-driven trigger registration
function Board:auto_register_triggers()
  -- Register workflow triggers if configuration exists
  if self.config.workflow then
    local WorkflowEngine = require('kanban-md.workflow_engine')
    WorkflowEngine:new(self) -- This will auto-setup triggers during initialization
  end

  -- Register board-level configured triggers
  if self.config.triggers then
    self:register_configured_triggers(self.config.triggers, self)
  end

  -- Register column-level triggers
  for _, column in ipairs(self.columns) do
    -- Register basic validation triggers on all columns
    self:register_basic_triggers(column)

    -- Register column-specific configured triggers
    if column.config and column.config.triggers then
      self:register_configured_triggers(column.config.triggers, column)
    end
  end
end


function Board:register_basic_triggers(column)
  -- Load basic trigger functions
  local triggers = require('kanban-md.triggers')
  local capacity_triggers = require('kanban-md.extras.capacity_triggers')

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

-- Export log for persistence
function Board:export_command_log(n)
  n = n or 100
  local entries = self.command_log:get_last_n(n)

  -- Convert to serialisable format
  local export_data = {
    board_id = self.id,
    timestamp = os.time(),
    entries = {}
  }

  for _, entry in ipairs(entries) do
    table.insert(export_data.entries, {
      command_name = entry.command.name,
      timestamp = entry.timestamp,
      success = entry.result.success,
      -- Don't export full context/state for space reasons
      -- but could be configured to do so
    })
  end

  return export_data
end

-- Example usage
local function example_usage()
  local Card = require('kanban-md.card')
  local triggers = require('kanban-md.triggers')

  local board = Board:new()
  local column1 = board:add_column("col1", "To Do")
  local column2 = board:add_column("col2", "In Progress")

  -- Register triggers with rollback
  local timestamp_exec, timestamp_rollback = triggers.timestamp()
  column1:register_trigger_with_rollback("on_entry", "add_timestamp", timestamp_exec, timestamp_rollback)
  column2:register_trigger_with_rollback("on_entry", "add_timestamp", timestamp_exec, timestamp_rollback)

  local wip_exec, wip_rollback = triggers.wip_limit(2)
  column2:register_trigger_with_rollback("on_entry", "check_wip", wip_exec, wip_rollback)

  local assign_exec, assign_rollback = triggers.assignment()
  column2:register_trigger_with_rollback("on_entry", "auto_assign", assign_exec, assign_rollback)
  column2.config.assignees = {"alice", "bob", "charlie"}

  -- Create and move cards
  local card1 = Card:new("card1", "Implement feature", {complexity = 3})
  column1:add_card(card1)

  -- Move card with full rollback support
  local success, err = board:move_card_with_rollback(card1, column1, column2)

  if not success then
    print("Move failed, all changes rolled back: " .. err)
  end

  -- Undo last action
  local undone, undo_errors = column2:undo(1)
  print(string.format("Undone %d actions", undone))

  -- Export log for persistence
  local log_export = board:export_command_log(50)
  -- Could save this to board metadata for migration
end

return Board
