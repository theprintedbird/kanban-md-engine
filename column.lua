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

function Column:add_card(card, context)
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
  local checking_triggers = self:get_triggers("on_checking")
  for name, _ in pairs(checking_triggers) do
    local success, result = self:execute_trigger_with_logging("on_checking", name, context)
    -- Check if trigger failed
    if not success then
      error(string.format("Card entry validation failed [%s]: %s", name, result or "Unknown error"))
    end
    -- Check if result indicates failure
    if result and type(result) == "table" and result.success == false then
      local err_msg = result.errors and result.errors[1] or "Unknown error"
      error(string.format("Card entry validation failed [%s]: %s", name, err_msg))
    end
  end

  -- Add card to column
  table.insert(self.cards, card)
  card.column = self.id
 
	-- ProcessingEntry state: ExecutingEntryTriggers
	local enter_triggers = self:get_triggers("on_entry")
	for name, _ in pairs(enter_triggers) do
		self:execute_trigger_with_logging("on_entry", name, context)
	end

  -- ProcessingEntry state: UpdatingStatistics (could be implemented later)
  -- TODO: Update column/board statistics here
end

function Column:remove_card(card_id, context)
  for i, card in ipairs(self.cards) do
    if card.id == card_id then
      -- Build context if not provided (for backward compatibility)
      if not context then
        context = {
          card = card,
          source_column = self,
          target_column = nil,
          board = nil
        }
      else
        -- Ensure card and source_column are set in context
        context.card = card
        context.source_column = self
      end

      -- ProcessingExit state: ExecutingCheckingTriggers
      local checking_triggers = self:get_triggers("on_checking")
      for name, _ in pairs(checking_triggers) do
        local success, result = self:execute_trigger_with_logging("on_checking", name, context)
        -- Check if trigger failed
        if not success then
          error(string.format("Card exit validation failed [%s]: %s", name, result or "Unknown error"))
        end
        -- Check if result indicates failure
        if result and type(result) == "table" and result.success == false then
          local err_msg = result.errors and result.errors[1] or "Unknown error"
          error(string.format("Card exit validation failed [%s]: %s", name, err_msg))
        end
      end

      -- ProcessingExit state: ExecutingExitTriggers
      local exit_triggers = self:get_triggers("on_exit")
      for name, _ in pairs(exit_triggers) do
        self:execute_trigger_with_logging("on_exit", name, context)
      end

      table.remove(self.cards, i)
      return card
    end
  end
  return nil
end

return Column
