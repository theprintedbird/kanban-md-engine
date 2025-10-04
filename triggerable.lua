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
    -- Fallback for triggers without rollback - capture multiple return values
    command = Command:new(
      string.format("%s.%s.%s", self.id or "unknown", event_type, name),
      function()
        local values = {self.triggers[event_type][name](self, unpack(args))}
        -- Return single value unwrapped, or multiple values as table
        if #values == 1 then
          return values[1]
        else
          return values
        end
      end,
      nil  -- No rollback
    )
  end

  -- Execute the command and capture multiple return values
  local exec_result = {pcall(function()
    local values = {command.execute(self, unpack(args))}
    return {success = true, values = values, n = #values}
  end)}

  local success = exec_result[1]
  local result

  if success then
    local packed = exec_result[2]
    -- The command now returns the values table directly
    if packed.n == 1 and type(packed.values[1]) == "table" then
      -- The command returned a values table from the trigger
      result = packed.values[1]
    elseif packed.n == 1 then
      result = packed.values[1]
    else
      result = packed.values  -- Multiple return values as table
    end
  else
    result = exec_result[2]  -- Error message
  end

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

function Triggerable:register_on_entry(name, execute_fn, rollback_fn)
  if rollback_fn then
    self:register_trigger_with_rollback("on_entry", name, execute_fn, rollback_fn)
  else
    self:register_trigger("on_entry", name, execute_fn)
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

function Triggerable:register_on_checking(name, execute_fn, rollback_fn)
  if rollback_fn then
    self:register_trigger_with_rollback("on_checking", name, execute_fn, rollback_fn)
  else
    self:register_trigger("on_checking", name, execute_fn)
  end
end

function Triggerable:register_on_create(name, execute_fn, rollback_fn)
  if rollback_fn then
    self:register_trigger_with_rollback("on_create", name, execute_fn, rollback_fn)
  else
    self:register_trigger("on_create", name, execute_fn)
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
    if success and result and type(result) == "table" and result.errors and result.warnings then
      table.insert(results, result)
    else
      -- Handle legacy format
      local error_msg, warning_msg, metadata = nil, nil, nil

      if success and result then
      -- Handle multiple return values format: success, error_message, warning_message, metadata
      if type(result) == "table" and result[1] ~= nil then
        -- Check if this is a standardized multi-value return or legacy single string
        if #result == 1 and type(result[1]) == "string" and event_type == "on_checking" then
          -- Legacy format - single string for checking triggers
          warning_msg = result[1]
        elseif type(result[1]) == "boolean" then
          -- Standardized multi-value format: success, error, warning, metadata
          local trigger_success = result[1]
          if not trigger_success then
            error_msg = result[2]  -- Error message
          else
            error_msg = result[2]  -- Could still be error message in success=true case
            warning_msg = result[3]  -- Warning message
            metadata = result[4]  -- Metadata
          end
        else
          -- Unknown format, treat first element as metadata
          metadata = result[1]
        end
      elseif type(result) == "table" and result.error then
        -- Table with named fields
        error_msg = result.error
        warning_msg = result.warning
        metadata = result.metadata
      elseif type(result) == "string" then
        -- Legacy format - treat as warning for checking triggers
        if event_type == "on_checking" then
          warning_msg = result
        end
      else
        metadata = result
      end
    elseif not success then
      error_msg = result
    end

      table.insert(results, {
        name = name,
        success = success,
        result = success and result or nil,
        error = error_msg,
        warning = warning_msg,
        metadata = metadata
      })

      if not success or error_msg then
        table.insert(errors, {name = name, error = error_msg or result})
      end
    end
  end

  return results, errors
end

-- Create enhanced context for checking triggers
function Triggerable:create_checking_context(card, source_column, target_column, board, transition_type, timestamp)
  return {
    card = card,
    source_column = source_column,
    target_column = target_column,
    target_column_name = target_column and target_column.name or nil,
    transition_type = transition_type or "move",
    timestamp = timestamp or os.time(),
    board = board
  }
end

-- Standard trigger result factory functions
-- Create a success result
function Triggerable:success(warning, metadata)
  return {
    success = true,
    errors = {},
    warnings = warning and {warning} or {},
    metadata = metadata or {}
  }
end

-- Create an error result
function Triggerable:error(error_message,metadata)
  return {
    success = false,
    errors = {error_message},
    warnings = {},
    metadata = metadata or {}
  }
end

-- Create a warning result (success with warnings)
function Triggerable:warning(warning_message, metadata)
  return {
    success = true,
    errors = {},
    warnings = {warning_message},
    metadata = metadata or {}
  }
end

-- Create a result with multiple errors
function Triggerable:errors(error_list, metadata)
  return {
    success = false,
    errors = error_list,
    warnings = {},
    metadata = metadata or {}
  }
end

-- Create a result with multiple warnings
function Triggerable:warnings(warning_list, metadata)
  return {
    success = true,
    errors = {},
    warnings = warning_list,
    metadata = metadata or {}
  }
end

-- Create a custom result
function Triggerable:custom(success, errors, warnings, metadata)
  return {
    success = success or false,
    errors = errors or {},
    warnings = warnings or {},
    metadata = metadata or {}
  }
end

-- Merge multiple results into one
function Triggerable:merge(results)
  local merged = {
    success = true,
    errors = {},
    warnings = {},
    metadata = {}
  }

  for _, result in ipairs(results) do
    if not result.success then
      merged.success = false
    end

    -- Merge errors
    for _, error in ipairs(result.errors or {}) do
      table.insert(merged.errors, error)
    end

    -- Merge warnings
    for _, warning in ipairs(result.warnings or {}) do
      table.insert(merged.warnings, warning)
    end

    -- Merge metadata (later values override earlier ones)
    for k, v in pairs(result.metadata or {}) do
      merged.metadata[k] = v
    end
  end

  return merged
end

-- Check if a result represents success (no errors)
function Triggerable:is_success(result)
  return result.success and #result.errors == 0
end

-- Check if a result has warnings
function Triggerable:has_warnings(result)
  return #result.warnings > 0
end

-- Check if a result has errors
function Triggerable:has_errors(result)
  return #result.errors > 0
end

-- Get a summary string of the result
function Triggerable:summary(result)
  local parts = {}

  if #result.errors > 0 then
    table.insert(parts, string.format("%d error(s)", #result.errors))
  end

  if #result.warnings > 0 then
    table.insert(parts, string.format("%d warning(s)", #result.warnings))
  end

  if #parts == 0 then
    return "Success"
  else
    return table.concat(parts, ", ")
  end
end

-- Clear triggers for specific event type and name, or all triggers
function Triggerable:clear_triggers(event_type, name)
  self:init_commands()

  if event_type and name then
    -- Clear specific trigger
    if self.triggers[event_type] then
      self.triggers[event_type][name] = nil
    end
    if self.command_factories[event_type] then
      self.command_factories[event_type][name] = nil
    end
  elseif event_type then
    -- Clear all triggers for event type
    self.triggers[event_type] = {}
    self.command_factories[event_type] = {}
  else
    -- Clear all triggers
    self.triggers = {}
    self.command_factories = {}
  end
end

-- Capture current state (to be overridden by specific classes)
function Triggerable:capture_state()
  -- Default implementation - override in Card/Column/Board
  return {}
end

return Triggerable
