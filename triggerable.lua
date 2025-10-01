--[[
Enhanced Triggerable mixin with command pattern

This module provides trigger functionality for Board, Column, and Card objects.
Triggers are functions that execute in response to events (entry, exit, stay, checking, create).

WRITING CUSTOM TRIGGERS
========================

Each trigger consists of two functions: execute and rollback (optional).

Execute Function Signature:
---------------------------
function(self, context)
  -- Parameters:
  --   self: The triggerable object (column, board, or card)
  --   context: Table containing:
  --     - board: The board object
  --     - column: The column object
  --     - card: The card object
  --     - timestamp: Event timestamp
  --     - args: Additional arguments passed to trigger
  --
  -- Returns:
  --   Value to be used for rollback (or true if nothing to rollback)
end

Rollback Function Signature (optional):
---------------------------------------
function(self, context)
  -- Parameters:
  --   self: The triggerable object
  --   context: Table containing:
  --     - result: The value returned by execute function
  --     - board, column, card: The relevant objects
  --     - args: Original arguments
  --
  -- Returns:
  --   true on successful rollback, false otherwise
end

EXAMPLE: Timestamp Trigger
---------------------------
local function create_timestamp_trigger()
  local execute_fn = function(self, card)
    local timestamp_key = self.name:lower():gsub("[^%w_]", "_")
    local old_value = card.properties[timestamp_key]
    card.properties[timestamp_key] = os.time()
    return old_value  -- For rollback
  end

  local rollback_fn = function(self, context)
    local card = context.args[1]
    local timestamp_key = self.name:lower():gsub("[^%w_]", "_")
    card.properties[timestamp_key] = context.result
    return true
  end

  return execute_fn, rollback_fn
end

EXAMPLE: WIP Limit Trigger
---------------------------
local function create_wip_limit_trigger(wip_limit)
  local execute_fn = function(self, card)
    if #self.cards > wip_limit then
      error(string.format("WIP limit exceeded: %d/%d", #self.cards, wip_limit))
    end
    return true
  end

  local rollback_fn = function(self, context)
    return true  -- Nothing to rollback for validation
  end

  return execute_fn, rollback_fn
end

REGISTERING TRIGGERS
--------------------
-- Register on a column
local execute_fn, rollback_fn = create_timestamp_trigger()
column:register_on_entry("timestamp", execute_fn, rollback_fn)

-- Register on a board
local execute_fn, rollback_fn = create_wip_limit_trigger(5)
board:register_on_checking("wip_limit", execute_fn, rollback_fn)

TRIGGER EVENTS
--------------
- on_entry: Fires when a card enters a column
- on_exit: Fires when a card leaves a column
- on_stay: Fires while a card remains in a column
- on_checking: Fires to validate before a transition
- on_create: Fires when a new card is created

See lua/kanban-md/triggers.lua and lua/kanban-md/extras/id_triggers.lua for more examples.
--]]

local Command = require('kanban-md.command')
local CommandLog = require('kanban-md.command_log')

-- Enhanced Triggerable mixin with command pattern
local Triggerable = {}

function Triggerable:init_commands()
  if not self.command_log then
    self.command_log = CommandLog:new()
  end
  if not self.triggers then
    self.triggers = {}
  end
  if not self.command_factories then
    self.command_factories = {}
  end
end

-- Register a trigger with optional rollback
function Triggerable:register_trigger_with_rollback(event_type, name, execute_fn, rollback_fn)
  self:init_commands()

  if not self.triggers[event_type] then
    self.triggers[event_type] = {}
  end

  -- Create a command factory for this trigger
  local command_factory = function(...)
    return Command:new(
      string.format("%s.%s.%s", self.id or "unknown", event_type, name),
      execute_fn,
      rollback_fn
    )
  end

  -- Store both the raw function (for backwards compatibility) and the factory
  self.triggers[event_type][name] = execute_fn
  if not self.command_factories[event_type] then
    self.command_factories[event_type] = {}
  end
  self.command_factories[event_type][name] = command_factory
end

-- Execute trigger with command logging
function Triggerable:execute_trigger_with_logging(event_type, name, ...)
  self:init_commands()

  if not self.triggers or not self.triggers[event_type] or not self.triggers[event_type][name] then
    return false, "Trigger not found"
  end

  local args = {...}
  local context = {
    self = self,
    event_type = event_type,
    trigger_name = name,
    args = args,
    state_before = self:capture_state()
  }

  -- Create command if factory exists, otherwise use raw function
  local command
  if self.command_factories[event_type] and self.command_factories[event_type][name] then
    command = self.command_factories[event_type][name](self, ...)
  else
    -- Fallback for triggers without rollback
    command = Command:new(
      string.format("%s.%s.%s", self.id or "unknown", event_type, name),
      function() return self.triggers[event_type][name](self, unpack(args)) end,
      nil  -- No rollback
    )
  end

  -- Execute the command
  local success, result = pcall(command.execute, self, ...)

  -- Log the command execution
  local log_entry = self.command_log:add(command, {success = success, result = result}, context)

  -- Store state after execution
  log_entry.state_after = self:capture_state()

  if not success then
    return false, result
  end

  return true, result
end

-- Undo last n commands
function Triggerable:undo(n)
  self:init_commands()
  n = n or 1

  local entries = self.command_log:get_last_n(n)
  local errors = {}
  local successes = 0

  -- Process in reverse order
  for i = #entries, 1, -1 do
    local entry = entries[i]
    if entry.command.rollback then
      local success, err = pcall(entry.command.rollback, entry.context.self, entry.context)
      if success then
        successes = successes + 1
      else
        table.insert(errors, string.format("Failed to undo %s: %s",
          entry.command.name, err or "unknown error"))
      end
    else
      table.insert(errors, string.format("No rollback available for %s", entry.command.name))
    end
  end

  return successes, errors
end

-- Simple trigger registration methods (for testing and basic usage)
function Triggerable:register_trigger(event_type, name, execute_fn)
  self:init_commands()
  
  if not self.triggers[event_type] then
    self.triggers[event_type] = {}
  end
  
  self.triggers[event_type][name] = execute_fn
end

function Triggerable:register_on_enter(name, execute_fn, rollback_fn)
  if rollback_fn then
    self:register_trigger_with_rollback("on_enter", name, execute_fn, rollback_fn)
  else
    self:register_trigger("on_enter", name, execute_fn)
  end
end

function Triggerable:register_on_exit(name, execute_fn, rollback_fn)
  if rollback_fn then
    self:register_trigger_with_rollback("on_exit", name, execute_fn, rollback_fn)
  else
    self:register_trigger("on_exit", name, execute_fn)
  end
end

function Triggerable:register_on_stay(name, execute_fn, rollback_fn)
  if rollback_fn then
    self:register_trigger_with_rollback("on_stay", name, execute_fn, rollback_fn)
  else
    self:register_trigger("on_stay", name, execute_fn)
  end
end

function Triggerable:get_triggers(event_type)
  self:init_commands()
  return self.triggers[event_type] or {}
end

function Triggerable:execute_triggers(event_type, context)
  self:init_commands()
  
  if not self.triggers[event_type] then
    return {}, {}
  end
  
  local results = {}
  local errors = {}
  
  -- Execute triggers in registration order (table iteration order)
  for name, trigger_fn in pairs(self.triggers[event_type]) do
    local success, result = self:execute_trigger_with_logging(event_type, name, context)
    
    table.insert(results, {
      name = name,
      success = success,
      result = success and result or nil,
      error = not success and result or nil
    })
    
    if not success then
      table.insert(errors, {name = name, error = result})
    end
  end
  
  return results, errors
end

-- Capture current state (to be overridden by specific classes)
function Triggerable:capture_state()
  -- Default implementation - override in Card/Column/Board
  return {}
end

return Triggerable
