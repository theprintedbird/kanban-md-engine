local Triggerable = require('kanban-md.triggerable')

-- Column class with enhanced capabilities
local Column = {}
Column.__index = Column
setmetatable(Column, { __index = Triggerable })

function Column:new(id, name)
  local obj = { 
    id = id,
    name = name or id,
    cards = {},
    config = {}
  }
  setmetatable(obj, Column)
  obj:init_commands()
  return obj
end

function Column:capture_state()
  local card_states = {}
  for _, card in ipairs(self.cards) do
    table.insert(card_states, card:capture_state())
  end
  return {
    id = self.id,
    name = self.name,
    cards = card_states,
    config = vim.deepcopy(self.config)
  }
end

function Column:add_card(card)
  table.insert(self.cards, card)
  card.column = self.id
  self:execute_trigger_with_logging("on_enter", "card_added", card)
end

function Column:remove_card(card_id)
  for i, card in ipairs(self.cards) do
    if card.id == card_id then
      self:execute_trigger_with_logging("on_exit", "card_removed", card)
      table.remove(self.cards, i)
      return card
    end
  end
  return nil
end

return Column