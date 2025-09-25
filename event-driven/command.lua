-- Command class for encapsulating trigger actions with undo
local Command = {}
Command.__index = Command

function Command:new(name, execute_fn, rollback_fn, metadata)
  local obj = {
    name = name,
    execute = execute_fn,
    rollback = rollback_fn or function() 
      return false, "Rollback not implemented for " .. name 
    end,
    metadata = metadata or {},
    timestamp = os.time(),
    id = string.format("%s_%d_%d", name, os.time(), math.random(10000))
  }
  setmetatable(obj, Command)
  return obj
end

return Command