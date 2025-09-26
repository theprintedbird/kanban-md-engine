local Command = require('kanban-md.event-driven.command')
local CommandLog = require('kanban-md.event-driven.command_log')

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

-- Capture current state (to be overridden by specific classes)
function Triggerable:capture_state()
  -- Default implementation - override in Card/Column/Board
  return {}
end

return Triggerable