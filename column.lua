local Triggerable = require('kanban-md.triggerable')
local TypeConverter = require('kanban-md.type_converter')

-- Column class with enhanced capabilities
local Column = {}
Column.__index = Column
setmetatable(Column, { __index = Triggerable })

function Column:new(id, name)
  local obj = {
    id = id,  -- Can be nil to trigger auto-generation
    name = name or id,
    cards = {},
    config = TypeConverter:new({})
  }
  setmetatable(obj, Column)
  obj:init_commands()

  -- Fire on_create triggers (both class-level and instance-level)
  local context = {
    column = obj,
    timestamp = os.time()
  }

  -- Execute class-level triggers first (if any)
  if Column.triggers and Column.triggers["on_create"] then
    for name, trigger_fn in pairs(Column.triggers["on_create"]) do
      local success, result = pcall(trigger_fn, obj, context)
      if not success then
        error(string.format("Error in on_create trigger '%s': %s", name, result))
      end
    end
  end

  -- Then execute instance-level triggers
  obj:execute_triggers("on_create", context)

  -- Fallback: if ID is still nil after triggers, generate a simple one
  if not obj.id then
    obj.id = obj.name or ("column_" .. os.time())
  end

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

local build_context_and_checking = function(event_type, self, card, context)
  -- Build context if not provided (for backward compatibility)
  if not context then
    context = {
      card = card,
      target_column = self,
      source_column = nil,
      board = nil
    }
  else
    -- Ensure card and target_column are set in context
    context.card = card
    context.target_column = self
  end

  -- ProcessingEntry state: ValidatingRequirements
  -- ProcessingExit	 state: ValidatingRequirements
  local checking_triggers = self:get_triggers("on_checking")
  for name, _ in pairs(checking_triggers) do
    local success, result = self:execute_trigger_with_logging("on_checking", name, context)
    -- Check if trigger failed
    if not success then
      error(string.format("Card %s validation failed [%s]: %s", event_type, name, result or "Unknown error"))
    end
    -- Check if result indicated failure
    if result and type(result) == "table" and result.success == false then
      local err_msg = result.errors and result.errors[1] or "Unknown error"
      error(string.format("Card %s validation failed [%s]: %s", event_type, name, err_msg))
    end
  end
	return context
end

-- ProcessingExit state: ExecutingExitTriggers
-- ProcessingEntry state: ExecutingEntryTriggers
local processingStuff = function(event_type, self, context)
	local e_triggers = self:get_triggers("on_" .. event_type)
	for name, _ in pairs(e_triggers) do
		self:execute_trigger_with_logging("on_" .. event_type, name, context)
	end
end

function Column:add_card(card, context)
	local final_context = build_context_and_checking("entry", self, card, context)

  -- Add card to column
  table.insert(self.cards, card)
  card.column = self.id

	processingStuff("entry", self, final_context)

  -- ProcessingEntry state: UpdatingStatistics (could be implemented later)
  -- TODO: Update column/board statistics here
end

function Column:remove_card(card, context)
	local card_index = nil

	for i, c in ipairs(self.cards) do
		if c.id == card.id or c == card then
			card_index = i
			break
		end
	end

	if not card_index then
		error(string.format("Card with ID '%s' not found in column '%s'", card.id, self.id))
		return
	end

	local final_context = build_context_and_checking("exit", self, card, context)
	processingStuff("exit", self, final_context)

	if card_index then
		table.remove(self.cards, card_index)
	end

	return card
end

return Column
