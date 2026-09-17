local Triggerable = require('kanban-md.triggerable')
local TypeConverter = require('kanban-md.type_converter')
local clock = require('kanban-md.helpers.clock')

-- Card class with enhanced state capture
local Card = {}
Card.__index = Card
setmetatable(Card, { __index = Triggerable })

-- Initialize class-level triggers
Card.triggers = {}
Card.trigger_order = {}

-- Monotonic counter used only by the fallback id below. Cards are created far
-- more frequently than Boards/Columns within a single os.time() second (e.g.
-- parsing a file with many cards, or bulk creation in a loop), so a bare
-- "card_" .. os.time() fallback (mirroring Board:new/Column:new) would collide
-- across cards created in the same second. The counter guarantees uniqueness
-- without pulling in any dependency.
local fallback_id_counter = 0

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
    content_lines = nil,  -- Array of all lines (including first line) for multi-line cards
    properties = props,
    column = nil,
    triggers = {},
    trigger_order = {}
  }
  setmetatable(obj, Card)

  -- Fire on_create triggers (both class-level and instance-level)
  local context = {
    card = obj,
    timestamp = clock.now()
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

  -- Fallback: if ID is still nil after triggers, generate a simple one
  -- (mirrors Board:new/Column:new). Without setup() there is no class-level
  -- ULID/hash on_create trigger, so pure-library consumers previously ended
  -- up with obj.id == nil forever -- see PLAN-config-fixes.md Task 2.
  if not obj.id then
    fallback_id_counter = fallback_id_counter + 1
    obj.id = "card_" .. clock.now() .. "_" .. fallback_id_counter
  end

  return obj
end

-- Simple table copy for plain property values (avoids vim.deepcopy metatable issues)
local function copy_table(t, seen)
  if type(t) ~= "table" then
    return t
  end

  -- Circular reference detection
  seen = seen or {}
  if seen[t] then
    return seen[t]  -- Return already-copied reference
  end

  local copy = {}
  seen[t] = copy  -- Mark as seen before recursing

  for k, v in pairs(t) do
    if type(v) == "table" then
      copy[k] = copy_table(v, seen) -- Recursive for arrays
    else
      copy[k] = v -- Numbers, strings, booleans, nil
    end
  end
  return copy
end

-- Create a deep copy of this card without firing on_create triggers
function Card:deep_copy()
  local props_copy = TypeConverter:new(copy_table(self.properties._raw))

  local obj = {
    id = self.id,
    text = self.text,
    content_lines = self.content_lines and copy_table(self.content_lines) or nil,
    properties = props_copy,
    column = self.column,
    triggers = {},
    trigger_order = {}
  }
  setmetatable(obj, Card)

  return obj
end

-- Get the full text content of the card
-- For single-line cards, returns card.text
-- For multi-line cards, returns all content_lines joined with newlines
function Card:get_full_text()
  if self.content_lines then
    return table.concat(self.content_lines, "\n")
  end
  return self.text
end

return Card
