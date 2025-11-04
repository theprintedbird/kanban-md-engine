local Triggerable = require('kanban-md.triggerable')
local TypeConverter = require('kanban-md.type_converter')

-- Column class with enhanced capabilities
local Column = {}
Column.__index = Column
setmetatable(Column, { __index = Triggerable })

-- Initialize class-level triggers
Column.triggers = {}
Column.trigger_order = {}

function Column:new(id, name)
  local obj = {
    id = id,  -- Can be nil to trigger auto-generation
    name = name or id,
    type = nil,  -- Resolved column type (string or nil)
    cards = {},
    config = TypeConverter:new({}),
    triggers = {},
    trigger_order = {}
  }
  setmetatable(obj, Column)

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

local build_context_and_checking = function(event_type, self, card, context)
  -- Build context if not provided (for backward compatibility)
  if not context then
    context = {
      card = card,
      target_column = self,
      target_column_name = self.name,
      source_column = card.column,
      board = self.board
    }
  else
    -- Ensure card is set and target_column_name is derived from target_column in context
    context.card = card
    -- Do NOT override target_column - it's already set correctly in the context
    context.target_column_name = context.target_column and context.target_column.name or nil
  end

  -- Add event_type to context so triggers can distinguish between entry and exit
  context.event_type = event_type

  -- ProcessingEntry state: ValidatingRequirements
  -- ProcessingExit	 state: ValidatingRequirements
  local checking_triggers = self:get_triggers("on_checking")
  local trigger_names = self.trigger_order["on_checking"] or {}
  for _, name in ipairs(trigger_names) do
    if checking_triggers[name] then
      -- Check if this trigger should be bypassed
      local metadata = self.trigger_metadata and
                      self.trigger_metadata["on_checking"] and
                      self.trigger_metadata["on_checking"][name] or {}

      local should_bypass = false
      if context._bypass_categories and metadata.bypassable then
        for _, category in ipairs(context._bypass_categories) do
          if metadata.category == category then
            should_bypass = true
            break
          end
        end
      end

      if not should_bypass then
        local success, result = pcall(checking_triggers[name], self, context)
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

	for _, name in ipairs(trigger_names) do
		if e_triggers[name] then
			local success, result = pcall(e_triggers[name], self, context)

			table.insert(results, {name = name, success = success, result = result})

			if not success then
				table.insert(errors, {name = name, error = result})
				return false, results, errors
			end
		end
	end

	-- All triggers succeeded
	return true, results, errors
end

function Column:add_card(card, context)
	-- Copy-and-commit: work with a copy, commit only if successful
	local card_copy
	if card.deep_copy then
		-- Use Card class method if available
		card_copy = card:deep_copy()
	else
		-- Fallback for plain objects (e.g., in tests)
		card_copy = {
			id = card.id,
			text = card.text,
			properties = vim.deepcopy(card.properties or {}),
			column = card.column
		}
	end

	local final_context = build_context_and_checking("entry", self, card_copy, context)

	-- Add copy to column
	table.insert(self.cards, card_copy)
	card_copy.column = self.id

	-- Execute entry triggers on the copy
	local success, results, errors = processingStuff("entry", self, final_context)

	if not success then
		-- Discard the copy - remove from column
		table.remove(self.cards)
		card_copy.column = nil

		-- Throw error with details
		local error_messages = {}
		for _, err in ipairs(errors) do
			table.insert(error_messages, string.format("%s: %s", err.name, err.error))
		end
		local error_msg = table.concat(error_messages, "; ")
		error(string.format("Entry trigger failed: %s", error_msg))
	end

	-- Commit: update original card from the copy
	card.id = card_copy.id
	card.text = card_copy.text
	card.properties = card_copy.properties
	card.column = card_copy.column

	-- Replace copy with original in cards array
	self.cards[#self.cards] = card

	-- ProcessingEntry state: UpdatingStatistics (could be implemented later)
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

	-- Copy-and-commit: work with a copy, commit only if successful
	local card_copy
	if card.deep_copy then
		-- Use Card class method if available
		card_copy = card:deep_copy()
	else
		-- Fallback for plain objects (e.g., in tests)
		card_copy = {
			id = card.id,
			text = card.text,
			properties = vim.deepcopy(card.properties or {}),
			column = card.column
		}
	end

	local final_context = build_context_and_checking("exit", self, card_copy, context)

	-- Execute exit triggers on the copy
	local success, results, errors = processingStuff("exit", self, final_context)

	if not success then
		-- Discard the copy, keep original unchanged in column
		-- Throw error with details
		local error_msg = errors[1] and errors[1].error or "Unknown error"
		error(string.format("Exit trigger '%s' failed: %s", errors[1].name, error_msg))
	end

	-- Commit: update original card from the copy
	card.id = card_copy.id
	card.text = card_copy.text
	card.properties = card_copy.properties
	card.column = card_copy.column

	-- Remove card from column (triggers succeeded)
	table.remove(self.cards, card_index)

	return card
end

return Column
