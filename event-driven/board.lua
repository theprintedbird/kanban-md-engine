-- lua/kanban-md/event-driven/board-with-commands.lua
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

local Triggerable = require('kanban-md.event-driven.triggerable')
local Column = require('kanban-md.event-driven.column')

-- Board class with transaction support
local Board = {}
Board.__index = Board
setmetatable(Board, { __index = Triggerable })

function Board:new()
  local obj = { 
    id = "board_" .. os.time(),
    columns = {},
    config = {}
  }
  setmetatable(obj, Board)
  obj:init_commands()
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
  local column = Column:new(id, name)
  table.insert(self.columns, column)
  
  -- Share the command log with child objects for unified history
  column.command_log = self.command_log
  
  return column
end

function Board:move_card_with_rollback(card_id, from_column_id, to_column_id)
  -- Begin transaction for complex operation
  self.command_log:begin_transaction()
  
  local from_column = self:get_column(from_column_id)
  local to_column = self:get_column(to_column_id)
  
  if not from_column or not to_column then
    self.command_log:rollback_transaction()
    return false, "Invalid columns"
  end
  
  local card = from_column:remove_card(card_id)
  if not card then
    self.command_log:rollback_transaction()
    return false, "Card not found"
  end
  
  -- Try to add to new column
  local success, err = pcall(function()
    to_column:add_card(card)
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
  local Card = require('kanban-md.event-driven.card')
  local triggers = require('kanban-md.event-driven.triggers')
  
  local board = Board:new()
  local column1 = board:add_column("col1", "To Do")
  local column2 = board:add_column("col2", "In Progress")
  
  -- Register triggers with rollback
  local timestamp_exec, timestamp_rollback = triggers.timestamp()
  column1:register_trigger_with_rollback("on_enter", "add_timestamp", timestamp_exec, timestamp_rollback)
  column2:register_trigger_with_rollback("on_enter", "add_timestamp", timestamp_exec, timestamp_rollback)
  
  local wip_exec, wip_rollback = triggers.wip_limit(2)
  column2:register_trigger_with_rollback("on_enter", "check_wip", wip_exec, wip_rollback)
  
  local assign_exec, assign_rollback = triggers.assignment()
  column2:register_trigger_with_rollback("on_enter", "auto_assign", assign_exec, assign_rollback)
  column2.config.assignees = {"alice", "bob", "charlie"}
  
  -- Create and move cards
  local card1 = Card:new("card1", "Implement feature", {complexity = 3})
  column1:add_card(card1)
  
  -- Move card with full rollback support
  local success, err = board:move_card_with_rollback("card1", "col1", "col2")
  
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
