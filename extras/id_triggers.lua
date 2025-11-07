-- ULID-based ID generation triggers for Board, Column, and Card
-- Uses the ulid helper with proper seeding for unique, sortable identifiers

local ulid = require('kanban-md.helpers.ulid')

-- Set up proper time function for Neovim
-- Neovim doesn't have socket.gettime, so we use os.time with millisecond emulation
ulid.set_time_func(function()
  -- os.time() only gives second precision, so we add sub-second component
  -- This is acceptable as ULID's random portion provides uniqueness
  local t = os.time()
  -- Add a small random offset to simulate milliseconds (0-999ms)
  return t + (math.random(0, 999) / 1000)
end)

-- Seed the random generator once on module load
-- Using a time-based seed with additional entropy
math.randomseed(os.time() * math.random(1, 10000))

-- Helper function to determine object type and generate appropriate prefix
local function get_id_prefix(obj, context)
  if context and context.board and obj == context.board then
    return "board_"
  elseif context and context.column and obj == context.column then
    return "column_"
  elseif context and context.card and obj == context.card then
    return "card_"
  end

  -- Fallback: try to detect type from metatable or properties
  if obj.columns then
    return "board_"
  elseif obj.cards then
    return "column_"
  else
    return "card_"
  end
end

-- Create ULID-based ID generation trigger
local function create_ulid_id_trigger()
  return function(self, context)
    local config = require('kanban-md.config')

    -- Check if auto_id is enabled in config
    if not config.get_value('auto_id') then
      return true
    end

    -- Determine which object we're generating an ID for
    local obj = context.board or context.column or context.card or self

    -- Only generate if ID doesn't exist or is empty
    if not obj.id or obj.id == "" then
      local prefix = get_id_prefix(obj, context)
      local generated_id = prefix .. ulid()
      obj.id = generated_id

      -- If persist_card_ids is enabled, sync to properties for persistence
      if config.get_value('persist_card_ids') and obj.properties then
        obj.properties.id = generated_id
      end
    elseif obj.id and config.get_value('persist_card_ids') and obj.properties then
      -- If ID already exists and persist_card_ids is enabled, ensure it's synced to properties
      obj.properties.id = obj.id
    end

    return true
  end
end

-- ID generation trigger (time-based hash)
-- Alternative to the ULID ID
local function create_time_based_id_trigger()
  return function(self, context)
    local card = context.card or self
    local config = require('kanban-md.config')

    -- Check if auto_id is enabled in config
    if not config.get_value('auto_id') then
      return true
    end

    -- Only generate if ID doesn't exist
    if not card.id or card.id == "" then
      local id_source = card.text .. (context.timestamp or os.time())
      local hash = 0
      for i = 1, #id_source do
        hash = (hash * 31 + string.byte(id_source, i)) % 0x100000000
      end
      local generated_id = string.format("%08x", hash)
      card.id = generated_id

      -- If persist_card_ids is enabled, sync to properties for persistence
      if config.get_value('persist_card_ids') and card.properties then
        card.properties.id = generated_id
      end
    elseif card.id and config.get_value('persist_card_ids') and card.properties then
      -- If ID already exists and persist_card_ids is enabled, ensure it's synced to properties
      card.properties.id = card.id
    end
    return true
  end
end


return {
  ulid_id = create_ulid_id_trigger,
  time_based_id = create_time_based_id_trigger,
}
