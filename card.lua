local Triggerable = require('kanban-md.triggerable')
local TypeConverter = require('kanban-md.type_converter')

-- Card class with enhanced state capture
local Card = {}
Card.__index = Card
setmetatable(Card, { __index = Triggerable })

function Card:new(id, text, properties)
  -- If properties is already a TypeConverter, use it directly to avoid double-wrapping
  local props = properties
  if type(properties) == "table" and not properties.to_table then
    -- Plain table, needs to be wrapped
    props = TypeConverter:new(properties)
  elseif not properties then
    -- No properties provided
    props = TypeConverter:new({})
  end
  -- else: properties is already a TypeConverter, use as-is

  local obj = {
    id = id,
    text = text or "",
    properties = props,
    column = nil
  }
  setmetatable(obj, Card)
  obj:init_commands()

  -- Fire on_create triggers (both class-level and instance-level)
  local context = {
    card = obj,
    timestamp = os.time()
  }

  -- Execute class-level triggers first (if any)
  if Card.triggers and Card.triggers["on_create"] then
    for name, trigger_fn in pairs(Card.triggers["on_create"]) do
      local success, result = pcall(trigger_fn, obj, context)
      if not success then
        error(string.format("Error in on_create trigger '%s': %s", name, result))
      end
    end
  end

  -- Then execute instance-level triggers
  obj:execute_triggers("on_create", context)

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
