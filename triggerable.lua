--[[
Triggerable mixin

This module provides trigger functionality for Board, Column, and Card objects.
Triggers are functions that execute in response to events (entry, exit, stay, checking, create).

WRITING CUSTOM TRIGGERS
========================

Each trigger is a single function that executes when the event occurs.

Trigger Function Signature:
----------------------------
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
  --   true on success, or error() on failure
end

EXAMPLE: Timestamp Trigger
---------------------------
local function create_timestamp_trigger()
  return function(self, context)
    local timestamp_key = self.name:lower():gsub("[^%w_]", "_")
    context.card.properties[timestamp_key] = os.time()
    return true
  end
end

EXAMPLE: WIP Limit Trigger
---------------------------
local function create_wip_limit_trigger(wip_limit)
  return function(self, context)
    if #self.cards >= wip_limit then
      error(string.format("WIP limit exceeded: %d/%d", #self.cards, wip_limit))
    end
    return true
  end
end

REGISTERING TRIGGERS
--------------------
-- Register on a column
local trigger_fn = create_timestamp_trigger()
column:register_on_entry("timestamp", trigger_fn)

-- Register on a board
local trigger_fn = create_wip_limit_trigger(5)
board:register_on_checking("wip_limit", trigger_fn)

TRIGGER EVENTS
--------------
- on_entry: Fires when a card enters a column
- on_exit: Fires when a card leaves a column
- on_stay: Fires while a card remains in a column
- on_checking: Fires to validate before a transition
- on_create: Fires when a new card is created

See lua/kanban-md/triggers.lua and lua/kanban-md/extras/id_triggers.lua for more examples.
--]]

-- Triggerable mixin
local Triggerable = {}

-- Register a trigger with optional metadata
function Triggerable:register_trigger(event_type, name, execute_fn, metadata)
  if not self.triggers[event_type] then
    self.triggers[event_type] = {}
  end
  if not self.trigger_order[event_type] then
    self.trigger_order[event_type] = {}
  end
  if not self.trigger_metadata then
    self.trigger_metadata = {}
  end
  if not self.trigger_metadata[event_type] then
    self.trigger_metadata[event_type] = {}
  end

  -- Track insertion order if this is a new trigger
  if not self.triggers[event_type][name] then
    table.insert(self.trigger_order[event_type], name)
  end

  self.triggers[event_type][name] = execute_fn
  self.trigger_metadata[event_type][name] = metadata or {}
end

function Triggerable:register_on_entry(name, execute_fn, metadata)
  self:register_trigger("on_entry", name, execute_fn, metadata)
end

function Triggerable:register_on_exit(name, execute_fn, metadata)
  self:register_trigger("on_exit", name, execute_fn, metadata)
end

function Triggerable:register_on_stay(name, execute_fn, metadata)
  self:register_trigger("on_stay", name, execute_fn, metadata)
end

function Triggerable:register_on_checking(name, execute_fn, metadata)
  self:register_trigger("on_checking", name, execute_fn, metadata)
end

function Triggerable:register_on_create(name, execute_fn, metadata)
  self:register_trigger("on_create", name, execute_fn, metadata)
end

function Triggerable:get_triggers(event_type)
  return self.triggers[event_type] or {}
end

function Triggerable:execute_triggers(event_type, context)

  if not self.triggers[event_type] then
    return {}, {}
  end

  local results = {}
  local errors = {}

  -- Execute triggers in registration order using trigger_order array
  local trigger_names = self.trigger_order[event_type] or {}
  for _, name in ipairs(trigger_names) do
    local trigger_fn = self.triggers[event_type][name]
    if trigger_fn then
      local success, result = pcall(trigger_fn, self, context)
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

  if event_type and name then
    -- Clear specific trigger
    if self.triggers[event_type] then
      self.triggers[event_type][name] = nil
    end
    if self.command_factories and self.command_factories[event_type] then
      self.command_factories[event_type][name] = nil
    end
    if self.trigger_metadata and self.trigger_metadata[event_type] then
      self.trigger_metadata[event_type][name] = nil
    end
    -- Remove from trigger order
    if self.trigger_order[event_type] then
      for i, trigger_name in ipairs(self.trigger_order[event_type]) do
        if trigger_name == name then
          table.remove(self.trigger_order[event_type], i)
          break
        end
      end
    end
  elseif event_type then
    -- Clear all triggers for event type
    self.triggers[event_type] = {}
    if self.command_factories then
      self.command_factories[event_type] = {}
    end
    if self.trigger_metadata then
      self.trigger_metadata[event_type] = {}
    end
    self.trigger_order[event_type] = {}
  else
    -- Clear all triggers
    self.triggers = {}
    if self.command_factories then
      self.command_factories = {}
    end
    if self.trigger_metadata then
      self.trigger_metadata = {}
    end
    self.trigger_order = {}
  end
end

-- Capture current state (to be overridden by specific classes)
function Triggerable:capture_state()
  -- Default implementation - override in Card/Column/Board
  return {}
end

return Triggerable
