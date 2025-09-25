-- CommandLog for tracking all executed commands
local CommandLog = {}
CommandLog.__index = CommandLog

function CommandLog:new(max_size)
  local obj = {
    entries = {},
    max_size = max_size or 1000,
    current_index = 0,
    transaction_stack = {}  -- For nested transactions
  }
  setmetatable(obj, CommandLog)
  return obj
end

function CommandLog:add(command, result, context)
  local entry = {
    command = command,
    result = result,
    context = vim.deepcopy(context),  -- Deep copy to preserve state
    timestamp = os.time(),
    index = self.current_index + 1
  }
  
  table.insert(self.entries, entry)
  self.current_index = self.current_index + 1
  
  -- Trim log if it exceeds max size
  if #self.entries > self.max_size then
    table.remove(self.entries, 1)
  end
  
  return entry
end

function CommandLog:get_last_n(n)
  local start_idx = math.max(1, #self.entries - n + 1)
  local result = {}
  for i = start_idx, #self.entries do
    table.insert(result, self.entries[i])
  end
  return result
end

function CommandLog:begin_transaction()
  table.insert(self.transaction_stack, self.current_index)
end

function CommandLog:commit_transaction()
  if #self.transaction_stack > 0 then
    table.remove(self.transaction_stack)
    return true
  end
  return false, "No transaction to commit"
end

function CommandLog:rollback_transaction()
  if #self.transaction_stack == 0 then
    return false, "No transaction to rollback"
  end
  
  local transaction_start = table.remove(self.transaction_stack)
  local errors = {}
  
  -- Rollback commands in reverse order
  for i = #self.entries, transaction_start + 1, -1 do
    local entry = self.entries[i]
    if entry and entry.command.rollback then
      local success, err = entry.command:rollback(entry.context)
      if not success then
        table.insert(errors, string.format("Failed to rollback %s: %s", 
          entry.command.name, err or "unknown error"))
      end
    end
    -- Remove the entry after rollback attempt
    table.remove(self.entries, i)
  end
  
  self.current_index = transaction_start
  
  if #errors > 0 then
    return false, table.concat(errors, "; ")
  end
  return true
end

return CommandLog