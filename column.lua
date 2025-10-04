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
      source_column = card.column,
      board = self.board
    }
  else
    -- Ensure card and target_column are set in context
    context.card = card
    context.target_column = self
  end

  -- ProcessingEntry state: ValidatingRequirements
  -- ProcessingExit	 state: ValidatingRequirements
  local checking_triggers = self:get_triggers("on_checking")
  local trigger_names = self.trigger_order["on_checking"] or {}
  for _, name in ipairs(trigger_names) do
    if checking_triggers[name] then
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
  end
	return context
end

-- ProcessingExit state: ExecutingExitTriggers
-- ProcessingEntry state: ExecutingEntryTriggers
local processingStuff = function(event_type, self, context)
	local e_triggers = self:get_triggers("on_" .. event_type)
	local trigger_names = self.trigger_order["on_" .. event_type] or {}
	local results = {}
	local errors = {}

	-- Start transaction for atomic rollback
	self.command_log:begin_transaction()

	for _, name in ipairs(trigger_names) do
		if e_triggers[name] then
			local success, result = self:execute_trigger_with_logging("on_" .. event_type, name, context)

			table.insert(results, {name = name, success = success, result = result})

			if not success then
				table.insert(errors, {name = name, error = result})
				-- Fail-fast: rollback and stop
				local rollback_success, rollback_err = self.command_log:rollback_transaction()
				if not rollback_success then
					-- Add rollback error to the error list
					table.insert(errors, {name = "ROLLBACK", error = rollback_err})
				end
				return false, results, errors
			end
		end
	end

	-- All triggers succeeded
	self.command_log:commit_transaction()
	return true, results, errors
end

function Column:add_card(card, context)
	local final_context = build_context_and_checking("entry", self, card, context)

  -- Add card to column
  table.insert(self.cards, card)
  card.column = self.id

	-- Execute entry triggers with transaction support
	local success, results, errors = processingStuff("entry", self, final_context)

	if not success then
		-- Rollback card addition (triggers already rolled back by processingStuff)
		table.remove(self.cards)
		card.column = nil

		-- Throw error with details
		local error_messages = {}
		for _, err in ipairs(errors) do
			table.insert(error_messages, string.format("%s: %s", err.name, err.error))
		end
		local error_msg = table.concat(error_messages, "; ")
		error(string.format("Entry trigger failed: %s", error_msg))
	end

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

	-- Execute exit triggers with transaction support
	local success, results, errors = processingStuff("exit", self, final_context)

	if not success then
		-- Triggers already rolled back by processingStuff
		-- Throw error with details
		local error_msg = errors[1] and errors[1].error or "Unknown error"
		error(string.format("Exit trigger '%s' failed: %s", errors[1].name, error_msg))
	end

	-- Only remove card if all triggers succeeded
	table.remove(self.cards, card_index)

	return card
end

return Column
