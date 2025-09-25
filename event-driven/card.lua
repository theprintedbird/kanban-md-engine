local Triggerable = require('kanban-md.event-driven.triggerable')

-- Card class with enhanced state capture
local Card = {}
Card.__index = Card
setmetatable(Card, { __index = Triggerable })

function Card:new(id, text, properties)
  local obj = { 
    id = id,
    text = text or "",
    properties = properties or {},
    column = nil
  }
  setmetatable(obj, Card)
  obj:init_commands()
  return obj
end

function Card:capture_state()
  return {
    id = self.id,
    text = self.text,
    properties = vim.deepcopy(self.properties),
    column = self.column
  }
end

return Card